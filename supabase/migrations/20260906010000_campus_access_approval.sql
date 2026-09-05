-- Acceso progresivo: persona, acceso al Campus y privilegios son conceptos independientes.
do $$ begin
 create type public.campus_access_status as enum ('PENDING_APPROVAL','ACTIVE','SUSPENDED','REJECTED','ARCHIVED');
exception when duplicate_object then null; end $$;

alter table public.user_accounts add column if not exists access_status public.campus_access_status not null default 'PENDING_APPROVAL';
alter table public.user_accounts add column if not exists requested_site_id uuid references public.sites(id) on delete set null;
alter table public.user_accounts add column if not exists access_decided_by uuid references public.user_accounts(id) on delete set null;
alter table public.user_accounts add column if not exists access_decided_at timestamptz;
alter table public.user_accounts add column if not exists access_observations text;

-- Compatibilidad: no bloquear cuentas que ya funcionaban antes de esta migración.
update public.user_accounts ua set access_status='ACTIVE'
where ua.person_id is not null or exists(select 1 from public.user_roles ur where ur.user_account_id=ua.id and ur.active);

create table if not exists public.access_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete restrict,
 site_id uuid not null,
 user_account_id uuid not null unique references public.user_accounts(id) on delete cascade,
 person_id uuid not null unique references public.people(id) on delete cascade,
 status public.campus_access_status not null default 'PENDING_APPROVAL',
 possible_duplicate boolean not null default false,
 duplicate_detail text,
 reviewed_by uuid references public.user_accounts(id) on delete set null,
 reviewed_at timestamptz,
 observations text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(organization_id,site_id) references public.sites(organization_id,id) on delete restrict,
 check(status<>'ACTIVE' or reviewed_at is not null)
);
create index if not exists access_requests_queue_idx on public.access_requests(site_id,status,created_at desc);
create trigger access_requests_set_updated_at before update on public.access_requests for each row execute function public.set_updated_at();

create table if not exists public.user_notifications(
 id uuid primary key default gen_random_uuid(), user_account_id uuid not null references public.user_accounts(id) on delete cascade,
 kind text not null, title text not null, message text not null, link text, read_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.email_delivery_queue(
 id uuid primary key default gen_random_uuid(), user_account_id uuid references public.user_accounts(id) on delete cascade,
 recipient_email text not null, template_code text not null, payload jsonb not null default '{}'::jsonb,
 status text not null default 'PENDING' check(status in('PENDING','SENT','FAILED')), created_at timestamptz not null default now(), sent_at timestamptz
);

insert into public.permissions(code,name,description) values
 ('campus.access','Acceder al Campus','Acceso base a la experiencia personal'),
 ('access_requests.review','Revisar solicitudes de acceso','Aprobar o rechazar acceso general al Campus dentro del alcance')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','access_requests.review'),('NATIONAL_PASTOR','access_requests.review'),('SITE_PASTOR','access_requests.review')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

create or replace function public.current_user_access_status() returns public.campus_access_status
language sql stable security definer set search_path='' as $$ select ua.access_status from public.user_accounts ua where ua.id=auth.uid() $$;
revoke all on function public.current_user_access_status() from public; grant execute on function public.current_user_access_status() to authenticated;

-- Un acceso suspendido/rechazado invalida también permisos previamente asignados.
create or replace function public.current_user_has_permission(required_permission text,target_organization_id uuid,target_site_id uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) and ur.organization_id=target_organization_id and p.code=required_permission and(ur.scope_type='ORGANIZATION' or(target_site_id is not null and ur.scope_type='SITE' and ur.site_id=target_site_id)));
$$;
create or replace function public.current_user_has_any_permission(required_permission text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) and p.code=required_permission);
$$;

