-- Gestión integral de Agenda sobre las tablas events/event_audiences existentes.
-- La autorización se resuelve por permiso efectivo, scope, sede y ministerio.

alter table public.events add column if not exists virtual_url text;
alter table public.events add column if not exists additional_info text;
alter table public.events add column if not exists updated_by uuid references public.user_accounts(id) on delete set null;
alter table public.events add column if not exists cancelled_at timestamptz;
alter table public.events add column if not exists cancelled_by uuid references public.user_accounts(id) on delete set null;
alter table public.events add column if not exists cancellation_reason text;
alter table public.event_audiences add column if not exists role_scope_site_id uuid references public.sites(id) on delete cascade;

insert into public.permissions(code,name,description) values
 ('events.create','Crear actividades','Crear actividades dentro del alcance autorizado'),
 ('events.update','Editar actividades','Editar actividades dentro del alcance autorizado'),
 ('events.cancel','Cancelar actividades','Cancelar actividades sin eliminarlas'),
 ('events.archive','Archivar actividades','Retirar actividades conservando su historial'),
 ('events.publish','Publicar actividades','Publicar actividades autorizadas'),
 ('events.manage_site','Gestionar agenda de sede','Gestionar audiencias dentro de una sede'),
 ('events.manage_ministry','Gestionar agenda de ministerio','Gestionar actividades del ministerio dirigido'),
 ('events.manage_national','Gestionar agenda nacional','Gestionar actividades de alcance nacional'),
 ('events.view_history','Ver histórico de agenda','Consultar actividades finalizadas, canceladas o archivadas')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','events.create'),('SUPER_ADMIN','events.update'),('SUPER_ADMIN','events.cancel'),('SUPER_ADMIN','events.archive'),('SUPER_ADMIN','events.publish'),('SUPER_ADMIN','events.manage_site'),('SUPER_ADMIN','events.manage_ministry'),('SUPER_ADMIN','events.manage_national'),('SUPER_ADMIN','events.view_history'),
 ('NATIONAL_PASTOR','events.create'),('NATIONAL_PASTOR','events.update'),('NATIONAL_PASTOR','events.cancel'),('NATIONAL_PASTOR','events.archive'),('NATIONAL_PASTOR','events.publish'),('NATIONAL_PASTOR','events.manage_site'),('NATIONAL_PASTOR','events.manage_ministry'),('NATIONAL_PASTOR','events.manage_national'),('NATIONAL_PASTOR','events.view_history'),
 ('SITE_PASTOR','events.create'),('SITE_PASTOR','events.update'),('SITE_PASTOR','events.cancel'),('SITE_PASTOR','events.archive'),('SITE_PASTOR','events.publish'),('SITE_PASTOR','events.manage_site'),('SITE_PASTOR','events.manage_ministry'),('SITE_PASTOR','events.view_history'),
 ('MINISTRY_LEADER','events.create'),('MINISTRY_LEADER','events.update'),('MINISTRY_LEADER','events.cancel'),('MINISTRY_LEADER','events.publish'),('MINISTRY_LEADER','events.manage_ministry'),('MINISTRY_LEADER','events.view_history')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code
on conflict do nothing;

create or replace function public.current_user_leads_ministry(target_ministry_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua
  join public.ministries m on m.leader_person_id=ua.person_id
  join public.person_ministries pm on pm.person_id=ua.person_id and pm.ministry_id=m.id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and m.id=target_ministry_id and m.active
    and pm.active and(pm.end_date is null or pm.end_date>=current_date)
 );
$$;

create or replace function public.can_user_manage_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.events e where e.id=target_event_id and(
   public.current_user_has_permission('events.manage_national',e.organization_id,null)
   or public.current_user_has_permission('events.manage_site',e.organization_id,e.site_id)
   or(e.ministry_id is not null and public.current_user_has_permission('events.manage_ministry',e.organization_id,e.site_id) and public.current_user_leads_ministry(e.ministry_id))
  )
 );
$$;

