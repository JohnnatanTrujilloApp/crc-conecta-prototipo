-- Gestión del equipo de Alabanza por sede, reutilizando people, ministries y person_ministries.
alter table public.person_ministries add column if not exists ministry_status text not null default 'TEAM_ACTIVE';
alter table public.person_ministries add column if not exists training_started_at date;
alter table public.person_ministries add column if not exists team_joined_at date;
alter table public.person_ministries add column if not exists ministry_notes text;
alter table public.person_ministries add column if not exists status_changed_by uuid references public.user_accounts(id) on delete set null;
alter table public.person_ministries drop constraint if exists person_ministries_ministry_status_check;
alter table public.person_ministries add constraint person_ministries_ministry_status_check check(ministry_status in('IN_TRAINING','TEAM_ACTIVE','PAUSED','INACTIVE','FORMER_MEMBER'));

create table if not exists public.worship_positions(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,code text not null,name text not null,category text not null,active boolean not null default true,created_at timestamptz not null default now(),unique(organization_id,code));
create table if not exists public.worship_instruments(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,code text not null,name text not null,active boolean not null default true,created_at timestamptz not null default now(),unique(organization_id,code));
create table if not exists public.person_worship_positions(id uuid primary key default gen_random_uuid(),person_ministry_id uuid not null references public.person_ministries(id) on delete cascade,position_id uuid not null references public.worship_positions(id) on delete restrict,level text not null default 'AVAILABLE',active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(person_ministry_id,position_id),check(level in('IN_TRAINING','AVAILABLE','PRIMARY','INACTIVE')));
create table if not exists public.person_worship_instruments(id uuid primary key default gen_random_uuid(),person_ministry_id uuid not null references public.person_ministries(id) on delete cascade,instrument_id uuid not null references public.worship_instruments(id) on delete restrict,level text not null default 'IN_TRAINING',active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(person_ministry_id,instrument_id),check(level in('IN_TRAINING','AVAILABLE','PRIMARY','INACTIVE')));
create table if not exists public.worship_membership_history(id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete restrict,site_id uuid not null,person_ministry_id uuid not null references public.person_ministries(id) on delete restrict,previous_status text,new_status text not null,changed_by uuid references public.user_accounts(id) on delete set null,notes text,changed_at timestamptz not null default now(),foreign key(organization_id,site_id) references public.sites(organization_id,id) on delete restrict);
create index if not exists worship_history_member_idx on public.worship_membership_history(person_ministry_id,changed_at desc);

insert into public.permissions(code,name,description) values
 ('worship.view_team','Ver equipo de Alabanza','Consultar el equipo autorizado de Alabanza'),('worship.manage_team','Gestionar equipo de Alabanza','Administrar pertenencia dentro del equipo'),('worship.add_candidate','Agregar candidato de Alabanza','Vincular una persona en formación'),('worship.update_candidate','Actualizar candidato de Alabanza','Actualizar su información ministerial'),('worship.promote_candidate','Promover candidato de Alabanza','Incorporar una persona al equipo activo'),('worship.assign_position','Asignar función de Alabanza','Asignar posiciones ministeriales'),('worship.assign_instrument','Asignar instrumento de Alabanza','Asignar capacidades musicales') on conflict(code) do update set name=excluded.name,description=excluded.description;
