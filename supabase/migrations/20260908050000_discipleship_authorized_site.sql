-- Resuelve la sede de Discipulado desde el alcance efectivo del usuario.
-- No depende de que user_accounts.person_id esté vinculado correctamente.
create or replace function public.get_my_discipleship_site(preferred_site_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare selected_site record;
begin
  select site.id,site.organization_id,site.name
    into selected_site
  from public.sites site
  where site.active
    and (preferred_site_id is null or site.id=preferred_site_id)
    and public.current_user_has_permission('groups.read',site.organization_id,site.id)
  order by case when site.id=preferred_site_id then 0 else 1 end,site.name
  limit 1;

  if selected_site.id is null and preferred_site_id is not null then
    select site.id,site.organization_id,site.name
      into selected_site
    from public.sites site
    where site.active
      and public.current_user_has_permission('groups.read',site.organization_id,site.id)
    order by site.name
    limit 1;
  end if;

  if selected_site.id is null then return null; end if;
  return jsonb_build_object('id',selected_site.id,'organizationId',selected_site.organization_id,'name',selected_site.name);
end $$;

revoke all on function public.get_my_discipleship_site(uuid) from public;
grant execute on function public.get_my_discipleship_site(uuid) to authenticated;
notify pgrst,'reload schema';
