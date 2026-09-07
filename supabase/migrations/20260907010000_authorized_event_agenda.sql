-- Agenda contextual: eventos visibles por audiencia, alcance, sede y ministerio.
do $$ begin
  create type public.event_audience_type as enum ('PUBLIC','ALL_CRC','ALL_MEMBERS','NATIONAL','SITE','MINISTRY','ROLE','SPECIFIC_USERS');
exception when duplicate_object then null; end $$;

alter table public.events add column if not exists banner_url text;
alter table public.events add column if not exists modality text not null default 'IN_PERSON'
  check (modality in ('IN_PERSON','ONLINE','HYBRID'));
alter table public.events add column if not exists ministry_id uuid;
alter table public.events add column if not exists organizer_person_id uuid;
alter table public.events add column if not exists is_featured boolean not null default false;
alter table public.events add column if not exists is_restricted boolean not null default false;
alter table public.events add column if not exists published_at timestamptz;
alter table public.events add column if not exists archived_at timestamptz;
alter table public.events add column if not exists timezone text not null default 'America/Bogota';

do $$ begin
 alter table public.events add constraint events_ministry_fk foreign key(organization_id,site_id,ministry_id)
 references public.ministries(organization_id,site_id,id) on delete set null;
exception when duplicate_object then null; end $$;
do $$ begin
 alter table public.events add constraint events_organizer_fk foreign key(organization_id,site_id,organizer_person_id)
 references public.people(organization_id,site_id,id) on delete set null;
exception when duplicate_object then null; end $$;

-- Los eventos vigentes previos se consideran publicados y visibles para su sede.
update public.events set published_at=coalesce(published_at,created_at)
where status in ('SCHEDULED','IN_PROGRESS') and published_at is null;