revoke all on function public.current_user_leads_ministry(uuid),public.can_user_manage_event(uuid) from public;
grant execute on function public.current_user_leads_ministry(uuid),public.can_user_manage_event(uuid) to authenticated;

create or replace function public.get_my_event_management_context()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor record; org_id uuid; can_national boolean; result jsonb;
begin
 select ua.person_id into actor from public.user_accounts ua where ua.id=auth.uid() and ua.access_status='ACTIVE';
 select ur.organization_id into org_id from public.user_roles ur where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) order by ur.scope_type limit 1;
 if actor.person_id is null or org_id is null then return jsonb_build_object('canCreate',false,'canViewHistory',false,'sites','[]'::jsonb,'ministries','[]'::jsonb,'roles','[]'::jsonb); end if;
 can_national:=public.current_user_has_permission('events.manage_national',org_id,null);
 select jsonb_build_object(
  'canCreate',public.current_user_has_any_permission('events.create'),
  'canPublish',public.current_user_has_any_permission('events.publish'),
  'canViewHistory',public.current_user_has_any_permission('events.view_history'),
  'canManageNational',can_national,
  'canManageSite',exists(select 1 from public.sites sx where sx.organization_id=org_id and public.current_user_has_permission('events.manage_site',org_id,sx.id)),
  'sites',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.sites s where s.organization_id=org_id and s.active and(can_national or public.current_user_has_permission('events.manage_site',org_id,s.id) or exists(select 1 from public.ministries m where m.site_id=s.id and public.current_user_leads_ministry(m.id)))),'[]'::jsonb),
  'ministries',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'siteId',m.site_id,'name',m.name,'mine',public.current_user_leads_ministry(m.id)) order by m.name) from public.ministries m where m.organization_id=org_id and m.active and(can_national or public.current_user_has_permission('events.manage_site',org_id,m.site_id) or public.current_user_leads_ministry(m.id))),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'name',r.name) order by r.name) from public.roles r where r.active and r.code in('SITE_PASTOR','MINISTRY_LEADER') and(can_national or exists(select 1 from public.sites sx where sx.organization_id=org_id and public.current_user_has_permission('events.manage_site',org_id,sx.id)))),'[]'::jsonb)
 ) into result;
 return result;
end;
$$;

