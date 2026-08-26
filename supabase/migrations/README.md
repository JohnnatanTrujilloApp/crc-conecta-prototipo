# Migraciones

Las migraciones se aplican en orden y nunca se reescriben después de ser usadas.

- `20260826010000_sprint_1_organizations_sites_people.sql`: organización,
  sedes, registro maestro de personas y vínculo opcional con Supabase Auth.

Las tablas de Sprint 1 quedan bloqueadas mediante RLS sin políticas autorizantes
hasta completar roles, permisos y scopes en Sprint 2.
