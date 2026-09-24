-- Un rol MINISTRY_LEADER de sede puede respaldar varios liderazgos vigentes.
-- leader_person_id conserva su significado histórico; las demás designaciones
-- explícitas se reconocen por is_leader en person_ministries.
alter table public.person_ministries
 add column if not exists is_leader boolean not null default false;

-- Solo el líder principal ya documentado se migra automáticamente.
-- Las descripciones libres en position no conceden autoridad.
update public.person_ministries pm
set is_leader=true
from public.ministries m
where pm.ministry_id=m.id and pm.organization_id=m.organization_id
 and pm.site_id=m.site_id and pm.person_id=m.leader_person_id
 and m.active and pm.active and pm.start_date<=current_date
 and(pm.end_date is null or pm.end_date>=current_date)
 and not pm.is_leader;

create or replace function public.current_user_leads_ministry(target_ministry_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua
  join public.ministries m on m.id=target_ministry_id
  join public.person_ministries pm on pm.ministry_id=m.id and pm.person_id=ua.person_id
  join public.user_roles ur on ur.user_account_id=ua.id and ur.organization_id=m.organization_id
  join public.roles r on r.id=ur.role_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and m.active
   and r.code='MINISTRY_LEADER' and ur.active and ur.starts_at<=now()
   and(ur.ends_at is null or ur.ends_at>now())
   and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=m.site_id))
   and pm.active and pm.start_date<=current_date
   and(pm.end_date is null or pm.end_date>=current_date)
   and(pm.is_leader or m.leader_person_id=ua.person_id)
 );
$$;

-- Las capacidades especializadas siguen requiriendo rol, sede y ministerio.
create or replace function public.current_user_can_manage_kids(target_organization_id uuid,target_site_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id
  join public.roles r on r.id=ur.role_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active
   and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and ur.organization_id=target_organization_id
   and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
   and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
 ) or exists(
  select 1 from public.ministries m
  where m.organization_id=target_organization_id and m.site_id=target_site_id
   and m.active and lower(trim(m.name)) in('kids','crc kids','ministerio kids','ministerio de niños')
   and public.current_user_leads_ministry(m.id)
 );
$$;

create or replace function public.current_user_can_manage_worship(target_organization_id uuid,target_site_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id
  join public.roles r on r.id=ur.role_id
  where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active
   and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and ur.organization_id=target_organization_id
   and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
   and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR')
 ) or exists(
  select 1 from public.ministries m
  where m.organization_id=target_organization_id and m.site_id=target_site_id
   and m.active and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración')
   and public.current_user_leads_ministry(m.id)
 );
$$;

create or replace function public.current_user_leads_training_ministry(target_ministry_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ministries m where m.id=target_ministry_id and m.active
  and lower(trim(m.name)) in('formación','formacion','ministerio de formación','ministerio de formacion')
  and public.current_user_leads_ministry(m.id));
$$;

create or replace function public.current_user_is_training_ministry_leader(target_organization_id uuid default null,target_site_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ministries m where m.active
  and(target_organization_id is null or m.organization_id=target_organization_id)
  and(target_site_id is null or m.site_id=target_site_id)
  and public.current_user_leads_training_ministry(m.id));
$$;

create or replace function public.current_user_is_restricted_worship_leader(target_organization_id uuid default null,target_site_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ministries m where m.active
  and(target_organization_id is null or m.organization_id=target_organization_id)
  and(target_site_id is null or m.site_id=target_site_id)
  and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración')
  and public.current_user_leads_ministry(m.id))
 and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now()
   and(ur.ends_at is null or ur.ends_at>now()) and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR'));
$$;

create or replace function public.current_user_is_restricted_specialized_ministry_leader(target_organization_id uuid default null,target_site_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.ministries m where m.active
  and(target_organization_id is null or m.organization_id=target_organization_id)
  and(target_site_id is null or m.site_id=target_site_id)
  and lower(trim(m.name)) in(
   'alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración',
   'damas','ministerio de damas','caballeros','ministerio de caballeros',
   'parejas','ministerio de parejas','kids','crc kids','ministerio kids','ministerio de niños',
   'intercesión','intercesion','ministerio de intercesión','ministerio de intercesion',
   'ujieres','ministerio de ujieres','finanzas','ministerio de finanzas',
   'formación','formacion','ministerio de formación','ministerio de formacion')
  and public.current_user_leads_ministry(m.id))
 and not exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now()
   and(ur.ends_at is null or ur.ends_at>now()) and r.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR'));
