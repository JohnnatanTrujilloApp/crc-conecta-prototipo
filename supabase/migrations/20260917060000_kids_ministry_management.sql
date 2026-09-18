-- Kids reutiliza people, families, person_ministries, events y attendance.
alter table public.people alter column phone drop not null;
alter table public.person_ministries add column if not exists kids_group text;

insert into public.permissions(code,name,description) values
 ('kids.view','Ver Kids','Consultar menores vinculados a Kids dentro del alcance'),
 ('kids.create_person','Registrar menor en Kids','Crear o vincular una persona al Ministerio Kids'),
 ('kids.update_person_basic','Actualizar datos básicos Kids','Actualizar únicamente datos básicos autorizados del menor'),
 ('kids.manage_members','Gestionar integrantes Kids','Vincular o inactivar integrantes conservando historial'),
 ('kids.attendance.create','Registrar asistencia Kids','Registrar asistencia de Escuela Dominical'),
 ('kids.attendance.update','Actualizar asistencia Kids','Corregir asistencia de Escuela Dominical'),
 ('kids.attendance.view_history','Ver historial Kids','Consultar historial de Escuela Dominical'),
 ('kids.guardian.manage','Gestionar acudientes Kids','Vincular responsables mediante familias')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','kids.view'),('SUPER_ADMIN','kids.create_person'),('SUPER_ADMIN','kids.update_person_basic'),('SUPER_ADMIN','kids.manage_members'),('SUPER_ADMIN','kids.attendance.create'),('SUPER_ADMIN','kids.attendance.update'),('SUPER_ADMIN','kids.attendance.view_history'),('SUPER_ADMIN','kids.guardian.manage'),
 ('NATIONAL_PASTOR','kids.view'),('NATIONAL_PASTOR','kids.create_person'),('NATIONAL_PASTOR','kids.update_person_basic'),('NATIONAL_PASTOR','kids.manage_members'),('NATIONAL_PASTOR','kids.attendance.create'),('NATIONAL_PASTOR','kids.attendance.update'),('NATIONAL_PASTOR','kids.attendance.view_history'),('NATIONAL_PASTOR','kids.guardian.manage'),
 ('SITE_PASTOR','kids.view'),('SITE_PASTOR','kids.create_person'),('SITE_PASTOR','kids.update_person_basic'),('SITE_PASTOR','kids.manage_members'),('SITE_PASTOR','kids.attendance.create'),('SITE_PASTOR','kids.attendance.update'),('SITE_PASTOR','kids.attendance.view_history'),('SITE_PASTOR','kids.guardian.manage')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

create or replace function public.current_user_can_manage_kids(target_organization_id uuid,target_site_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.roles r on r.id=ur.role_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and ur.organization_id=target_organization_id and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
   and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
 ) or exists(
  select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.roles r on r.id=ur.role_id
  join public.ministries m on m.organization_id=ur.organization_id and m.site_id=target_site_id and m.leader_person_id=ua.person_id
  join public.person_ministries pm on pm.ministry_id=m.id and pm.person_id=ua.person_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and ur.organization_id=target_organization_id and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
   and r.code='MINISTRY_LEADER' and m.active and pm.active and(pm.end_date is null or pm.end_date>=current_date)
   and lower(trim(m.name)) in('kids','crc kids','ministerio kids','ministerio de niños')
 );
$$;

create or replace function public.get_my_kids_scope()
returns table(organization_id uuid,site_id uuid,site_name text,ministry_id uuid,ministry_name text)
language sql stable security definer set search_path='' as $$
 select m.organization_id,m.site_id,s.name,m.id,m.name from public.ministries m join public.sites s on s.id=m.site_id
 where m.active and lower(trim(m.name)) in('kids','crc kids','ministerio kids','ministerio de niños')
  and public.current_user_can_manage_kids(m.organization_id,m.site_id)
 order by case when m.leader_person_id=(select person_id from public.user_accounts where id=auth.uid()) then 0 else 1 end,s.name limit 1;
$$;

