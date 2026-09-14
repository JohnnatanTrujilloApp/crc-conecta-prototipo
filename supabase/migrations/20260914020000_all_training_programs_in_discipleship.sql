-- Todo programa formativo activo puede acompañarse desde Discipulado.
-- El alumno seguirá viendo únicamente sus propias asignaciones en Mi CRC.
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
    'programType',program.program_type,
    'lessonCount',coalesce(lesson_data.lesson_count,0),
    'lessons',coalesce(lesson_data.lessons,'[]'::jsonb)
  ) order by program.program_type,program.title),'[]'::jsonb)
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
    and program.active;

  return result;
end $$;

create or replace function public.create_individual_discipleship(
  target_site_id uuid,
  target_program_id uuid,
  target_disciple_person_id uuid,
  target_discipler_person_id uuid,
  given_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare s record; created_id uuid;
begin
  select * into s from public.sites where id=target_site_id;
  if s.id is null or not public.current_user_has_permission('discipleship.assign',s.organization_id,s.id) then raise exception 'DISCIPLESHIP_ASSIGN_DENIED'; end if;
  if target_disciple_person_id=target_discipler_person_id then raise exception 'SELF_DISCIPLESHIP_NOT_ALLOWED'; end if;
  if not exists(select 1 from public.training_programs p where p.id=target_program_id and p.organization_id=s.organization_id and p.active) then raise exception 'INVALID_TRAINING_PROGRAM'; end if;
  if not exists(select 1 from public.people p where p.id=target_disciple_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLE_NOT_AVAILABLE'; end if;
  if not exists(select 1 from public.people p where p.id=target_discipler_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLER_NOT_AVAILABLE'; end if;
  insert into public.discipleship_assignments(organization_id,site_id,program_id,disciple_person_id,discipler_person_id,notes,created_by)
  values(s.organization_id,s.id,target_program_id,target_disciple_person_id,target_discipler_person_id,nullif(trim(given_notes),''),auth.uid()) returning id into created_id;
  return created_id;
exception when unique_violation then raise exception 'DISCIPLESHIP_ALREADY_ASSIGNED'; end;
$$;

revoke all on function public.get_my_discipleship_programs(uuid) from public;
revoke all on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) from public;
grant execute on function public.get_my_discipleship_programs(uuid) to authenticated;
grant execute on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) to authenticated;
comment on function public.get_my_discipleship_programs(uuid) is 'Catálogo completo de programas activos que pueden acompañarse desde Discipulado.';
comment on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) is 'Asigna cualquier programa formativo activo a un alumno con un discipulador responsable.';
notify pgrst,'reload schema';