create table if not exists public.event_audiences(
 id uuid primary key default gen_random_uuid(),
 event_id uuid not null references public.events(id) on delete cascade,
 audience_type public.event_audience_type not null,
 site_id uuid references public.sites(id) on delete cascade,
 ministry_id uuid references public.ministries(id) on delete cascade,
 role_id uuid references public.roles(id) on delete cascade,
 user_account_id uuid references public.user_accounts(id) on delete cascade,
 created_at timestamptz not null default now(),
 created_by uuid references public.user_accounts(id) on delete set null,
 check (
   (audience_type in ('PUBLIC','ALL_CRC','ALL_MEMBERS','NATIONAL') and site_id is null and ministry_id is null and role_id is null and user_account_id is null) or
   (audience_type='SITE' and site_id is not null and ministry_id is null and role_id is null and user_account_id is null) or
   (audience_type='MINISTRY' and ministry_id is not null and site_id is null and role_id is null and user_account_id is null) or
   (audience_type='ROLE' and role_id is not null and site_id is null and ministry_id is null and user_account_id is null) or
   (audience_type='SPECIFIC_USERS' and user_account_id is not null and site_id is null and ministry_id is null and role_id is null)
 )
);
create unique index if not exists event_audiences_unique_target on public.event_audiences(
 event_id,audience_type,coalesce(site_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(ministry_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(role_id,'00000000-0000-0000-0000-000000000000'::uuid),
 coalesce(user_account_id,'00000000-0000-0000-0000-000000000000'::uuid)
);
create index if not exists events_agenda_idx on public.events(organization_id,is_featured desc,start_at)
where status in ('SCHEDULED','IN_PROGRESS') and archived_at is null;
create index if not exists event_audiences_event_idx on public.event_audiences(event_id,audience_type);

create or replace function public.validate_event_audience_scope() returns trigger
language plpgsql security definer set search_path='' as $$
declare event_row record;
begin
 select organization_id,site_id into event_row from public.events where id=new.event_id;
 if new.audience_type='SITE' and not exists(select 1 from public.sites s where s.id=new.site_id and s.organization_id=event_row.organization_id) then raise exception 'EVENT_AUDIENCE_SITE_OUT_OF_SCOPE'; end if;
 if new.audience_type='MINISTRY' and not exists(select 1 from public.ministries m where m.id=new.ministry_id and m.organization_id=event_row.organization_id) then raise exception 'EVENT_AUDIENCE_MINISTRY_OUT_OF_SCOPE'; end if;
 if auth.uid() is not null then new.created_by=coalesce(old.created_by,auth.uid()); end if;
 return new;
end; $$;
drop trigger if exists event_audiences_validate_scope on public.event_audiences;
create trigger event_audiences_validate_scope before insert or update on public.event_audiences for each row execute function public.validate_event_audience_scope();

create or replace function public.prepare_event_publication() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.status in ('SCHEDULED','IN_PROGRESS') and new.published_at is null then new.published_at=now(); end if;
 return new;
end; $$;
drop trigger if exists events_prepare_publication on public.events;
create trigger events_prepare_publication before insert or update on public.events for each row execute function public.prepare_event_publication();

create or replace function public.ensure_event_default_audience() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.published_at is not null and not exists(select 1 from public.event_audiences ea where ea.event_id=new.id) then
  insert into public.event_audiences(event_id,audience_type,site_id,created_by) values(new.id,'SITE',new.site_id,new.created_by) on conflict do nothing;
 end if;
 return new;
end; $$;
drop trigger if exists events_default_audience on public.events;
create trigger events_default_audience after insert or update of published_at,status on public.events for each row execute function public.ensure_event_default_audience();

insert into public.event_audiences(event_id,audience_type,site_id)
select e.id,'SITE',e.site_id from public.events e
where e.published_at is not null and not exists(select 1 from public.event_audiences ea where ea.event_id=e.id)
on conflict do nothing;

create or replace function public.can_user_view_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.events e
  where e.id=target_event_id and e.published_at is not null and e.archived_at is null
   and e.status in ('SCHEDULED','IN_PROGRESS') and coalesce(e.end_at,e.start_at)>=now()
   and (
    exists(select 1 from public.event_audiences ea where ea.event_id=e.id and ea.audience_type='PUBLIC')
    or (auth.uid() is not null and exists(select 1 from public.user_accounts ua where ua.id=auth.uid() and ua.access_status='ACTIVE') and (
      exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
       and ur.organization_id=e.organization_id and r.code='SUPER_ADMIN')
      or (not e.is_restricted and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
       and ur.organization_id=e.organization_id and r.code='NATIONAL_PASTOR' and ur.scope_type='ORGANIZATION'))
      or (not e.is_restricted and exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
       and ur.organization_id=e.organization_id and r.code='SITE_PASTOR' and(ur.scope_type='ORGANIZATION' or ur.site_id=e.site_id)))
      or exists(select 1 from public.event_audiences ea where ea.event_id=e.id and(
        ea.audience_type in ('ALL_CRC','NATIONAL')
        or(ea.audience_type='ALL_MEMBERS' and exists(select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id where ua.id=auth.uid() and p.person_status<>'VISITOR'))
        or(ea.audience_type='SITE' and exists(select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id where ua.id=auth.uid() and p.site_id=ea.site_id))
        or(ea.audience_type='MINISTRY' and exists(select 1 from public.user_accounts ua join public.person_ministries pm on pm.person_id=ua.person_id where ua.id=auth.uid() and pm.ministry_id=ea.ministry_id and pm.active and(pm.end_date is null or pm.end_date>=current_date)))
        or(ea.audience_type='ROLE' and exists(select 1 from public.user_roles ur where ur.user_account_id=auth.uid() and ur.role_id=ea.role_id and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())))
        or(ea.audience_type='SPECIFIC_USERS' and ea.user_account_id=auth.uid())
      ))
    ))
   )
 );
$$;
revoke all on function public.can_user_view_event(uuid) from public;
grant execute on function public.can_user_view_event(uuid) to authenticated;

drop policy if exists events_select_scoped on public.events;
drop policy if exists events_select_authorized_agenda on public.events;
create policy events_select_authorized_agenda on public.events for select to authenticated
using(public.can_user_view_event(id) or public.current_user_has_permission('events.manage',organization_id,site_id));

