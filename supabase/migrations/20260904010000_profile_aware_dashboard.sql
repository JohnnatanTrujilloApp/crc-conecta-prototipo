-- Inicio contextual por perfil y sede. Devuelve solo datos agregados o personales.
create or replace function public.get_my_dashboard(target_site_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  selected_site record;
  my_person_id uuid;
  role_codes text[];
  dashboard_kind text;
  permissions jsonb;
  metrics jsonb;
  alerts jsonb := '[]'::jsonb;
  upcoming jsonb := '[]'::jsonb;
  active_groups bigint := 0;
  pending_followups bigint := 0;
  next_classes bigint := 0;
  average_progress numeric := 0;
begin
  select array_agg(distinct r.code order by r.code)
    into role_codes
  from public.user_roles ur
  join public.roles r on r.id=ur.role_id
  where ur.user_account_id=auth.uid() and ur.active
    and ur.starts_at<=now() and (ur.ends_at is null or ur.ends_at>now());

  if coalesce(array_length(role_codes,1),0)=0 then
    return jsonb_build_object('kind','NONE','roles','[]'::jsonb,'sites','[]'::jsonb,'metrics','{}'::jsonb,'alerts','[]'::jsonb,'upcoming','[]'::jsonb,'permissions','[]'::jsonb);
  end if;

  select ua.person_id into my_person_id from public.user_accounts ua where ua.id=auth.uid();

  select s.id,s.organization_id,s.name into selected_site
  from public.sites s
  where s.active and (target_site_id is null or s.id=target_site_id)
    and exists(select 1 from public.user_roles ur where ur.user_account_id=auth.uid() and ur.active and ur.organization_id=s.organization_id and ur.starts_at<=now() and (ur.ends_at is null or ur.ends_at>now()) and (ur.scope_type='ORGANIZATION' or ur.site_id=s.id))
  order by case when s.id=target_site_id then 0 else 1 end,s.name limit 1;

  if selected_site.id is null then
    return jsonb_build_object('kind','NONE','roles',to_jsonb(role_codes),'sites','[]'::jsonb,'metrics','{}'::jsonb,'alerts','[]'::jsonb,'upcoming','[]'::jsonb,'permissions','[]'::jsonb);
  end if;

  dashboard_kind := case
    when role_codes && array['SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR','SITE_ADMIN'] then 'ADMIN'
    when role_codes && array['DISCIPLESHIP_COORDINATOR','MINISTRY_LEADER'] then 'LEADER'
    when role_codes && array['DISCIPLESHIP_TEACHER','COURSE_TEACHER','USHER'] then 'TEACHER'
    else 'PERSONAL' end;

  select coalesce(jsonb_agg(code),'[]'::jsonb) into permissions
  from (select code from (values('people.read'),('people.create'),('attendance.register'),('groups.read'),('groups.manage'),('training.read'),('training.manage'),('followups.read'),('reports.read')) p(code)
    where public.current_user_has_permission(p.code,selected_site.organization_id,selected_site.id)) allowed;

  if dashboard_kind in ('ADMIN','LEADER') then
    select count(*) into active_groups from public.training_groups g where g.site_id=selected_site.id and g.status='ACTIVE';
    select count(*) into pending_followups from public.discipleship_followups f where f.site_id=selected_site.id and f.requires_followup;
    metrics := jsonb_build_object(
      'people',(select count(*) from public.people p where p.site_id=selected_site.id and p.archived_at is null),
      'attendance',(select count(*) from public.attendance a where a.site_id=selected_site.id and a.status in('PRESENT','LATE') and a.check_in_at>=date_trunc('month',now())),
      'visitors',(select count(*) from public.people p where p.site_id=selected_site.id and p.person_status='VISITOR' and p.first_visit_date>=current_date-30),
      'groups',active_groups
    );
    if pending_followups>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('tone','urgent','title',pending_followups||' seguimientos pendientes','detail','Personas que requieren contacto','action','followups')); end if;
  elsif dashboard_kind='TEACHER' then
    select count(*) into active_groups from public.training_groups g where g.site_id=selected_site.id and g.status='ACTIVE' and (g.teacher_person_id=my_person_id or g.assistant_person_id=my_person_id);
    select count(*) into next_classes from public.class_sessions cs where cs.site_id=selected_site.id and cs.teacher_person_id=my_person_id and cs.status in('SCHEDULED','IN_PROGRESS') and cs.session_date>=current_date;
    select count(*) into pending_followups from public.discipleship_followups f where f.site_id=selected_site.id and f.leader_person_id=my_person_id and f.requires_followup;
    metrics:=jsonb_build_object('groups',active_groups,'classes',next_classes,'followups',pending_followups,'students',(select count(distinct e.person_id) from public.enrollments e join public.training_groups g on g.id=e.group_id where g.site_id=selected_site.id and (g.teacher_person_id=my_person_id or g.assistant_person_id=my_person_id) and e.status in('ENROLLED','ACTIVE','PAUSED')));
    if next_classes>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('tone','info','title',next_classes||' clases próximas','detail','Revisa lección, horario y alumnos','action','discipleship')); end if;
    if pending_followups>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('tone','urgent','title',pending_followups||' alumnos requieren seguimiento','detail','Tienes acompañamientos pendientes','action','followups')); end if;
  else
    select coalesce(round(avg(e.progress_percentage),0),0),count(*) into average_progress,active_groups from public.enrollments e where e.person_id=my_person_id and e.site_id=selected_site.id and e.status in('ENROLLED','ACTIVE','PAUSED');
    select count(*) into next_classes from public.class_sessions cs join public.enrollments e on e.group_id=cs.group_id and e.person_id=my_person_id where cs.site_id=selected_site.id and cs.status in('SCHEDULED','IN_PROGRESS') and cs.session_date>=current_date;
    metrics:=jsonb_build_object('progress',average_progress,'courses',active_groups,'classes',next_classes,'events',(select count(*) from public.events e where e.site_id=selected_site.id and e.status in('SCHEDULED','IN_PROGRESS') and e.start_at>=now() and e.start_at<now()+interval '30 days'));
    if next_classes>0 then alerts:=alerts||jsonb_build_array(jsonb_build_object('tone','info','title','Tienes una próxima clase','detail','Consulta el horario y contenido preparado','action','discipleship')); end if;
    if active_groups>0 and average_progress<100 then alerts:=alerts||jsonb_build_array(jsonb_build_object('tone','progress','title','Continúa tu formación','detail','Avance promedio: '||average_progress||'%','action','training')); end if;
  end if;

  select coalesce(jsonb_agg(item order by start_at),'[]'::jsonb) into upcoming from (
    select jsonb_build_object('type','EVENT','title',e.title,'date',e.start_at,'detail',e.event_type) item,e.start_at
    from public.events e where e.site_id=selected_site.id and e.status in('SCHEDULED','IN_PROGRESS') and e.start_at>=now()
    order by e.start_at limit 4
  ) q;

  return jsonb_build_object(
    'kind',dashboard_kind,'roles',to_jsonb(role_codes),'personId',my_person_id,'siteId',selected_site.id,'siteName',selected_site.name,
    'sites',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name),'[]'::jsonb) from public.sites s where s.active and exists(select 1 from public.user_roles ur where ur.user_account_id=auth.uid() and ur.active and ur.organization_id=s.organization_id and ur.starts_at<=now() and (ur.ends_at is null or ur.ends_at>now()) and (ur.scope_type='ORGANIZATION' or ur.site_id=s.id))),
    'permissions',permissions,'metrics',metrics,'alerts',alerts,'upcoming',upcoming
  );
end;
$$;

revoke all on function public.get_my_dashboard(uuid) from public;
grant execute on function public.get_my_dashboard(uuid) to authenticated;
comment on function public.get_my_dashboard(uuid) is 'Inicio contextual: datos agregados por alcance y datos personales solo del usuario autenticado.';
