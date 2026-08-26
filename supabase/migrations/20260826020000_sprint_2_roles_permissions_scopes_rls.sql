-- Sprint 2: roles, permissions, scopes and site-isolated RLS policies.

do $$ begin
  create type public.scope_type as enum ('ORGANIZATION', 'SITE');
exception when duplicate_object then null;
end $$;

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z][A-Z0-9_]*$'),
  name text not null check (char_length(trim(name)) between 2 and 120),
  description text,
  system_role boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z][a-z0-9_.]*$'),
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (role_id, permission_id)
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_account_id uuid not null references public.user_accounts(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  scope_type public.scope_type not null,
  site_id uuid,
  assigned_by uuid references public.user_accounts(id) on delete set null,
  active boolean not null default true,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_roles_scope_shape check (
    (scope_type = 'ORGANIZATION' and site_id is null) or
    (scope_type = 'SITE' and site_id is not null)
  ),
  constraint user_roles_site_organization_fk
    foreign key (organization_id, site_id)
    references public.sites (organization_id, id)
    on delete cascade,
  constraint user_roles_period check (ends_at is null or ends_at > starts_at)
);

create unique index if not exists user_roles_active_assignment_idx
  on public.user_roles (user_account_id, role_id, organization_id, scope_type, coalesce(site_id, '00000000-0000-0000-0000-000000000000'::uuid))
  where active;