create or replace function public.save_authorized_event(
 target_event_id uuid,
 given_site_id uuid,
 given_ministry_id uuid,
 given_event_type text,
 given_title text,
 given_description text,
 given_banner_url text,
 given_start_at timestamptz,
 given_end_at timestamptz,
 given_modality text,
 given_location text,
 given_virtual_url text,
 given_additional_info text,
 given_audiences jsonb,
 publish_now boolean default false
)
returns uuid language plpgsql security definer set search_path='' as $$
declare site_row record; event_row record; actor record; target jsonb; target_type text; target_id uuid; result_id uuid; can_national boolean; can_site boolean; can_ministry boolean;
begin
 select s.id,s.organization_id into site_row from public.sites s where s.id=given_site_id and s.active;
 select ua.person_id into actor from public.user_accounts ua where ua.id=auth.uid() and ua.access_status='ACTIVE';
 if site_row.id is null or actor.person_id is null then raise exception 'EVENT_ACTOR_DENIED'; end if;
 if nullif(trim(given_title),'') is null or char_length(trim(given_title))<2 then raise exception 'EVENT_TITLE_REQUIRED'; end if;
 if given_end_at is null or given_end_at<=given_start_at then raise exception 'EVENT_INVALID_DATES'; end if;
 if given_modality not in('IN_PERSON','ONLINE','HYBRID') then raise exception 'EVENT_INVALID_MODALITY'; end if;
 if given_modality in('ONLINE','HYBRID') and nullif(trim(given_virtual_url),'') is null then raise exception 'EVENT_VIRTUAL_URL_REQUIRED'; end if;
 if jsonb_typeof(given_audiences)<>'array' or jsonb_array_length(given_audiences)=0 then raise exception 'EVENT_AUDIENCE_REQUIRED'; end if;
 can_national:=public.current_user_has_permission('events.manage_national',site_row.organization_id,null);
 can_site:=public.current_user_has_permission('events.manage_site',site_row.organization_id,site_row.id);
 can_ministry:=given_ministry_id is not null and public.current_user_has_permission('events.manage_ministry',site_row.organization_id,site_row.id) and public.current_user_leads_ministry(given_ministry_id);
 if not(can_national or can_site or can_ministry) then raise exception 'EVENT_SCOPE_DENIED'; end if;
 if given_ministry_id is not null and not exists(select 1 from public.ministries m where m.id=given_ministry_id and m.organization_id=site_row.organization_id and m.site_id=site_row.id and m.active) then raise exception 'EVENT_MINISTRY_OUT_OF_SCOPE'; end if;
 if can_ministry and not(can_national or can_site) and given_ministry_id is null then raise exception 'EVENT_MINISTRY_REQUIRED'; end if;
 if target_event_id is not null then
  select * into event_row from public.events e where e.id=target_event_id;
  if event_row.id is null or not public.can_user_manage_event(event_row.id) or event_row.organization_id<>site_row.organization_id or not public.current_user_has_permission('events.update',site_row.organization_id,site_row.id) then raise exception 'EVENT_UPDATE_DENIED'; end if;
 else
  if not public.current_user_has_permission('events.create',site_row.organization_id,site_row.id) then raise exception 'EVENT_CREATE_DENIED'; end if;
 end if;
 if publish_now and not public.current_user_has_permission('events.publish',site_row.organization_id,site_row.id) then raise exception 'EVENT_PUBLISH_DENIED'; end if;
 for target in select value from jsonb_array_elements(given_audiences) loop
  target_type:=target->>'type'; target_id:=nullif(target->>'id','')::uuid;
  if target_type in('ALL_CRC','PUBLIC','NATIONAL') and not can_national then raise exception 'EVENT_NATIONAL_AUDIENCE_DENIED'; end if;
  if target_type='SITE' and(not(can_national or can_site) or target_id<>given_site_id) then raise exception 'EVENT_SITE_AUDIENCE_DENIED'; end if;
  if target_type='MINISTRY' and(not exists(select 1 from public.ministries m where m.id=target_id and m.organization_id=site_row.organization_id and m.site_id=given_site_id and m.active) or(not(can_national or can_site) and not public.current_user_leads_ministry(target_id))) then raise exception 'EVENT_MINISTRY_AUDIENCE_DENIED'; end if;
  if target_type='ROLE' and(not(can_national or can_site) or not exists(select 1 from public.roles r where r.id=target_id and r.code in('SITE_PASTOR','MINISTRY_LEADER'))) then raise exception 'EVENT_ROLE_AUDIENCE_DENIED'; end if;
  if target_type='SPECIFIC_USERS' and(not(can_national or can_site) or not exists(select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id where ua.id=target_id and p.organization_id=site_row.organization_id and(can_national or p.site_id=given_site_id))) then raise exception 'EVENT_USER_AUDIENCE_DENIED'; end if;
  if target_type not in('ALL_CRC','PUBLIC','NATIONAL','SITE','MINISTRY','ROLE','SPECIFIC_USERS') then raise exception 'EVENT_AUDIENCE_TYPE_DENIED'; end if;
 end loop;
 if target_event_id is null then
  insert into public.events(organization_id,site_id,ministry_id,organizer_person_id,event_type,title,description,banner_url,start_at,end_at,modality,location,virtual_url,additional_info,status,published_at,created_by,updated_by)
  values(site_row.organization_id,given_site_id,given_ministry_id,actor.person_id,given_event_type::public.event_type,trim(given_title),nullif(trim(given_description),''),nullif(trim(given_banner_url),''),given_start_at,given_end_at,given_modality,nullif(trim(given_location),''),nullif(trim(given_virtual_url),''),nullif(trim(given_additional_info),''),case when publish_now then 'SCHEDULED'::public.event_status else 'DRAFT'::public.event_status end,case when publish_now then now() else null end,auth.uid(),auth.uid()) returning id into result_id;
 else
  update public.events set site_id=given_site_id,ministry_id=given_ministry_id,event_type=given_event_type::public.event_type,title=trim(given_title),description=nullif(trim(given_description),''),banner_url=nullif(trim(given_banner_url),''),start_at=given_start_at,end_at=given_end_at,modality=given_modality,location=nullif(trim(given_location),''),virtual_url=nullif(trim(given_virtual_url),''),additional_info=nullif(trim(given_additional_info),''),status=case when publish_now then 'SCHEDULED'::public.event_status else status end,published_at=case when publish_now then coalesce(published_at,now()) else published_at end,updated_by=auth.uid() where id=target_event_id returning id into result_id;
  delete from public.event_audiences where event_id=result_id;
 end if;
 for target in select value from jsonb_array_elements(given_audiences) loop
  target_type:=target->>'type'; target_id:=nullif(target->>'id','')::uuid;
  insert into public.event_audiences(event_id,audience_type,site_id,ministry_id,role_id,user_account_id,created_by)
  values(result_id,target_type::public.event_audience_type,case when target_type='SITE' then given_site_id else null end,case when target_type='MINISTRY' then target_id else null end,case when target_type='ROLE' then target_id else null end,case when target_type='SPECIFIC_USERS' then target_id else null end,auth.uid());
  if target_type='ROLE' then update public.event_audiences set role_scope_site_id=given_site_id where event_id=result_id and audience_type='ROLE' and role_id=target_id; end if;
 end loop;
 return result_id;
