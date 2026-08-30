-- Ejecutar una sola vez en Supabase de desarrollo.
-- Reemplace el marcador por el correo de la cuenta creada en Authentication.
do $$
declare
  target_email text := 'REEMPLAZAR_CON_EL_CORREO';
  target_user_id uuid;
  target_role_id uuid;
  target_organization_id uuid := '10000000-0000-0000-0000-000000000001';
begin
  select id into target_user_id
  from auth.users
  where lower(email)=lower(target_email);

  if target_user_id is null then
    raise exception 'No existe un usuario Auth con el correo indicado';
  end if;

  select id into target_role_id from public.roles where code='SUPER_ADMIN';
  if target_role_id is null then
    raise exception 'No existe el rol SUPER_ADMIN; revise las migraciones';
  end if;

  insert into public.user_accounts(id) values(target_user_id)
  on conflict(id) do nothing;

  insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,assigned_by)
  select target_user_id,target_role_id,target_organization_id,'ORGANIZATION',null,target_user_id
  where not exists(
    select 1 from public.user_roles
    where user_account_id=target_user_id
      and role_id=target_role_id
      and organization_id=target_organization_id
      and scope_type='ORGANIZATION'
      and active
  );
end $$;

select r.code,o.name,ur.scope_type,s.name as site_name
from public.user_roles ur
join public.roles r on r.id=ur.role_id
join public.organizations o on o.id=ur.organization_id
left join public.sites s on s.id=ur.site_id
join auth.users u on u.id=ur.user_account_id
where lower(u.email)=lower('REEMPLAZAR_CON_EL_CORREO');
