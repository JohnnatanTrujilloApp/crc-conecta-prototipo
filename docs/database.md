# Base de datos

La base de datos oficial del producto será PostgreSQL administrado por Supabase.

## Reglas

- Todo cambio de esquema se crea como una migración SQL nueva y versionada.
- No se editan ni eliminan migraciones que ya hayan sido aplicadas.
- Las tablas de negocio usarán UUID y marcas de creación/actualización.
- Los registros relevantes incluirán `organization_id` y/o `site_id` según su
  alcance.
- RLS se habilitará antes de almacenar información real.
- La autorización del frontend nunca reemplaza las políticas ni las validaciones
  del servidor.
- Seeds y pruebas usarán exclusivamente información ficticia.

## Sprint 1 implementado

La migración `20260826010000_sprint_1_organizations_sites_people.sql` crea:

- `organizations` como raíz multi-sede;
- `sites` con unicidad por organización;
- `people` como registro maestro independiente de autenticación;
- `user_accounts` como vínculo opcional con `auth.users`.

Las cuatro tablas tienen RLS activado y no incluyen políticas todavía, por lo
que permanecieron cerradas a las API públicas durante el Sprint 1.

## Sprint 2 implementado

La segunda migración incorpora `roles`, `permissions`, `role_permissions` y
`user_roles`. Cada asignación contiene organización, tipo de alcance y sede
cuando corresponda. Las políticas RLS llaman una función central que exige al
mismo tiempo permiso y coincidencia de alcance.

El primer `SUPER_ADMIN` debe asignarse deliberadamente con la clave de servicio
desde un entorno seguro. Después de ese bootstrap, las asignaciones se gestionan
con `roles.manage`. La clave de servicio nunca se expone al navegador.

## Sprint 3 implementado

La tercera migración agrega familias, integrantes, ministerios y participación
de personas en ministerios. Las claves compuestas impiden vincular registros de
sedes diferentes. La función `search_people` busca por nombre, documento,
celular, correo o código CRC y conserva las políticas RLS de `people`.

## Sprint 4 implementado

La cuarta migración agrega eventos genéricos y un registro de asistencia por
persona/evento. La restricción única evita duplicados y la función
`dashboard_site_metrics` calcula indicadores usando las políticas RLS de las
tablas subyacentes. `FACE_RECOGNITION` permanece reservado y bloqueado en el MVP.

## Sprint 5 implementado

La quinta migración incorpora `training_programs`, `training_modules` y
`lessons`. El orden es único dentro de cada nivel y los permisos de formación
se validan contra la organización para compartir el currículo entre sedes sin
mezclar organizaciones. Los campos de auditoría se protegen mediante triggers.

## Sprint 6 implementado

La sexta migración agrega grupos por sede, matrículas, sesiones y asistencia de
clase. Las claves compuestas impiden relaciones entre sedes y los triggers
validan que la lección pertenezca al programa del grupo y que cada asistente
esté matriculado. La combinación sesión/persona evita registros duplicados.

## Sprint 7 implementado

La séptima migración agrega seguimientos administrativos de discipulado con
llamadas, visitas, observaciones y líder responsable. Los triggers exigen una
matrícula válida y coherencia entre grupo y sesión. Las métricas del dashboard
se calculan sobre tablas protegidas por RLS. Las notas pastorales sensibles
permanecen fuera de este módulo.

## Sprint 8 implementado

La octava migración agrega solicitudes de exportación y una bitácora de
auditoría sin permisos de modificación para usuarios autenticados. Triggers
registran cambios sensibles en personas, roles, asistencias, matrículas y
seguimientos. Los reportes y exportaciones respetan permisos y alcance RLS.
