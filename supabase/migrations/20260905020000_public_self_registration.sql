-- Autoregistro público seguro: OAuth -> user_accounts -> people.
-- VISITOR es el estado existente equivalente a SELF_REGISTERED; self_registered_at identifica el origen.

alter table public.people add column if not exists self_registered_at timestamptz;
alter table public.people add column if not exists data_consent_at timestamptz;
alter table public.people add column if not exists currently_congregates_declared boolean;
alter table public.people add column if not exists baptized_declared boolean;
alter table public.people add column if not exists discipleship_status_declared text;

create index if not exists people_normalized_email_idx
  on public.people (organization_id, lower(trim(email)))
  where email is not null and archived_at is null;

create policy people_select_own_profile on public.people for select to authenticated
using (exists(select 1 from public.user_accounts ua where ua.id=auth.uid() and ua.person_id=people.id));

create or replace function public.get_public_registration_sites()
returns table(id uuid,organization_id uuid,name text,city text,department text)
language sql stable security definer set search_path=''
as $$
 select s.id,s.organization_id,s.name,s.city,s.department
 from public.sites s join public.organizations o on o.id=s.organization_id
 where s.active and o.active order by s.name;
$$;

revoke all on function public.get_public_registration_sites() from public;
grant execute on function public.get_public_registration_sites() to anon,authenticated;

