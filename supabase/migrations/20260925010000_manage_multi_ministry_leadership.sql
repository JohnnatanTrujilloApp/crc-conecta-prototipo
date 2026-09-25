-- Nombramientos ministeriales explícitos; no ejecutada automáticamente en DEV.
insert into public.permissions(code,name,description)
values ('ministries.manage_leadership','Administrar liderazgos ministeriales','Otorgar o retirar liderazgo ministerial dentro del alcance pastoral')
on conflict(code) do nothing;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code in ('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
  and p.code='ministries.manage_leadership'
on conflict do nothing;

-- Permite distinguir un rol creado por este flujo de un rol preexistente.
alter table public.user_roles
 add column if not exists ministry_leadership_managed boolean not null default false;

-- El cliente conserva las modificaciones ordinarias de membresía, pero nunca
-- puede escribir is_leader directamente sin la RPC y su auditoría atómica.
revoke update on public.person_ministries from authenticated;
revoke insert on public.person_ministries from authenticated;
grant insert(organization_id,site_id,person_id,ministry_id,position,start_date,end_date,
 active,ministry_status,training_started_at,team_joined_at,ministry_notes,
 status_changed_by,kids_group,created_at,updated_at)
on public.person_ministries to authenticated;
grant update(position,start_date,end_date,active,ministry_status,training_started_at,
 team_joined_at,ministry_notes,status_changed_by,kids_group,updated_at)
on public.person_ministries to authenticated;

create or replace function public.set_ministry_leadership(
 target_person_id uuid,target_ministry_id uuid,given_is_leader boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare
 actor_id uuid:=auth.uid(); target public.ministries%rowtype;
 member public.person_ministries%rowtype; account_id uuid; ministry_role_id uuid;
 existing_role public.user_roles%rowtype; other_leadership boolean;
begin
 if actor_id is null or given_is_leader is null then raise exception 'MINISTRY_LEADERSHIP_DENIED'; end if;
 select * into target from public.ministries where id=target_ministry_id and active for update;
 if not found then raise exception 'MINISTRY_NOT_FOUND'; end if;
 if not exists(select 1 from public.user_accounts where id=actor_id and access_status='ACTIVE')
    or not public.current_user_has_permission('ministries.manage_leadership',target.organization_id,target.site_id)
    or not exists(
      select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
      where ur.user_account_id=actor_id and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
       and ur.organization_id=target.organization_id and ur.active
       and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
       and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target.site_id))
    ) then raise exception 'MINISTRY_LEADERSHIP_DENIED'; end if;
 if not exists(select 1 from public.people p where p.id=target_person_id
   and p.organization_id=target.organization_id and p.site_id=target.site_id and p.archived_at is null)
 then raise exception 'MINISTRY_PERSON_OUT_OF_SCOPE'; end if;
 select * into member from public.person_ministries pm
 where pm.person_id=target_person_id and pm.ministry_id=target.id
  and pm.organization_id=target.organization_id and pm.site_id=target.site_id
  and pm.active and pm.start_date<=current_date
  and(pm.end_date is null or pm.end_date>=current_date)
 order by pm.start_date desc,pm.id desc limit 1 for update;
 if not found then raise exception 'MINISTRY_MEMBERSHIP_REQUIRED'; end if;
 if member.is_leader=given_is_leader then return given_is_leader; end if;
 if not given_is_leader and target.leader_person_id=target_person_id
 then raise exception 'MINISTRY_PRIMARY_LEADER_CHANGE_REQUIRED'; end if;
 select ua.id into account_id from public.user_accounts ua
 where ua.person_id=target_person_id and ua.access_status='ACTIVE' for update;
 if account_id is null then raise exception 'MINISTRY_ACCOUNT_REQUIRED'; end if;
 select id into ministry_role_id from public.roles where code='MINISTRY_LEADER' and active;
 if ministry_role_id is null then raise exception 'MINISTRY_LEADER_ROLE_MISSING'; end if;
 -- Bloqueo por cuenta para serializar nombramientos simultáneos de ministerios distintos.
 perform 1 from public.user_accounts where id=account_id for update;
 if given_is_leader then
   select ur.* into existing_role from public.user_roles ur
   where ur.user_account_id=account_id and ur.role_id=ministry_role_id
    and ur.organization_id=target.organization_id and ur.active
    and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
    and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target.site_id))
   order by case when ur.scope_type='SITE' then 0 else 1 end limit 1 for update;
   if existing_role.id is null then
     if exists(select 1 from public.user_roles ur where ur.user_account_id=account_id
       and ur.role_id=ministry_role_id and ur.organization_id=target.organization_id
       and ur.scope_type='SITE' and ur.site_id=target.site_id and ur.active)
     then raise exception 'MINISTRY_ROLE_CONFLICT'; end if;
     insert into public.user_roles(user_account_id,role_id,organization_id,scope_type,site_id,
       assigned_by,active,starts_at,ministry_leadership_managed)
     values(account_id,ministry_role_id,target.organization_id,'SITE',target.site_id,
       actor_id,true,now(),true);
   end if;
 end if;
 update public.person_ministries set is_leader=given_is_leader where id=member.id;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
 values(target.organization_id,target.site_id,actor_id,
  case when given_is_leader then 'MINISTRY_LEADERSHIP_GRANTED' else 'MINISTRY_LEADERSHIP_REVOKED' end,
  'PERSON_MINISTRY',member.id,
  jsonb_build_object('personId',target_person_id,'ministryId',target.id,'isLeader',member.is_leader),
  jsonb_build_object('personId',target_person_id,'ministryId',target.id,'isLeader',given_is_leader));
 if not given_is_leader then
   select exists(select 1 from public.person_ministries pm
    join public.ministries m on m.id=pm.ministry_id
    where pm.person_id=target_person_id and pm.organization_id=target.organization_id
     and pm.site_id=target.site_id and m.active and pm.active
     and pm.start_date<=current_date and(pm.end_date is null or pm.end_date>=current_date)
     and(pm.is_leader or m.leader_person_id=target_person_id)) into other_leadership;
   if not other_leadership then
     update public.user_roles ur set active=false,ends_at=case when ur.starts_at<now() then now() else ur.ends_at end
     where ur.user_account_id=account_id and ur.role_id=ministry_role_id
      and ur.organization_id=target.organization_id and ur.scope_type='SITE'
      and ur.site_id=target.site_id and ur.active and ur.ministry_leadership_managed;
   end if;
 end if;
 return given_is_leader;
end; $$;
revoke all on function public.set_ministry_leadership(uuid,uuid,boolean) from public;
grant execute on function public.set_ministry_leadership(uuid,uuid,boolean) to authenticated;
notify pgrst,'reload schema';