alter table public.event_audiences enable row level security;
grant select,insert,update,delete on public.event_audiences to authenticated;
create policy event_audiences_select on public.event_audiences for select to authenticated
using(public.can_user_view_event(event_id) or exists(select 1 from public.events e where e.id=event_id and public.current_user_has_permission('events.manage',e.organization_id,e.site_id)));
create policy event_audiences_manage on public.event_audiences for all to authenticated
using(exists(select 1 from public.events e where e.id=event_id and public.current_user_has_permission('events.manage',e.organization_id,e.site_id)))
with check(exists(select 1 from public.events e where e.id=event_id and public.current_user_has_permission('events.manage',e.organization_id,e.site_id)));

create or replace function public.get_my_upcoming_events(result_limit integer default 12)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.is_featured desc,q.start_at),'[]'::jsonb) from(
  select e.id,e.title,e.description,e.start_at,e.end_at,e.timezone,e.banner_url,e.modality,e.location,e.event_type,
   e.is_featured,s.id site_id,s.name site_name,m.name ministry_name,
   trim(concat_ws(' ',p.first_name,p.last_name)) organizer_name
  from public.events e join public.sites s on s.id=e.site_id
  left join public.ministries m on m.id=e.ministry_id
  left join public.people p on p.id=e.organizer_person_id
  where public.can_user_view_event(e.id) and coalesce(e.end_at,e.start_at)>=now()
  order by e.is_featured desc,e.start_at limit least(greatest(result_limit,1),20)
 )q;
$$;
create or replace function public.get_visible_event(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select case when public.can_user_view_event(e.id) then jsonb_build_object(
  'id',e.id,'title',e.title,'description',e.description,'start_at',e.start_at,'end_at',e.end_at,'timezone',e.timezone,
  'banner_url',e.banner_url,'modality',e.modality,'location',e.location,'event_type',e.event_type,'is_featured',e.is_featured,
  'site_id',s.id,'site_name',s.name,'ministry_name',m.name,'organizer_name',trim(concat_ws(' ',p.first_name,p.last_name))
 ) else null end from public.events e join public.sites s on s.id=e.site_id left join public.ministries m on m.id=e.ministry_id left join public.people p on p.id=e.organizer_person_id where e.id=target_event_id;
$$;
revoke all on function public.get_my_upcoming_events(integer),public.get_visible_event(uuid) from public;
grant execute on function public.get_my_upcoming_events(integer),public.get_visible_event(uuid) to authenticated;

create or replace function public.capture_event_agenda_audit() returns trigger
language plpgsql security definer set search_path='' as $$
declare audit_org uuid; audit_site uuid; affected_id uuid; action_name text;
begin
 if tg_table_name='event_audiences' then
  affected_id=case when tg_op='DELETE' then old.event_id else new.event_id end;
  select organization_id,site_id into audit_org,audit_site from public.events where id=affected_id;
  action_name='EVENT_AUDIENCE_UPDATED';
 else
  affected_id=case when tg_op='DELETE' then old.id else new.id end;
  audit_org=case when tg_op='DELETE' then old.organization_id else new.organization_id end;
  audit_site=case when tg_op='DELETE' then old.site_id else new.site_id end;
  action_name=case when tg_op='INSERT' then 'EVENT_CREATED' when new.status='CANCELLED' and old.status is distinct from new.status then 'EVENT_CANCELLED' when new.published_at is not null and old.published_at is null then 'EVENT_PUBLISHED' else 'EVENT_UPDATED' end;
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
 values(audit_org,audit_site,auth.uid(),action_name,'EVENT',affected_id,case when tg_op='INSERT' then null else to_jsonb(old) end,case when tg_op='DELETE' then null else to_jsonb(new) end);
 return case when tg_op='DELETE' then old else new end;
end; $$;
drop trigger if exists events_agenda_audit on public.events;
create trigger events_agenda_audit after insert or update or delete on public.events for each row execute function public.capture_event_agenda_audit();
drop trigger if exists event_audiences_audit on public.event_audiences;
create trigger event_audiences_audit after insert or update or delete on public.event_audiences for each row execute function public.capture_event_agenda_audit();

notify pgrst,'reload schema';
