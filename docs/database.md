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
