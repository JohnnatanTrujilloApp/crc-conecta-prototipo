-- Individual discipleship without changing the existing group model.
do $$ begin create type public.discipleship_assignment_status as enum ('ASSIGNED','ACTIVE','PAUSED','COMPLETED','CANCELLED'); exception when duplicate_object then null; end $$;
do $$ begin create type public.discipleship_modality as enum ('IN_PERSON','VIRTUAL'); exception when duplicate_object then null; end $$;

create table if not exists public.discipleship_assignments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null,
 program_id uuid not null, disciple_person_id uuid not null, discipler_person_id uuid not null,
 status public.discipleship_assignment_status not null default 'ASSIGNED', assigned_at timestamptz not null default now(),
 completed_at timestamptz, notes text, created_by uuid references public.user_accounts(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id) references public.sites(organization_id,id) on delete restrict,
 foreign key(organization_id,program_id) references public.training_programs(organization_id,id) on delete restrict,
 foreign key(organization_id,disciple_person_id) references public.people(organization_id,id) on delete restrict,
 foreign key(organization_id,discipler_person_id) references public.people(organization_id,id) on delete restrict,
 check(disciple_person_id<>discipler_person_id), check((status='COMPLETED' and completed_at is not null) or status<>'COMPLETED')
);
create unique index if not exists discipleship_assignment_one_open_program
 on public.discipleship_assignments(disciple_person_id,program_id) where status in('ASSIGNED','ACTIVE','PAUSED');
create index if not exists discipleship_assignment_teacher_idx on public.discipleship_assignments(discipler_person_id,status,updated_at desc);
create index if not exists discipleship_assignment_site_idx on public.discipleship_assignments(site_id,status,updated_at desc);

create table if not exists public.discipleship_lesson_records (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null,
 assignment_id uuid not null references public.discipleship_assignments(id) on delete cascade,
 lesson_id uuid not null references public.lessons(id) on delete restrict, discipler_person_id uuid not null,
 delivered_on date not null default current_date, delivered_at time, modality public.discipleship_modality not null,
 notes text, recorded_by uuid references public.user_accounts(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id) references public.sites(organization_id,id) on delete restrict,
 foreign key(organization_id,discipler_person_id) references public.people(organization_id,id) on delete restrict,
 unique(assignment_id,lesson_id)
);
create index if not exists discipleship_lesson_assignment_idx on public.discipleship_lesson_records(assignment_id,delivered_on desc);

create trigger discipleship_assignments_updated before update on public.discipleship_assignments for each row execute function public.set_updated_at();
create trigger discipleship_lesson_records_updated before update on public.discipleship_lesson_records for each row execute function public.set_updated_at();
create trigger discipleship_assignments_audit after insert or update on public.discipleship_assignments for each row execute function public.capture_audit_log();
create trigger discipleship_lesson_records_audit after insert or update on public.discipleship_lesson_records for each row execute function public.capture_audit_log();