create index if not exists user_roles_user_scope_idx on public.user_roles (user_account_id, organization_id, site_id) where active;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_accounts (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_created_create_account on auth.users;
create trigger auth_user_created_create_account
after insert on auth.users
for each row execute function public.handle_new_auth_user();

insert into public.user_accounts (id)
select id from auth.users
on conflict (id) do nothing;

drop trigger if exists roles_set_updated_at on public.roles;
create trigger roles_set_updated_at before update on public.roles
for each row execute function public.set_updated_at();

drop trigger if exists user_roles_set_updated_at on public.user_roles;
create trigger user_roles_set_updated_at before update on public.user_roles
for each row execute function public.set_updated_at();

create or replace function public.protect_user_role_assignment_audit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.assigned_by = auth.uid();
    else
      new.assigned_by = old.assigned_by;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists user_roles_protect_assignment_audit on public.user_roles;
create trigger user_roles_protect_assignment_audit
before insert or update on public.user_roles
for each row execute function public.protect_user_role_assignment_audit();

insert into public.permissions (code, name, description) values
  ('organizations.read', 'Ver organizaciones', 'Consultar organizaciones autorizadas'),
  ('organizations.manage', 'Administrar organizaciones', 'Actualizar la organización'),
  ('sites.read', 'Ver sedes', 'Consultar sedes autorizadas'),
  ('sites.manage', 'Administrar sedes', 'Crear y actualizar sedes'),
  ('people.read', 'Ver personas', 'Consultar personas dentro del alcance'),
  ('people.create', 'Crear personas', 'Registrar personas dentro del alcance'),
  ('people.update', 'Editar personas', 'Actualizar personas dentro del alcance'),
  ('families.read', 'Ver familias', 'Consultar familias autorizadas'),
  ('attendance.register', 'Registrar asistencia', 'Registrar asistencia autorizada'),
  ('training.manage', 'Administrar formación', 'Gestionar programas y cursos'),
  ('classes.teach', 'Dictar clase', 'Registrar clases y estudiantes asignados'),
  ('reports.read', 'Ver reportes', 'Consultar reportes autorizados'),
  ('roles.read', 'Ver accesos', 'Consultar roles, permisos y asignaciones'),
  ('roles.manage', 'Gestionar accesos', 'Asignar roles y alcances')
on conflict (code) do update set name = excluded.name, description = excluded.description;

insert into public.roles (code, name, description) values
  ('SUPER_ADMIN', 'Superadministrador', 'Control completo de una organización'),
  ('NATIONAL_PASTOR', 'Pastor nacional', 'Visualización y administración nacional'),
  ('SITE_PASTOR', 'Pastor de sede', 'Administración pastoral de una sede'),
  ('SITE_ADMIN', 'Administrador de sede', 'Administración operativa de una sede'),
  ('MINISTRY_LEADER', 'Líder de ministerio', 'Administración de su ministerio'),
  ('DISCIPLESHIP_COORDINATOR', 'Coordinador de discipulado', 'Administración del discipulado'),
  ('DISCIPLESHIP_TEACHER', 'Maestro de discipulado', 'Clases y estudiantes asignados'),
  ('COURSE_TEACHER', 'Maestro de curso', 'Gestión académica asignada'),
  ('USHER', 'Ujier', 'Registro autorizado de asistencia'),
  ('MEMBER', 'Miembro', 'Acceso personal'),
  ('STUDENT', 'Estudiante', 'Acceso a formación'),
  ('VISITOR', 'Visitante', 'Acceso limitado')
on conflict (code) do update set name = excluded.name, description = excluded.description;

with grants(role_code, permission_code) as (values
  ('SUPER_ADMIN', 'organizations.read'), ('SUPER_ADMIN', 'organizations.manage'),
  ('SUPER_ADMIN', 'sites.read'), ('SUPER_ADMIN', 'sites.manage'),
  ('SUPER_ADMIN', 'people.read'), ('SUPER_ADMIN', 'people.create'), ('SUPER_ADMIN', 'people.update'),
  ('SUPER_ADMIN', 'families.read'), ('SUPER_ADMIN', 'attendance.register'),
  ('SUPER_ADMIN', 'training.manage'), ('SUPER_ADMIN', 'classes.teach'),
  ('SUPER_ADMIN', 'reports.read'), ('SUPER_ADMIN', 'roles.read'), ('SUPER_ADMIN', 'roles.manage'),
  ('NATIONAL_PASTOR', 'organizations.read'), ('NATIONAL_PASTOR', 'sites.read'),
  ('NATIONAL_PASTOR', 'people.read'), ('NATIONAL_PASTOR', 'people.create'), ('NATIONAL_PASTOR', 'people.update'),
  ('NATIONAL_PASTOR', 'families.read'), ('NATIONAL_PASTOR', 'attendance.register'),
  ('NATIONAL_PASTOR', 'training.manage'), ('NATIONAL_PASTOR', 'classes.teach'),
  ('NATIONAL_PASTOR', 'reports.read'), ('NATIONAL_PASTOR', 'roles.read'),
  ('SITE_PASTOR', 'sites.read'), ('SITE_PASTOR', 'sites.manage'),
  ('SITE_PASTOR', 'people.read'), ('SITE_PASTOR', 'people.create'), ('SITE_PASTOR', 'people.update'),
  ('SITE_PASTOR', 'families.read'), ('SITE_PASTOR', 'attendance.register'),
  ('SITE_PASTOR', 'training.manage'), ('SITE_PASTOR', 'classes.teach'),
  ('SITE_PASTOR', 'reports.read'), ('SITE_PASTOR', 'roles.read'),
  ('SITE_ADMIN', 'sites.read'), ('SITE_ADMIN', 'people.read'), ('SITE_ADMIN', 'people.create'),
  ('SITE_ADMIN', 'people.update'), ('SITE_ADMIN', 'families.read'),
  ('SITE_ADMIN', 'attendance.register'), ('SITE_ADMIN', 'reports.read'), ('SITE_ADMIN', 'roles.read'),
  ('DISCIPLESHIP_COORDINATOR', 'people.read'), ('DISCIPLESHIP_COORDINATOR', 'people.update'),
  ('DISCIPLESHIP_COORDINATOR', 'training.manage'), ('DISCIPLESHIP_COORDINATOR', 'classes.teach'),
  ('DISCIPLESHIP_COORDINATOR', 'reports.read'),
  ('DISCIPLESHIP_TEACHER', 'people.read'), ('DISCIPLESHIP_TEACHER', 'classes.teach'),
  ('COURSE_TEACHER', 'people.read'), ('COURSE_TEACHER', 'classes.teach'),
  ('USHER', 'people.read'), ('USHER', 'attendance.register'),
  ('MEMBER', 'people.read'), ('STUDENT', 'people.read'), ('VISITOR', 'people.read')
)
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from grants g
join public.roles r on r.code = g.role_code
join public.permissions p on p.code = g.permission_code
on conflict do nothing;

create or replace function public.current_user_has_permission(
  required_permission text,
  target_organization_id uuid,
  target_site_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_account_id = auth.uid()
      and ur.active
      and ur.starts_at <= now()
      and (ur.ends_at is null or ur.ends_at > now())
      and ur.organization_id = target_organization_id
      and p.code = required_permission
      and (
        ur.scope_type = 'ORGANIZATION' or
        (target_site_id is not null and ur.scope_type = 'SITE' and ur.site_id = target_site_id)
      )
  );
$$;

create or replace function public.current_user_has_any_permission(required_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_account_id = auth.uid()
      and ur.active and ur.starts_at <= now()
      and (ur.ends_at is null or ur.ends_at > now())
      and p.code = required_permission
  );
$$;

revoke all on function public.current_user_has_permission(text, uuid, uuid) from public;
revoke all on function public.current_user_has_any_permission(text) from public;
grant execute on function public.current_user_has_permission(text, uuid, uuid) to authenticated;
grant execute on function public.current_user_has_any_permission(text) to authenticated;

alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;

grant select on public.organizations, public.sites, public.people, public.user_accounts to authenticated;
grant insert, update on public.organizations, public.sites, public.people to authenticated;
grant select on public.roles, public.permissions, public.role_permissions, public.user_roles to authenticated;
grant insert, update, delete on public.user_roles to authenticated;

create policy organizations_select_scoped on public.organizations for select to authenticated
using (public.current_user_has_permission('organizations.read', id, null));
create policy organizations_update_scoped on public.organizations for update to authenticated
using (public.current_user_has_permission('organizations.manage', id, null))
with check (public.current_user_has_permission('organizations.manage', id, null));

create policy sites_select_scoped on public.sites for select to authenticated
using (public.current_user_has_permission('sites.read', organization_id, id));
create policy sites_insert_scoped on public.sites for insert to authenticated
with check (public.current_user_has_permission('sites.manage', organization_id, id));
create policy sites_update_scoped on public.sites for update to authenticated
using (public.current_user_has_permission('sites.manage', organization_id, id))
with check (public.current_user_has_permission('sites.manage', organization_id, id));

create policy people_select_scoped on public.people for select to authenticated
using (public.current_user_has_permission('people.read', organization_id, site_id));
create policy people_insert_scoped on public.people for insert to authenticated
with check (public.current_user_has_permission('people.create', organization_id, site_id));
create policy people_update_scoped on public.people for update to authenticated
using (public.current_user_has_permission('people.update', organization_id, site_id))
with check (public.current_user_has_permission('people.update', organization_id, site_id));

create policy user_accounts_select_self on public.user_accounts for select to authenticated
using (id = auth.uid());
create policy user_accounts_select_scoped_manager on public.user_accounts for select to authenticated
using (
  exists (
    select 1 from public.people person
    where person.id = user_accounts.person_id
      and public.current_user_has_permission('roles.read', person.organization_id, person.site_id)
  )
);

create policy roles_select_authorized on public.roles for select to authenticated
using (public.current_user_has_any_permission('roles.read'));
create policy permissions_select_authorized on public.permissions for select to authenticated
using (public.current_user_has_any_permission('roles.read'));
create policy role_permissions_select_authorized on public.role_permissions for select to authenticated
using (public.current_user_has_any_permission('roles.read'));

create policy user_roles_select_self_or_manager on public.user_roles for select to authenticated
using (
  user_account_id = auth.uid() or
  public.current_user_has_permission('roles.read', organization_id, site_id)
);
create policy user_roles_insert_manager on public.user_roles for insert to authenticated
with check (public.current_user_has_permission('roles.manage', organization_id, site_id));
create policy user_roles_update_manager on public.user_roles for update to authenticated
using (public.current_user_has_permission('roles.manage', organization_id, site_id))
with check (public.current_user_has_permission('roles.manage', organization_id, site_id));
create policy user_roles_delete_manager on public.user_roles for delete to authenticated
using (public.current_user_has_permission('roles.manage', organization_id, site_id));

comment on function public.current_user_has_permission(text, uuid, uuid)
is 'Checks permission plus organization/site scope for auth.uid().';
