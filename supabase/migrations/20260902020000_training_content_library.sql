-- Formación 2.0: biblioteca multimedia privada para cada lección.
do $$ begin
 create type public.lesson_resource_type as enum ('FILE','PDF','PRESENTATION','IMAGE','AUDIO','LINK','YOUTUBE');
exception when duplicate_object then null; end $$;

create table if not exists public.lesson_resources (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
 lesson_id uuid not null references public.lessons(id) on delete cascade, title text not null check(char_length(trim(title)) between 1 and 220),
 resource_type public.lesson_resource_type not null, source_url text, storage_path text, mime_type text,
 file_size_bytes bigint check(file_size_bytes is null or file_size_bytes between 0 and 26214400), sort_order integer not null check(sort_order>0),
 active boolean not null default true, created_by uuid references public.user_accounts(id) on delete set null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint lesson_resource_source check((resource_type in ('LINK','YOUTUBE') and source_url is not null and storage_path is null) or (resource_type not in ('LINK','YOUTUBE') and storage_path is not null and source_url is null)),
 unique(lesson_id,sort_order), unique(storage_path)
);
create index if not exists lesson_resources_lesson_idx on public.lesson_resources(lesson_id,sort_order) where active;
create trigger lesson_resources_set_updated_at before update on public.lesson_resources for each row execute function public.set_updated_at();
create trigger lesson_resources_protect_audit before insert or update on public.lesson_resources for each row execute function public.protect_training_audit();
alter table public.lesson_resources enable row level security;
grant select,insert,update,delete on public.lesson_resources to authenticated;
create policy lesson_resources_select_org on public.lesson_resources for select to authenticated using(public.current_user_has_org_permission('training.read',organization_id));
create policy lesson_resources_insert_org on public.lesson_resources for insert to authenticated with check(public.current_user_has_org_permission('training.manage',organization_id));
create policy lesson_resources_update_org on public.lesson_resources for update to authenticated using(public.current_user_has_org_permission('training.manage',organization_id)) with check(public.current_user_has_org_permission('training.manage',organization_id));
create policy lesson_resources_delete_org on public.lesson_resources for delete to authenticated using(public.current_user_has_org_permission('training.manage',organization_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('training-materials','training-materials',false,26214400,array['application/pdf','image/jpeg','image/png','image/webp','image/gif','audio/mpeg','audio/mp4','audio/ogg','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','text/plain']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.training_storage_allowed(object_name text,required_permission text) returns boolean language plpgsql stable security definer set search_path='' as $$
declare org_id uuid; begin if split_part(object_name,'/',1)!~'^[0-9a-fA-F-]{36}$' then return false; end if; org_id:=split_part(object_name,'/',1)::uuid; return public.current_user_has_org_permission(required_permission,org_id); exception when others then return false; end; $$;
revoke all on function public.training_storage_allowed(text,text) from public;
grant execute on function public.training_storage_allowed(text,text) to authenticated;
create policy training_materials_read on storage.objects for select to authenticated using(bucket_id='training-materials' and public.training_storage_allowed(name,'training.read'));
create policy training_materials_insert on storage.objects for insert to authenticated with check(bucket_id='training-materials' and public.training_storage_allowed(name,'training.manage'));
create policy training_materials_update on storage.objects for update to authenticated using(bucket_id='training-materials' and public.training_storage_allowed(name,'training.manage')) with check(bucket_id='training-materials' and public.training_storage_allowed(name,'training.manage'));
create policy training_materials_delete on storage.objects for delete to authenticated using(bucket_id='training-materials' and public.training_storage_allowed(name,'training.manage'));