end;
$$;

create or replace function public.cancel_authorized_event(target_event_id uuid,given_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_user_manage_event(target_event_id) or not public.current_user_has_any_permission('events.cancel') then raise exception 'EVENT_CANCEL_DENIED'; end if;
 update public.events set status='CANCELLED',cancelled_at=now(),cancelled_by=auth.uid(),cancellation_reason=nullif(trim(given_reason),''),updated_by=auth.uid() where id=target_event_id;
end;
$$;

create or replace function public.archive_authorized_event(target_event_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.can_user_manage_event(target_event_id) or not public.current_user_has_any_permission('events.archive') then raise exception 'EVENT_ARCHIVE_DENIED'; end if;
 update public.events set archived_at=now(),updated_by=auth.uid() where id=target_event_id;
end;
$$;

create or replace function public.get_authorized_event_history(history_filters jsonb default '{}'::jsonb,result_limit integer default 100)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.start_at desc),'[]'::jsonb) from(
  select e.id,e.title,e.description,e.start_at,e.end_at,e.timezone,e.banner_url,e.modality,e.location,e.virtual_url,e.additional_info,e.event_type,e.status,e.published_at,e.archived_at,e.cancelled_at,e.cancellation_reason,e.created_at,e.updated_at,
   s.id site_id,s.name site_name,m.id ministry_id,m.name ministry_name,trim(concat_ws(' ',creator.first_name,creator.last_name)) creator_name,
   coalesce((select jsonb_agg(jsonb_build_object('type',ea.audience_type,'label',coalesce(ms.name,rr.name,ss.name,recipient.email,ea.audience_type::text)) order by ea.audience_type) from public.event_audiences ea left join public.ministries ms on ms.id=ea.ministry_id left join public.roles rr on rr.id=ea.role_id left join public.sites ss on ss.id=ea.site_id left join public.user_accounts ua on ua.id=ea.user_account_id left join public.people recipient on recipient.id=ua.person_id where ea.event_id=e.id),'[]'::jsonb) audiences
  from public.events e join public.sites s on s.id=e.site_id left join public.ministries m on m.id=e.ministry_id left join public.user_accounts cu on cu.id=e.created_by left join public.people creator on creator.id=cu.person_id
  where public.current_user_has_any_permission('events.view_history') and public.can_user_manage_event(e.id)
   and(coalesce(e.end_at,e.start_at)<now() or e.status='CANCELLED' or e.archived_at is not null)
   and(nullif(history_filters->>'siteId','') is null or e.site_id=(history_filters->>'siteId')::uuid)
   and(nullif(history_filters->>'ministryId','') is null or e.ministry_id=(history_filters->>'ministryId')::uuid)
   and(nullif(history_filters->>'status','') is null or e.status::text=history_filters->>'status')
   and(nullif(history_filters->>'creator','') is null or trim(concat_ws(' ',creator.first_name,creator.last_name)) ilike '%'||(history_filters->>'creator')||'%')
   and(nullif(history_filters->>'from','') is null or e.start_at>=(history_filters->>'from')::timestamptz)
   and(nullif(history_filters->>'to','') is null or e.start_at<(history_filters->>'to')::timestamptz+interval '1 day')
  order by e.start_at desc limit least(greatest(result_limit,1),250)
 )q;