create or replace function public.get_my_portal_context() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb;
begin
 select * into ua from public.user_accounts where id=auth.uid();
 if ua.id is null then return jsonb_build_object('status','PENDING_APPROVAL','permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name into person from public.people p join public.sites s on s.id=p.site_id where p.id=ua.person_id;
 select coalesce(jsonb_agg(distinct p.code),'[]'::jsonb) into effective_permissions from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions p on p.id=rp.permission_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 select coalesce(jsonb_agg(distinct r.code),'[]'::jsonb) into roles_json from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 return jsonb_build_object('status',ua.access_status,'personId',person.id,'firstName',person.first_name,'lastName',person.last_name,'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,'permissions',effective_permissions,'roles',roles_json);
end $$;
revoke all on function public.get_my_portal_context() from public; grant execute on function public.get_my_portal_context() to authenticated;

create or replace function public.review_access_request(target_request_id uuid,decision text,given_observations text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare request_row record; next_status public.campus_access_status; recipient text;
begin
 select ar.* into request_row from public.access_requests ar where ar.id=target_request_id for update;
 if request_row.id is null then raise exception 'REQUEST_NOT_FOUND'; end if;
 if request_row.user_account_id=auth.uid() then raise exception 'SELF_APPROVAL_DENIED'; end if;
 if not public.current_user_has_permission('access_requests.review',request_row.organization_id,request_row.site_id) then raise exception 'ACCESS_DENIED'; end if;
 next_status:=case upper(decision) when 'APPROVE' then 'ACTIVE'::public.campus_access_status when 'REJECT' then 'REJECTED'::public.campus_access_status when 'SUSPEND' then 'SUSPENDED'::public.campus_access_status else 'PENDING_APPROVAL'::public.campus_access_status end;
 update public.access_requests set status=next_status,reviewed_by=auth.uid(),reviewed_at=case when next_status='PENDING_APPROVAL' then null else now() end,observations=nullif(trim(given_observations),'') where id=request_row.id;
 update public.user_accounts set access_status=next_status,access_decided_by=case when next_status='PENDING_APPROVAL' then null else auth.uid() end,access_decided_at=case when next_status='PENDING_APPROVAL' then null else now() end,access_observations=nullif(trim(given_observations),'') where id=request_row.user_account_id;
 if next_status='ACTIVE' then
  insert into public.user_notifications(user_account_id,kind,title,message,link) values(request_row.user_account_id,'CAMPUS_ACCESS_APPROVED','Tu acceso fue habilitado','Tu acceso a CRC Conecta ha sido habilitado.','/campus');
  select lower(trim(email)) into recipient from auth.users where id=request_row.user_account_id;
  if recipient is not null then insert into public.email_delivery_queue(user_account_id,recipient_email,template_code,payload) values(request_row.user_account_id,recipient,'CAMPUS_ACCESS_APPROVED',jsonb_build_object('link','/campus')); end if;
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(request_row.organization_id,request_row.site_id,auth.uid(),case next_status when 'ACTIVE' then 'CAMPUS_ACCESS_APPROVED' when 'REJECTED' then 'CAMPUS_ACCESS_REJECTED' when 'SUSPENDED' then 'CAMPUS_ACCESS_SUSPENDED' else 'ACCESS_REQUEST_RETAINED' end,'ACCESS_REQUEST',request_row.id,jsonb_build_object('status',request_row.status),jsonb_build_object('status',next_status,'observations',given_observations));
 return jsonb_build_object('id',request_row.id,'status',next_status);
end $$;
revoke all on function public.review_access_request(uuid,text,text) from public; grant execute on function public.review_access_request(uuid,text,text) to authenticated;

-- Impide autoelevación y que un gestor conceda permisos que él no posee.
create or replace function public.protect_role_elevation() returns trigger language plpgsql set search_path='' as $$
begin
 if auth.uid() is null then return case when tg_op='DELETE' then old else new end; end if;
 if coalesce(new.user_account_id,old.user_account_id)=auth.uid() then raise exception 'SELF_PRIVILEGE_ESCALATION_DENIED'; end if;
 if tg_op='INSERT' and exists(select 1 from public.role_permissions rp join public.permissions p on p.id=rp.permission_id where rp.role_id=new.role_id and not public.current_user_has_permission(p.code,new.organization_id,new.site_id)) then raise exception 'CANNOT_GRANT_SUPERIOR_PERMISSION'; end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists user_roles_prevent_elevation on public.user_roles;
create trigger user_roles_prevent_elevation before insert or update or delete on public.user_roles for each row execute function public.protect_role_elevation();

create or replace function public.audit_role_permission_change() returns trigger language plpgsql security definer set search_path='' as $$
declare org_id uuid; site uuid; action_name text; affected_id uuid;
begin
 if tg_table_name='user_roles' then org_id=coalesce(new.organization_id,old.organization_id);site=coalesce(new.site_id,old.site_id);affected_id=coalesce(new.id,old.id);action_name=case when tg_op='INSERT' then 'ROLE_ASSIGNED' when tg_op='DELETE' or(old.active and not new.active) then 'ROLE_REMOVED' else 'ROLE_ASSIGNED' end;
 else select ur.organization_id,ur.site_id into org_id,site from public.user_roles ur where ur.user_account_id=auth.uid() and ur.active order by ur.scope_type limit 1;affected_id=coalesce(new.role_id,old.role_id);action_name=case when tg_op='DELETE' then 'PERMISSION_REVOKED' else 'PERMISSION_GRANTED' end; end if;
 if org_id is not null then insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(org_id,site,auth.uid(),action_name,upper(tg_table_name),affected_id,case when tg_op='INSERT' then null else to_jsonb(old) end,case when tg_op='DELETE' then null else to_jsonb(new) end);end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists user_roles_explicit_audit on public.user_roles;create trigger user_roles_explicit_audit after insert or update or delete on public.user_roles for each row execute function public.audit_role_permission_change();
drop trigger if exists role_permissions_explicit_audit on public.role_permissions;create trigger role_permissions_explicit_audit after insert or delete on public.role_permissions for each row execute function public.audit_role_permission_change();

alter table public.access_requests enable row level security; alter table public.user_notifications enable row level security; alter table public.email_delivery_queue enable row level security;
grant select on public.access_requests,public.user_notifications to authenticated;
create policy access_requests_own on public.access_requests for select to authenticated using(user_account_id=auth.uid());
create policy access_requests_review_scope on public.access_requests for select to authenticated using(public.current_user_has_permission('access_requests.review',organization_id,site_id));
create policy notifications_own on public.user_notifications for select to authenticated using(user_account_id=auth.uid());
drop policy if exists people_select_own_profile on public.people;
create policy people_select_own_profile on public.people for select to authenticated using(public.current_user_access_status()='ACTIVE' and exists(select 1 from public.user_accounts ua where ua.id=auth.uid() and ua.person_id=people.id));

-- El enlace creado por el RPC existente queda pendiente aunque el cliente sea manipulado.
create or replace function public.create_pending_request_after_self_registration() returns trigger
language plpgsql security definer set search_path='' as $$
declare person record;
begin
 if new.person_id is null or old.person_id is not null then return new; end if;
 select p.id,p.organization_id,p.site_id,p.self_registered_at into person from public.people p where p.id=new.person_id;
 if person.self_registered_at is null then return new; end if;
 update public.user_accounts set requested_site_id=person.site_id,access_status='PENDING_APPROVAL',access_decided_by=null,access_decided_at=null where id=new.id;
 insert into public.access_requests(organization_id,site_id,user_account_id,person_id,status) values(person.organization_id,person.site_id,new.id,person.id,'PENDING_APPROVAL') on conflict(user_account_id) do update set site_id=excluded.site_id,status='PENDING_APPROVAL',updated_at=now();
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values) values(person.organization_id,person.site_id,new.id,'ACCESS_REQUEST_CREATED','ACCESS_REQUEST',person.id,jsonb_build_object('status','PENDING_APPROVAL'));
 return new;
end $$;
drop trigger if exists user_accounts_create_pending_request on public.user_accounts;
create trigger user_accounts_create_pending_request after update of person_id on public.user_accounts for each row execute function public.create_pending_request_after_self_registration();

notify pgrst,'reload schema';
