-- Sprint 1: organization, sites, authentication linkage and people.
-- All tables start locked with RLS and no policies. Sprint 2 adds scoped access.

create extension if not exists pgcrypto;

do $$ begin
  create type public.person_status as enum (
    'VISITOR', 'CONGREGANT', 'MEMBER', 'SERVER', 'LEADER',
    'PASTOR', 'INACTIVE', 'TRANSFERRED'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.document_type as enum (
    'CC', 'CE', 'TI', 'PASSPORT', 'BIRTH_CERTIFICATE', 'OTHER'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 160),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sites (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 160),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  country text not null default 'Colombia',
  department text,
  city text,
  address text,
  phone text,
  email text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, slug),
  unique (organization_id, id)
);

create table if not exists public.people (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  site_id uuid not null,
  document_type public.document_type,
  document_number text,
  first_name text not null check (char_length(trim(first_name)) between 2 and 80),
  middle_name text,
  last_name text not null check (char_length(trim(last_name)) between 2 and 80),
  second_last_name text,
  preferred_name text,
  birth_date date,
  sex text,
  marital_status text,
  email text,
  phone text not null check (char_length(trim(phone)) between 7 and 30),
  secondary_phone text,
  address text,
  city text,
  department text,
  country text not null default 'Colombia',
  first_visit_date date,
  membership_date date,
  person_status public.person_status not null default 'VISITOR',
  baptized boolean not null default false,
  baptism_date date,
  discipleship_status text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint people_site_in_organization_fk
    foreign key (organization_id, site_id)
    references public.sites (organization_id, id)
    on delete restrict,
  constraint people_document_unique unique nulls not distinct (organization_id, document_type, document_number),
  constraint baptism_date_consistency check (baptized or baptism_date is null)
);

create table if not exists public.user_accounts (
  id uuid primary key references auth.users(id) on delete cascade,
  person_id uuid unique references public.people(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sites_organization_idx on public.sites (organization_id);
create index if not exists people_organization_site_idx on public.people (organization_id, site_id);
create index if not exists people_name_search_idx on public.people (organization_id, lower(last_name), lower(first_name));
create index if not exists people_phone_idx on public.people (organization_id, phone);
create index if not exists people_status_idx on public.people (organization_id, site_id, person_status);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists organizations_set_updated_at on public.organizations;
create trigger organizations_set_updated_at before update on public.organizations
for each row execute function public.set_updated_at();

drop trigger if exists sites_set_updated_at on public.sites;
create trigger sites_set_updated_at before update on public.sites
for each row execute function public.set_updated_at();

drop trigger if exists people_set_updated_at on public.people;
create trigger people_set_updated_at before update on public.people
for each row execute function public.set_updated_at();

drop trigger if exists user_accounts_set_updated_at on public.user_accounts;
create trigger user_accounts_set_updated_at before update on public.user_accounts
for each row execute function public.set_updated_at();

alter table public.organizations enable row level security;
alter table public.sites enable row level security;
alter table public.people enable row level security;
alter table public.user_accounts enable row level security;

comment on table public.people is 'Master person record; a person does not require an auth account.';
comment on table public.user_accounts is 'Optional link between Supabase Auth and a person record.';
