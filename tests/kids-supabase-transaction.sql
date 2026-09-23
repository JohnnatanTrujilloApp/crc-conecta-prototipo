-- Ejecutar solo en crc-conecta-dev. Los registros son sintéticos y se revierten.
begin;
do $$
declare
  scope record;
  test_user uuid;
  minor_id uuid;
  adult_id uuid;
  unknown_age_id uuid;
  future_id uuid;
  guardian_id uuid;
  second_minor_id uuid;
  second_guardian_id uuid;
  second_family_id uuid;
  family_one uuid;
  family_two uuid;
  duplicate_doc text := 'KIDSTEST-' || left(gen_random_uuid()::text, 8);
  relation public.family_relationship;
begin
  select id into test_user from auth.users where lower(email)='johnnatan.trujillo+kids2@gmail.com';
  if test_user is null then raise exception 'TEST_KIDS_USER_MISSING'; end if;
  perform set_config('request.jwt.claim.sub', test_user::text, true);
  select * into scope from public.get_my_kids_scope();
  if scope.ministry_id is null then raise exception 'TEST_KIDS_SCOPE_MISSING'; end if;

  insert into public.people(organization_id,site_id,first_name,last_name,birth_date,sex,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Minor','Kids QA',(current_date-interval '17 years')::date,'M','VISITOR',current_date)
  returning id into minor_id;
  insert into public.people(organization_id,site_id,first_name,last_name,birth_date,sex,document_number,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Adult','Kids QA',(current_date-interval '18 years')::date,'M',duplicate_doc,'VISITOR',current_date)
  returning id into adult_id;
  insert into public.people(organization_id,site_id,first_name,last_name,sex,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic No Birth','Kids QA','M','VISITOR',current_date)
  returning id into unknown_age_id;
  insert into public.people(organization_id,site_id,first_name,last_name,birth_date,sex,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Future','Kids QA',current_date+1,'M','VISITOR',current_date)
  returning id into future_id;
  insert into public.people(organization_id,site_id,first_name,last_name,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Guardian','Kids QA','VISITOR',current_date)
  returning id into guardian_id;

  begin
    perform public.save_kids_child(jsonb_build_object('existingPersonId',adult_id));
    raise exception 'TEST_ADULT_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_AGE_NOT_ALLOWED' then raise; end if;
  end;
  begin
    perform public.save_kids_child(jsonb_build_object('firstName','Synthetic Adult','lastName','Kids QA','birthDate',(current_date-interval '17 years')::date,'documentNumber',duplicate_doc));
    raise exception 'TEST_DUPLICATE_ADULT_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_AGE_NOT_ALLOWED' then raise; end if;
  end;
  begin
    perform public.save_kids_child(jsonb_build_object('existingPersonId',unknown_age_id));
    raise exception 'TEST_MISSING_AGE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_BIRTH_DATE_REQUIRED' then raise; end if;
  end;
  begin
    perform public.save_kids_child(jsonb_build_object('existingPersonId',future_id));
    raise exception 'TEST_FUTURE_AGE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_BIRTH_DATE_FUTURE' then raise; end if;
  end;

  insert into public.families(organization_id,site_id,name,active)
  values(scope.organization_id,scope.site_id,'Synthetic Kids Family One',true)
  returning id into family_one;
  insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact)
  values(scope.organization_id,scope.site_id,family_one,minor_id,'SON',false),
        (scope.organization_id,scope.site_id,family_one,guardian_id,'FATHER',true);
  perform public.save_kids_child(jsonb_build_object('existingPersonId',minor_id,'guardianPersonId',guardian_id,'guardianRelationship','GUARDIAN'));
  select fm.relationship into relation from public.family_members fm
  where fm.family_id=family_one and fm.person_id=guardian_id;
  if relation <> 'FATHER' then raise exception 'TEST_FATHER_OVERWRITTEN'; end if;
  if public.resolve_kids_family(scope.organization_id,scope.site_id,minor_id,guardian_id) <> family_one then
    raise exception 'TEST_SHARED_FAMILY_NOT_PREFERRED';
  end if;
  if public.get_kids_guardian_link(minor_id,guardian_id)->>'relationship' <> 'FATHER' then
    raise exception 'TEST_EXISTING_RELATION_NOT_VISIBLE';
  end if;
  begin
    perform public.resolve_kids_family(scope.organization_id,gen_random_uuid(),minor_id,guardian_id);
    raise exception 'TEST_OTHER_SITE_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_PERSON_OUT_OF_SCOPE' then raise; end if;
  end;

  insert into public.people(organization_id,site_id,first_name,last_name,birth_date,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Other Minor','Kids QA',(current_date-interval '10 years')::date,'VISITOR',current_date)
  returning id into second_minor_id;
  insert into public.people(organization_id,site_id,first_name,last_name,person_status,first_visit_date)
  values(scope.organization_id,scope.site_id,'Synthetic Other Guardian','Kids QA','VISITOR',current_date)
  returning id into second_guardian_id;
  perform public.save_kids_child(jsonb_build_object('existingPersonId',second_minor_id,'guardianPersonId',second_guardian_id,'guardianRelationship','MOTHER'));
  select fm.family_id into second_family_id from public.family_members fm where fm.person_id=second_minor_id;
  if (select fm.relationship from public.family_members fm where fm.family_id=second_family_id and fm.person_id=second_minor_id) <> 'OTHER' then
    raise exception 'TEST_UNKNOWN_SEX_NOT_OTHER';
  end if;
  if (select fm.relationship from public.family_members fm where fm.family_id=second_family_id and fm.person_id=second_guardian_id) <> 'MOTHER' then
    raise exception 'TEST_SELECTED_RELATION_NOT_CREATED';
  end if;
  perform public.save_kids_child(jsonb_build_object('existingPersonId',second_minor_id,'guardianPersonId',second_guardian_id,'guardianRelationship','GUARDIAN'));
  if (select count(*) from public.family_members fm where fm.family_id=second_family_id and fm.person_id in (second_minor_id,second_guardian_id)) <> 2 then
    raise exception 'TEST_REPEAT_CREATED_DUPLICATES';
  end if;
  if (select fm.relationship from public.family_members fm where fm.family_id=second_family_id and fm.person_id=second_guardian_id) <> 'MOTHER' then
    raise exception 'TEST_REPEAT_CHANGED_RELATION';
  end if;

  insert into public.families(organization_id,site_id,name,active)
  values(scope.organization_id,scope.site_id,'Synthetic Kids Family Two',true)
  returning id into family_two;
  insert into public.family_members(organization_id,site_id,family_id,person_id,relationship,is_primary_contact)
  values(scope.organization_id,scope.site_id,family_two,minor_id,'SON',false),
        (scope.organization_id,scope.site_id,family_two,guardian_id,'FATHER',true);
  begin
    perform public.resolve_kids_family(scope.organization_id,scope.site_id,minor_id,guardian_id);
    raise exception 'TEST_AMBIGUOUS_FAMILY_ACCEPTED';
  exception when others then
    if sqlerrm <> 'KIDS_FAMILY_AMBIGUOUS' then raise; end if;
  end;
end $$;
rollback;
