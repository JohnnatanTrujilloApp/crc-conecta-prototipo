-- Sprint 5: reusable training programs, ordered modules and lessons.

do $$ begin
  create type public.training_program_type as enum ('DISCIPLESHIP','COURSE','SCHOOL','SEMINAR','DIPLOMA','WORKSHOP');
exception when duplicate_object then null;
end $$;

create table public.training_programs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text,
  program_type public.training_program_type not null,
  active boolean not null default true,
  created_by uuid references public.user_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,id),
  unique (organization_id,title)
);

create table public.training_modules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  program_id uuid not null,
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text,
  sort_order integer not null check (sort_order > 0),
  active boolean not null default true,
  created_by uuid references public.user_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,program_id) references public.training_programs(organization_id,id) on delete cascade,
  unique (organization_id,id),
  unique (program_id,sort_order)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  module_id uuid not null,
  title text not null check (char_length(trim(title)) between 3 and 180),
  description text,
  biblical_text text,
  central_verse text,
  content text,
  video_url text,
  audio_url text,
  document_url text,
  sort_order integer not null check (sort_order > 0),
  duration_minutes integer check (duration_minutes is null or duration_minutes between 1 and 1440),
  active boolean not null default true,
  created_by uuid references public.user_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (organization_id,module_id) references public.training_modules(organization_id,id) on delete cascade,
  unique (module_id,sort_order)
);

create index training_programs_org_idx on public.training_programs(organization_id) where active;
create index training_modules_program_idx on public.training_modules(program_id,sort_order);
create index lessons_module_idx on public.lessons(module_id,sort_order);

create trigger training_programs_set_updated_at before update on public.training_programs
for each row execute function public.set_updated_at();
create trigger training_modules_set_updated_at before update on public.training_modules
for each row execute function public.set_updated_at();
create trigger lessons_set_updated_at before update on public.lessons
for each row execute function public.set_updated_at();

create or replace function public.protect_training_audit()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='INSERT' and auth.uid() is not null then new.created_by=auth.uid(); end if;
  if tg_op='UPDATE' then new.created_by=old.created_by; end if;
  return new;
end;
$$;

create trigger training_programs_protect_audit before insert or update on public.training_programs
for each row execute function public.protect_training_audit();
create trigger training_modules_protect_audit before insert or update on public.training_modules
for each row execute function public.protect_training_audit();
create trigger lessons_protect_audit before insert or update on public.lessons
for each row execute function public.protect_training_audit();

insert into public.permissions(code,name,description) values
  ('training.read','Ver formación','Consultar programas, módulos y lecciones de la organización'),
  ('training.manage','Gestionar formación','Crear y actualizar programas, módulos y lecciones')
on conflict(code) do update set name=excluded.name,description=excluded.description;

with grants(role_code,permission_code) as (values
  ('SUPER_ADMIN','training.read'),('SUPER_ADMIN','training.manage'),
  ('NATIONAL_PASTOR','training.read'),('NATIONAL_PASTOR','training.manage'),
  ('SITE_PASTOR','training.read'),('SITE_PASTOR','training.manage'),
  ('SITE_ADMIN','training.read'),('SITE_ADMIN','training.manage'),
  ('DISCIPLESHIP_COORDINATOR','training.read'),('DISCIPLESHIP_COORDINATOR','training.manage'),
  ('DISCIPLESHIP_TEACHER','training.read'),('COURSE_TEACHER','training.read'),
  ('MINISTRY_LEADER','training.read'),('MEMBER','training.read')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g join public.roles r on r.code=g.role_code
join public.permissions p on p.code=g.permission_code on conflict do nothing;

create or replace function public.current_user_has_org_permission(required_permission text,target_organization_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists (
    select 1 from public.user_roles ur
    join public.role_permissions rp on rp.role_id=ur.role_id
    join public.permissions p on p.id=rp.permission_id
    where ur.user_account_id=auth.uid() and ur.organization_id=target_organization_id
      and ur.active and ur.starts_at<=now() and (ur.ends_at is null or ur.ends_at>now())
      and p.code=required_permission
  );
$$;
revoke all on function public.current_user_has_org_permission(text,uuid) from public;
grant execute on function public.current_user_has_org_permission(text,uuid) to authenticated;

alter table public.training_programs enable row level security;
alter table public.training_modules enable row level security;
alter table public.lessons enable row level security;
grant select,insert,update on public.training_programs,public.training_modules,public.lessons to authenticated;

create policy training_programs_select_org on public.training_programs for select to authenticated
using (public.current_user_has_org_permission('training.read',organization_id));
create policy training_programs_insert_org on public.training_programs for insert to authenticated
with check (public.current_user_has_org_permission('training.manage',organization_id));
create policy training_programs_update_org on public.training_programs for update to authenticated
using (public.current_user_has_org_permission('training.manage',organization_id))
with check (public.current_user_has_org_permission('training.manage',organization_id));

create policy training_modules_select_org on public.training_modules for select to authenticated
using (public.current_user_has_org_permission('training.read',organization_id));
create policy training_modules_insert_org on public.training_modules for insert to authenticated
with check (public.current_user_has_org_permission('training.manage',organization_id));
create policy training_modules_update_org on public.training_modules for update to authenticated
using (public.current_user_has_org_permission('training.manage',organization_id))
with check (public.current_user_has_org_permission('training.manage',organization_id));

create policy lessons_select_org on public.lessons for select to authenticated
using (public.current_user_has_org_permission('training.read',organization_id));
create policy lessons_insert_org on public.lessons for insert to authenticated
with check (public.current_user_has_org_permission('training.manage',organization_id));
create policy lessons_update_org on public.lessons for update to authenticated
using (public.current_user_has_org_permission('training.manage',organization_id))
with check (public.current_user_has_org_permission('training.manage',organization_id));

comment on function public.current_user_has_org_permission(text,uuid) is
  'Checks an active permission inside one organization, including site-scoped assignments.';
