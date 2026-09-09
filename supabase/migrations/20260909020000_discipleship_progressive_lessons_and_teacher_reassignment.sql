-- Discipulado: evita repetir lecciones por persona y permite relevar al discipulador sin perder historia.
create or replace function public.get_discipleship_lesson_availability(target_group_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 with grp as (
  select g.id,g.organization_id,g.site_id,g.program_id
  from public.training_groups g
  where g.id=target_group_id and g.status<>'CANCELLED'
   and public.current_user_has_permission('groups.read',g.organization_id,g.site_id)
 ), active_students as (
  select e.person_id from public.enrollments e join grp on grp.id=e.group_id
  where e.status in('ENROLLED','ACTIVE','PAUSED')
 ), program_lessons as (
  select l.id,l.title,l.sort_order from public.lessons l
  join public.training_modules m on m.id=l.module_id
  join grp on grp.program_id=m.program_id
  where l.active and m.active
 ), received as (
  select distinct ca.person_id,cs.lesson_id
  from public.class_attendance ca
  join public.class_sessions cs on cs.id=ca.session_id
  join grp on grp.organization_id=cs.organization_id
  where cs.status='COMPLETED' and ca.attendance_status in('PRESENT','LATE')
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'lessonId',lesson.id,'title',lesson.title,'sortOrder',lesson.sort_order,
  'pendingCount',(select count(*) from active_students student where not exists(select 1 from received r where r.person_id=student.person_id and r.lesson_id=lesson.id)),
  'completedCount',(select count(*) from active_students student where exists(select 1 from received r where r.person_id=student.person_id and r.lesson_id=lesson.id)),
  'eligiblePersonIds',coalesce((select jsonb_agg(student.person_id) from active_students student where not exists(select 1 from received r where r.person_id=student.person_id and r.lesson_id=lesson.id)),'[]'::jsonb)
 ) order by lesson.sort_order),'[]'::jsonb) from program_lessons lesson;
$$;
revoke all on function public.get_discipleship_lesson_availability(uuid) from public;
grant execute on function public.get_discipleship_lesson_availability(uuid) to authenticated;

create or replace function public.schedule_discipleship_session(target_group_id uuid,given_lesson_id uuid,given_teacher_person_id uuid,given_date date,given_time time)
returns uuid language plpgsql security definer set search_path='' as $$
declare grp record; created_id uuid; eligible_count integer;
begin
 select g.* into grp from public.training_groups g where g.id=target_group_id and g.status<>'CANCELLED';
 if grp.id is null then raise exception 'GROUP_NOT_FOUND'; end if;
 if not public.current_user_has_permission('groups.manage',grp.organization_id,grp.site_id) then raise exception 'ACCESS_DENIED'; end if;
 if not exists(select 1 from public.lessons l join public.training_modules m on m.id=l.module_id where l.id=given_lesson_id and l.active and m.active and m.program_id=grp.program_id) then raise exception 'LESSON_NOT_IN_PROGRAM'; end if;
 if not exists(select 1 from public.people p where p.id=given_teacher_person_id and p.organization_id=grp.organization_id and p.site_id=grp.site_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'TEACHER_NOT_AVAILABLE'; end if;
 select count(*) into eligible_count from public.enrollments e
 where e.group_id=grp.id and e.status in('ENROLLED','ACTIVE','PAUSED')
 and not exists(
  select 1 from public.class_attendance ca join public.class_sessions cs on cs.id=ca.session_id
  where ca.person_id=e.person_id and cs.organization_id=grp.organization_id and cs.lesson_id=given_lesson_id
   and cs.status='COMPLETED' and ca.attendance_status in('PRESENT','LATE')
 );
 if eligible_count=0 then raise exception 'LESSON_ALREADY_COMPLETED_BY_ALL'; end if;
 insert into public.class_sessions(organization_id,site_id,group_id,lesson_id,teacher_person_id,session_date,start_time,status,created_by)
 values(grp.organization_id,grp.site_id,grp.id,given_lesson_id,given_teacher_person_id,given_date,given_time,'SCHEDULED',auth.uid()) returning id into created_id;
 return created_id;
end $$;
revoke all on function public.schedule_discipleship_session(uuid,uuid,uuid,date,time) from public;
grant execute on function public.schedule_discipleship_session(uuid,uuid,uuid,date,time) to authenticated;

create or replace function public.reassign_discipleship_teacher(target_group_id uuid,new_teacher_person_id uuid,given_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare grp record; teacher_name text;
begin
 select g.* into grp from public.training_groups g where g.id=target_group_id for update;
 if grp.id is null then raise exception 'GROUP_NOT_FOUND'; end if;
 if not public.current_user_has_permission('groups.manage',grp.organization_id,grp.site_id) then raise exception 'ACCESS_DENIED'; end if;
 if grp.teacher_person_id=new_teacher_person_id then raise exception 'TEACHER_UNCHANGED'; end if;
 select trim(concat_ws(' ',p.first_name,p.last_name)) into teacher_name from public.people p
 where p.id=new_teacher_person_id and p.organization_id=grp.organization_id and p.site_id=grp.site_id and p.person_status not in('INACTIVE','TRANSFERRED');
 if teacher_name is null then raise exception 'TEACHER_NOT_AVAILABLE'; end if;
 update public.training_groups set teacher_person_id=new_teacher_person_id,updated_at=now() where id=grp.id;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
 values(grp.organization_id,grp.site_id,auth.uid(),'DISCIPLESHIP_TEACHER_REASSIGNED','TRAINING_GROUP',grp.id,
  jsonb_build_object('teacherPersonId',grp.teacher_person_id),jsonb_build_object('teacherPersonId',new_teacher_person_id,'reason',nullif(trim(given_reason),'')));
 return jsonb_build_object('groupId',grp.id,'teacherPersonId',new_teacher_person_id,'teacherName',teacher_name);
end $$;
revoke all on function public.reassign_discipleship_teacher(uuid,uuid,text) from public;
grant execute on function public.reassign_discipleship_teacher(uuid,uuid,text) to authenticated;

create or replace function public.prevent_repeated_lesson_attendance() returns trigger
language plpgsql set search_path='' as $$
declare selected_lesson uuid; selected_org uuid;
begin
 if new.attendance_status not in('PRESENT','LATE') then return new; end if;
 select cs.lesson_id,cs.organization_id into selected_lesson,selected_org from public.class_sessions cs where cs.id=new.session_id;
 if exists(
  select 1 from public.class_attendance ca join public.class_sessions cs on cs.id=ca.session_id
  where ca.person_id=new.person_id and ca.id<>new.id and cs.organization_id=selected_org and cs.lesson_id=selected_lesson
   and cs.status='COMPLETED' and ca.attendance_status in('PRESENT','LATE')
 ) then raise exception 'PERSON_ALREADY_COMPLETED_LESSON'; end if;
 return new;
end $$;
drop trigger if exists class_attendance_prevent_repeated_lesson on public.class_attendance;
create trigger class_attendance_prevent_repeated_lesson before insert or update on public.class_attendance
for each row execute function public.prevent_repeated_lesson_attendance();

notify pgrst,'reload schema';
