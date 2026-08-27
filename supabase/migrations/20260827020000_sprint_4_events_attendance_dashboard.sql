-- Sprint 4: generic events, attendance and scoped dashboard metrics.

do $$ begin
  create type public.event_type as enum (
    'SERVICE','DISCIPLESHIP','COURSE','PRAYER','FAST','MINISTRY_MEETING',
    'CONFERENCE','RETREAT','OTHER'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.event_status as enum ('DRAFT','SCHEDULED','IN_PROGRESS','COMPLETED','CANCELLED');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.attendance_status as enum ('PRESENT','ABSENT','EXCUSED','LATE');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.check_in_method as enum ('MANUAL','QR','SELF_CHECKIN','IMPORT','FACE_RECOGNITION');
exception when duplicate_object then null;
end $$;

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid not null,
  event_type public.event_type not null,
  title text not null check (char_length(trim(title)) between 2 and 180),
  description text,
  start_at timestamptz not null,
  end_at timestamptz,
  location text,
  capacity integer check (capacity is null or capacity > 0),
  created_by uuid references public.user_accounts(id) on delete set null,
  status public.event_status not null default 'DRAFT',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,site_id) references public.sites(organization_id,id) on delete cascade,
  unique (organization_id,site_id,id),
  check (end_at is null or end_at > start_at)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  site_id uuid not null,
  event_id uuid not null,
  person_id uuid not null,
  status public.attendance_status not null default 'PRESENT',
  check_in_method public.check_in_method not null default 'MANUAL',
  check_in_at timestamptz,
  registered_by uuid references public.user_accounts(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,site_id,event_id)
    references public.events(organization_id,site_id,id) on delete cascade,
  foreign key (organization_id,site_id,person_id)
    references public.people(organization_id,site_id,id) on delete cascade,
  unique (event_id,person_id),
  check (check_in_method <> 'FACE_RECOGNITION')
);

create index events_site_start_idx on public.events(organization_id,site_id,start_at desc);
create index attendance_event_status_idx on public.attendance(event_id,status);
create index attendance_person_idx on public.attendance(person_id,created_at desc);

create trigger events_set_updated_at before update on public.events
for each row execute function public.set_updated_at();
create trigger attendance_set_updated_at before update on public.attendance
for each row execute function public.set_updated_at();

create or replace function public.protect_event_attendance_audit()
returns trigger language plpgsql set search_path='' as $$
begin
  if auth.uid() is not null then
    if tg_table_name='events' then
      if tg_op='INSERT' then new.created_by=auth.uid(); else new.created_by=old.created_by; end if;
    else
      if tg_op='INSERT' then new.registered_by=auth.uid(); else new.registered_by=old.registered_by; end if;
      if new.status in ('PRESENT','LATE') and new.check_in_at is null then new.check_in_at=now(); end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger events_protect_audit before insert or update on public.events
for each row execute function public.protect_event_attendance_audit();
create trigger attendance_protect_audit before insert or update on public.attendance
for each row execute function public.protect_event_attendance_audit();

insert into public.permissions(code,name,description) values
  ('events.read','Ver eventos','Consultar eventos dentro del alcance'),
  ('events.manage','Gestionar eventos','Crear y actualizar eventos'),
  ('attendance.read','Ver asistencia','Consultar asistencia y métricas autorizadas')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as (values
  ('SUPER_ADMIN','events.read'),('SUPER_ADMIN','events.manage'),('SUPER_ADMIN','attendance.read'),
  ('NATIONAL_PASTOR','events.read'),('NATIONAL_PASTOR','events.manage'),('NATIONAL_PASTOR','attendance.read'),
  ('SITE_PASTOR','events.read'),('SITE_PASTOR','events.manage'),('SITE_PASTOR','attendance.read'),
  ('SITE_ADMIN','events.read'),('SITE_ADMIN','events.manage'),('SITE_ADMIN','attendance.read'),
  ('MINISTRY_LEADER','events.read'),('MINISTRY_LEADER','events.manage'),('MINISTRY_LEADER','attendance.read'),
  ('DISCIPLESHIP_COORDINATOR','events.read'),('DISCIPLESHIP_COORDINATOR','events.manage'),('DISCIPLESHIP_COORDINATOR','attendance.read'),
  ('DISCIPLESHIP_TEACHER','events.read'),('DISCIPLESHIP_TEACHER','attendance.read'),('DISCIPLESHIP_TEACHER','attendance.register'),
  ('COURSE_TEACHER','events.read'),('COURSE_TEACHER','attendance.read'),('COURSE_TEACHER','attendance.register'),
  ('USHER','events.read'),('USHER','attendance.read'),
  ('MEMBER','events.read'),('MEMBER','attendance.read')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code
join public.permissions p on p.code=g.permission_code on conflict do nothing;

alter table public.events enable row level security;
alter table public.attendance enable row level security;
grant select,insert,update on public.events,public.attendance to authenticated;

create policy events_select_scoped on public.events for select to authenticated
using (public.current_user_has_permission('events.read',organization_id,site_id));
create policy events_insert_scoped on public.events for insert to authenticated
with check (public.current_user_has_permission('events.manage',organization_id,site_id));
create policy events_update_scoped on public.events for update to authenticated
using (public.current_user_has_permission('events.manage',organization_id,site_id))
with check (public.current_user_has_permission('events.manage',organization_id,site_id));

create policy attendance_select_scoped on public.attendance for select to authenticated
using (public.current_user_has_permission('attendance.read',organization_id,site_id));
create policy attendance_insert_scoped on public.attendance for insert to authenticated
with check (public.current_user_has_permission('attendance.register',organization_id,site_id));
create policy attendance_update_scoped on public.attendance for update to authenticated
using (public.current_user_has_permission('attendance.register',organization_id,site_id))
with check (public.current_user_has_permission('attendance.register',organization_id,site_id));

create or replace function public.dashboard_site_metrics(
  target_organization_id uuid,target_site_id uuid,period_start timestamptz,period_end timestamptz
)
returns table(registered_people bigint,event_attendance bigint,new_visitors bigint,active_events bigint)
language sql stable security invoker set search_path='' as $$
  select
    (select count(*) from public.people p where p.organization_id=target_organization_id and p.site_id=target_site_id),
    (select count(*) from public.attendance a where a.organization_id=target_organization_id and a.site_id=target_site_id and a.status in ('PRESENT','LATE') and a.check_in_at>=period_start and a.check_in_at<period_end),
    (select count(*) from public.people p where p.organization_id=target_organization_id and p.site_id=target_site_id and p.person_status='VISITOR' and p.first_visit_date>=period_start::date and p.first_visit_date<period_end::date),
    (select count(*) from public.events e where e.organization_id=target_organization_id and e.site_id=target_site_id and e.start_at>=period_start and e.start_at<period_end and e.status<>'CANCELLED');
$$;

revoke all on function public.dashboard_site_metrics(uuid,uuid,timestamptz,timestamptz) from public;
grant execute on function public.dashboard_site_metrics(uuid,uuid,timestamptz,timestamptz) to authenticated;
comment on function public.dashboard_site_metrics(uuid,uuid,timestamptz,timestamptz) is 'Dashboard metrics filtered by underlying RLS policies.';