with grants(role_code,permission_code) as(values
 ('SUPER_ADMIN','worship.view_team'),('SUPER_ADMIN','worship.manage_team'),('SUPER_ADMIN','worship.add_candidate'),('SUPER_ADMIN','worship.update_candidate'),('SUPER_ADMIN','worship.promote_candidate'),('SUPER_ADMIN','worship.assign_position'),('SUPER_ADMIN','worship.assign_instrument'),
 ('NATIONAL_PASTOR','worship.view_team'),('NATIONAL_PASTOR','worship.manage_team'),('NATIONAL_PASTOR','worship.add_candidate'),('NATIONAL_PASTOR','worship.update_candidate'),('NATIONAL_PASTOR','worship.promote_candidate'),('NATIONAL_PASTOR','worship.assign_position'),('NATIONAL_PASTOR','worship.assign_instrument'),
 ('SITE_PASTOR','worship.view_team'),('SITE_PASTOR','worship.manage_team'),('SITE_PASTOR','worship.add_candidate'),('SITE_PASTOR','worship.update_candidate'),('SITE_PASTOR','worship.promote_candidate'),('SITE_PASTOR','worship.assign_position'),('SITE_PASTOR','worship.assign_instrument'),
 ('MINISTRY_LEADER','worship.view_team'),('MINISTRY_LEADER','worship.manage_team'),('MINISTRY_LEADER','worship.add_candidate'),('MINISTRY_LEADER','worship.update_candidate'),('MINISTRY_LEADER','worship.promote_candidate'),('MINISTRY_LEADER','worship.assign_position'),('MINISTRY_LEADER','worship.assign_instrument'))
insert into public.role_permissions(role_id,permission_id) select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code=g.permission_code on conflict do nothing;

create or replace function public.current_user_can_manage_worship(target_organization_id uuid,target_site_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.roles role on role.id=ur.role_id
 where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()) and ur.organization_id=target_organization_id
 and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id)) and role.code in('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR'))
 or exists(select 1 from public.user_accounts ua join public.user_roles ur on ur.user_account_id=ua.id join public.roles role on role.id=ur.role_id
 join public.ministries m on m.organization_id=ur.organization_id and m.site_id=target_site_id and m.leader_person_id=ua.person_id
 join public.person_ministries pm on pm.ministry_id=m.id and pm.person_id=ua.person_id
 where ua.id=auth.uid() and ua.access_status='ACTIVE' and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
 and ur.organization_id=target_organization_id and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
 and role.code='MINISTRY_LEADER' and m.active and pm.active and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración'));
$$;

create or replace function public.current_user_has_worship_permission(permission_code text,target_organization_id uuid,target_site_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select public.current_user_can_manage_worship(target_organization_id,target_site_id) and exists(
  select 1 from public.user_roles ur
  join public.role_permissions rp on rp.role_id=ur.role_id
  join public.permissions permission on permission.id=rp.permission_id
  where ur.user_account_id=auth.uid() and ur.organization_id=target_organization_id and ur.active
   and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
   and(ur.scope_type='ORGANIZATION' or(ur.scope_type='SITE' and ur.site_id=target_site_id))
   and permission.code=permission_code);
$$;

do $$ declare org record; begin for org in select id from public.organizations loop
 insert into public.worship_positions(organization_id,code,name,category) values(org.id,'WORSHIP_LEADER','Líder de Alabanza','DIRECCIÓN'),(org.id,'MUSIC_DIRECTOR','Director musical','DIRECCIÓN'),(org.id,'LEAD_VOCAL','Voz principal','VOCES'),(org.id,'BACKING_VOCAL','Corista / voz de apoyo','VOCES'),(org.id,'INSTRUMENTALIST','Instrumentista','INSTRUMENTISTAS') on conflict do nothing;
 insert into public.worship_instruments(organization_id,code,name) values(org.id,'PIANO','Piano'),(org.id,'KEYBOARD','Teclado'),(org.id,'ACOUSTIC_GUITAR','Guitarra acústica'),(org.id,'ELECTRIC_GUITAR','Guitarra eléctrica'),(org.id,'BASS','Bajo'),(org.id,'DRUMS','Batería'),(org.id,'PERCUSSION','Percusión'),(org.id,'OTHER','Otro') on conflict do nothing;
end loop; end $$;

create or replace function public.get_my_worship_team() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare target record; begin
 select m.id ministry_id,m.organization_id,m.site_id,s.name site_name into target from public.ministries m join public.sites s on s.id=m.site_id where m.active and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración') and public.current_user_can_manage_worship(m.organization_id,m.site_id) order by case when m.leader_person_id=(select person_id from public.user_accounts where id=auth.uid()) then 0 else 1 end limit 1;
 if target.ministry_id is null then raise exception 'WORSHIP_SCOPE_DENIED'; end if;
 if not public.current_user_has_worship_permission('worship.view_team',target.organization_id,target.site_id) then raise exception 'WORSHIP_PERMISSION_DENIED'; end if;
 return jsonb_build_object('ministryId',target.ministry_id,'siteId',target.site_id,'siteName',target.site_name,
 'positions',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'category',p.category) order by p.category,p.name) from public.worship_positions p where p.organization_id=target.organization_id and p.active),'[]'::jsonb),
 'instruments',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name) order by i.name) from public.worship_instruments i where i.organization_id=target.organization_id and i.active),'[]'::jsonb),
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',pm.id,'personId',person.id,'name',trim(concat_ws(' ',person.first_name,person.last_name)),'status',pm.ministry_status,'trainingStartedAt',pm.training_started_at,'teamJoinedAt',pm.team_joined_at,'notes',pm.ministry_notes,
 'positions',coalesce((select jsonb_agg(jsonb_build_object('id',wp.id,'name',wp.name,'level',link.level)) from public.person_worship_positions link join public.worship_positions wp on wp.id=link.position_id where link.person_ministry_id=pm.id and link.active),'[]'::jsonb),
 'instruments',coalesce((select jsonb_agg(jsonb_build_object('id',wi.id,'name',wi.name,'level',link.level)) from public.person_worship_instruments link join public.worship_instruments wi on wi.id=link.instrument_id where link.person_ministry_id=pm.id and link.active),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(jsonb_build_object('from',h.previous_status,'to',h.new_status,'at',h.changed_at,'notes',h.notes) order by h.changed_at desc) from public.worship_membership_history h where h.person_ministry_id=pm.id),'[]'::jsonb)) order by person.first_name,person.last_name) from public.person_ministries pm join public.people person on person.id=pm.person_id where pm.ministry_id=target.ministry_id),'[]'::jsonb)); end; $$;

