-- Sprint 3: families, ministries, person profile support and global search.

do $$ begin
  create type public.family_relationship as enum (
    'FATHER', 'MOTHER', 'HUSBAND', 'WIFE', 'SON', 'DAUGHTER',
    'GUARDIAN', 'CAREGIVER', 'OTHER'
  );
exception when duplicate_object then null;
end $$;

create sequence if not exists public.person_crc_code_seq start 1000;
alter table public.people add column if not exists crc_code text;
alter table public.people alter column crc_code set default
  ('CRC-' || lpad(nextval('public.person_crc_code_seq')::text, 8, '0'));
update public.people set crc_code = default where crc_code is null;
alter table public.people alter column crc_code set not null;
create unique index if not exists people_crc_code_unique_idx on public.people (crc_code);
alter table public.people add constraint people_organization_site_id_unique
  unique (organization_id, site_id, id);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 160),
  address text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, site_id) references public.sites(organization_id, id) on delete cascade,
  unique (organization_id, site_id, id)
);

create table public.family_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  site_id uuid not null,
  family_id uuid not null,
  person_id uuid not null,
  relationship public.family_relationship not null default 'OTHER',
  is_primary_contact boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (organization_id, site_id, family_id)
    references public.families(organization_id, site_id, id) on delete cascade,
  foreign key (organization_id, site_id, person_id)
    references public.people(organization_id, site_id, id) on delete cascade,
  unique (family_id, person_id)
);

create table public.ministries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  site_id uuid not null,
  name text not null check (char_length(trim(name)) between 2 and 120),
  description text,
  leader_person_id uuid,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, site_id) references public.sites(organization_id, id) on delete cascade,
  foreign key (organization_id, site_id, leader_person_id)
    references public.people(organization_id, site_id, id) on delete set null,
  unique (organization_id, site_id, name),
  unique (organization_id, site_id, id)
);

create table public.person_ministries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  site_id uuid not null,
  person_id uuid not null,
  ministry_id uuid not null,
  position text not null check (char_length(trim(position)) between 2 and 100),
  start_date date not null default current_date,
  end_date date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id, site_id, person_id)
    references public.people(organization_id, site_id, id) on delete cascade,
  foreign key (organization_id, site_id, ministry_id)
    references public.ministries(organization_id, site_id, id) on delete cascade,
  check (end_date is null or end_date >= start_date),
  unique (person_id, ministry_id, start_date)
);

create index families_site_idx on public.families(organization_id, site_id) where active;
create index family_members_person_idx on public.family_members(person_id);
create index ministries_site_idx on public.ministries(organization_id, site_id) where active;
create index person_ministries_person_idx on public.person_ministries(person_id) where active;

create trigger families_set_updated_at before update on public.families
for each row execute function public.set_updated_at();
create trigger ministries_set_updated_at before update on public.ministries
for each row execute function public.set_updated_at();
create trigger person_ministries_set_updated_at before update on public.person_ministries
for each row execute function public.set_updated_at();

insert into public.permissions(code, name, description) values
  ('families.create', 'Crear familias', 'Crear familias dentro del alcance'),
  ('families.update', 'Editar familias', 'Editar familias y sus integrantes'),
  ('ministries.read', 'Ver ministerios', 'Consultar ministerios dentro del alcance'),
  ('ministries.manage', 'Gestionar ministerios', 'Crear ministerios y administrar integrantes')
on conflict(code) do update set name=excluded.name, description=excluded.description;

with grants(role_code, permission_code) as (values
  ('SUPER_ADMIN','families.create'), ('SUPER_ADMIN','families.update'),
  ('SUPER_ADMIN','ministries.read'), ('SUPER_ADMIN','ministries.manage'),
  ('NATIONAL_PASTOR','families.create'), ('NATIONAL_PASTOR','families.update'),
  ('NATIONAL_PASTOR','ministries.read'), ('NATIONAL_PASTOR','ministries.manage'),
  ('SITE_PASTOR','families.create'), ('SITE_PASTOR','families.update'),
  ('SITE_PASTOR','ministries.read'), ('SITE_PASTOR','ministries.manage'),
  ('SITE_ADMIN','families.create'), ('SITE_ADMIN','families.update'),
  ('SITE_ADMIN','ministries.read'), ('SITE_ADMIN','ministries.manage'),
  ('MINISTRY_LEADER','people.read'), ('MINISTRY_LEADER','ministries.read'),
  ('MINISTRY_LEADER','ministries.manage'),
  ('DISCIPLESHIP_COORDINATOR','families.read'), ('DISCIPLESHIP_COORDINATOR','ministries.read'),
  ('DISCIPLESHIP_TEACHER','families.read'), ('MEMBER','families.read'), ('MEMBER','ministries.read')
)
insert into public.role_permissions(role_id, permission_id)
select r.id,p.id from grants g
join public.roles r on r.code=g.role_code
join public.permissions p on p.code=g.permission_code
on conflict do nothing;

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.ministries enable row level security;
alter table public.person_ministries enable row level security;