-- Enlace de datos para la nueva identidad de prueba; las reglas no dependen del correo.
do $$ declare target record; auth_id uuid; person_id uuid; leader_role uuid;
begin
 select m.organization_id,m.site_id,m.id ministry_id into target from public.ministries m where m.active and lower(trim(m.name)) in('kids','crc kids','ministerio kids','ministerio de niños') and exists(select 1 from public.sites s where s.id=m.site_id and(lower(s.name) like '%nemocón%' or lower(s.slug) like '%nemocon%')) order by m.created_at limit 1;
 select id into auth_id from auth.users where lower(trim(email))='johnnatan.trujillo+kids2@gmail.com' limit 1;
 if target.ministry_id is not null and auth_id is not null then
  select ua.person_id into person_id from public.user_accounts ua where ua.id=auth_id;
  if person_id is null then
   select p.id into person_id from public.people p where p.organization_id=target.organization_id and lower(trim(p.email))='johnnatan.trujillo+kids2@gmail.com' limit 1;
  end if;
  if person_id is null then insert into public.people(organization_id,site_id,first_name,last_name,email,phone,person_status,first_visit_date) values(target.organization_id,target.site_id,'Líder','Kids','johnnatan.trujillo+kids2@gmail.com',null,'LEADER',current_date) returning id into person_id; end if;
  insert into public.user_accounts(id,person_id) values(auth_id,person_id) on conflict(id) do update set person_id=excluded.person_id;
  update public.user_accounts set access_status='ACTIVE',requested_site_id=target.site_id where id=auth_id;
  select id into leader_role from public.roles where code='MINISTRY_LEADER' and active;
  insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,active) values(auth_id,leader_role,target.organization_id,'SITE',target.site_id,true) on conflict do nothing;
  insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,active) values(target.organization_id,target.site_id,person_id,target.ministry_id,'Líder de Kids',true) on conflict(person_id,ministry_id,start_date) do update set active=true,end_date=null,position=excluded.position;
  update public.ministries set leader_person_id=person_id where id=target.ministry_id;
 end if;
end $$;

create or replace function public.search_kids_people(search_term text,result_limit integer default 20)
returns table(id uuid,name text,"birthDate" date,"documentNumber" text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare scope record; normalized text:=lower(trim(coalesce(search_term,'')));
begin
 select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null or normalized='' then return; end if;
 return query select p.id,trim(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name)),p.birth_date,p.document_number,p.phone
 from public.people p where p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null
  and(
   lower(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name,p.document_number,p.crc_code,coalesce(p.phone,''))) like '%'||normalized||'%'
   or exists(
    select 1 from public.family_members child_link
    join public.family_members guardian_link on guardian_link.family_id=child_link.family_id and guardian_link.person_id<>child_link.person_id
    join public.people guardian on guardian.id=guardian_link.person_id
    where child_link.person_id=p.id
     and lower(concat_ws(' ',guardian.first_name,guardian.middle_name,guardian.last_name,guardian.second_last_name,guardian.document_number,coalesce(guardian.phone,''))) like '%'||normalized||'%'
   )
  )
 order by p.first_name,p.last_name limit least(greatest(result_limit,1),30);
end; $$;