$$;

-- Las escrituras se canalizan por RPC para validar audiencias además del registro principal.
drop trigger if exists events_default_audience on public.events;
revoke insert,update,delete on public.events from authenticated;
revoke insert,update,delete on public.event_audiences from authenticated;

drop policy if exists events_insert_scoped on public.events;
drop policy if exists events_update_scoped on public.events;
drop policy if exists event_audiences_manage on public.event_audiences;
drop policy if exists events_select_scoped on public.events;
drop policy if exists events_select_authorized_agenda on public.events;
drop policy if exists event_audiences_select on public.event_audiences;

create or replace function public.can_user_view_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.events e where e.id=target_event_id and e.published_at is not null and e.archived_at is null
   and e.status in('SCHEDULED','IN_PROGRESS') and coalesce(e.end_at,e.start_at)>=now()
   and(
    exists(select 1 from public.event_audiences ea where ea.event_id=e.id and ea.audience_type='PUBLIC')
    or(auth.uid() is not null and exists(select 1 from public.user_accounts ua where ua.id=auth.uid() and ua.access_status='ACTIVE') and(
     exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) and ur.organization_id=e.organization_id and r.code='SUPER_ADMIN')
     or exists(select 1 from public.event_audiences ea where ea.event_id=e.id and(
      ea.audience_type in('ALL_CRC','NATIONAL')
      or(ea.audience_type='ALL_MEMBERS' and exists(select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id where ua.id=auth.uid() and p.person_status<>'VISITOR'))
      or(ea.audience_type='SITE' and exists(select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id where ua.id=auth.uid() and p.site_id=ea.site_id))
      or(ea.audience_type='MINISTRY' and exists(select 1 from public.user_accounts ua join public.person_ministries pm on pm.person_id=ua.person_id where ua.id=auth.uid() and pm.ministry_id=ea.ministry_id and pm.active and(pm.end_date is null or pm.end_date>=current_date)))
      or(ea.audience_type='ROLE' and exists(select 1 from public.user_roles ur where ur.user_account_id=auth.uid() and ur.role_id=ea.role_id and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) and(ea.role_scope_site_id is null or ur.scope_type='ORGANIZATION' or ur.site_id=ea.role_scope_site_id)))
      or(ea.audience_type='SPECIFIC_USERS' and ea.user_account_id=auth.uid())
     ))
    ))
   )
 );
$$;

create policy events_select_authorized_agenda on public.events for select to authenticated
using (public.can_user_view_event(id) or public.can_user_manage_event(id));

create policy event_audiences_select on public.event_audiences for select to authenticated
using (public.can_user_view_event(event_id) or public.can_user_manage_event(event_id));

