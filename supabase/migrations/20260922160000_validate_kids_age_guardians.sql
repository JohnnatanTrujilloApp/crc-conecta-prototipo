-- Resolución determinista de familias activas dentro del alcance Kids.
create or replace function public.resolve_kids_family(
 target_organization_id uuid,target_site_id uuid,target_child_id uuid,target_guardian_id uuid
) returns uuid language plpgsql stable security definer set search_path='' as $$
declare chosen uuid; matches integer;
begin
 if target_child_id is null or target_guardian_id is null then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 if not exists(select 1 from public.people p where p.id=target_child_id and p.organization_id=target_organization_id and p.site_id=target_site_id and p.archived_at is null) then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 if not exists(select 1 from public.people p where p.id=target_guardian_id and p.organization_id=target_organization_id and p.site_id=target_site_id and p.archived_at is null) then raise exception 'KIDS_GUARDIAN_OUT_OF_SCOPE'; end if;

 select count(*)::integer,(array_agg(f.id))[1] into matches,chosen
 from public.families f
 join public.family_members c on c.family_id=f.id and c.person_id=target_child_id
 join public.family_members g on g.family_id=f.id and g.person_id=target_guardian_id
 where f.organization_id=target_organization_id and f.site_id=target_site_id and f.active;
 if matches>1 then raise exception 'KIDS_FAMILY_AMBIGUOUS'; end if;
 if matches=1 then return chosen; end if;

 select count(*)::integer,(array_agg(f.id))[1] into matches,chosen
 from public.families f join public.family_members fm on fm.family_id=f.id
 where f.organization_id=target_organization_id and f.site_id=target_site_id and f.active and fm.person_id=target_child_id;
 if matches>1 then raise exception 'KIDS_FAMILY_AMBIGUOUS'; end if;
 if matches=1 then return chosen; end if;

 select count(*)::integer,(array_agg(f.id))[1] into matches,chosen
 from public.families f join public.family_members fm on fm.family_id=f.id
 where f.organization_id=target_organization_id and f.site_id=target_site_id and f.active and fm.person_id=target_guardian_id;
 if matches>1 then raise exception 'KIDS_FAMILY_AMBIGUOUS'; end if;
 return chosen;
end; $$;