create or replace function public.search_worship_people(search_term text,result_limit integer default 20)
returns table(id uuid,full_name text,document_number text,phone text,email text) language plpgsql stable security definer set search_path='' as $$
declare target record; normalized text:=lower(trim(search_term)); begin
 select m.organization_id,m.site_id into target from public.ministries m where m.active and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración') and public.current_user_can_manage_worship(m.organization_id,m.site_id) limit 1;
 if target.site_id is null then raise exception 'WORSHIP_SCOPE_DENIED'; end if;
 if not public.current_user_has_worship_permission('worship.add_candidate',target.organization_id,target.site_id) then raise exception 'WORSHIP_PERMISSION_DENIED'; end if;
 return query select p.id,trim(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name)),p.document_number,p.phone,p.email from public.people p where p.organization_id=target.organization_id and p.site_id=target.site_id and p.archived_at is null and p.person_status not in('INACTIVE','TRANSFERRED') and(normalized='' or lower(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name,p.document_number,p.phone,p.email)) like '%'||normalized||'%') order by p.first_name,p.last_name limit least(greatest(result_limit,1),30); end; $$;

create or replace function public.save_worship_member(target_person_id uuid,given_status text,given_position_ids uuid[],given_instruments jsonb,given_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare target record; member_id uuid; old_status text; item jsonb; begin
 select m.id ministry_id,m.organization_id,m.site_id into target from public.ministries m where m.active and lower(trim(m.name)) in('alabanza','alabanza y adoración','ministerio de alabanza','ministerio de alabanza y adoración') and public.current_user_can_manage_worship(m.organization_id,m.site_id) limit 1;
 if target.ministry_id is null then raise exception 'WORSHIP_SCOPE_DENIED'; end if; if given_status not in('IN_TRAINING','TEAM_ACTIVE','PAUSED','INACTIVE','FORMER_MEMBER') then raise exception 'WORSHIP_STATUS_INVALID'; end if;
 if not exists(select 1 from public.people p where p.id=target_person_id and p.organization_id=target.organization_id and p.site_id=target.site_id and p.archived_at is null) then raise exception 'WORSHIP_PERSON_OUT_OF_SCOPE'; end if;
 select id,ministry_status into member_id,old_status from public.person_ministries where person_id=target_person_id and ministry_id=target.ministry_id order by created_at desc limit 1;
 if member_id is null and not public.current_user_has_worship_permission('worship.add_candidate',target.organization_id,target.site_id) then raise exception 'WORSHIP_PERMISSION_DENIED'; end if;
 if member_id is not null and not public.current_user_has_worship_permission('worship.update_candidate',target.organization_id,target.site_id) then raise exception 'WORSHIP_PERMISSION_DENIED'; end if;
 if old_status='IN_TRAINING' and given_status='TEAM_ACTIVE' and not public.current_user_has_worship_permission('worship.promote_candidate',target.organization_id,target.site_id) then raise exception 'WORSHIP_PROMOTION_DENIED'; end if;
 if coalesce(array_length(given_position_ids,1),0)>0 and not public.current_user_has_worship_permission('worship.assign_position',target.organization_id,target.site_id) then raise exception 'WORSHIP_POSITION_DENIED'; end if;
 if jsonb_array_length(coalesce(given_instruments,'[]'::jsonb))>0 and not public.current_user_has_worship_permission('worship.assign_instrument',target.organization_id,target.site_id) then raise exception 'WORSHIP_INSTRUMENT_DENIED'; end if;
 if member_id is null then insert into public.person_ministries(organization_id,site_id,person_id,ministry_id,position,ministry_status,training_started_at,team_joined_at,ministry_notes,status_changed_by,active) values(target.organization_id,target.site_id,target_person_id,target.ministry_id,'Equipo de Alabanza',given_status,case when given_status='IN_TRAINING' then current_date end,case when given_status='TEAM_ACTIVE' then current_date end,nullif(trim(given_notes),''),auth.uid(),given_status not in('INACTIVE','FORMER_MEMBER')) returning id into member_id;
 else update public.person_ministries set ministry_status=given_status,training_started_at=case when given_status='IN_TRAINING' then coalesce(training_started_at,current_date) else training_started_at end,team_joined_at=case when given_status='TEAM_ACTIVE' then coalesce(team_joined_at,current_date) else team_joined_at end,ministry_notes=nullif(trim(given_notes),''),status_changed_by=auth.uid(),active=given_status not in('INACTIVE','FORMER_MEMBER') where id=member_id; end if;
 delete from public.person_worship_positions where person_ministry_id=member_id; insert into public.person_worship_positions(person_ministry_id,position_id,level) select member_id,pid,case when given_status='IN_TRAINING' then 'IN_TRAINING' else 'AVAILABLE' end from unnest(coalesce(given_position_ids,'{}'::uuid[])) pid join public.worship_positions p on p.id=pid and p.organization_id=target.organization_id;
 delete from public.person_worship_instruments where person_ministry_id=member_id; for item in select value from jsonb_array_elements(coalesce(given_instruments,'[]'::jsonb)) loop insert into public.person_worship_instruments(person_ministry_id,instrument_id,level) select member_id,i.id,case when item->>'level' in('IN_TRAINING','AVAILABLE','PRIMARY','INACTIVE') then item->>'level' else 'IN_TRAINING' end from public.worship_instruments i where i.id=(item->>'id')::uuid and i.organization_id=target.organization_id; end loop;
 if old_status is distinct from given_status then insert into public.worship_membership_history(organization_id,site_id,person_ministry_id,previous_status,new_status,changed_by,notes) values(target.organization_id,target.site_id,member_id,old_status,given_status,auth.uid(),nullif(trim(given_notes),'')); end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values) values(target.organization_id,target.site_id,auth.uid(),case when old_status='IN_TRAINING' and given_status='TEAM_ACTIVE' then 'WORSHIP_MEMBER_PROMOTED' when given_status in('INACTIVE','FORMER_MEMBER') then 'WORSHIP_MEMBER_INACTIVATED' else 'WORSHIP_MEMBER_UPDATED' end,'PERSON_MINISTRY',member_id,jsonb_build_object('status',old_status),jsonb_build_object('status',given_status)); return member_id; end; $$;