create or replace function public.get_my_kids_context()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare scope record; result jsonb;
begin
 select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 select jsonb_build_object(
  'site',jsonb_build_object('id',scope.site_id,'name',scope.site_name),'ministry',jsonb_build_object('id',scope.ministry_id,'name',scope.ministry_name),'canManage',true,
  'children',coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'membershipId',q.membership_id,'name',q.name,'birthDate',q.birth_date,'age',q.age,'sex',q.sex,'groupName',q.group_name,'guardianName',q.guardian_name,'guardianPhone',q.guardian_phone,'lastAttendance',q.last_attendance,'status',q.status,'presentCount',q.present_count,'absentCount',q.absent_count) order by q.name) from(
   select p.id,pm.id membership_id,trim(concat_ws(' ',p.first_name,p.last_name)) name,p.birth_date,extract(year from age(current_date,p.birth_date))::int age,p.sex,
    coalesce(nullif(trim(pm.kids_group),''),'Por definir') group_name,
    guardian.full_name guardian_name,guardian.phone guardian_phone,
    (select max(e.start_at)::date from public.attendance a join public.events e on e.id=a.event_id where a.person_id=p.id and a.status in('PRESENT','LATE') and e.ministry_id=scope.ministry_id) last_attendance,
    case when pm.active then 'Activo' else 'Inactivo' end status,
    (select count(*) from public.attendance a join public.events e on e.id=a.event_id where a.person_id=p.id and a.status in('PRESENT','LATE') and e.ministry_id=scope.ministry_id and e.start_at::date>=pm.start_date)::int present_count,
    (select count(*) from public.attendance a join public.events e on e.id=a.event_id where a.person_id=p.id and a.status in('ABSENT','EXCUSED') and e.ministry_id=scope.ministry_id and e.start_at::date>=pm.start_date)::int absent_count
   from public.person_ministries pm join public.people p on p.id=pm.person_id
   left join lateral(select trim(concat_ws(' ',gp.first_name,gp.last_name)) full_name,gp.phone from public.family_members child_link join public.family_members guardian_link on guardian_link.family_id=child_link.family_id and guardian_link.person_id<>child_link.person_id join public.people gp on gp.id=guardian_link.person_id where child_link.person_id=p.id order by guardian_link.is_primary_contact desc,guardian_link.created_at limit 1) guardian on true
   where pm.ministry_id=scope.ministry_id and pm.active and p.archived_at is null
  )q),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'title',e.title,'startAt',e.start_at,'status',e.status) order by e.start_at desc) from public.events e where e.ministry_id=scope.ministry_id and e.site_id=scope.site_id and e.archived_at is null and e.status<>'CANCELLED' and e.start_at>=now()-interval '180 days'),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(jsonb_build_object('eventId',a.event_id,'personId',a.person_id,'status',a.status)) from public.attendance a join public.events e on e.id=a.event_id where e.ministry_id=scope.ministry_id and e.site_id=scope.site_id and e.start_at>=now()-interval '180 days'),'[]'::jsonb)
 ) into result; return result;
end; $$;

