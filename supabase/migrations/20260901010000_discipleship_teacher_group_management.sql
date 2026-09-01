-- Permite al discipulador administrar sus grupos y matrículas.
-- La restricción por sede continúa protegida por las políticas RLS existentes.
with grants(role_code,permission_code) as (values
  ('DISCIPLESHIP_TEACHER','groups.manage'),
  ('DISCIPLESHIP_TEACHER','enrollments.manage')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from grants g
join public.roles r on r.code=g.role_code
join public.permissions p on p.code=g.permission_code
on conflict do nothing;

