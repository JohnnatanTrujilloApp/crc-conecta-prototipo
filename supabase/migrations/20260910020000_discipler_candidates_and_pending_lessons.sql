-- Permite designar como discipulador a cualquier persona activa de la organización.
-- La autorización para registrar lecciones continúa validándose de forma independiente.
create or replace function public.search_individual_discipleship_people(target_site_id uuid,search_term text,candidate_kind text,result_limit int default 20)
returns table(id uuid,name text,crc_code text,site_name text,phone_masked text,document_masked text)
language plpgsql stable security definer set search_path='' as $$
declare s record; term text:=lower(trim(search_term));
begin
 select * into s from public.sites where sites.id=target_site_id;
 if s.id is null or not public.current_user_has_permission('discipleship.assign',s.organization_id,s.id) then raise exception 'DISCIPLESHIP_SEARCH_DENIED'; end if;
 if candidate_kind not in('DISCIPLER','DISCIPLE') then raise exception 'INVALID_CANDIDATE_KIND'; end if;
 if char_length(term)<2 then return; end if;
 return query select p.id,trim(p.first_name||' '||p.last_name),p.crc_code,coalesce(ps.name,'Sin sede'),
  case when p.phone is null then null else '***'||right(regexp_replace(p.phone,'\D','','g'),4) end,
  case when p.document_number is null then null else '***'||right(p.document_number,4) end
 from public.people p left join public.sites ps on ps.id=p.site_id
 where p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')
 and (lower(p.first_name||' '||p.last_name) like '%'||term||'%' or lower(coalesce(p.email,'')) like '%'||term||'%' or regexp_replace(coalesce(p.phone,''),'\D','','g') like '%'||regexp_replace(term,'\D','','g')||'%' or lower(coalesce(p.document_number,'')) like '%'||term||'%')
 order by p.first_name,p.last_name limit least(greatest(result_limit,1),30);
end; $$;

revoke all on function public.search_individual_discipleship_people(uuid,text,text,int) from public;
grant execute on function public.search_individual_discipleship_people(uuid,text,text,int) to authenticated;
comment on function public.search_individual_discipleship_people(uuid,text,text,int) is 'Busca personas activas de la organización para discipulado; la capacidad de registrar lecciones se autoriza por separado.';
notify pgrst,'reload schema';
