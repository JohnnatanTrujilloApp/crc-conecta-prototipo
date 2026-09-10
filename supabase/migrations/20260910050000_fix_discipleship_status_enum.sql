-- Corrige el tipo del estado calculado al registrar una lección individual.
create or replace function public.record_individual_discipleship_lesson(target_assignment_id uuid,target_lesson_id uuid,given_date date default current_date,given_time time default null,given_modality public.discipleship_modality default 'IN_PERSON',given_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare a record; my_person uuid:=public.get_my_active_person_id(); created_id uuid; lesson_total int; completed_total int;
begin
 select * into a from public.discipleship_assignments where id=target_assignment_id for update;
 if a.id is null then raise exception 'ASSIGNMENT_NOT_FOUND'; end if;
 if a.status not in('ASSIGNED','ACTIVE') then raise exception 'ASSIGNMENT_NOT_ACTIVE'; end if;
 if my_person=a.disciple_person_id then raise exception 'STUDENT_CANNOT_RECORD_LESSON'; end if;
 if my_person<>a.discipler_person_id and not public.current_user_has_permission('discipleship.edit_lesson',a.organization_id,a.site_id) then raise exception 'LESSON_RECORD_DENIED'; end if;
 if my_person=a.discipler_person_id and not public.current_user_has_any_permission('discipleship.record_lesson') then raise exception 'LESSON_RECORD_DENIED'; end if;
 if not exists(select 1 from public.lessons l join public.training_modules m on m.id=l.module_id where l.id=target_lesson_id and m.program_id=a.program_id and l.active and m.active) then raise exception 'LESSON_OUTSIDE_PROGRAM'; end if;
 insert into public.discipleship_lesson_records(organization_id,site_id,assignment_id,lesson_id,discipler_person_id,delivered_on,delivered_at,modality,notes,recorded_by)
 values(a.organization_id,a.site_id,a.id,target_lesson_id,a.discipler_person_id,coalesce(given_date,current_date),given_time,given_modality,nullif(trim(given_notes),''),auth.uid()) returning id into created_id;
 select count(*) into lesson_total from public.lessons l join public.training_modules m on m.id=l.module_id where m.program_id=a.program_id and l.active and m.active;
 select count(*) into completed_total from public.discipleship_lesson_records where assignment_id=a.id;
 update public.discipleship_assignments
 set status=case when lesson_total>0 and completed_total>=lesson_total
   then 'COMPLETED'::public.discipleship_assignment_status
   else 'ACTIVE'::public.discipleship_assignment_status end,
  completed_at=case when lesson_total>0 and completed_total>=lesson_total then now() else null end
 where id=a.id;
 return created_id;
exception when unique_violation then raise exception 'LESSON_ALREADY_RECORDED'; end; $$;

revoke all on function public.record_individual_discipleship_lesson(uuid,uuid,date,time,public.discipleship_modality,text) from public;
grant execute on function public.record_individual_discipleship_lesson(uuid,uuid,date,time,public.discipleship_modality,text) to authenticated;
notify pgrst,'reload schema';
