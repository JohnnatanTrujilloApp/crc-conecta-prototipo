-- Sprint 6: site-scoped training groups, enrollments, class sessions and attendance.
do $$ begin create type public.training_group_status as enum ('PLANNED','ACTIVE','COMPLETED','CANCELLED'); exception when duplicate_object then null; end $$;
do $$ begin create type public.enrollment_status as enum ('ENROLLED','ACTIVE','PAUSED','COMPLETED','WITHDRAWN'); exception when duplicate_object then null; end $$;
do $$ begin create type public.class_session_status as enum ('SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED'); exception when duplicate_object then null; end $$;

create table public.training_groups (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null, program_id uuid not null,
 name text not null check(char_length(trim(name)) between 3 and 180), teacher_person_id uuid not null, assistant_person_id uuid,
 start_date date not null, end_date date, status public.training_group_status not null default 'PLANNED',
 created_by uuid references public.user_accounts(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id) references public.sites(organization_id,id) on delete cascade,
 foreign key(organization_id,program_id) references public.training_programs(organization_id,id) on delete restrict,
 foreign key(organization_id,site_id,teacher_person_id) references public.people(organization_id,site_id,id) on delete restrict,
 foreign key(organization_id,site_id,assistant_person_id) references public.people(organization_id,site_id,id) on delete restrict,
 unique(organization_id,site_id,id), unique(site_id,name), check(end_date is null or end_date>=start_date), check(assistant_person_id is null or assistant_person_id<>teacher_person_id)
);

create table public.enrollments (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null, program_id uuid not null, group_id uuid not null, person_id uuid not null,
 enrollment_date date not null default current_date, status public.enrollment_status not null default 'ENROLLED',
 progress_percentage numeric(5,2) not null default 0 check(progress_percentage between 0 and 100), completion_date date,
 created_by uuid references public.user_accounts(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id,group_id) references public.training_groups(organization_id,site_id,id) on delete cascade,
 foreign key(organization_id,site_id,person_id) references public.people(organization_id,site_id,id) on delete cascade,
 foreign key(organization_id,program_id) references public.training_programs(organization_id,id) on delete restrict,
 unique(group_id,person_id), check((status='COMPLETED' and completion_date is not null) or status<>'COMPLETED')
);

create table public.class_sessions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null, group_id uuid not null,
 lesson_id uuid not null references public.lessons(id) on delete restrict, teacher_person_id uuid not null,
 session_date date not null, start_time time not null, end_time time, status public.class_session_status not null default 'SCHEDULED', notes text,
 created_by uuid references public.user_accounts(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id,group_id) references public.training_groups(organization_id,site_id,id) on delete cascade,
 foreign key(organization_id,site_id,teacher_person_id) references public.people(organization_id,site_id,id) on delete restrict,
 unique(organization_id,site_id,id), unique(group_id,session_date,start_time), check(end_time is null or end_time>start_time)
);

create table public.class_attendance (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null, site_id uuid not null, session_id uuid not null, person_id uuid not null,
 attendance_status public.attendance_status not null, notes text, registered_by uuid references public.user_accounts(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id,session_id) references public.class_sessions(organization_id,site_id,id) on delete cascade,
 foreign key(organization_id,site_id,person_id) references public.people(organization_id,site_id,id) on delete cascade, unique(session_id,person_id)
);

create index training_groups_site_status_idx on public.training_groups(organization_id,site_id,status);
create index enrollments_group_status_idx on public.enrollments(group_id,status);
create index enrollments_person_idx on public.enrollments(person_id,status);
create index class_sessions_group_date_idx on public.class_sessions(group_id,session_date desc);
create index class_attendance_session_idx on public.class_attendance(session_id,attendance_status);
create trigger training_groups_set_updated_at before update on public.training_groups for each row execute function public.set_updated_at();
create trigger enrollments_set_updated_at before update on public.enrollments for each row execute function public.set_updated_at();
create trigger class_sessions_set_updated_at before update on public.class_sessions for each row execute function public.set_updated_at();
create trigger class_attendance_set_updated_at before update on public.class_attendance for each row execute function public.set_updated_at();

create or replace function public.validate_training_operations() returns trigger language plpgsql set search_path='' as $$
declare expected_program uuid; session_group uuid;
begin
 if tg_table_name='enrollments' then
  select g.program_id into expected_program from public.training_groups g where g.id=new.group_id;
  if expected_program is null or expected_program<>new.program_id then raise exception 'Enrollment program must match group program'; end if;
 elsif tg_table_name='class_sessions' then
  select tm.program_id into expected_program from public.lessons l join public.training_modules tm on tm.id=l.module_id where l.id=new.lesson_id;
  if expected_program is null or expected_program<>(select g.program_id from public.training_groups g where g.id=new.group_id) then raise exception 'Lesson must belong to group program'; end if;
 elsif tg_table_name='class_attendance' then
  select cs.group_id into session_group from public.class_sessions cs where cs.id=new.session_id;
  if not exists(select 1 from public.enrollments e where e.group_id=session_group and e.person_id=new.person_id and e.status in('ENROLLED','ACTIVE','PAUSED')) then raise exception 'Person must be enrolled in the session group'; end if;
 end if;
 if auth.uid() is not null then
  if tg_table_name='class_attendance' then if tg_op='INSERT' then new.registered_by=auth.uid(); else new.registered_by=old.registered_by; end if;
  else if tg_op='INSERT' then new.created_by=auth.uid(); else new.created_by=old.created_by; end if; end if;
 end if;
 return new;
