-- La administración de Ministerios corresponde exclusivamente al equipo pastoral.
-- Los demás perfiles conservan la visibilidad de sus actividades autorizadas,
-- pero no pueden consultar ni modificar el módulo administrativo de Ministerios.

create or replace function public.current_user_has_pastoral_ministry_access(
  target_organization_id uuid default null,
  target_site_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.user_accounts ua
    join public.user_roles ur on ur.user_account_id=ua.id
    join public.roles r on r.id=ur.role_id
    where ua.id=auth.uid()
      and ua.access_status='ACTIVE'
      and ur.active
      and ur.starts_at<=now()
      and(ur.ends_at is null or ur.ends_at>now())
      and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
      and(target_organization_id is null or ur.organization_id=target_organization_id)
      and(
        target_site_id is null
        or ur.scope_type='ORGANIZATION'
        or(ur.scope_type='SITE' and ur.site_id=target_site_id)
      )
  );
$$;

revoke all on function public.current_user_has_pastoral_ministry_access(uuid,uuid) from public;
grant execute on function public.current_user_has_pastoral_ministry_access(uuid,uuid) to authenticated;

create or replace function public.current_user_has_permission(required_permission text,target_organization_id uuid,target_site_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select
  not(
    required_permission in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export')
    and public.current_user_is_restricted_discipleship_coordinator(target_organization_id,target_site_id)
  )
  and not(
    required_permission in('ministries.read','ministries.manage')
    and not public.current_user_has_pastoral_ministry_access(target_organization_id,target_site_id)
  )
  and exists(
    select 1
    from public.user_accounts ua
    join public.user_roles ur on ur.user_account_id=ua.id
    join public.role_permissions rp on rp.role_id=ur.role_id
    join public.permissions p on p.id=rp.permission_id
    where ua.id=auth.uid() and ua.access_status='ACTIVE'
      and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
      and ur.organization_id=target_organization_id and p.code=required_permission
      and(ur.scope_type='ORGANIZATION' or(target_site_id is not null and ur.scope_type='SITE' and ur.site_id=target_site_id))
  );
$$;

create or replace function public.current_user_has_any_permission(required_permission text)
returns boolean language sql stable security definer set search_path='' as $$
 select
  not(
    required_permission in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export')
    and public.current_user_is_restricted_discipleship_coordinator(null,null)
  )
  and not(
    required_permission in('ministries.read','ministries.manage')
    and not public.current_user_has_pastoral_ministry_access(null,null)
  )
  and exists(
    select 1
    from public.user_accounts ua
    join public.user_roles ur on ur.user_account_id=ua.id
    join public.role_permissions rp on rp.role_id=ur.role_id
    join public.permissions p on p.id=rp.permission_id
    where ua.id=auth.uid() and ua.access_status='ACTIVE'
      and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
      and p.code=required_permission
  );
$$;

create or replace function public.current_user_has_org_permission(required_permission text,target_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select
  not(
    required_permission in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export')
    and public.current_user_is_restricted_discipleship_coordinator(target_organization_id,null)
  )
  and not(
    required_permission in('ministries.read','ministries.manage')
    and not public.current_user_has_pastoral_ministry_access(target_organization_id,null)
  )
  and exists(
    select 1
    from public.user_accounts ua
    join public.user_roles ur on ur.user_account_id=ua.id
    join public.role_permissions rp on rp.role_id=ur.role_id
    join public.permissions p on p.id=rp.permission_id
    where ua.id=auth.uid() and ua.access_status='ACTIVE'
      and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
      and ur.organization_id=target_organization_id and p.code=required_permission
  );
$$;

create or replace function public.get_my_portal_context() returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb;
begin
 select * into ua from public.user_accounts where id=auth.uid();
 if ua.id is null or ua.person_id is null then
  return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb);
 end if;
 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name into person
 from public.people p left join public.sites s on s.id=p.site_id
 where p.id=ua.person_id and p.archived_at is null;
 if person.id is null then
  return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb);
 end if;
 select coalesce(jsonb_agg(distinct p.code),'[]'::jsonb) into effective_permissions
 from public.user_roles ur
 join public.role_permissions rp on rp.role_id=ur.role_id
 join public.permissions p on p.id=rp.permission_id
 where ur.user_account_id=auth.uid()
   and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and not(
     p.code in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export')
     and public.current_user_is_restricted_discipleship_coordinator(null,null)
   )
   and not(
     p.code in('ministries.read','ministries.manage')
     and not public.current_user_has_pastoral_ministry_access(null,null)
   );
 select coalesce(jsonb_agg(distinct r.code),'[]'::jsonb) into roles_json
 from public.user_roles ur join public.roles r on r.id=ur.role_id
 where ur.user_account_id=auth.uid()
   and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 return jsonb_build_object(
  'status',ua.access_status,'needsRegistration',false,'personId',person.id,
  'firstName',person.first_name,'lastName',person.last_name,
  'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,
  'permissions',effective_permissions,'roles',roles_json
 );
end;
$$;

revoke all on function public.get_my_portal_context() from public;
grant execute on function public.get_my_portal_context() to authenticated;
comment on function public.current_user_has_pastoral_ministry_access(uuid,uuid)
is 'Autoriza el módulo administrativo de Ministerios únicamente a superadministradores y pastores dentro de su alcance.';

notify pgrst,'reload schema';