$$;

-- Conservar la semántica de todas las audiencias, incluida Discipulado.
-- Únicamente se exige que la membresía ministerial ya haya comenzado.
create or replace function public.can_user_view_event(target_event_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.events e where e.id=target_event_id
   and e.published_at is not null and e.archived_at is null
   and e.status in('SCHEDULED','IN_PROGRESS')
   and coalesce(e.end_at,e.start_at)>=now()
   and(
    exists(select 1 from public.event_audiences ea where ea.event_id=e.id and ea.audience_type='PUBLIC')
    or(auth.uid() is not null
     and exists(select 1 from public.user_accounts ua where ua.id=auth.uid() and ua.access_status='ACTIVE')
     and(
      exists(select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
       where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now()
        and(ur.ends_at is null or ur.ends_at>now()) and ur.organization_id=e.organization_id
        and r.code='SUPER_ADMIN')
      or exists(select 1 from public.event_audiences ea where ea.event_id=e.id and(
       ea.audience_type in('ALL_CRC','NATIONAL')
       or(ea.audience_type='ALL_MEMBERS' and exists(
        select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id
        where ua.id=auth.uid() and p.person_status<>'VISITOR'))
       or(ea.audience_type='SITE' and exists(
        select 1 from public.user_accounts ua join public.people p on p.id=ua.person_id
        where ua.id=auth.uid() and p.site_id=ea.site_id))
       or(ea.audience_type='MINISTRY' and(
        exists(select 1 from public.user_accounts ua
         join public.person_ministries pm on pm.person_id=ua.person_id
         where ua.id=auth.uid() and pm.ministry_id=ea.ministry_id and pm.active
          and pm.start_date<=current_date
          and(pm.end_date is null or pm.end_date>=current_date))
        or exists(select 1 from public.user_accounts ua
         join public.discipleship_assignments da on da.disciple_person_id=ua.person_id
         join public.ministries ministry on ministry.id=ea.ministry_id
         where ua.id=auth.uid() and da.organization_id=e.organization_id
          and da.site_id=e.site_id and da.status in('ASSIGNED','ACTIVE','PAUSED')
          and ministry.organization_id=e.organization_id and ministry.site_id=e.site_id
          and ministry.active and lower(trim(ministry.name)) in('discipulado','ministerio de discipulado'))))
       or(ea.audience_type='ROLE' and exists(select 1 from public.user_roles ur
        where ur.user_account_id=auth.uid() and ur.role_id=ea.role_id and ur.active
         and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
         and(ea.role_scope_site_id is null or ur.scope_type='ORGANIZATION' or ur.site_id=ea.role_scope_site_id)))
       or(ea.audience_type='SPECIFIC_USERS' and ea.user_account_id=auth.uid())
      ))
     ))
   )
 );
$$;

revoke all on function public.current_user_leads_ministry(uuid),public.current_user_can_manage_kids(uuid,uuid),public.current_user_can_manage_worship(uuid,uuid),public.current_user_leads_training_ministry(uuid),public.current_user_is_training_ministry_leader(uuid,uuid),public.current_user_is_restricted_worship_leader(uuid,uuid),public.current_user_is_restricted_specialized_ministry_leader(uuid,uuid),public.can_user_view_event(uuid) from public;
grant execute on function public.current_user_leads_ministry(uuid),public.current_user_can_manage_kids(uuid,uuid),public.current_user_can_manage_worship(uuid,uuid),public.current_user_leads_training_ministry(uuid),public.current_user_is_training_ministry_leader(uuid,uuid),public.current_user_is_restricted_worship_leader(uuid,uuid),public.current_user_is_restricted_specialized_ministry_leader(uuid,uuid),public.can_user_view_event(uuid) to authenticated;

notify pgrst,'reload schema';
