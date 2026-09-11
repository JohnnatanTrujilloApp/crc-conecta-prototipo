-- Una identidad autenticada no equivale a una solicitud de acceso completa.
-- Si todavía no existe el vínculo con people, el cliente debe solicitar los datos
-- personales y la sede antes de mostrar el estado pendiente de aprobación.
create or replace function public.get_my_portal_context() returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
  ua record;
  person record;
  effective_permissions jsonb;
  roles_json jsonb;
begin
  select * into ua
  from public.user_accounts
  where id=auth.uid();

  if ua.id is null or ua.person_id is null then
    return jsonb_build_object(
      'status','PENDING_APPROVAL',
      'needsRegistration',true,
      'permissions','[]'::jsonb,
      'roles','[]'::jsonb
    );
  end if;

  select p.id,p.first_name,p.last_name,p.site_id,s.name site_name
  into person
  from public.people p
  left join public.sites s on s.id=p.site_id
  where p.id=ua.person_id and p.archived_at is null;

  if person.id is null then
    return jsonb_build_object(
      'status','PENDING_APPROVAL',
      'needsRegistration',true,
      'permissions','[]'::jsonb,
      'roles','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(distinct p.code),'[]'::jsonb)
  into effective_permissions
  from public.user_roles ur
  join public.role_permissions rp on rp.role_id=ur.role_id
  join public.permissions p on p.id=rp.permission_id
  where ur.user_account_id=auth.uid()
    and ur.active and ur.starts_at<=now()
    and(ur.ends_at is null or ur.ends_at>now());

  select coalesce(jsonb_agg(distinct r.code),'[]'::jsonb)
  into roles_json
  from public.user_roles ur
  join public.roles r on r.id=ur.role_id
  where ur.user_account_id=auth.uid()
    and ur.active and ur.starts_at<=now()
    and(ur.ends_at is null or ur.ends_at>now());

  return jsonb_build_object(
    'status',ua.access_status,
    'needsRegistration',false,
    'personId',person.id,
    'firstName',person.first_name,
    'lastName',person.last_name,
    'siteId',coalesce(person.site_id,ua.requested_site_id),
    'siteName',person.site_name,
    'permissions',effective_permissions,
    'roles',roles_json
  );
end;
$$;

revoke all on function public.get_my_portal_context() from public;
grant execute on function public.get_my_portal_context() to authenticated;
comment on function public.get_my_portal_context()
is 'Devuelve needsRegistration cuando la identidad autenticada aún no está vinculada a una persona activa.';

notify pgrst, 'reload schema';
