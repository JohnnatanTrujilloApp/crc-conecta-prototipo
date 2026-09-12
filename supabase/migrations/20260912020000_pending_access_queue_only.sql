-- La bandeja de decisiones contiene únicamente solicitudes aún pendientes.
create or replace function public.list_authorized_access_requests()
returns jsonb
language sql stable security definer set search_path=''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', request.id,'status',request.status,'created_at',request.created_at,
    'possible_duplicate',request.possible_duplicate,
    'observations',coalesce(request.observations,''),
    'person',jsonb_build_object(
      'first_name',person.first_name,'last_name',person.last_name,
      'email',person.email,'phone',person.phone,
      'document_type',person.document_type,'document_number',person.document_number
    ),
    'site',jsonb_build_object('name',site.name)
  ) order by request.created_at desc),'[]'::jsonb)
  from public.access_requests request
  join public.people person on person.id=request.person_id
  join public.sites site on site.id=request.site_id
  where request.status='PENDING_APPROVAL'
    and public.current_user_has_permission(
      'access_requests.review',request.organization_id,request.site_id
    );
$$;

revoke all on function public.list_authorized_access_requests() from public;
grant execute on function public.list_authorized_access_requests() to authenticated;

-- Refuerzo de servidor: una solicitud ya resuelta no puede volver a decidirse
-- desde la bandeja, incluso si un cliente antiguo intenta hacerlo.
create or replace function public.review_access_request(target_request_id uuid,decision text,given_observations text default null) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare request_row record; next_status public.campus_access_status; recipient text;
begin
 select ar.* into request_row from public.access_requests ar where ar.id=target_request_id for update;
 if request_row.id is null then raise exception 'REQUEST_NOT_FOUND'; end if;
 if request_row.status<>'PENDING_APPROVAL' then raise exception 'REQUEST_ALREADY_DECIDED'; end if;
 if request_row.user_account_id=auth.uid() then raise exception 'SELF_APPROVAL_DENIED'; end if;
 if not public.current_user_has_permission('access_requests.review',request_row.organization_id,request_row.site_id) then raise exception 'ACCESS_DENIED'; end if;
 next_status:=case upper(decision)
   when 'APPROVE' then 'ACTIVE'::public.campus_access_status
   when 'REJECT' then 'REJECTED'::public.campus_access_status
   else null
 end;
 if next_status is null then raise exception 'INVALID_DECISION'; end if;
 update public.access_requests set status=next_status,reviewed_by=auth.uid(),reviewed_at=now(),observations=nullif(trim(given_observations),'') where id=request_row.id;
 update public.user_accounts set access_status=next_status,access_decided_by=auth.uid(),access_decided_at=now(),access_observations=nullif(trim(given_observations),'') where id=request_row.user_account_id;
 if next_status='ACTIVE' then
  insert into public.user_notifications(user_account_id,kind,title,message,link)
  values(request_row.user_account_id,'CAMPUS_ACCESS_APPROVED','Tu acceso fue habilitado','Tu acceso a CRC Conecta ha sido habilitado.','/campus');
  select lower(trim(email)) into recipient from auth.users where id=request_row.user_account_id;
  if recipient is not null then
   insert into public.email_delivery_queue(user_account_id,recipient_email,template_code,payload)
   values(request_row.user_account_id,recipient,'CAMPUS_ACCESS_APPROVED',jsonb_build_object('link','/campus'));
  end if;
 end if;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
 values(request_row.organization_id,request_row.site_id,auth.uid(),case next_status when 'ACTIVE' then 'CAMPUS_ACCESS_APPROVED' else 'CAMPUS_ACCESS_REJECTED' end,'ACCESS_REQUEST',request_row.id,jsonb_build_object('status',request_row.status),jsonb_build_object('status',next_status,'observations',given_observations));
 return jsonb_build_object('id',request_row.id,'status',next_status);
end;
$$;

revoke all on function public.review_access_request(uuid,text,text) from public;
grant execute on function public.review_access_request(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
