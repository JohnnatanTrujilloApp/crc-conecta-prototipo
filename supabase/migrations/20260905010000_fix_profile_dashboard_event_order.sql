-- Corrige el ordenamiento de próximos eventos en Inicio contextual.
-- La función original referenciaba `starts_at`, pero la subconsulta expone `start_at`.
do $$
declare
  function_definition text;
begin
  select pg_get_functiondef(p.oid)
    into function_definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_my_dashboard'
    and pg_get_function_identity_arguments(p.oid) = 'target_site_id uuid';

  if function_definition is null then
    raise exception 'No existe public.get_my_dashboard(uuid). Aplica primero la migración 20260904010000.';
  end if;

  function_definition := replace(
    function_definition,
    'jsonb_agg(item ORDER BY starts_at)',
    'jsonb_agg(item ORDER BY start_at)'
  );

  function_definition := replace(
    function_definition,
    'jsonb_agg(item order by starts_at)',
    'jsonb_agg(item order by start_at)'
  );

  if lower(function_definition) like '%jsonb_agg(item order by starts_at)%' then
    raise exception 'No fue posible corregir el ordenamiento de eventos del panel.';
  end if;

  execute function_definition;
end;
$$;

notify pgrst, 'reload schema';