end; $$;
create trigger enrollments_validate before insert or update on public.enrollments for each row execute function public.validate_training_operations();
create trigger class_sessions_validate before insert or update on public.class_sessions for each row execute function public.validate_training_operations();
create trigger class_attendance_validate before insert or update on public.class_attendance for each row execute function public.validate_training_operations();
create trigger training_groups_audit before insert or update on public.training_groups for each row execute function public.protect_training_audit();

insert into public.permissions(code,name,description) values
 ('groups.read','Ver grupos','Consultar grupos, matrículas y sesiones de la sede'),('groups.manage','Gestionar grupos','Crear y actualizar grupos y sesiones'),
 ('enrollments.manage','Gestionar matrículas','Matricular y actualizar estudiantes'),('class_attendance.register','Registrar asistencia de clase','Registrar asistencia de estudiantes matriculados')
on conflict(code) do update set name=excluded.name,description=excluded.description;
with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','groups.read'),('SUPER_ADMIN','groups.manage'),('SUPER_ADMIN','enrollments.manage'),('SUPER_ADMIN','class_attendance.register'),
 ('NATIONAL_PASTOR','groups.read'),('NATIONAL_PASTOR','groups.manage'),('NATIONAL_PASTOR','enrollments.manage'),('NATIONAL_PASTOR','class_attendance.register'),
 ('SITE_PASTOR','groups.read'),('SITE_PASTOR','groups.manage'),('SITE_PASTOR','enrollments.manage'),('SITE_PASTOR','class_attendance.register'),
 ('SITE_ADMIN','groups.read'),('SITE_ADMIN','groups.manage'),('SITE_ADMIN','enrollments.manage'),('SITE_ADMIN','class_attendance.register'),
 ('DISCIPLESHIP_COORDINATOR','groups.read'),('DISCIPLESHIP_COORDINATOR','groups.manage'),('DISCIPLESHIP_COORDINATOR','enrollments.manage'),('DISCIPLESHIP_COORDINATOR','class_attendance.register'),
 ('DISCIPLESHIP_TEACHER','groups.read'),('DISCIPLESHIP_TEACHER','class_attendance.register'),('COURSE_TEACHER','groups.read'),('COURSE_TEACHER','class_attendance.register'))
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

alter table public.training_groups enable row level security; alter table public.enrollments enable row level security;
alter table public.class_sessions enable row level security; alter table public.class_attendance enable row level security;
grant select,insert,update on public.training_groups,public.enrollments,public.class_sessions,public.class_attendance to authenticated;
create policy training_groups_select_scoped on public.training_groups for select to authenticated using(public.current_user_has_permission('groups.read',organization_id,site_id));
create policy training_groups_insert_scoped on public.training_groups for insert to authenticated with check(public.current_user_has_permission('groups.manage',organization_id,site_id));
create policy training_groups_update_scoped on public.training_groups for update to authenticated using(public.current_user_has_permission('groups.manage',organization_id,site_id)) with check(public.current_user_has_permission('groups.manage',organization_id,site_id));
create policy enrollments_select_scoped on public.enrollments for select to authenticated using(public.current_user_has_permission('groups.read',organization_id,site_id));
create policy enrollments_insert_scoped on public.enrollments for insert to authenticated with check(public.current_user_has_permission('enrollments.manage',organization_id,site_id));
create policy enrollments_update_scoped on public.enrollments for update to authenticated using(public.current_user_has_permission('enrollments.manage',organization_id,site_id)) with check(public.current_user_has_permission('enrollments.manage',organization_id,site_id));
create policy class_sessions_select_scoped on public.class_sessions for select to authenticated using(public.current_user_has_permission('groups.read',organization_id,site_id));
create policy class_sessions_insert_scoped on public.class_sessions for insert to authenticated with check(public.current_user_has_permission('groups.manage',organization_id,site_id));
create policy class_sessions_update_scoped on public.class_sessions for update to authenticated using(public.current_user_has_permission('groups.manage',organization_id,site_id)) with check(public.current_user_has_permission('groups.manage',organization_id,site_id));
create policy class_attendance_select_scoped on public.class_attendance for select to authenticated using(public.current_user_has_permission('groups.read',organization_id,site_id));
create policy class_attendance_insert_scoped on public.class_attendance for insert to authenticated with check(public.current_user_has_permission('class_attendance.register',organization_id,site_id));
create policy class_attendance_update_scoped on public.class_attendance for update to authenticated using(public.current_user_has_permission('class_attendance.register',organization_id,site_id)) with check(public.current_user_has_permission('class_attendance.register',organization_id,site_id));