insert into public.permissions(code,name,description) values
 ('discipleship.assign','Asignar discipulado','Crear asignaciones individuales en el scope autorizado'),
 ('discipleship.view_site','Ver discipulados de sede','Consultar asignaciones individuales de una sede'),
 ('discipleship.record_lesson','Registrar lección','Registrar una lección realmente impartida'),
 ('discipleship.edit_lesson','Editar lección','Corregir una lección registrada'),
 ('discipleship.reassign','Reasignar discipulador','Cambiar el discipulador sin perder historia'),
 ('discipleship.complete','Completar discipulado','Completar o reabrir una asignación'),
 ('discipleship.manage_groups','Gestionar grupos de discipulado','Administrar la modalidad grupal')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','discipleship.assign'),('SUPER_ADMIN','discipleship.view_site'),('SUPER_ADMIN','discipleship.record_lesson'),('SUPER_ADMIN','discipleship.edit_lesson'),('SUPER_ADMIN','discipleship.reassign'),('SUPER_ADMIN','discipleship.complete'),('SUPER_ADMIN','discipleship.manage_groups'),
 ('NATIONAL_PASTOR','discipleship.assign'),('NATIONAL_PASTOR','discipleship.view_site'),('NATIONAL_PASTOR','discipleship.record_lesson'),('NATIONAL_PASTOR','discipleship.edit_lesson'),('NATIONAL_PASTOR','discipleship.reassign'),('NATIONAL_PASTOR','discipleship.complete'),('NATIONAL_PASTOR','discipleship.manage_groups'),
 ('SITE_PASTOR','discipleship.assign'),('SITE_PASTOR','discipleship.view_site'),('SITE_PASTOR','discipleship.record_lesson'),('SITE_PASTOR','discipleship.edit_lesson'),('SITE_PASTOR','discipleship.reassign'),('SITE_PASTOR','discipleship.complete'),('SITE_PASTOR','discipleship.manage_groups'),
 ('SITE_ADMIN','discipleship.assign'),('SITE_ADMIN','discipleship.view_site'),('SITE_ADMIN','discipleship.record_lesson'),('SITE_ADMIN','discipleship.edit_lesson'),('SITE_ADMIN','discipleship.reassign'),('SITE_ADMIN','discipleship.complete'),('SITE_ADMIN','discipleship.manage_groups'),
 ('DISCIPLESHIP_COORDINATOR','discipleship.assign'),('DISCIPLESHIP_COORDINATOR','discipleship.view_site'),('DISCIPLESHIP_COORDINATOR','discipleship.record_lesson'),('DISCIPLESHIP_COORDINATOR','discipleship.edit_lesson'),('DISCIPLESHIP_COORDINATOR','discipleship.reassign'),('DISCIPLESHIP_COORDINATOR','discipleship.complete'),('DISCIPLESHIP_COORDINATOR','discipleship.manage_groups'),
 ('DISCIPLESHIP_TEACHER','discipleship.record_lesson'))
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

alter table public.discipleship_assignments enable row level security;
alter table public.discipleship_lesson_records enable row level security;
grant select on public.discipleship_assignments,public.discipleship_lesson_records to authenticated;

create policy discipleship_assignments_read on public.discipleship_assignments for select to authenticated using(
 public.current_user_has_permission('discipleship.view_site',organization_id,site_id)
 or discipler_person_id=public.get_my_active_person_id() or disciple_person_id=public.get_my_active_person_id());
create policy discipleship_lesson_records_read on public.discipleship_lesson_records for select to authenticated using(
 public.current_user_has_permission('discipleship.view_site',organization_id,site_id)
 or exists(select 1 from public.discipleship_assignments a where a.id=assignment_id and (a.discipler_person_id=public.get_my_active_person_id() or a.disciple_person_id=public.get_my_active_person_id())));

