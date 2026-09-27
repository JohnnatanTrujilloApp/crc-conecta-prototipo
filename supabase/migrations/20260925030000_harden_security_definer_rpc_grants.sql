-- RPC administrativas: acceso directo solo para usuarios autenticados.
revoke all on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) from public;
revoke all on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) from anon;
grant execute on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) to authenticated;

revoke all on function public.create_kids_sunday_session(date,time without time zone) from public;
revoke all on function public.create_kids_sunday_session(date,time without time zone) from anon;
grant execute on function public.create_kids_sunday_session(date,time without time zone) to authenticated;

revoke all on function public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,jsonb,boolean) from public;
revoke all on function public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,jsonb,boolean) from anon;
grant execute on function public.save_authorized_event(uuid,uuid,uuid,text,text,text,text,timestamp with time zone,timestamp with time zone,text,text,text,text,jsonb,boolean) to authenticated;

revoke all on function public.save_kids_attendance(uuid,jsonb) from public;
revoke all on function public.save_kids_attendance(uuid,jsonb) from anon;
grant execute on function public.save_kids_attendance(uuid,jsonb) to authenticated;

revoke all on function public.save_worship_member(uuid,text,uuid[],jsonb,text) from public;
revoke all on function public.save_worship_member(uuid,text,uuid[],jsonb,text) from anon;
grant execute on function public.save_worship_member(uuid,text,uuid[],jsonb,text) to authenticated;

revoke all on function public.update_kids_child_basic(uuid,jsonb) from public;
revoke all on function public.update_kids_child_basic(uuid,jsonb) from anon;
grant execute on function public.update_kids_child_basic(uuid,jsonb) to authenticated;

-- Función interna: el trigger existente no necesita EXECUTE directo del cliente.
-- Se conservan los privilegios existentes del propietario y de infraestructura.
revoke all on function public.create_pending_request_after_self_registration() from public;
revoke all on function public.create_pending_request_after_self_registration() from anon;
revoke all on function public.create_pending_request_after_self_registration() from authenticated;
