-- Supabase puede conservar un grant explícito para anon al crear una función.
-- Revocarlo además del privilegio heredable de PUBLIC.
revoke all on function public.set_ministry_leadership(uuid,uuid,boolean) from public;
revoke all on function public.set_ministry_leadership(uuid,uuid,boolean) from anon;
grant execute on function public.set_ministry_leadership(uuid,uuid,boolean) to authenticated;
