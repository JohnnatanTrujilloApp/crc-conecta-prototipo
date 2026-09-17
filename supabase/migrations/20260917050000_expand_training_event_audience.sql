-- Formación puede convocar a toda su sede sin obtener administración general de sede.
create or replace function public.current_user_leads_training_ministry(target_ministry_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua
  join public.ministries m on m.leader_person_id=ua.person_id
  join public.person_ministries pm on pm.person_id=ua.person_id and pm.ministry_id=m.id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and m.id=target_ministry_id
   and m.active and pm.active and(pm.end_date is null or pm.end_date>=current_date)
   and lower(trim(m.name)) in('formación','formacion','ministerio de formación','ministerio de formacion')
 );
$$;
revoke all on function public.current_user_leads_training_ministry(uuid) from public;
grant execute on function public.current_user_leads_training_ministry(uuid) to authenticated;

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
  'canManageSite',exists(select 1 from public.sites sx where sx.organization_id=org_id and(public.current_user_has_permission('events.manage_site',org_id,sx.id) or public.current_user_is_training_ministry_leader(org_id,sx.id))),
  'sites',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.sites s where s.organization_id=org_id and s.active and(can_national or public.current_user_has_permission('events.manage_site',org_id,s.id) or exists(select 1 from public.ministries m where m.site_id=s.id and public.current_user_leads_ministry(m.id)))),'[]'::jsonb),
  'ministries',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'siteId',m.site_id,'name',m.name,'mine',public.current_user_leads_ministry(m.id)) order by m.name) from public.ministries m where m.organization_id=org_id and m.active and(can_national or public.current_user_has_permission('events.manage_site',org_id,m.site_id) or public.current_user_leads_ministry(m.id))),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'name',r.name) order by r.name) from public.roles r where r.active and r.code in('SITE_PASTOR','MINISTRY_LEADER') and(can_national or exists(select 1 from public.sites sx where sx.organization_id=org_id and public.current_user_has_permission('events.manage_site',org_id,sx.id)))),'[]'::jsonb)
 ) into result;
 return result;
end;
$$;

create or replace function public.save_authorized_event(
 target_event_id uuid,given_site_id uuid,given_ministry_id uuid,given_event_type text,given_title text,given_description text,given_banner_url text,given_start_at timestamptz,given_end_at timestamptz,given_modality text,given_location text,given_virtual_url text,given_additional_info text,given_audiences jsonb,publish_now boolean default false
)
returns uuid language plpgsql security definer set search_path='' as $$
declare site_row record; event_row record; actor record; target jsonb; target_type text; target_id uuid; result_id uuid; can_national boolean; can_site boolean; can_ministry boolean; can_training_site_audience boolean;
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
 can_training_site_audience:=given_ministry_id is not null and public.current_user_leads_training_ministry(given_ministry_id) and public.current_user_is_training_ministry_leader(site_row.organization_id,site_row.id);
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
  if target_type='SITE' and(not(can_national or can_site or can_training_site_audience) or target_id<>given_site_id) then raise exception 'EVENT_SITE_AUDIENCE_DENIED'; end if;
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

revoke all on function public.get_my_event_management_context(),public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,text,text,text,jsonb,boolean) from public;
grant execute on function public.get_my_event_management_context(),public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamptz,timestamptz,text,text,text,text,jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
