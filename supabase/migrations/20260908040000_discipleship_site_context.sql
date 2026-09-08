-- El coordinador de Discipulado opera únicamente en su sede asignada.
-- Se crea un programa base vacío; las lecciones reales se administran en Formación.
insert into public.role_permissions(role_id,permission_id)
select role.id,permission.id
from public.roles role
join public.permissions permission on permission.code='sites.read'
where role.code='DISCIPLESHIP_COORDINATOR'
on conflict do nothing;

insert into public.training_programs(
  organization_id,title,description,program_type,active
)
select
  organization.id,
  'Discipulado CRC',
  'Programa base para organizar grupos. Carga los módulos y las lecciones reales desde Formación.',
  'DISCIPLESHIP',
  true
from public.organizations organization
where organization.active
on conflict(organization_id,title) do update set
  program_type='DISCIPLESHIP',
  active=true;

notify pgrst,'reload schema';
