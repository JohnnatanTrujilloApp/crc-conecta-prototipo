-- Proyección segura y de solo lectura para Mi CRC.
create or replace function public.get_my_personal_campus() returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare my_person_id uuid; result jsonb;
begin
 my_person_id:=public.get_my_active_person_id();
 if my_person_id is null then raise exception 'ACTIVE_PERSON_REQUIRED'; end if;
 select jsonb_build_object(
  'profile',jsonb_build_object('firstName',p.first_name,'lastName',p.last_name,'email',p.email,'phone',p.phone,'city',p.city,'crcCode',p.crc_code,'site',s.name),
  'discipleships',coalesce((select jsonb_agg(jsonb_build_object(
   'id',a.id,'program',tp.title,'programDescription',tp.description,'discipler',trim(concat_ws(' ',teacher.first_name,teacher.last_name)),
   'site',assignment_site.name,'status',a.status,'assignedAt',a.assigned_at,
   'completed',(select count(*) from public.discipleship_lesson_records done where done.assignment_id=a.id),
   'total',(select count(*) from public.lessons lesson_count join public.training_modules module_count on module_count.id=lesson_count.module_id where module_count.program_id=a.program_id and module_count.active and lesson_count.active),
   'progress',case when (select count(*) from public.lessons lesson_count join public.training_modules module_count on module_count.id=lesson_count.module_id where module_count.program_id=a.program_id and module_count.active and lesson_count.active)=0 then 0 else round((select count(*) from public.discipleship_lesson_records done where done.assignment_id=a.id)::numeric/(select count(*) from public.lessons lesson_count join public.training_modules module_count on module_count.id=lesson_count.module_id where module_count.program_id=a.program_id and module_count.active and lesson_count.active)*100) end,
   'lastLessonAt',(select max(last_record.delivered_on) from public.discipleship_lesson_records last_record where last_record.assignment_id=a.id),
   'lessons',coalesce((select jsonb_agg(jsonb_build_object('id',lesson.id,'title',lesson.title,'module',module.title,'completed',record.id is not null,'deliveredOn',record.delivered_on,'deliveredBy',case when record.id is null then null else trim(concat_ws(' ',historical_teacher.first_name,historical_teacher.last_name)) end) order by module.sort_order,lesson.sort_order)
    from public.training_modules module join public.lessons lesson on lesson.module_id=module.id and lesson.active
    left join public.discipleship_lesson_records record on record.assignment_id=a.id and record.lesson_id=lesson.id
    left join public.people historical_teacher on historical_teacher.id=record.discipler_person_id
    where module.program_id=a.program_id and module.active),'[]'::jsonb)
  ) order by a.updated_at desc) from public.discipleship_assignments a
  join public.training_programs tp on tp.id=a.program_id join public.people teacher on teacher.id=a.discipler_person_id
  join public.sites assignment_site on assignment_site.id=a.site_id where a.disciple_person_id=my_person_id),'[]'::jsonb)
 ) into result from public.people p join public.sites s on s.id=p.site_id where p.id=my_person_id and p.archived_at is null;
 if result is null then raise exception 'PERSON_NOT_AVAILABLE'; end if;
 return result;
end;
$$;
revoke all on function public.get_my_personal_campus() from public;
grant execute on function public.get_my_personal_campus() to authenticated;
comment on function public.get_my_personal_campus() is 'Devuelve solo el perfil, formación y discipulados donde la persona autenticada es el alumno.';
notify pgrst,'reload schema';
