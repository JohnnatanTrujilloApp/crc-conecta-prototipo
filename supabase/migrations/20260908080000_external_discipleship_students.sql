-- Discipulado abierto: una persona puede estudiar en un grupo de otra sede.
-- people.site_id conserva su sede de referencia; enrollments.site_id es la sede del grupo.
do $$
declare fk record;
begin
  for fk in
    select conname from pg_constraint
    where conrelid='public.enrollments'::regclass
      and confrelid='public.people'::regclass and contype='f'
  loop
    execute format('alter table public.enrollments drop constraint %I',fk.conname);
  end loop;
  if not exists(select 1 from pg_constraint where conrelid='public.people'::regclass and conname='people_organization_id_id_key') then
    alter table public.people add constraint people_organization_id_id_key unique(organization_id,id);
  end if;
  alter table public.enrollments add constraint enrollments_organization_id_person_id_fkey
    foreign key(organization_id,person_id) references public.people(organization_id,id) on delete cascade;
end $$;

-- Directorio mínimo multisedes. Solo funciona para quien puede administrar el grupo.
create or replace function public.search_discipleship_candidates(
  target_group_id uuid, search_term text, result_limit integer default 20
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare grp record; term text; digits text; result jsonb;
begin
  select g.id,g.organization_id,g.site_id into grp from public.training_groups g
  where g.id=target_group_id and g.status<>'CANCELLED';
  if grp.id is null then raise exception 'GROUP_NOT_FOUND'; end if;
  if not public.current_user_has_permission('groups.manage',grp.organization_id,grp.site_id)
    or not public.current_user_has_permission('enrollments.manage',grp.organization_id,grp.site_id)
  then raise exception 'ACCESS_DENIED'; end if;
  term:=lower(trim(coalesce(search_term,'')));
  digits:=regexp_replace(term,'[^0-9]','','g');
  if length(term)<2 then raise exception 'SEARCH_TERM_TOO_SHORT'; end if;

  select coalesce(jsonb_agg(q.item order by q.person_name),'[]'::jsonb) into result from (
    select trim(concat_ws(' ',p.first_name,p.last_name)) person_name,
      jsonb_build_object(
        'id',p.id,'name',trim(concat_ws(' ',p.first_name,p.last_name)),
        'crcCode',p.crc_code,'siteId',p.site_id,'siteName',s.name,
        'phoneMasked',case when nullif(p.phone,'') is null then null else '***'||right(regexp_replace(p.phone,'[^0-9]','','g'),4) end,
        'documentMasked',case when nullif(p.document_number,'') is null then null else coalesce(p.document_type::text||' ','')||'***'||right(p.document_number,4) end
      ) item
    from public.people p join public.sites s on s.organization_id=p.organization_id and s.id=p.site_id
    where p.organization_id=grp.organization_id and p.archived_at is null
      and not exists(select 1 from public.enrollments e where e.group_id=grp.id and e.person_id=p.id and e.status in('ENROLLED','ACTIVE','PAUSED'))
      and (
        lower(trim(concat_ws(' ',p.first_name,p.last_name))) like '%'||term||'%'
        or lower(coalesce(p.crc_code,'')) like '%'||term||'%'
        or (length(digits)>=3 and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g') like '%'||digits||'%')
        or upper(regexp_replace(coalesce(p.document_number,''),'[^A-Za-z0-9]','','g')) like '%'||upper(regexp_replace(term,'[^A-Za-z0-9]','','g'))||'%'
      )
    order by person_name limit least(greatest(coalesce(result_limit,20),1),20)
  ) q;
  return result;
end $$;

-- Crea o reutiliza la persona y la matricula de forma atómica.
create or replace function public.register_external_discipleship_student(
  target_group_id uuid, given_first_name text, given_last_name text, given_phone text,
  given_email text default null, given_document_type text default null,
  given_document_number text default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  grp record; matched record; candidate_count integer;
  email_normalized text; phone_normalized text; document_normalized text; document_type_normalized text;
  created_new boolean:=false;
begin
  select g.id,g.organization_id,g.site_id,g.program_id into grp from public.training_groups g
  where g.id=target_group_id and g.status<>'CANCELLED';
  if grp.id is null then raise exception 'GROUP_NOT_FOUND'; end if;
  if not public.current_user_has_permission('groups.manage',grp.organization_id,grp.site_id)
    or not public.current_user_has_permission('enrollments.manage',grp.organization_id,grp.site_id)
  then raise exception 'ACCESS_DENIED'; end if;
  if length(trim(given_first_name))<2 or length(trim(given_last_name))<2 then raise exception 'INVALID_NAME'; end if;

  phone_normalized:=regexp_replace(coalesce(given_phone,''),'[^0-9]','','g');
  email_normalized:=nullif(lower(trim(given_email)),'');
  document_normalized:=nullif(upper(regexp_replace(coalesce(given_document_number,''),'[^A-Za-z0-9]','','g')),'');
  document_type_normalized:=nullif(upper(trim(given_document_type)),'');
  if length(phone_normalized)<7 then raise exception 'INVALID_PHONE'; end if;
  if email_normalized is not null and email_normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'INVALID_EMAIL'; end if;
  if (document_type_normalized is null)<>(document_normalized is null) then raise exception 'DOCUMENT_TYPE_AND_NUMBER_REQUIRED'; end if;
  if document_type_normalized is not null and document_type_normalized not in('CC','CE','TI','PASSPORT','BIRTH_CERTIFICATE','OTHER') then raise exception 'INVALID_DOCUMENT_TYPE'; end if;

  select count(distinct p.id) into candidate_count from public.people p
  where p.organization_id=grp.organization_id and p.archived_at is null and(
    (document_normalized is not null and p.document_type::text=document_type_normalized and upper(regexp_replace(coalesce(p.document_number,''),'[^A-Za-z0-9]','','g'))=document_normalized)
    or(email_normalized is not null and lower(trim(coalesce(p.email,'')))=email_normalized)
    or regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=phone_normalized
  );
  if candidate_count>1 then raise exception 'DUPLICATE_DATA_CONFLICT'; end if;

  select p.id,p.site_id,p.first_name,p.last_name into matched from public.people p
  where p.organization_id=grp.organization_id and p.archived_at is null and(
    (document_normalized is not null and p.document_type::text=document_type_normalized and upper(regexp_replace(coalesce(p.document_number,''),'[^A-Za-z0-9]','','g'))=document_normalized)
    or(email_normalized is not null and lower(trim(coalesce(p.email,'')))=email_normalized)
    or regexp_replace(coalesce(p.phone,''),'[^0-9]','','g')=phone_normalized
  ) limit 1;

  if matched.id is null then
    insert into public.people(organization_id,site_id,document_type,document_number,first_name,last_name,email,phone,person_status,currently_congregates_declared,first_visit_date)
    values(grp.organization_id,grp.site_id,document_type_normalized::public.document_type,document_normalized,trim(given_first_name),trim(given_last_name),email_normalized,phone_normalized,'VISITOR',false,null)
    returning id,site_id,first_name,last_name into matched;
    created_new:=true;
  end if;

  insert into public.enrollments(organization_id,site_id,program_id,group_id,person_id,status)
  values(grp.organization_id,grp.site_id,grp.program_id,grp.id,matched.id,'ACTIVE')
  on conflict(group_id,person_id) do update set status='ACTIVE',updated_at=now();

  return jsonb_build_object('personId',matched.id,'created',created_new,
    'crossSite',matched.site_id<>grp.site_id,'personSiteId',matched.site_id,
    'name',trim(concat_ws(' ',matched.first_name,matched.last_name)));
end $$;

revoke all on function public.search_discipleship_candidates(uuid,text,integer) from public;
grant execute on function public.search_discipleship_candidates(uuid,text,integer) to authenticated;
revoke all on function public.register_external_discipleship_student(uuid,text,text,text,text,text,text) from public;
grant execute on function public.register_external_discipleship_student(uuid,text,text,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