create or replace function public.save_kids_child(payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare scope record; child_id uuid; duplicate_id uuid; guardian_id uuid; family_id uuid; rel public.family_relationship; attendance_event uuid; old_values jsonb;
begin
 select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 child_id:=nullif(payload->>'existingPersonId','')::uuid;
 if child_id is not null then
  if not exists(select 1 from public.people p where p.id=child_id and p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null) then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 else
  if nullif(trim(payload->>'firstName'),'') is null or nullif(trim(payload->>'lastName'),'') is null or nullif(payload->>'birthDate','') is null then raise exception 'KIDS_REQUIRED_FIELDS'; end if;
  if nullif(payload->>'documentNumber','') is not null then select p.id into duplicate_id from public.people p where p.organization_id=scope.organization_id and p.document_number=trim(payload->>'documentNumber') and p.archived_at is null limit 1; end if;
  if duplicate_id is null then select p.id into duplicate_id from public.people p where p.organization_id=scope.organization_id and lower(trim(p.first_name))=lower(trim(payload->>'firstName')) and lower(trim(p.last_name))=lower(trim(payload->>'lastName')) and p.birth_date=(payload->>'birthDate')::date and p.archived_at is null limit 1; end if;
  if duplicate_id is not null then child_id:=duplicate_id; else
   insert into public.people(organization_id,site_id,document_type,document_number,first_name,last_name,birth_date,sex,email,phone,person_status,first_visit_date)
   values(scope.organization_id,scope.site_id,nullif(payload->>'documentType','')::public.document_type,nullif(trim(payload->>'documentNumber'),''),trim(payload->>'firstName'),trim(payload->>'lastName'),(payload->>'birthDate')::date,nullif(payload->>'sex',''),nullif(lower(trim(payload->>'email')),''),nullif(trim(payload->>'phone'),''),'VISITOR',current_date) returning id into child_id;
  end if;
 end if;
 insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,active) values(scope.organization_id,scope.site_id,child_id,scope.ministry_id,'Participante Kids',true) on conflict(person_id,ministry_id,start_date) do update set active=true,end_date=null,position=excluded.position;
 guardian_id:=nullif(payload->>'guardianPersonId','')::uuid;
 if guardian_id is null and nullif(trim(payload->>'guardianName'),'') is not null then
  select p.id into guardian_id from public.people p where p.organization_id=scope.organization_id and p.site_id=scope.site_id and((nullif(payload->>'guardianPhone','') is not null and p.phone=trim(payload->>'guardianPhone')) or(nullif(payload->>'guardianEmail','') is not null and lower(p.email)=lower(trim(payload->>'guardianEmail')))) and p.archived_at is null limit 1;
  if guardian_id is null then insert into public.people(organization_id,site_id,first_name,last_name,email,phone,person_status,first_visit_date) values(scope.organization_id,scope.site_id,split_part(trim(payload->>'guardianName'),' ',1),coalesce(nullif(trim(substr(trim(payload->>'guardianName'),length(split_part(trim(payload->>'guardianName'),' ',1))+1)),''),'Acudiente'),nullif(lower(trim(payload->>'guardianEmail')),''),nullif(trim(payload->>'guardianPhone'),''),'VISITOR',current_date) returning id into guardian_id; end if;
 end if;
 if guardian_id is not null then
  if not exists(select 1 from public.people p where p.id=guardian_id and p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null) then raise exception 'KIDS_GUARDIAN_OUT_OF_SCOPE'; end if;
  select fm.family_id into family_id from public.family_members fm where fm.person_id=child_id limit 1;
  if family_id is null then insert into public.families(organization_id,site_id,name,active) values(scope.organization_id,scope.site_id,'Familia '||(select last_name from public.people where id=child_id),true) returning id into family_id; insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact) values(scope.organization_id,scope.site_id,family_id,child_id,case when(select sex from public.people where id=child_id)='F' then 'DAUGHTER'::public.family_relationship else 'SON'::public.family_relationship end,false) on conflict(family_id,person_id) do nothing; end if;
  rel:=coalesce(nullif(payload->>'guardianRelationship','')::public.family_relationship,'GUARDIAN'::public.family_relationship);
  insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact) values(scope.organization_id,scope.site_id,family_id,guardian_id,rel,coalesce((payload->>'primaryContact')::boolean,true)) on conflict(family_id,person_id) do update set relationship=excluded.relationship,is_primary_contact=excluded.is_primary_contact;
  insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values) values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_GUARDIAN_LINKED','PERSON',child_id,jsonb_build_object('guardianId',guardian_id,'relationship',rel));
 end if;
 attendance_event:=nullif(payload->>'attendanceEventId','')::uuid;
 if attendance_event is not null then
  if not exists(select 1 from public.events e where e.id=attendance_event and e.ministry_id=scope.ministry_id and e.site_id=scope.site_id) then raise exception 'KIDS_EVENT_OUT_OF_SCOPE'; end if;
  insert into public.attendance(organization_id,site_id,event_id,person_id,status,check_in_method,check_in_at,registered_by) values(scope.organization_id,scope.site_id,attendance_event,child_id,'PRESENT','MANUAL',now(),auth.uid()) on conflict(event_id,person_id) do update set status='PRESENT',check_in_at=now();
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values) values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_PERSON_ADDED','PERSON',child_id,jsonb_build_object('ministryId',scope.ministry_id,'existing',payload?'existingPersonId'));
 return child_id;
end; $$;

