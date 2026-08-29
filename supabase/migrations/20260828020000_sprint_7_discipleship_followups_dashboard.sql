-- Sprint 7: discipleship followups, calls, visits and scoped dashboard metrics.

create table public.discipleship_followups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  site_id uuid not null,
  person_id uuid not null,
  group_id uuid not null,
  session_id uuid,
  followup_date date not null default current_date,
  call_made boolean not null default false,
  visit_made boolean not null default false,
  requires_followup boolean not null default false,
  notes text,
  leader_person_id uuid not null,
  created_by uuid references public.user_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,site_id,person_id) references public.people(organization_id,site_id,id) on delete cascade,
  foreign key (organization_id,site_id,group_id) references public.training_groups(organization_id,site_id,id) on delete cascade,
  foreign key (organization_id,site_id,session_id) references public.class_sessions(organization_id,site_id,id) on delete restrict,
  foreign key (organization_id,site_id,leader_person_id) references public.people(organization_id,site_id,id) on delete restrict,
  check (call_made or visit_made or requires_followup or nullif(trim(notes),'') is not null)
);

create unique index discipleship_followups_session_person_unique_idx
  on public.discipleship_followups(session_id,person_id) where session_id is not null;
create index discipleship_followups_pending_idx
  on public.discipleship_followups(organization_id,site_id,followup_date desc) where requires_followup;
create index discipleship_followups_person_idx
  on public.discipleship_followups(person_id,followup_date desc);

create trigger discipleship_followups_set_updated_at before update on public.discipleship_followups
for each row execute function public.set_updated_at();

create or replace function public.validate_discipleship_followup()
returns trigger language plpgsql set search_path='' as $$
begin
  if not exists (
    select 1 from public.enrollments e
    where e.group_id=new.group_id and e.person_id=new.person_id
      and e.organization_id=new.organization_id and e.site_id=new.site_id
  ) then raise exception 'Person must be enrolled in the followup group'; end if;
  if new.session_id is not null and not exists (
    select 1 from public.class_sessions cs
    where cs.id=new.session_id and cs.group_id=new.group_id
  ) then raise exception 'Followup session must belong to the selected group'; end if;
  if auth.uid() is not null then
    if tg_op='INSERT' then new.created_by=auth.uid(); else new.created_by=old.created_by; end if;
  end if;
  return new;
end;
$$;
create trigger discipleship_followups_validate before insert or update on public.discipleship_followups
for each row execute function public.validate_discipleship_followup();

insert into public.permissions(code,name,description) values
  ('followups.read','Ver seguimientos','Consultar seguimiento administrativo de discipulado'),
  ('followups.manage','Gestionar seguimientos','Registrar llamadas, visitas y seguimiento')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as (values
  ('SUPER_ADMIN','followups.read'),('SUPER_ADMIN','followups.manage'),
  ('NATIONAL_PASTOR','followups.read'),('NATIONAL_PASTOR','followups.manage'),
  ('SITE_PASTOR','followups.read'),('SITE_PASTOR','followups.manage'),
  ('SITE_ADMIN','followups.read'),('SITE_ADMIN','followups.manage'),
  ('DISCIPLESHIP_COORDINATOR','followups.read'),('DISCIPLESHIP_COORDINATOR','followups.manage'),
  ('DISCIPLESHIP_TEACHER','followups.read'),('DISCIPLESHIP_TEACHER','followups.manage'),
  ('COURSE_TEACHER','followups.read'),('COURSE_TEACHER','followups.manage')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code
join public.permissions p on p.code=g.permission_code on conflict do nothing;

alter table public.discipleship_followups enable row level security;
grant select,insert,update on public.discipleship_followups to authenticated;
create policy discipleship_followups_select_scoped on public.discipleship_followups for select to authenticated
using (public.current_user_has_permission('followups.read',organization_id,site_id));
create policy discipleship_followups_insert_scoped on public.discipleship_followups for insert to authenticated
with check (public.current_user_has_permission('followups.manage',organization_id,site_id));
create policy discipleship_followups_update_scoped on public.discipleship_followups for update to authenticated
using (public.current_user_has_permission('followups.manage',organization_id,site_id))
with check (public.current_user_has_permission('followups.manage',organization_id,site_id));

create or replace function public.discipleship_site_metrics(target_organization_id uuid,target_site_id uuid)
returns table(pending_followups bigint,pending_calls bigint,pending_visits bigint,average_progress numeric)
language sql stable security invoker set search_path='' as $$
  select
    (select count(*) from public.discipleship_followups f where f.organization_id=target_organization_id and f.site_id=target_site_id and f.requires_followup),
    (select count(*) from public.discipleship_followups f where f.organization_id=target_organization_id and f.site_id=target_site_id and f.requires_followup and not f.call_made),
    (select count(*) from public.discipleship_followups f where f.organization_id=target_organization_id and f.site_id=target_site_id and f.requires_followup and not f.visit_made),
    (select coalesce(round(avg(e.progress_percentage),2),0) from public.enrollments e where e.organization_id=target_organization_id and e.site_id=target_site_id and e.status in ('ENROLLED','ACTIVE','PAUSED'));
$$;
revoke all on function public.discipleship_site_metrics(uuid,uuid) from public;
grant execute on function public.discipleship_site_metrics(uuid,uuid) to authenticated;
comment on table public.discipleship_followups is 'Administrative followups only; sensitive pastoral notes require a separate restricted module.';
