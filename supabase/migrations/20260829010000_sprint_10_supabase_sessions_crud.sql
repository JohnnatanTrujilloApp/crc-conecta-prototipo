-- Sprint 10: sesiones reales, contexto autorizado y borrado lógico.
alter table public.people drop constraint if exists people_document_unique;
create unique index if not exists people_document_present_unique on public.people(organization_id,document_type,document_number) where document_type is not null and document_number is not null;
alter table public.people add column if not exists archived_at timestamptz;
create index if not exists people_active_scope_idx on public.people(organization_id,site_id,created_at desc) where archived_at is null;
insert into public.permissions(code,name,description) values('people.archive','Archivar personas','Retirar registros conservando su historia') on conflict(code) do update set name=excluded.name,description=excluded.description;
with grants(role_code) as (values('SUPER_ADMIN'),('NATIONAL_PASTOR'),('SITE_PASTOR'),('SITE_ADMIN')) insert into public.role_permissions(role_id,permission_id) select r.id,p.id from grants g join public.roles r on r.code=g.role_code join public.permissions p on p.code='people.archive' on conflict do nothing;
create policy people_archive_scoped on public.people for update to authenticated using(public.current_user_has_permission('people.archive',organization_id,site_id)) with check(public.current_user_has_permission('people.archive',organization_id,site_id));
create or replace function public.protect_people_archive() returns trigger language plpgsql set search_path='' as $$ begin if old.archived_at is distinct from new.archived_at and auth.uid() is not null and not public.current_user_has_permission('people.archive',old.organization_id,old.site_id) then raise exception 'No autorizado para archivar personas'; end if; return new; end $$;
drop trigger if exists people_protect_archive on public.people;
create trigger people_protect_archive before update of archived_at on public.people for each row execute function public.protect_people_archive();
create or replace function public.get_my_access_context() returns table(role_code text,organization_id uuid,organization_name text,scope_type public.scope_type,site_id uuid,site_name text) language sql stable security definer set search_path='' as $$ select r.code,ur.organization_id,o.name,ur.scope_type,ur.site_id,s.name from public.user_roles ur join public.roles r on r.id=ur.role_id join public.organizations o on o.id=ur.organization_id left join public.sites s on s.id=ur.site_id where ur.user_account_id=auth.uid() and ur.active and ur.starts_at<=now() and(ur.ends_at is null or ur.ends_at>now()); $$;
revoke all on function public.get_my_access_context() from public;
grant execute on function public.get_my_access_context() to authenticated;
