-- Los líderes de ministerios especializados trabajan desde su panel y no requieren Personas ni Reportes.
create or replace function public.current_user_is_restricted_specialized_ministry_leader(target_organization_id uuid default null,target_site_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1
  from public.user_accounts ua
  join public.user_roles ur on ur.user_account_id=ua.id
  join public.roles r on r.id=ur.role_id
  join public.ministries m on m.organization_id=ur.organization_id and m.leader_person_id=ua.person_id
  join public.person_ministries pm on pm.ministry_id=m.id and pm.person_id=ua.person_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active
   and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and r.code='MINISTRY_LEADER' and m.active and pm.active
   and lower(trim(m.name)) in(
    'alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración',
    'damas','ministerio de damas','caballeros','ministerio de caballeros',
    'parejas','ministerio de parejas','kids','crc kids','ministerio kids','ministerio de niños',
    'intercesión','intercesion','ministerio de intercesión','ministerio de intercesion',
    'ujieres','ministerio de ujieres','finanzas','ministerio de finanzas'
   )
   and(target_organization_id is null or ur.organization_id=target_organization_id)
   and(target_site_id is null or m.site_id=target_site_id)
 ) and not exists(
  select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now()
   and(ur.ends_at is null or ur.ends_at>now())
   and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
 );
$$;
revoke all on function public.current_user_is_restricted_specialized_ministry_leader(uuid,uuid) from public;
grant execute on function public.current_user_is_restricted_specialized_ministry_leader(uuid,uuid) to authenticated;

create or replace function public.get_my_portal_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb; begin
 select * into ua from public.user_accounts where id=auth.uid(); if ua.id is null or ua.person_id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name into person from public.people p left join public.sites s on s.id=p.site_id where p.id=ua.person_id and p.archived_at is null; if person.id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select coalesce(jsonb_agg(distinct permission.code),'[]'::jsonb) into effective_permissions from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions permission on permission.id=rp.permission_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
 and not(permission.code in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export') and public.current_user_is_restricted_discipleship_coordinator(null,null))
 and not(permission.code in('ministries.read','ministries.manage') and not public.current_user_has_pastoral_ministry_access(null,null))
 and not(permission.code in('people.read','people.create','people.update','people.archive','reports.read','reports.export') and public.current_user_is_restricted_specialized_ministry_leader(null,null))
 and not(permission.code like 'worship.%' and not exists(select 1 from public.sites site where site.organization_id=ur.organization_id and(ur.scope_type='ORGANIZATION' or site.id=ur.site_id) and public.current_user_can_manage_worship(ur.organization_id,site.id)));
 select coalesce(jsonb_agg(distinct role.code),'[]'::jsonb) into roles_json from public.user_roles ur join public.roles role on role.id=ur.role_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 return jsonb_build_object('status',ua.access_status,'needsRegistration',false,'personId',person.id,'firstName',person.first_name,'lastName',person.last_name,'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,'permissions',effective_permissions,'roles',roles_json); end; $$;
grant execute on function public.get_my_portal_context() to authenticated;
notify pgrst,'reload schema';