-- Solo devuelve la relación de esta pareja, sin permiso de lectura de familias.
create or replace function public.get_kids_guardian_link(target_child_id uuid,target_guardian_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare scope record; chosen uuid; link record;
begin
 select * into scope from public.get_my_kids_scope();
 if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 chosen:=public.resolve_kids_family(scope.organization_id,scope.site_id,target_child_id,target_guardian_id);
 if chosen is null then return jsonb_build_object('familyId',null,'relationship',null,'isPrimaryContact',null); end if;
 select fm.relationship,fm.is_primary_contact into link
 from public.family_members fm where fm.family_id=chosen and fm.person_id=target_guardian_id;
 return jsonb_build_object('familyId',chosen,'relationship',link.relationship,'isPrimaryContact',link.is_primary_contact);
end; $$;

create or replace function public.save_kids_child(payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare scope record; child_id uuid; duplicate_id uuid; guardian_id uuid; chosen_family uuid;
 birth_date date; child_sex text; requested_rel text; guardian_rel public.family_relationship;
 attendance_event uuid; existing_link boolean;
begin
 select * into scope from public.get_my_kids_scope();
 if scope.ministry_id is null then raise exception 'KIDS_SCOPE_DENIED'; end if;
 child_id:=nullif(payload->>'existingPersonId','')::uuid;
 if child_id is null then
  if nullif(trim(payload->>'firstName'),'') is null or nullif(trim(payload->>'lastName'),'') is null then raise exception 'KIDS_REQUIRED_FIELDS'; end if;
  if nullif(payload->>'birthDate','') is null then raise exception 'KIDS_BIRTH_DATE_REQUIRED'; end if;
  if nullif(payload->>'documentNumber','') is not null then
   select p.id into duplicate_id from public.people p
   where p.organization_id=scope.organization_id and p.document_number=trim(payload->>'documentNumber') and p.archived_at is null limit 1;
  end if;
  if duplicate_id is null then
   select p.id into duplicate_id from public.people p
   where p.organization_id=scope.organization_id and lower(trim(p.first_name))=lower(trim(payload->>'firstName'))
    and lower(trim(p.last_name))=lower(trim(payload->>'lastName')) and p.birth_date=(payload->>'birthDate')::date and p.archived_at is null limit 1;
  end if;
  if duplicate_id is not null then child_id:=duplicate_id;
  else
   insert into public.people(organization_id,site_id,document_type,document_number,first_name,last_name,birth_date,sex,email,phone,person_status,first_visit_date)
   values(scope.organization_id,scope.site_id,nullif(payload->>'documentType','')::public.document_type,nullif(trim(payload->>'documentNumber'),''),trim(payload->>'firstName'),trim(payload->>'lastName'),(payload->>'birthDate')::date,nullif(payload->>'sex',''),nullif(lower(trim(payload->>'email')),''),nullif(trim(payload->>'phone'),''),'VISITOR',current_date)
   returning id into child_id;
  end if;
 end if;

 -- La identidad definitiva gobierna edad y sede, incluso si se detectó un duplicado.
 select p.birth_date,p.sex into birth_date,child_sex from public.people p
 where p.id=child_id and p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null;
 if not found then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'; end if;
 if birth_date is null then raise exception 'KIDS_BIRTH_DATE_REQUIRED'; end if;
 if birth_date>current_date then raise exception 'KIDS_BIRTH_DATE_FUTURE'; end if;
 if birth_date<=(current_date-interval '18 years')::date then raise exception 'KIDS_AGE_NOT_ALLOWED'; end if;

 guardian_id:=nullif(payload->>'guardianPersonId','')::uuid;
 if guardian_id is null and nullif(trim(payload->>'guardianName'),'') is not null then
  select p.id into guardian_id from public.people p
  where p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null
   and((nullif(payload->>'guardianPhone','') is not null and p.phone=trim(payload->>'guardianPhone'))
    or(nullif(payload->>'guardianEmail','') is not null and lower(p.email)=lower(trim(payload->>'guardianEmail')))) limit 1;
  if guardian_id is null then
   insert into public.people(organization_id,site_id,first_name,last_name,email,phone,person_status,first_visit_date)
   values(scope.organization_id,scope.site_id,split_part(trim(payload->>'guardianName'),' ',1),coalesce(nullif(trim(substr(trim(payload->>'guardianName'),length(split_part(trim(payload->>'guardianName'),' ',1))+1)),''),'Acudiente'),nullif(lower(trim(payload->>'guardianEmail')),''),nullif(trim(payload->>'guardianPhone'),''),'VISITOR',current_date)
   returning id into guardian_id;
  end if;
 end if;

 if guardian_id is not null then
  chosen_family:=public.resolve_kids_family(scope.organization_id,scope.site_id,child_id,guardian_id);
  if chosen_family is not null then
   select exists(select 1 from public.family_members fm where fm.family_id=chosen_family and fm.person_id=guardian_id) into existing_link;
  end if;
  if not coalesce(existing_link,false) then
   requested_rel:=payload->>'guardianRelationship';
   if requested_rel is null or requested_rel not in('FATHER','MOTHER','GUARDIAN','CAREGIVER','OTHER') then raise exception 'KIDS_GUARDIAN_RELATIONSHIP_REQUIRED'; end if;
   guardian_rel:=requested_rel::public.family_relationship;
  end if;
 end if;

 insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,active)
 values(scope.organization_id,scope.site_id,child_id,scope.ministry_id,'Participante Kids',true)
 on conflict(person_id,ministry_id,start_date) do update set active=true,end_date=null,position=excluded.position;

 if guardian_id is not null then
  if chosen_family is null then
   insert into public.families(organization_id,site_id,name,active)
   values(scope.organization_id,scope.site_id,'Familia '||(select p.last_name from public.people p where p.id=child_id),true)
   returning id into chosen_family;
  end if;
  insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact)
  values(scope.organization_id,scope.site_id,chosen_family,child_id,
   case child_sex when 'F' then 'DAUGHTER'::public.family_relationship when 'M' then 'SON'::public.family_relationship else 'OTHER'::public.family_relationship end,false)
  on conflict(family_id,person_id) do nothing;
  if not coalesce(existing_link,false) then
   insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact)
   values(scope.organization_id,scope.site_id,chosen_family,guardian_id,guardian_rel,coalesce((payload->>'primaryContact')::boolean,true))
   on conflict(family_id,person_id) do update set is_primary_contact=excluded.is_primary_contact;
  else
   update public.family_members set is_primary_contact=coalesce((payload->>'primaryContact')::boolean,true)
   where family_id=chosen_family and person_id=guardian_id;
  end if;
  insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values)
  values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_GUARDIAN_LINKED','PERSON',child_id,
   jsonb_build_object('guardianId',guardian_id,'familyId',chosen_family));
 end if;

 attendance_event:=nullif(payload->>'attendanceEventId','')::uuid;
 if attendance_event is not null then
  if not exists(select 1 from public.events e where e.id=attendance_event and e.ministry_id=scope.ministry_id and e.site_id=scope.site_id) then raise exception 'KIDS_EVENT_OUT_OF_SCOPE'; end if;
  insert into public.attendance(organization_id,site_id,event_id,person_id,status,check_in_method,check_in_at,registered_by)
  values(scope.organization_id,scope.site_id,attendance_event,child_id,'PRESENT','MANUAL',now(),auth.uid())
  on conflict(event_id,person_id) do update set status='PRESENT',check_in_at=now();
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values)
 values(scope.organization_id,scope.site_id,auth.uid(),'KIDS_PERSON_ADDED','PERSON',child_id,jsonb_build_object('ministryId',scope.ministry_id,'existing',payload?'existingPersonId'));
 return child_id;
end; $$;

revoke all on function public.resolve_kids_family(uuid,uuid,uuid,uuid),public.get_kids_guardian_link(uuid,uuid),public.save_kids_child(jsonb) from public;
revoke all on function public.resolve_kids_family(uuid,uuid,uuid,uuid),public.get_kids_guardian_link(uuid,uuid),public.save_kids_child(jsonb) from anon,authenticated;
grant execute on function public.get_kids_guardian_link(uuid,uuid),public.save_kids_child(jsonb) to authenticated;
notify pgrst,'reload schema';
