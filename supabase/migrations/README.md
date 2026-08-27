# Migraciones

Las migraciones se aplican en orden y nunca se reescriben después de ser usadas.

- `20260826010000_sprint_1_organizations_sites_people.sql`: organización,
  sedes, registro maestro de personas y vínculo opcional con Supabase Auth.
- `20260826020000_sprint_2_roles_permissions_scopes_rls.sql`: roles, permisos,
  asignaciones con alcance y políticas RLS por organización/sede.
- `20260827010000_sprint_3_families_ministries_profile_search.sql`: familias,
  integrantes, ministerios, servicio, código CRC y búsqueda global protegida.
- `20260827020000_sprint_4_events_attendance_dashboard.sql`: eventos genéricos,
  asistencia sin duplicados y métricas de dashboard protegidas por RLS.
- `20260827030000_sprint_5_training_programs_modules_lessons.sql`: programas de
  formación, módulos ordenados y lecciones con contenido y recursos.

Las políticas de Sprint 2 niegan el acceso cuando no existe una asignación
activa con el permiso y el alcance requeridos.
