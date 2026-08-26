# Arquitectura inicial

CRC Conecta se construye como plataforma multi-sede. La organización y la sede
son límites de datos desde el primer modelo; ninguna funcionalidad administrativa
debe asumir una única congregación.

## Capas

- `app/`: rutas y composición de interfaz.
- `features/`: lógica por dominio, incorporada de manera incremental.
- `components/`: componentes visuales reutilizables.
- `lib/supabase/`: acceso a autenticación y datos.
- `supabase/migrations/`: única fuente de cambios versionados de PostgreSQL.
- `docs/`: decisiones y contratos técnicos.

## Decisiones vigentes

1. Una persona puede existir sin cuenta de autenticación.
2. Los identificadores internos serán UUID.
3. La autorización combinará rol, permiso y alcance.
4. Las decisiones de acceso se validarán en servidor y mediante RLS.
5. La clave `service_role` solo puede usarse en módulos marcados para servidor.
6. La interfaz existente es una demostración con datos ficticios; no es todavía
   una fuente persistente ni prueba de que los módulos de dominio estén completos.
7. No se implementará biometría durante el MVP.

## Compatibilidad de despliegue

El frontend conserva la salida ESM compatible con Cloudflare Sites. Supabase
proporcionará PostgreSQL, Auth y Storage mediante HTTPS, sin conexiones TCP
directas desde el runtime de Cloudflare.