create or replace function public.complete_self_registration(
 target_site_id uuid,
 given_first_name text,
 given_last_name text,
 given_document_type text,
 given_document_number text,
 given_birth_date date,
 given_phone text,
 given_country text,
 given_department text,
 given_city text,
 given_address text,
 given_marital_status text,
 given_currently_congregates boolean,
 given_baptized boolean,
 given_discipleship_status text,
 given_photo_url text,
 accepted_data_policy boolean
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
 current_email text;
 normalized_document text;
 selected_site record;
 linked_person_id uuid;
 document_person record;
 email_person record;
 result_status text;
begin
 if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
 if not accepted_data_policy then raise exception 'DATA_POLICY_REQUIRED'; end if;
 select lower(trim(u.email)) into current_email from auth.users u where u.id=auth.uid();
 if current_email is null then raise exception 'VERIFIED_EMAIL_REQUIRED'; end if;
 select s.id,s.organization_id into selected_site from public.sites s join public.organizations o on o.id=s.organization_id where s.id=target_site_id and s.active and o.active;
 if selected_site.id is null then raise exception 'INVALID_SITE'; end if;
 if length(trim(given_first_name))<2 or length(trim(given_last_name))<2 then raise exception 'INVALID_NAME'; end if;
 if given_birth_date is null or given_birth_date>current_date or given_birth_date<current_date-interval '120 years' then raise exception 'INVALID_BIRTH_DATE'; end if;
 if length(trim(given_phone))<7 then raise exception 'INVALID_PHONE'; end if;
 if given_document_type not in('CC','CE','TI','PASSPORT','BIRTH_CERTIFICATE','OTHER') then raise exception 'INVALID_DOCUMENT_TYPE'; end if;
 normalized_document:=upper(regexp_replace(trim(given_document_number),'[^A-Za-z0-9]','','g'));
 if length(normalized_document)<5 then raise exception 'INVALID_DOCUMENT_NUMBER'; end if;
 if given_document_type='CC' and normalized_document!~'^[0-9]{6,10}$' then raise exception 'INVALID_DOCUMENT_NUMBER'; end if;
 if given_document_type='TI' and normalized_document!~'^[0-9]{10,11}$' then raise exception 'INVALID_DOCUMENT_NUMBER'; end if;
 if given_document_type='BIRTH_CERTIFICATE' and normalized_document!~'^[A-Z0-9]{8,15}$' then raise exception 'INVALID_DOCUMENT_NUMBER'; end if;
 if given_document_type in('CE','PASSPORT','OTHER') and normalized_document!~'^[A-Z0-9]{5,20}$' then raise exception 'INVALID_DOCUMENT_NUMBER'; end if;

 insert into public.user_accounts(id) values(auth.uid()) on conflict(id) do nothing;
 select ua.person_id into linked_person_id from public.user_accounts ua where ua.id=auth.uid() for update;
 if linked_person_id is not null then
   return jsonb_build_object('status','ALREADY_REGISTERED','personId',linked_person_id,'message','Este correo ya está registrado en CRC Conecta. Inicia sesión para continuar.');
 end if;

 select p.id,p.email,p.document_type,p.document_number into document_person
 from public.people p where p.organization_id=selected_site.organization_id and p.archived_at is null
 and p.document_type::text=given_document_type
 and upper(regexp_replace(trim(p.document_number),'[^A-Za-z0-9]','','g'))=normalized_document limit 1;

 select p.id,p.email,p.document_type,p.document_number into email_person
 from public.people p where p.organization_id=selected_site.organization_id and p.archived_at is null
 and lower(trim(p.email))=current_email limit 1;

 if document_person.id is not null and email_person.id is not null and document_person.id<>email_person.id then
   return jsonb_build_object('status','VERIFICATION_REQUIRED','message','Encontramos registros diferentes asociados al correo y al documento. Solicita apoyo a la sede para verificar tu identidad.');
 end if;
 if document_person.id is not null and document_person.email is not null and lower(trim(document_person.email))<>current_email then
   return jsonb_build_object('status','VERIFICATION_REQUIRED','message','Aparentemente ya existe un registro con este documento y otro correo. Solicita apoyo a la sede para verificar tu identidad.');
 end if;

 linked_person_id:=coalesce(document_person.id,email_person.id);
 if linked_person_id is not null then
   update public.people set
    first_name=trim(given_first_name),last_name=trim(given_last_name),
    document_type=coalesce(document_type,given_document_type::public.document_type),document_number=coalesce(document_number,normalized_document),
    birth_date=coalesce(birth_date,given_birth_date),phone=trim(given_phone),email=coalesce(email,current_email),
    country=coalesce(nullif(trim(given_country),''),country),department=coalesce(nullif(trim(given_department),''),department),city=coalesce(nullif(trim(given_city),''),city),
    address=coalesce(nullif(trim(given_address),''),address),marital_status=coalesce(nullif(trim(given_marital_status),''),marital_status),photo_url=coalesce(nullif(trim(given_photo_url),''),photo_url),
    currently_congregates_declared=given_currently_congregates,baptized_declared=given_baptized,discipleship_status_declared=nullif(trim(given_discipleship_status),''),
    self_registered_at=coalesce(self_registered_at,now()),data_consent_at=now()
   where id=linked_person_id;
   result_status:='LINKED';
 else
   insert into public.people(organization_id,site_id,document_type,document_number,first_name,last_name,birth_date,email,phone,country,department,city,address,marital_status,photo_url,first_visit_date,person_status,currently_congregates_declared,baptized_declared,discipleship_status_declared,self_registered_at,data_consent_at)
   values(selected_site.organization_id,selected_site.id,given_document_type::public.document_type,normalized_document,trim(given_first_name),trim(given_last_name),given_birth_date,current_email,trim(given_phone),trim(given_country),trim(given_department),trim(given_city),nullif(trim(given_address),''),trim(given_marital_status),nullif(trim(given_photo_url),''),current_date,'VISITOR',given_currently_congregates,given_baptized,nullif(trim(given_discipleship_status),''),now(),now())
   returning id into linked_person_id;
   result_status:='CREATED';
 end if;

 update public.user_accounts set person_id=linked_person_id where id=auth.uid() and person_id is null;
 return jsonb_build_object('status',result_status,'personId',linked_person_id,'message',case when result_status='LINKED' then 'Encontramos tu registro anterior y lo vinculamos de forma segura con tu cuenta.' else '¡Bienvenido a CRC Conecta! Tu registro fue recibido correctamente.' end);
end;
$$;

revoke all on function public.complete_self_registration(uuid,text,text,text,text,date,text,text,text,text,text,text,boolean,boolean,text,text,boolean) from public;
grant execute on function public.complete_self_registration(uuid,text,text,text,text,date,text,text,text,text,text,text,boolean,boolean,text,text,boolean) to authenticated;

comment on function public.complete_self_registration(uuid,text,text,text,text,date,text,text,text,text,text,text,boolean,boolean,text,text,boolean)
is 'Crea o vincula de forma segura el perfil propio. Nunca asigna roles, permisos, ministerios ni estados pastorales.';

notify pgrst, 'reload schema';
