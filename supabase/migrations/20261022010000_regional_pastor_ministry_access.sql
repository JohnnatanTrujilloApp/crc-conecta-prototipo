-- Un pastor regional puede tener asignaciones SITE vigentes en varias sedes.
-- No se asigna el rol a ningún usuario automáticamente.
insert into public.roles (code, name, description)
values ('REGIONAL_PASTOR', 'Pastor regional', 'Acceso pastoral a las sedes regionales asignadas')
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code = 'ministries.read'
where r.code = 'REGIONAL_PASTOR'
on conflict do nothing;

create or replace function public.current_user_has_pastoral_ministry_access(
  target_organization_id uuid default null,
  target_site_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_accounts ua
    join public.user_roles ur on ur.user_account_id = ua.id
    join public.roles r on r.id = ur.role_id
    where ua.id = auth.uid()
      and ua.access_status = 'ACTIVE'
      and ur.active
      and ur.starts_at <= now()
      and (ur.ends_at is null or ur.ends_at > now())
      and (target_organization_id is null or ur.organization_id = target_organization_id)
      and (
        (r.code in ('SUPER_ADMIN', 'NATIONAL_PASTOR', 'SITE_PASTOR')
          and (target_site_id is null or ur.scope_type = 'ORGANIZATION'
            or (ur.scope_type = 'SITE' and ur.site_id = target_site_id)))
        or (r.code = 'REGIONAL_PASTOR'
          and ur.scope_type = 'SITE'
          and (target_site_id is null or ur.site_id = target_site_id))
      )
  );
$$;

revoke all on function public.current_user_has_pastoral_ministry_access(uuid, uuid) from public;
revoke all on function public.current_user_has_pastoral_ministry_access(uuid, uuid) from anon;
grant execute on function public.current_user_has_pastoral_ministry_access(uuid, uuid) to authenticated;
