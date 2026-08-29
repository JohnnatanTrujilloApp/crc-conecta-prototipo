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
- `20260828010000_sprint_6_groups_enrollments_class_sessions_attendance.sql`:
  grupos por sede, matrículas, sesiones y asistencia de clase sin duplicados.
- `20260828020000_sprint_7_discipleship_followups_dashboard.sql`: llamadas,
  visitas, seguimientos administrativos y métricas de discipulado por sede.
- `20260828030000_sprint_8_reports_exports_audit_logs.sql`: reportes por sede,
  solicitudes de exportación y bitácora inmutable de acciones sensibles.
- `20260828040000_sprint_9_public_cms_seo.sql`: páginas y bloques públicos,
  solicitudes protegidas, permisos editoriales y políticas RLS por sede.
- `20260829010000_sprint_10_supabase_sessions_crud.sql`: contexto de sesión,
  archivado lógico y protección adicional del CRUD de personas.

Las políticas de Sprint 2 niegan el acceso cuando no existe una asignación
activa con el permiso y el alcance requeridos.