create or replace function public.get_my_upcoming_events(result_limit integer default 12)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(q) order by q.is_featured desc,q.start_at),'[]'::jsonb) from(
  select e.id,e.title,e.description,e.start_at,e.end_at,e.timezone,e.banner_url,e.modality,e.location,e.virtual_url,e.additional_info,e.event_type,e.status,e.is_featured,s.id site_id,s.name site_name,m.id ministry_id,m.name ministry_name,trim(concat_ws(' ',p.first_name,p.last_name)) organizer_name,public.can_user_manage_event(e.id) can_manage,
   (public.can_user_manage_event(e.id) and public.current_user_has_any_permission('events.archive')) can_archive,
   coalesce((select jsonb_agg(distinct coalesce(am.name,ar.name,ast.name,ea.audience_type::text)) from public.event_audiences ea left join public.ministries am on am.id=ea.ministry_id left join public.roles ar on ar.id=ea.role_id left join public.sites ast on ast.id=ea.site_id where ea.event_id=e.id),'[]'::jsonb) audience_labels,
   coalesce((select jsonb_agg(jsonb_build_object('type',ea.audience_type,'id',coalesce(ea.site_id,ea.ministry_id,ea.role_id,ea.user_account_id),'label',coalesce(am.name,ar.name,ast.name,ea.audience_type::text))) from public.event_audiences ea left join public.ministries am on am.id=ea.ministry_id left join public.roles ar on ar.id=ea.role_id left join public.sites ast on ast.id=ea.site_id where ea.event_id=e.id),'[]'::jsonb) audiences
  from public.events e join public.sites s on s.id=e.site_id left join public.ministries m on m.id=e.ministry_id left join public.people p on p.id=e.organizer_person_id
  where public.can_user_view_event(e.id)
  order by e.is_featured desc,e.start_at limit least(greatest(result_limit,1),20)
)q;
$$;

create or replace function public.get_visible_event(target_event_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select case when public.can_user_view_event(e.id) then jsonb_build_object(
  'id',e.id,'title',e.title,'description',e.description,'start_at',e.start_at,'end_at',e.end_at,'timezone',e.timezone,'banner_url',e.banner_url,'modality',e.modality,'location',e.location,'virtual_url',e.virtual_url,'additional_info',e.additional_info,'event_type',e.event_type,'status',e.status,'is_featured',e.is_featured,'site_id',s.id,'site_name',s.name,'ministry_id',m.id,'ministry_name',m.name,'organizer_name',trim(concat_ws(' ',p.first_name,p.last_name)),'can_manage',public.can_user_manage_event(e.id),'can_archive',(public.can_user_manage_event(e.id) and public.current_user_has_any_permission('events.archive'))
 ) else null end from public.events e join public.sites s on s.id=e.site_id left join public.ministries m on m.id=e.ministry_id left join public.people p on p.id=e.organizer_person_id where e.id=target_event_id;
$$;

create or replace function public.capture_event_agenda_audit() returns trigger
language plpgsql security definer set search_path='' as $$
declare audit_org uuid; audit_site uuid; affected_id uuid; action_name text;
begin
 if tg_table_name='event_audiences' then affected_id=case when tg_op='DELETE' then old.event_id else new.event_id end; select organization_id,site_id into audit_org,audit_site from public.events where id=affected_id; action_name='EVENT_AUDIENCE_UPDATED';
 else affected_id=case when tg_op='DELETE' then old.id else new.id end; audit_org=case when tg_op='DELETE' then old.organization_id else new.organization_id end; audit_site=case when tg_op='DELETE' then old.site_id else new.site_id end;
  action_name=case when tg_op='INSERT' then 'EVENT_CREATED' when new.archived_at is not null and old.archived_at is null then 'EVENT_ARCHIVED' when new.status='CANCELLED' and old.status is distinct from new.status then 'EVENT_CANCELLED' when new.published_at is not null and old.published_at is null then 'EVENT_PUBLISHED' else 'EVENT_UPDATED' end;
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(audit_org,audit_site,auth.uid(),action_name,'EVENT',affected_id,case when tg_op='INSERT' then null else to_jsonb(old) end,case when tg_op='DELETE' then null else to_jsonb(new) end);
 return case when tg_op='DELETE' then old else new end;
end; $$;

revoke all on function public.get_my_event_management_context(),public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,text,text,text,jsonb,boolean),public.cancel_authorized_event(uuid,text),public.archive_authorized_event(uuid),public.get_authorized_event_history(jsonb,integer) from public;
grant execute on function public.get_my_event_management_context(),public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,text,text,text,jsonb,boolean),public.cancel_authorized_event(uuid,text),public.archive_authorized_event(uuid),public.get_authorized_event_history(jsonb,integer) to authenticated;

notify pgrst,'reload schema';