create or replace function public.create_individual_discipleship(target_site_id uuid,target_program_id uuid,target_disciple_person_id uuid,target_discipler_person_id uuid,given_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare s record; created_id uuid;
begin
 select * into s from public.sites where id=target_site_id;
 if s.id is null or not public.current_user_has_permission('discipleship.assign',s.organization_id,s.id) then raise exception 'DISCIPLESHIP_ASSIGN_DENIED'; end if;
 if target_disciple_person_id=target_discipler_person_id then raise exception 'SELF_DISCIPLESHIP_NOT_ALLOWED'; end if;
 if not exists(select 1 from public.training_programs p where p.id=target_program_id and p.organization_id=s.organization_id and p.program_type='DISCIPLESHIP' and p.active) then raise exception 'INVALID_DISCIPLESHIP_PROGRAM'; end if;
 if not exists(select 1 from public.people p where p.id=target_disciple_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLE_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.people p join public.user_accounts ua on ua.person_id=p.id and ua.access_status='ACTIVE' join public.user_roles ur on ur.user_account_id=ua.id and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions pm on pm.id=rp.permission_id and pm.code='discipleship.record_lesson' where p.id=target_discipler_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLER_REQUIRES_ACTIVE_ACCOUNT'; end if;
 insert into public.discipleship_assignments(organization_id,site_id,program_id,disciple_person_id,discipler_person_id,notes,created_by)
 values(s.organization_id,s.id,target_program_id,target_disciple_person_id,target_discipler_person_id,nullif(trim(given_notes),''),auth.uid()) returning id into created_id;
 return created_id;
exception when unique_violation then raise exception 'DISCIPLESHIP_ALREADY_ASSIGNED'; end; $$;

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
 update public.discipleship_assignments set status=case when lesson_total>0 and completed_total>=lesson_total then 'COMPLETED' else 'ACTIVE' end,completed_at=case when lesson_total>0 and completed_total>=lesson_total then now() else null end where id=a.id;
 return created_id;
exception when unique_violation then raise exception 'LESSON_ALREADY_RECORDED'; end; $$;

create or replace function public.reassign_individual_discipler(target_assignment_id uuid,new_discipler_person_id uuid,given_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare a record; old_teacher uuid;
begin
 select * into a from public.discipleship_assignments where id=target_assignment_id for update;
 if a.id is null or not public.current_user_has_permission('discipleship.reassign',a.organization_id,a.site_id) then raise exception 'DISCIPLESHIP_REASSIGN_DENIED'; end if;
 if new_discipler_person_id=a.disciple_person_id then raise exception 'SELF_DISCIPLESHIP_NOT_ALLOWED'; end if;
 if not exists(select 1 from public.people p join public.user_accounts ua on ua.person_id=p.id and ua.access_status='ACTIVE' join public.user_roles ur on ur.user_account_id=ua.id and ur.active join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions pm on pm.id=rp.permission_id and pm.code='discipleship.record_lesson' where p.id=new_discipler_person_id and p.organization_id=a.organization_id) then raise exception 'DISCIPLER_REQUIRES_ACTIVE_ACCOUNT'; end if;
 old_teacher:=a.discipler_person_id; update public.discipleship_assignments set discipler_person_id=new_discipler_person_id where id=a.id;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(a.organization_id,a.site_id,auth.uid(),'DISCIPLESHIP_DISCIPLER_REASSIGNED','DISCIPLESHIP_ASSIGNMENT',a.id,jsonb_build_object('disciplerPersonId',old_teacher),jsonb_build_object('disciplerPersonId',new_discipler_person_id,'reason',given_reason));
end; $$;

revoke all on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) from public;
revoke all on function public.record_individual_discipleship_lesson(uuid,uuid,date,time,public.discipleship_modality,text) from public;
revoke all on function public.reassign_individual_discipler(uuid,uuid,text) from public;
grant execute on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) to authenticated;
grant execute on function public.record_individual_discipleship_lesson(uuid,uuid,date,time,public.discipleship_modality,text) to authenticated;
grant execute on function public.reassign_individual_discipler(uuid,uuid,text) to authenticated;

create or replace function public.get_individual_discipleship_dashboard(target_site_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s record; my_person uuid:=public.get_my_active_person_id(); can_view boolean; result jsonb;
begin
 select * into s from public.sites where id=target_site_id;
 if s.id is null then raise exception 'SITE_NOT_FOUND'; end if;
 can_view:=public.current_user_has_permission('discipleship.view_site',s.organization_id,s.id);
 select jsonb_build_object(
  'canAssign',public.current_user_has_permission('discipleship.assign',s.organization_id,s.id),
  'canReassign',public.current_user_has_permission('discipleship.reassign',s.organization_id,s.id),
  'canRecord',public.current_user_has_permission('discipleship.record_lesson',s.organization_id,s.id),
  'assignments',coalesce(jsonb_agg(item order by (item->>'updatedAt') desc) filter(where item is not null),'[]'::jsonb)
 ) into result from (
  select jsonb_build_object('id',a.id,'siteId',a.site_id,'programId',a.program_id,'program',tp.title,
   'discipleId',a.disciple_person_id,'disciple',trim(dp.first_name||' '||dp.last_name),
   'disciplerId',a.discipler_person_id,'discipler',trim(dr.first_name||' '||dr.last_name),'status',a.status,
   'assignedAt',a.assigned_at,'updatedAt',a.updated_at,'completed',count(lr.id),'total',count(l.id),
   'progress',case when count(l.id)=0 then 0 else round(count(lr.id)::numeric/count(l.id)*100) end,
   'lastLessonAt',max(lr.delivered_on),'completedLessonIds',coalesce((select jsonb_agg(done.lesson_id) from public.discipleship_lesson_records done where done.assignment_id=a.id),'[]'::jsonb)) item
  from public.discipleship_assignments a join public.training_programs tp on tp.id=a.program_id
  join public.people dp on dp.id=a.disciple_person_id join public.people dr on dr.id=a.discipler_person_id
  left join public.training_modules tm on tm.program_id=a.program_id and tm.active left join public.lessons l on l.module_id=tm.id and l.active
  left join public.discipleship_lesson_records lr on lr.assignment_id=a.id and lr.lesson_id=l.id
  where a.site_id=s.id and (can_view or a.discipler_person_id=my_person or a.disciple_person_id=my_person)
  group by a.id,tp.title,dp.first_name,dp.last_name,dr.first_name,dr.last_name
 ) q;
 return result;
end; $$;

create or replace function public.search_individual_discipleship_people(target_site_id uuid,search_term text,candidate_kind text,result_limit int default 20)
returns table(id uuid,name text,crc_code text,site_name text,phone_masked text,document_masked text) language plpgsql stable security definer set search_path='' as $$
declare s record; term text:=lower(trim(search_term));
begin
 select * into s from public.sites where sites.id=target_site_id;
 if s.id is null or not public.current_user_has_permission('discipleship.assign',s.organization_id,s.id) then raise exception 'DISCIPLESHIP_SEARCH_DENIED'; end if;
 if char_length(term)<2 then return; end if;
 return query select p.id,trim(p.first_name||' '||p.last_name),p.crc_code,ps.name,
  case when p.phone is null then null else '***'||right(regexp_replace(p.phone,'\D','','g'),4) end,
  case when p.document_number is null then null else '***'||right(p.document_number,4) end
 from public.people p join public.sites ps on ps.id=p.site_id
 where p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')
 and (lower(p.first_name||' '||p.last_name) like '%'||term||'%' or lower(coalesce(p.email,'')) like '%'||term||'%' or regexp_replace(coalesce(p.phone,''),'\D','','g') like '%'||regexp_replace(term,'\D','','g')||'%' or lower(coalesce(p.document_number,'')) like '%'||term||'%')
 and (candidate_kind<>'DISCIPLER' or exists(select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions pm on pm.id=rp.permission_id and pm.code='discipleship.record_lesson' where ua.person_id=p.id and ua.access_status='ACTIVE'))
 order by p.first_name,p.last_name limit least(greatest(result_limit,1),30);
end; $$;
revoke all on function public.get_individual_discipleship_dashboard(uuid) from public;
revoke all on function public.search_individual_discipleship_people(uuid,text,text,int) from public;
grant execute on function public.get_individual_discipleship_dashboard(uuid) to authenticated;
grant execute on function public.search_individual_discipleship_people(uuid,text,text,int) to authenticated;

comment on table public.discipleship_assignments is 'Individual discipleship relationship; groups remain in training_groups.';
comment on table public.discipleship_lesson_records is 'Actual delivered lessons; one record per assignment and lesson.';
notify pgrst,'reload schema';
