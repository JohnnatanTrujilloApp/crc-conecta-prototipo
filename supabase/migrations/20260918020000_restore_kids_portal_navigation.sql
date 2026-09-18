-- Restaura la navegación Kids si una definición anterior del contexto del portal
-- fue ejecutada después de la migración del módulo.

-- Reafirma de forma idempotente el alcance del usuario de prueba Kids.
do $$
declare
 target record;
 auth_id uuid;
 target_person_id uuid;
 leader_role uuid;
begin
 select m.organization_id,m.site_id,m.id ministry_id
 into target
 from public.ministries m
 join public.sites s on s.id=m.site_id
 where m.active
  and lower(trim(m.name)) in('kids','crc kids','ministerio kids','ministerio de niños')
  and(lower(s.name) like '%nemocón%' or lower(s.slug) like '%nemocon%')
 order by m.created_at
 limit 1;

 select id into auth_id
 from auth.users
 where lower(trim(email))='johnnatan.trujillo+kids2@gmail.com'
 limit 1;

 if target.ministry_id is not null and auth_id is not null then
  select ua.person_id into target_person_id from public.user_accounts ua where ua.id=auth_id;
  if target_person_id is null then
   select p.id into target_person_id
   from public.people p
   where p.organization_id=target.organization_id
    and lower(trim(p.email))='johnnatan.trujillo+kids2@gmail.com'
   limit 1;
  end if;

  if target_person_id is null then
   insert into public.people(organization_id,site_id,first_name,last_name,email,person_status,first_visit_date)
   values(target.organization_id,target.site_id,'Líder','Kids','johnnatan.trujillo+kids2@gmail.com','LEADER',current_date)
   returning id into target_person_id;
  end if;

  insert into public.user_accounts(id,person_id)
  values(auth_id,target_person_id)
  on conflict(id) do update set person_id=excluded.person_id,access_status='ACTIVE',requested_site_id=target.site_id;
  update public.user_accounts set access_status='ACTIVE',requested_site_id=target.site_id where id=auth_id;

  select id into leader_role from public.roles where code='MINISTRY_LEADER' and active;
  insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,active)
  values(auth_id,leader_role,target.organization_id,'SITE',target.site_id,true)
  on conflict do nothing;

  insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,active)
  values(target.organization_id,target.site_id,target_person_id,target.ministry_id,'Líder de Kids',true)
  on conflict(person_id,ministry_id,start_date)
  do update set active=true,end_date=null,position=excluded.position,site_id=excluded.site_id;

  update public.ministries set leader_person_id=target_person_id where id=target.ministry_id;
 end if;
end $$;

-- Mantiene las restricciones de perfiles especializados y añade Kids únicamente
-- cuando el usuario dirige realmente ese ministerio dentro de su sede.
create or replace function public.get_my_portal_context()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb;
begin
 select * into ua from public.user_accounts where id=auth.uid();
 if ua.id is null or ua.person_id is null then
  return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb);
 end if;

 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name,p.organization_id
 into person
 from public.people p left join public.sites s on s.id=p.site_id
 where p.id=ua.person_id and p.archived_at is null;
 if person.id is null then
  return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb);
 end if;

 select coalesce(jsonb_agg(distinct granted.code),'[]'::jsonb)
 into effective_permissions
 from(
  select permission.code
  from public.user_roles ur
  join public.role_permissions rp on rp.role_id=ur.role_id
  join public.permissions permission on permission.id=rp.permission_id
  where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and not(permission.code in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export') and public.current_user_is_restricted_discipleship_coordinator(null,null))
   and not(permission.code in('ministries.read','ministries.manage') and not public.current_user_has_pastoral_ministry_access(null,null))
   and not(permission.code in('people.read','people.create','people.update','people.archive','reports.read','reports.export') and public.current_user_is_restricted_specialized_ministry_leader(null,null))
   and not(permission.code like 'worship.%' and not exists(select 1 from public.sites site where site.organization_id=ur.organization_id and(ur.scope_type='ORGANIZATION' or site.id=ur.site_id) and public.current_user_can_manage_worship(ur.organization_id,site.id)))
  union all select 'training.manage' where public.current_user_is_training_ministry_leader(null,null)
  union all
  select unnest(array[
   'kids.view','kids.create_person','kids.update_person_basic','kids.manage_members',
   'kids.attendance.create','kids.attendance.update','kids.attendance.view_history','kids.guardian.manage'
  ])
  where public.current_user_can_manage_kids(person.organization_id,person.site_id)
 )granted;

 select coalesce(jsonb_agg(distinct role.code),'[]'::jsonb)
 into roles_json
 from public.user_roles ur join public.roles role on role.id=ur.role_id
 where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());

 return jsonb_build_object(
  'status',ua.access_status,'needsRegistration',false,'personId',person.id,
  'firstName',person.first_name,'lastName',person.last_name,
  'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,
  'permissions',effective_permissions,'roles',roles_json
 );
end; $$;

revoke all on function public.get_my_portal_context() from public;
grant execute on function public.get_my_portal_context() to authenticated;
notify pgrst,'reload schema';