grant select,insert,update on public.families,public.family_members,public.ministries,public.person_ministries to authenticated;
grant delete on public.family_members,public.person_ministries to authenticated;

create policy families_select_scoped on public.families for select to authenticated
using (public.current_user_has_permission('families.read',organization_id,site_id));
create policy families_insert_scoped on public.families for insert to authenticated
with check (public.current_user_has_permission('families.create',organization_id,site_id));
create policy families_update_scoped on public.families for update to authenticated
using (public.current_user_has_permission('families.update',organization_id,site_id))
with check (public.current_user_has_permission('families.update',organization_id,site_id));

create policy family_members_select_scoped on public.family_members for select to authenticated
using (public.current_user_has_permission('families.read',organization_id,site_id));
create policy family_members_insert_scoped on public.family_members for insert to authenticated
with check (public.current_user_has_permission('families.update',organization_id,site_id));
create policy family_members_update_scoped on public.family_members for update to authenticated
using (public.current_user_has_permission('families.update',organization_id,site_id))
with check (public.current_user_has_permission('families.update',organization_id,site_id));
create policy family_members_delete_scoped on public.family_members for delete to authenticated
using (public.current_user_has_permission('families.update',organization_id,site_id));

create policy ministries_select_scoped on public.ministries for select to authenticated
using (public.current_user_has_permission('ministries.read',organization_id,site_id));
create policy ministries_insert_scoped on public.ministries for insert to authenticated
with check (public.current_user_has_permission('ministries.manage',organization_id,site_id));
create policy ministries_update_scoped on public.ministries for update to authenticated
using (public.current_user_has_permission('ministries.manage',organization_id,site_id))
with check (public.current_user_has_permission('ministries.manage',organization_id,site_id));

create policy person_ministries_select_scoped on public.person_ministries for select to authenticated
using (public.current_user_has_permission('ministries.read',organization_id,site_id));
create policy person_ministries_insert_scoped on public.person_ministries for insert to authenticated
with check (public.current_user_has_permission('ministries.manage',organization_id,site_id));
create policy person_ministries_update_scoped on public.person_ministries for update to authenticated
using (public.current_user_has_permission('ministries.manage',organization_id,site_id))
with check (public.current_user_has_permission('ministries.manage',organization_id,site_id));
create policy person_ministries_delete_scoped on public.person_ministries for delete to authenticated
using (public.current_user_has_permission('ministries.manage',organization_id,site_id));

create or replace function public.search_people(search_term text, result_limit integer default 20)
returns table(
  id uuid, crc_code text, full_name text, document_number text,
  phone text, email text, site_id uuid, person_status public.person_status
)
language sql
stable
security invoker
set search_path=''
as $$
  select p.id,p.crc_code,
    concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name),
    p.document_number,p.phone,p.email,p.site_id,p.person_status
  from public.people p
  where nullif(trim(search_term),'') is not null
    and (
      concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name) ilike '%'||trim(search_term)||'%' or
      coalesce(p.document_number,'') ilike '%'||trim(search_term)||'%' or
      p.phone ilike '%'||trim(search_term)||'%' or
      coalesce(p.email,'') ilike '%'||trim(search_term)||'%' or
      p.crc_code ilike '%'||trim(search_term)||'%'
    )
  order by p.last_name,p.first_name
  limit least(greatest(result_limit,1),50);
$$;

revoke all on function public.search_people(text,integer) from public;
grant execute on function public.search_people(text,integer) to authenticated;
comment on function public.search_people(text,integer) is 'Global person search; underlying people RLS limits results by scope.';