alter table public.worship_positions enable row level security; alter table public.worship_instruments enable row level security; alter table public.person_worship_positions enable row level security; alter table public.person_worship_instruments enable row level security; alter table public.worship_membership_history enable row level security;
revoke insert,update,delete on public.worship_positions,public.worship_instruments,public.person_worship_positions,public.person_worship_instruments,public.worship_membership_history from authenticated;
grant select on public.worship_positions,public.worship_instruments,public.person_worship_positions,public.person_worship_instruments,public.worship_membership_history to authenticated;
create policy worship_positions_read on public.worship_positions for select to authenticated using(exists(select 1 from public.sites s where s.organization_id=worship_positions.organization_id and public.current_user_can_manage_worship(s.organization_id,s.id)));
create policy worship_instruments_read on public.worship_instruments for select to authenticated using(exists(select 1 from public.sites s where s.organization_id=worship_instruments.organization_id and public.current_user_can_manage_worship(s.organization_id,s.id)));
create policy person_worship_positions_read on public.person_worship_positions for select to authenticated using(exists(select 1 from public.person_ministries pm where pm.id=person_ministry_id and public.current_user_can_manage_worship(pm.organization_id,pm.site_id)));
create policy person_worship_instruments_read on public.person_worship_instruments for select to authenticated using(exists(select 1 from public.person_ministries pm where pm.id=person_ministry_id and public.current_user_can_manage_worship(pm.organization_id,pm.site_id)));
create policy worship_history_read on public.worship_membership_history for select to authenticated using(public.current_user_can_manage_worship(organization_id,site_id));
revoke all on function public.current_user_can_manage_worship(uuid,uuid),public.current_user_has_worship_permission(text,uuid,uuid),public.get_my_worship_team(),public.search_worship_people(text,integer),public.save_worship_member(uuid,text,uuid[],jsonb,text) from public;
grant execute on function public.current_user_can_manage_worship(uuid,uuid),public.current_user_has_worship_permission(text,uuid,uuid),public.get_my_worship_team(),public.search_worship_people(text,integer),public.save_worship_member(uuid,text,uuid[],jsonb,text) to authenticated;

