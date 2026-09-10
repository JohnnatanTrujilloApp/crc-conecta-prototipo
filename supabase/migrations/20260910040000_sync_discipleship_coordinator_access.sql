-- Repara y mantiene el acceso especializado de quienes lideran el Ministerio de
-- Discipulado. Es idempotente y cubre cuentas Auth creadas después del seed inicial.
do $$
declare coordinator_role_id uuid; assignment record;
begin
 select id into coordinator_role_id from public.roles where code='DISCIPLESHIP_COORDINATOR' and active;
 if coordinator_role_id is null then raise exception 'No existe el rol DISCIPLESHIP_COORDINATOR'; end if;

 insert into public.role_permissions(role_id,permission_id)
 select coordinator_role_id,p.id from public.permissions p
 where p.code in('discipleship.assign','discipleship.view_site','discipleship.record_lesson','discipleship.edit_lesson','discipleship.reassign','discipleship.complete','discipleship.manage_groups')
 on conflict do nothing;

 for assignment in
  select distinct ua.id user_account_id,m.organization_id,m.site_id
  from public.ministries m
  join public.person_ministries pm on pm.ministry_id=m.id and pm.person_id=m.leader_person_id
   and pm.active and(pm.end_date is null or pm.end_date>=current_date)
  join public.user_accounts ua on ua.person_id=pm.person_id and ua.access_status='ACTIVE'
  where m.active and lower(trim(m.name)) in('discipulado','ministerio de discipulado')
 loop
  insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,active)
  values(assignment.user_account_id,coordinator_role_id,assignment.organization_id,'SITE',assignment.site_id,true)
  on conflict do nothing;
 end loop;
end $$;

notify pgrst,'reload schema';
