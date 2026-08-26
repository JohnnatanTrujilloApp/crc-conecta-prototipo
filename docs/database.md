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

## Orden previsto

La primera migración de negocio pertenecerá al Sprint 1 e incluirá
organizaciones, sedes y personas. Roles, permisos, scopes y sus políticas RLS se
incorporarán en Sprint 2. Este directorio permanece deliberadamente sin tablas
durante el cierre del Sprint 0.