-- El portal solo expone los permisos de Alabanza al líder real del ministerio o a autoridad superior.
create or replace function public.get_my_portal_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ua record; person record; effective_permissions jsonb; roles_json jsonb; begin
 select * into ua from public.user_accounts where id=auth.uid(); if ua.id is null or ua.person_id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select p.id,p.first_name,p.last_name,p.site_id,s.name site_name into person from public.people p left join public.sites s on s.id=p.site_id where p.id=ua.person_id and p.archived_at is null; if person.id is null then return jsonb_build_object('status','PENDING_APPROVAL','needsRegistration',true,'permissions','[]'::jsonb,'roles','[]'::jsonb); end if;
 select coalesce(jsonb_agg(distinct permission.code),'[]'::jsonb) into effective_permissions from public.user_roles ur join public.role_permissions rp on rp.role_id=ur.role_id join public.permissions permission on permission.id=rp.permission_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now())
 and not(permission.code in('people.read','people.create','people.update','people.archive','families.read','families.create','families.update','training.manage','followups.read','followups.manage','reports.read','reports.export') and public.current_user_is_restricted_discipleship_coordinator(null,null))
 and not(permission.code in('ministries.read','ministries.manage') and not public.current_user_has_pastoral_ministry_access(null,null))
 and not(permission.code like 'worship.%' and not exists(select 1 from public.sites site where site.organization_id=ur.organization_id and(ur.scope_type='ORGANIZATION' or site.id=ur.site_id) and public.current_user_can_manage_worship(ur.organization_id,site.id)));
 select coalesce(jsonb_agg(distinct role.code),'[]'::jsonb) into roles_json from public.user_roles ur join public.roles role on role.id=ur.role_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now());
 return jsonb_build_object('status',ua.access_status,'needsRegistration',false,'personId',person.id,'firstName',person.first_name,'lastName',person.last_name,'siteId',coalesce(person.site_id,ua.requested_site_id),'siteName',person.site_name,'permissions',effective_permissions,'roles',roles_json); end; $$;
grant execute on function public.get_my_portal_context() to authenticated;
notify pgrst,'reload schema';
