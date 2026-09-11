-- Secure access-request queue without PostgREST embedded relations crossing RLS.
create or replace function public.list_authorized_access_requests()
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', request.id,
    'status', request.status,
    'created_at', request.created_at,
    'possible_duplicate', request.possible_duplicate,
    'observations', coalesce(request.observations, ''),
    'person', jsonb_build_object(
      'first_name', person.first_name,
      'last_name', person.last_name,
      'email', person.email,
      'phone', person.phone,
      'document_type', person.document_type,
      'document_number', person.document_number
    ),
    'site', jsonb_build_object('name', site.name)
  ) order by request.created_at desc), '[]'::jsonb)
  from public.access_requests request
  join public.people person on person.id=request.person_id
  join public.sites site on site.id=request.site_id
  where public.current_user_has_permission(
    'access_requests.review', request.organization_id, request.site_id
  );
$$;

revoke all on function public.list_authorized_access_requests() from public;
grant execute on function public.list_authorized_access_requests() to authenticated;
comment on function public.list_authorized_access_requests()
is 'Returns access requests only inside the authenticated reviewer effective scope.';

notify pgrst,'reload schema';
