-- Sprint 8: authorized reports, export requests and immutable audit logs.

do $$ begin create type public.report_export_format as enum ('CSV','XLSX','PDF'); exception when duplicate_object then null; end $$;
do $$ begin create type public.report_export_status as enum ('PENDING','PROCESSING','COMPLETED','FAILED','EXPIRED'); exception when duplicate_object then null; end $$;

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  site_id uuid,
  user_id uuid references public.user_accounts(id) on delete set null,
  action text not null check (char_length(trim(action)) between 3 and 120),
  entity_type text not null check (char_length(trim(entity_type)) between 2 and 120),
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now(),
  foreign key (organization_id,site_id) references public.sites(organization_id,id) on delete restrict
);

create table public.report_exports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  site_id uuid not null,
  report_code text not null check (char_length(trim(report_code)) between 2 and 100),
  export_format public.report_export_format not null,
  filters jsonb not null default '{}'::jsonb,
  status public.report_export_status not null default 'PENDING',
  file_path text,
  requested_by uuid references public.user_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz,
  foreign key (organization_id,site_id) references public.sites(organization_id,id) on delete cascade,
  check ((status='COMPLETED' and file_path is not null and completed_at is not null) or status<>'COMPLETED'),
  check (expires_at is null or expires_at>created_at)
);

create index audit_logs_scope_date_idx on public.audit_logs(organization_id,site_id,created_at desc);
create index audit_logs_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);
create index audit_logs_user_idx on public.audit_logs(user_id,created_at desc);
create index report_exports_scope_date_idx on public.report_exports(organization_id,site_id,created_at desc);

create or replace function public.capture_audit_log()
returns trigger language plpgsql security definer set search_path='' as $$
declare payload jsonb; previous jsonb; audit_org uuid; audit_site uuid; audit_id uuid; action_name text;
begin
  if tg_op='DELETE' then payload=null; previous=to_jsonb(old); else payload=to_jsonb(new); previous=case when tg_op='UPDATE' then to_jsonb(old) else null end; end if;
  audit_org=coalesce((payload->>'organization_id')::uuid,(previous->>'organization_id')::uuid);
  audit_site=coalesce((payload->>'site_id')::uuid,(previous->>'site_id')::uuid);
  audit_id=coalesce((payload->>'id')::uuid,(previous->>'id')::uuid);
  action_name=(case tg_table_name when 'people' then 'PERSON' when 'user_roles' then 'ROLE' when 'discipleship_followups' then 'FOLLOWUP' else upper(tg_table_name) end)||'_'||(case tg_op when 'INSERT' then 'CREATED' when 'UPDATE' then 'UPDATED' else 'DELETED' end);
  insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
  values(audit_org,audit_site,auth.uid(),action_name,upper(tg_table_name),audit_id,previous,payload);
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function public.capture_audit_log() from public;

create trigger people_audit after insert or update or delete on public.people for each row execute function public.capture_audit_log();
create trigger user_roles_audit after insert or update or delete on public.user_roles for each row execute function public.capture_audit_log();
create trigger attendance_audit after insert or update on public.attendance for each row execute function public.capture_audit_log();
create trigger enrollments_audit after insert or update on public.enrollments for each row execute function public.capture_audit_log();
create trigger class_attendance_audit after insert or update on public.class_attendance for each row execute function public.capture_audit_log();
create trigger discipleship_followups_audit after insert or update on public.discipleship_followups for each row execute function public.capture_audit_log();
create trigger report_exports_audit after insert or update on public.report_exports for each row execute function public.capture_audit_log();

create or replace function public.protect_report_export_audit()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='INSERT' and auth.uid() is not null then new.requested_by=auth.uid(); end if;
  if tg_op='UPDATE' then new.requested_by=old.requested_by; end if;
  return new;
end;
$$;
create trigger report_exports_protect before insert or update on public.report_exports for each row execute function public.protect_report_export_audit();

insert into public.permissions(code,name,description) values
  ('reports.read','Ver reportes','Consultar reportes dentro del alcance autorizado'),
  ('reports.export','Exportar reportes','Solicitar exportaciones CSV, XLSX o PDF'),
  ('audit.read','Ver auditoría','Consultar la bitácora inmutable dentro del alcance')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as (values
 ('SUPER_ADMIN','reports.read'),('SUPER_ADMIN','reports.export'),('SUPER_ADMIN','audit.read'),
 ('NATIONAL_PASTOR','reports.read'),('NATIONAL_PASTOR','reports.export'),('NATIONAL_PASTOR','audit.read'),
 ('SITE_PASTOR','reports.read'),('SITE_PASTOR','reports.export'),('SITE_PASTOR','audit.read'),
 ('SITE_ADMIN','reports.read'),('SITE_ADMIN','reports.export'),('SITE_ADMIN','audit.read'),
 ('DISCIPLESHIP_COORDINATOR','reports.read'),('DISCIPLESHIP_COORDINATOR','reports.export'),
 ('MINISTRY_LEADER','reports.read'),('DISCIPLESHIP_TEACHER','reports.read'),('COURSE_TEACHER','reports.read')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

alter table public.audit_logs enable row level security;
alter table public.report_exports enable row level security;
grant select on public.audit_logs to authenticated;
grant select,insert on public.report_exports to authenticated;
create policy audit_logs_select_scoped on public.audit_logs for select to authenticated
using (public.current_user_has_permission('audit.read',organization_id,site_id));
create policy report_exports_select_scoped on public.report_exports for select to authenticated
using (public.current_user_has_permission('reports.export',organization_id,site_id));
create policy report_exports_insert_scoped on public.report_exports for insert to authenticated
with check (public.current_user_has_permission('reports.export',organization_id,site_id));

create or replace function public.report_site_summary(target_organization_id uuid,target_site_id uuid,period_start timestamptz,period_end timestamptz)
returns table(people_count bigint,new_visitors bigint,event_attendance bigint,active_enrollments bigint,pending_followups bigint,lessons_taught bigint)
language sql stable security invoker set search_path='' as $$
 select
  (select count(*) from public.people p where p.organization_id=target_organization_id and p.site_id=target_site_id),
  (select count(*) from public.people p where p.organization_id=target_organization_id and p.site_id=target_site_id and p.person_status='VISITOR' and p.first_visit_date>=period_start::date and p.first_visit_date<period_end::date),
  (select count(*) from public.attendance a where a.organization_id=target_organization_id and a.site_id=target_site_id and a.status in('PRESENT','LATE') and a.created_at>=period_start and a.created_at<period_end),
  (select count(*) from public.enrollments e where e.organization_id=target_organization_id and e.site_id=target_site_id and e.status in('ENROLLED','ACTIVE','PAUSED')),
  (select count(*) from public.discipleship_followups f where f.organization_id=target_organization_id and f.site_id=target_site_id and f.requires_followup),
  (select count(*) from public.class_sessions cs where cs.organization_id=target_organization_id and cs.site_id=target_site_id and cs.status='COMPLETED' and cs.session_date>=period_start::date and cs.session_date<period_end::date)
 where public.current_user_has_permission('reports.read',target_organization_id,target_site_id);
$$;
revoke all on function public.report_site_summary(uuid,uuid,timestamptz,timestamptz) from public;
grant execute on function public.report_site_summary(uuid,uuid,timestamptz,timestamptz) to authenticated;
comment on table public.audit_logs is 'Append-only application audit trail; authenticated roles receive SELECT only through RLS.';
