-- Catálogo de Formación consumido por Discipulado, validado por sede y permisos.
create or replace function public.get_my_discipleship_programs(target_site_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare target_site record; result jsonb;
begin
  select site.id,site.organization_id into target_site
  from public.sites site
  where site.id=target_site_id and site.active
    and public.current_user_has_permission('groups.read',site.organization_id,site.id)
    and public.current_user_has_permission('training.read',site.organization_id,site.id);

  if target_site.id is null then raise exception 'DISCIPLESHIP_SITE_NOT_AUTHORIZED'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',program.id,
    'organizationId',program.organization_id,
    'title',program.title,
    'lessonCount',coalesce(lesson_data.lesson_count,0),
    'lessons',coalesce(lesson_data.lessons,'[]'::jsonb)
  ) order by program.title),'[]'::jsonb)
  into result
  from public.training_programs program
  left join lateral (
    select count(lesson.id)::integer lesson_count,
      coalesce(jsonb_agg(jsonb_build_object(
        'id',lesson.id,'programId',program.id,'title',lesson.title,'sortOrder',lesson.sort_order
      ) order by module.sort_order,lesson.sort_order) filter(where lesson.id is not null),'[]'::jsonb) lessons
    from public.training_modules module
    left join public.lessons lesson on lesson.module_id=module.id and lesson.active
    where module.program_id=program.id and module.active
  ) lesson_data on true
  where program.organization_id=target_site.organization_id
    and program.program_type='DISCIPLESHIP' and program.active;

  return result;
end $$;

revoke all on function public.get_my_discipleship_programs(uuid) from public;
grant execute on function public.get_my_discipleship_programs(uuid) to authenticated;
notify pgrst,'reload schema';
