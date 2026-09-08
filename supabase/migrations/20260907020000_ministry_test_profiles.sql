-- Perfiles de prueba por ministerio. Puede repetirse después de crear identidades faltantes en Auth.
do $$ declare target_site record; leader_role uuid; item record; target_person_id uuid; auth_id uuid; target_ministry_id uuid;
begin
 select s.id,s.organization_id into target_site from public.sites s where s.active and(lower(s.name) like '%nemocón%' or lower(s.slug) like '%nemocon%') order by s.created_at limit 1;
 if target_site.id is null then raise exception 'No se encontró una sede activa CRC Nemocón'; end if;
 select id into leader_role from public.roles where code='MINISTRY_LEADER' and active;
 for item in select * from(values('Alabanza','alabanza','3009001001'),('Ujieres','ujieres','3009001002'),('CRC Kids','kids','3009001003'),('Intercesión','intercesion','3009001004'),('Caballeros','caballeros','3009001005'),('Damas','damas','3009001006'),('Parejas','parejas','3009001007'),('Formación','formacion','3009001008'),('Discipulado','discipulado','3009001009'))v(ministry_name,email_slug,test_phone)
 loop
  insert into public.ministries(organization_id,site_id,name,description,active) values(target_site.organization_id,target_site.id,item.ministry_name,'Ministerio CRC · cuenta de prueba autorizada',true) on conflict(organization_id,site_id,name) do update set active=true returning id into target_ministry_id;
  select id into target_person_id from public.people where organization_id=target_site.organization_id and lower(trim(email))='johnnatan.trujillo+'||item.email_slug||'@gmail.com' limit 1;
  if target_person_id is null then insert into public.people(organization_id,site_id,first_name,last_name,email,phone,person_status,first_visit_date) values(target_site.organization_id,target_site.id,'Líder',item.ministry_name,'johnnatan.trujillo+'||item.email_slug||'@gmail.com',item.test_phone,'LEADER',current_date) returning id into target_person_id; end if;
  insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,active) values(target_site.organization_id,target_site.id,target_person_id,target_ministry_id,'Líder de ministerio',true) on conflict(person_id,ministry_id,start_date) do update set active=true,end_date=null,position=excluded.position;
  update public.ministries set leader_person_id=target_person_id where id=target_ministry_id;
  select id into auth_id from auth.users where lower(trim(email))='johnnatan.trujillo+'||item.email_slug||'@gmail.com' limit 1;
  if auth_id is not null then
   insert into public.user_accounts(id,person_id) values(auth_id,target_person_id) on conflict(id) do update set person_id=excluded.person_id;
   update public.user_accounts set access_status='ACTIVE',requested_site_id=target_site.id where id=auth_id;
   insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,active) values(auth_id,leader_role,target_site.organization_id,'SITE',target_site.id,true) on conflict do nothing;
  end if;
 end loop;
end $$;
notify pgrst,'reload schema';
