create or replace function public.swap_individual_discipleship_participants(target_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  assignment_row public.discipleship_assignments%rowtype;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select * into assignment_row
  from public.discipleship_assignments
  where id = target_assignment_id
  for update;

  if not found then
    raise exception 'ASSIGNMENT_NOT_FOUND';
  end if;

  if not public.current_user_has_permission(
    'discipleship.assign',
    assignment_row.organization_id,
    assignment_row.site_id
  ) then
    raise exception 'ASSIGNMENT_CORRECTION_DENIED';
  end if;

  if exists (
    select 1 from public.discipleship_lesson_records
    where assignment_id = assignment_row.id
  ) then
    raise exception 'ASSIGNMENT_HAS_PROGRESS';
  end if;

  if exists (
    select 1
    from public.discipleship_assignments other_assignment
    where other_assignment.id <> assignment_row.id
      and other_assignment.disciple_person_id = assignment_row.discipler_person_id
      and other_assignment.program_id = assignment_row.program_id
      and other_assignment.status in ('ASSIGNED', 'ACTIVE', 'PAUSED')
  ) then
    raise exception 'ALREADY_ASSIGNED';
  end if;

  update public.discipleship_assignments
  set disciple_person_id = assignment_row.discipler_person_id,
      discipler_person_id = assignment_row.disciple_person_id,
      updated_at = now()
  where id = assignment_row.id;

  insert into public.audit_logs(
    organization_id, site_id, user_id, action, entity_type, entity_id, old_values, new_values
  ) values (
    assignment_row.organization_id,
    assignment_row.site_id,
    auth.uid(),
    'DISCIPLESHIP_PARTICIPANTS_SWAPPED',
    'DISCIPLESHIP_ASSIGNMENT',
    assignment_row.id,
    jsonb_build_object(
      'disciplePersonId', assignment_row.disciple_person_id,
      'disciplerPersonId', assignment_row.discipler_person_id
    ),
    jsonb_build_object(
      'disciplePersonId', assignment_row.discipler_person_id,
      'disciplerPersonId', assignment_row.disciple_person_id
    )
  );
end;
$$;

revoke all on function public.swap_individual_discipleship_participants(uuid) from public;
grant execute on function public.swap_individual_discipleship_participants(uuid) to authenticated;
