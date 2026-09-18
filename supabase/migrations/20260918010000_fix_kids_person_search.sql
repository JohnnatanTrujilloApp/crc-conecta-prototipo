-- Separate child lookup (which may match a guardian) from the guardian picker.
drop function if exists public.search_kids_people(text,integer);

create or replace function public.search_kids_people(
 search_term text,
 result_limit integer default 20,
 include_guardian_matches boolean default true
)
returns table(id uuid,name text,"birthDate" date,"documentNumber" text,phone text)
language plpgsql stable security definer set search_path='' as $$
declare scope record; normalized text:=lower(trim(coalesce(search_term,'')));
begin
 select * into scope from public.get_my_kids_scope();
 if scope.ministry_id is null or length(normalized)<2 then return; end if;
 return query
 select p.id,trim(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name)),p.birth_date,p.document_number,p.phone
 from public.people p
 where p.organization_id=scope.organization_id and p.site_id=scope.site_id and p.archived_at is null
  and(
   lower(concat_ws(' ',p.first_name,p.middle_name,p.last_name,p.second_last_name,p.document_number,p.crc_code,coalesce(p.phone,''))) like '%'||normalized||'%'
   or(include_guardian_matches and exists(
    select 1 from public.family_members child_link
    join public.family_members guardian_link on guardian_link.family_id=child_link.family_id and guardian_link.person_id<>child_link.person_id
    join public.people guardian on guardian.id=guardian_link.person_id
    where child_link.person_id=p.id
     and lower(concat_ws(' ',guardian.first_name,guardian.middle_name,guardian.last_name,guardian.second_last_name,guardian.document_number,coalesce(guardian.phone,''))) like '%'||normalized||'%'
   ))
  )
 order by p.first_name,p.last_name limit least(greatest(result_limit,1),30);
end; $$;

revoke all on function public.search_kids_people(text,integer,boolean) from public;
grant execute on function public.search_kids_people(text,integer,boolean) to authenticated;
notify pgrst,'reload schema';
