-- Directorio de personas autorizado por permisos y alcance efectivos.
-- Evita depender de relaciones embebidas de PostgREST y mantiene el control en backend.
create or replace function public.list_authorized_people()
returns table(
  id uuid,
  organization_id uuid,
  site_id uuid,
  site_name text,
  crc_code text,
  document_type public.document_type,
  document_number text,
  first_name text,
  last_name text,
  preferred_name text,
  email text,
  phone text,
  person_status public.person_status,
  first_visit_date date,
  birth_date date,
  baptized boolean
)
language sql
stable
security definer
set search_path=''
as $$
  select
    person.id,
    person.organization_id,
    person.site_id,
    site.name,
    person.crc_code,
    person.document_type,
    person.document_number,
    person.first_name,
    person.last_name,
    person.preferred_name,
    person.email,
    person.phone,
    person.person_status,
    person.first_visit_date,
    person.birth_date,
    person.baptized
  from public.people person
  join public.sites site
    on site.organization_id=person.organization_id
   and site.id=person.site_id
  where person.archived_at is null
    and public.current_user_has_permission(
      'people.read',
      person.organization_id,
      person.site_id
    )
  order by person.created_at desc;
$$;

revoke all on function public.list_authorized_people() from public;
grant execute on function public.list_authorized_people() to authenticated;
comment on function public.list_authorized_people()
is 'Returns only people inside the authenticated user effective people.read scope.';

notify pgrst,'reload schema';