create or replace function public.create_kids_sunday_session(session_date date,start_time time)
returns uuid language plpgsql security definer set search_path='' as $$
declare scope record; result_id uuid; start_value timestamptz;
begin
 select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if; start_value:=(session_date+start_time) at time zone 'America/Bogota';
 select e.id into result_id from public.events e where e.ministry_id=scope.ministry_id and e.start_at::date=session_date and e.title='Escuela Dominical' limit 1;
 if result_id is null then
  insert into public.events(organization_id,site_id,ministry_id,organizer_person_id,event_type,title,description,start_at,end_at,modality,location,status,published_at,created_by,updated_by)
  values(scope.organization_id,scope.site_id,scope.ministry_id,(select person_id from public.user_accounts where id=auth.uid()),'MINISTRY_MEETING','Escuela Dominical','Sesión de asistencia del Ministerio Kids',start_value,start_value+interval '2 hours','IN_PERSON',scope.site_name,'SCHEDULED',now(),auth.uid(),auth.uid()) returning id into result_id;
  insert into public.event_audiences(event_id,audience_type,ministry_id,created_by) values(result_id,'MINISTRY',scope.ministry_id,auth.uid());
 end if; return result_id;
end; $$;

create or replace function public.update_kids_child_basic(target_person_id uuid,payload jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare scope record; previous jsonb; changed jsonb;
begin
 select * into scope from public.get_my_kids_scope();
 if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 if not exists(select 1 from public.person_ministries pm where pm.person_id=target_person_id and pm.ministry_id=scope.ministry_id and pm.site_id=scope.site_id and pm.active) then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 select to_jsonb(p) into previous from public.people p where p.id=target_person_id and p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null;
 if previous is null then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 update public.people set
  first_name=coalesce(nullif(trim(payload->>'firstName'),''),first_name),
  last_name=coalesce(nullif(trim(payload->>'lastName'),''),last_name),
  birth_date=coalesce(nullif(payload->>'birthDate','')::date,birth_date),
  sex=case when payload?'sex' then nullif(payload->>'sex','') else sex end,
  document_type=case when payload?'documentType' then nullif(payload->>'documentType','')::public.document_type else document_type end,
  document_number=case when payload?'documentNumber' then nullif(trim(payload->>'documentNumber'),'') else document_number end,
  phone=case when payload?'phone' then nullif(trim(payload->>'phone'),'') else phone end,
  email=case when payload?'email' then nullif(lower(trim(payload->>'email')),'') else email end
 where id=target_person_id;
 update public.person_ministries set kids_group=case when payload?'groupName' then nullif(trim(payload->>'groupName'),'') else kids_group end,status_changed_by=auth.uid() where person_id=target_person_id and ministry_id=scope.ministry_id and active;
 select to_jsonb(p)||jsonb_build_object('kidsGroup',(select pm.kids_group from public.person_ministries pm where pm.person_id=target_person_id and pm.ministry_id=scope.ministry_id and pm.active order by pm.start_date desc limit 1)) into changed from public.people p where p.id=target_person_id;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_PERSON_BASIC_UPDATED','PERSON',target_person_id,previous-'email'-'phone',changed-'email'-'phone');
end; $$;

create or replace function public.save_kids_attendance(target_event_id uuid,attendance_rows jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare scope record; row_data jsonb; child_id uuid; given_status public.attendance_status; old_status text;
begin
 select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 if not exists(select 1 from public.events e where e.id=target_event_id and e.ministry_id=scope.ministry_id and e.site_id=scope.site_id) then raise exception 'KIDS_EVENT_OUT_OF_SCOPE'; end if;
 for row_data in select value from jsonb_array_elements(attendance_rows) loop
  child_id:=(row_data->>'personId')::uuid; given_status:=(row_data->>'status')::public.attendance_status;
  if given_status not in('PRESENT','ABSENT','EXCUSED','LATE') or not exists(select 1 from public.person_ministries pm where pm.person_id=child_id and pm.ministry_id=scope.ministry_id and pm.active) then raise exception 'KIDS_ATTENDANCE_PERSON_DENIED'; end if;
  select status::text into old_status from public.attendance where event_id=target_event_id and person_id=child_id;
  insert into public.attendance(organization_id,site_id,event_id,person_id,status,check_in_method,check_in_at,registered_by) values(scope.organization_id,scope.site_id,target_event_id,child_id,given_status,'MANUAL',case when given_status in('PRESENT','LATE') then now() else null end,auth.uid()) on conflict(event_id,person_id) do update set status=excluded.status,check_in_method='MANUAL',check_in_at=excluded.check_in_at;
  insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(scope.organization_id,scope.site_id,auth.uid(),case when old_status is null then 'KIDS_ATTENDANCE_RECORDED' else 'KIDS_ATTENDANCE_UPDATED' end,'EVENT',target_event_id,case when old_status is null then null else jsonb_build_object('personId',child_id,'status',old_status) end,jsonb_build_object('personId',child_id,'status',given_status));
 end loop;
end; $$;

create or replace function public.inactivate_kids_child(target_person_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare scope record;
begin select * into scope from public.get_my_kids_scope(); if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 update public.person_ministries set active=false,end_date=current_date,status_changed_by=auth.uid() where person_id=target_person_id and ministry_id=scope.ministry_id and active;
 if not found then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values) values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_PERSON_INACTIVATED','PERSON',target_person_id,jsonb_build_object('ministryId',scope.ministry_id));
end; $$;

-- Añade permisos Kids efectivos al portal solo para alcance Kids real.
create or replace function public.get_my_portal_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb; begin
 select * into ua from public.user_accounts where id=auth.uid(); if ua.id is null or ua.person_id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name,p.organization_id into person from public.people p left join public.sites s on s.id=p.site_id where p.id=ua.person_id and p.archived_at is null; if person.id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select coalesce(jsonb_agg(distinct granted.code),'[]'::jsonb) into effective_permissions from(
  select permission.code from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions permission on permission.id=rp.permission_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and not(permission.code in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export') and public.current_user_is_restricted_discipleship_coordinator(null,null))
   and not(permission.code in('ministries.read','ministries.manage') and not public.current_user_has_pastoral_ministry_access(null,null))
   and not(permission.code in('people.read','people.create','people.update','people.archive','reports.read','reports.export') and public.current_user_is_restricted_specialized_ministry_leader(null,null))
   and not(permission.code like 'worship.%' and not exists(select 1 from public.sites site where site.organization_id=ur.organization_id and(ur.scope_type='ORGANIZATION' or site.id=ur.site_id) and public.current_user_can_manage_worship(ur.organization_id,site.id)))
  union all select 'training.manage' where public.current_user_is_training_ministry_leader(null,null)
  union all select unnest(array['kids.view','kids.create_person','kids.update_person_basic','kids.manage_members','kids.attendance.create','kids.attendance.update','kids.attendance.view_history','kids.guardian.manage']) where public.current_user_can_manage_kids(person.organization_id,person.site_id)
 )granted;
 select coalesce(jsonb_agg(distinct role.code),'[]'::jsonb) into roles_json from public.user_roles ur join public.roles role on role.id=ur.role_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 return jsonb_build_object('status',ua.access_status,'needsRegistration',false,'personId',person.id,'firstName',person.first_name,'lastName',person.last_name,'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,'permissions',effective_permissions,'roles',roles_json); end; $$;

revoke all on function public.current_user_can_manage_kids(uuid,uuid),public.get_my_kids_scope(),public.search_kids_people(text,integer),public.get_my_kids_context(),public.save_kids_child(jsonb),public.create_kids_sunday_session(date,time),public.update_kids_child_basic(uuid,jsonb),public.save_kids_attendance(uuid,jsonb),public.inactivate_kids_child(uuid) from public;
grant execute on function public.current_user_can_manage_kids(uuid,uuid),public.get_my_kids_scope(),public.search_kids_people(text,integer),public.get_my_kids_context(),public.save_kids_child(jsonb),public.create_kids_sunday_session(date,time),public.update_kids_child_basic(uuid,jsonb),public.save_kids_attendance(uuid,jsonb),public.inactivate_kids_child(uuid),public.get_my_portal_context() to authenticated;
notify pgrst,'reload schema';
