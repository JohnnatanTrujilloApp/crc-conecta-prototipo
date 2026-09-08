-- Rompe el ciclo people -> user_accounts -> people de las políticas RLS.
-- El identificador propio se resuelve dentro de una función SECURITY DEFINER.
create or replace function public.get_my_active_person_id()
returns uuid
language sql
stable
security definer
set search_path=''
as $$
  select account.person_id
  from public.user_accounts account
  where account.id=auth.uid()
    and account.access_status='ACTIVE'
  limit 1;
$$;

revoke all on function public.get_my_active_person_id() from public;
grant execute on function public.get_my_active_person_id() to authenticated;

drop policy if exists people_select_own_profile on public.people;
create policy people_select_own_profile on public.people
for select to authenticated
using(id=public.get_my_active_person_id());

comment on function public.get_my_active_person_id()
is 'Resolves the authenticated active person without recursively evaluating people and user_accounts RLS policies.';

notify pgrst,'reload schema';
