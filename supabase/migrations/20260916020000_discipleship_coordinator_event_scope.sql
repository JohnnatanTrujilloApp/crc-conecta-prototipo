-- Permite al coordinador de Discipulado administrar únicamente la agenda del
-- ministerio que lidera dentro de su sede. No concede alcance de sede o nacional.

with grants(permission_code) as (
  values
    ('events.create'),
    ('events.update'),
    ('events.cancel'),
    ('events.publish'),
    ('events.manage_ministry'),
    ('events.view_history')
)
insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join grants g
join public.permissions p on p.code=g.permission_code
where r.code='DISCIPLESHIP_COORDINATOR'
  and r.active
on conflict do nothing;

notify pgrst,'reload schema';
