-- Los superadministradores ya autorizados no deben ingresar a la bandeja ordinaria
-- cuando terminan de vincular su identidad con una persona.
create or replace function public.create_pending_request_after_self_registration() returns trigger
language plpgsql security definer set search_path=''
as $$
declare
  person record;
  is_super_admin boolean;
begin
  if new.person_id is null or old.person_id is not null then return new; end if;

  select p.id,p.organization_id,p.site_id,p.self_registered_at
  into person
  from public.people p
  where p.id=new.person_id;

  if person.self_registered_at is null then return new; end if;

  select exists(
    select 1
    from public.user_roles ur
    join public.roles r on r.id=ur.role_id
    where ur.user_account_id=new.id
      and r.code='SUPER_ADMIN'
      and r.active and ur.active
      and ur.starts_at<=now()
      and(ur.ends_at is null or ur.ends_at>now())
  ) into is_super_admin;

  if is_super_admin then
    update public.user_accounts
    set requested_site_id=person.site_id,
        access_status='ACTIVE',
        access_decided_at=coalesce(access_decided_at,now()),
        access_observations='Acceso conservado automáticamente por rol SUPER_ADMIN.'
    where id=new.id;

    update public.access_requests
    set status='ACTIVE',reviewed_at=now(),
        observations='Activación automática por rol SUPER_ADMIN.',updated_at=now()
    where user_account_id=new.id and status='PENDING_APPROVAL';

    insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values)
    values(person.organization_id,person.site_id,new.id,'ACCESS_AUTO_ACTIVATED','USER_ACCOUNT',new.id,
      jsonb_build_object('status','ACTIVE','reason','SUPER_ADMIN'));
    return new;
  end if;

  update public.user_accounts
  set requested_site_id=person.site_id,access_status='PENDING_APPROVAL',
      access_decided_by=null,access_decided_at=null
  where id=new.id;

  insert into public.access_requests(organization_id,site_id,user_account_id,person_id,status)
  values(person.organization_id,person.site_id,new.id,person.id,'PENDING_APPROVAL')
  on conflict(user_account_id) do update
  set site_id=excluded.site_id,person_id=excluded.person_id,status='PENDING_APPROVAL',updated_at=now();

  insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,new_values)
  values(person.organization_id,person.site_id,new.id,'ACCESS_REQUEST_CREATED','ACCESS_REQUEST',person.id,
    jsonb_build_object('status','PENDING_APPROVAL'));
  return new;
end;
$$;

-- Repara las cuentas SUPER_ADMIN que el flujo anterior dejó pendientes.
update public.user_accounts account
set access_status='ACTIVE',access_decided_at=coalesce(account.access_decided_at,now()),
    access_observations='Acceso restablecido por rol SUPER_ADMIN.'
where exists(
  select 1 from public.user_roles ur
  join public.roles r on r.id=ur.role_id
  where ur.user_account_id=account.id and r.code='SUPER_ADMIN'
    and r.active and ur.active and ur.starts_at<=now()
    and(ur.ends_at is null or ur.ends_at>now())
);

update public.access_requests request
set status='ACTIVE',reviewed_at=coalesce(request.reviewed_at,now()),
    observations='Activación automática por rol SUPER_ADMIN.',updated_at=now()
where request.status='PENDING_APPROVAL' and exists(
  select 1 from public.user_roles ur
  join public.roles r on r.id=ur.role_id
  where ur.user_account_id=request.user_account_id and r.code='SUPER_ADMIN'
    and r.active and ur.active and ur.starts_at<=now()
    and(ur.ends_at is null or ur.ends_at>now())
);

notify pgrst,'reload schema';
