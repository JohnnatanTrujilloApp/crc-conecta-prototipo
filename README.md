# CRC Conecta

Plataforma multi-sede para la gestión de personas, familias, asistencia,
discipulado, formación y seguimiento de la Comunidad de Renovación Cristiana.

## Estado del desarrollo

El proyecto completó el **Sprint 1**. La interfaz demostrativa incluye ahora el
registro maestro de personas y la base PostgreSQL multi-sede permanece cerrada
por RLS hasta incorporar autorización en el Sprint 2.

Incluido en esta base:

- Next.js/Vinext, React y TypeScript estricto.
- Tailwind CSS y ESLint.
- Cliente de Supabase separado para navegador y servidor.
- Contrato de variables de entorno sin credenciales reales.
- Documentación inicial de arquitectura, base de datos y requisitos.
- Directorio de migraciones versionadas, aún sin tablas de negocio.
- Git y despliegue compatible con Cloudflare Sites.

## Configuración local

1. Copie `.env.example` como `.env.local`.
2. Complete la URL y la clave pública de su proyecto Supabase de desarrollo.
3. Mantenga `SUPABASE_SERVICE_ROLE_KEY` únicamente en entornos de servidor.
4. Instale dependencias y ejecute el servidor local.

```bash
pnpm install
pnpm dev
```

## Comandos

```bash
pnpm dev
pnpm build
pnpm lint
pnpm test
```

## Documentación

- `docs/architecture.md`: límites y decisiones de arquitectura.
- `docs/database.md`: reglas para PostgreSQL, migraciones y RLS.
- `docs/requirements.md`: alcance y orden incremental del producto.

## Próximo sprint

Sprint 2 implementará roles, permisos, scopes y políticas RLS autorizantes. No
se cargarán datos personales reales hasta probar el aislamiento entre sedes.

## Base técnica de Sites

A clean full-stack starter running on
[vinext](https://github.com/cloudflare/vinext), with optional Cloudflare D1 and
Drizzle support.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run dev
npm run build
```

This starter does not use `wrangler.jsonc`.

## Included Shape

- edit site code under `app/`
- `.openai/hosting.json` declares optional Sites D1 and R2 bindings
- `vite.config.ts` simulates declared bindings for local development
- `db/schema.ts` starts intentionally empty
- `examples/d1/` contains an optional D1 example surface
- `drizzle.config.ts` supports local migration generation when needed

## Workspace Auth Headers

Signed-in visitors receive both `oai-authenticated-user-id` and `oai-authenticated-user-email`. Private Sites require every visitor to sign in; public Sites may also have anonymous visitors, for whom neither header is present.

The user ID is stable for the same user on the same Site and different across Sites. Email and name are intended for display or contact purposes.

SIWC-authenticated workspace sites may also receive
`oai-authenticated-user-full-name` when the user's SIWC profile has a non-empty
`name` claim. The full-name value is percent-encoded UTF-8 and is accompanied by
`oai-authenticated-user-full-name-encoding: percent-encoded-utf-8`.

Treat the full name as optional and fall back to email when it is absent:

```tsx
import { headers } from "next/headers";

export default async function Home() {
  const requestHeaders = await headers();
  const userId = requestHeaders.get("oai-authenticated-user-id");
  const email = requestHeaders.get("oai-authenticated-user-email");
  const encodedFullName = requestHeaders.get("oai-authenticated-user-full-name");
  const fullName =
    encodedFullName &&
    requestHeaders.get("oai-authenticated-user-full-name-encoding") ===
      "percent-encoded-utf-8"
      ? decodeURIComponent(encodedFullName)
      : null;

  const displayName = fullName ?? email;
  // ...
}
```

## Optional Dispatch-Owned ChatGPT Sign-In

Import the ready-to-use helpers from `app/chatgpt-auth.ts` when the site needs
optional or required ChatGPT sign-in:

- Use `getChatGPTUser()` for optional signed-in UI.
- Use `requireChatGPTUser(returnTo)` for server-rendered pages that should send
  anonymous visitors through Sign in with ChatGPT.
- Use `chatGPTSignInPath(returnTo)` and `chatGPTSignOutPath(returnTo)` for
  browser links or actions.
- Pass a same-origin relative `returnTo` path for the destination after sign-in
  or sign-out. The helper validates and safely encodes it.
- Mark protected pages with `export const dynamic = "force-dynamic"` because
  they depend on per-request identity headers.

Dispatch owns `/signin-with-chatgpt`, `/signout-with-chatgpt`, `/callback`, the
OAuth cookies, and identity header injection. Do not implement app routes for
those reserved paths. Routes that do not import and call the helper remain
anonymous-compatible.

SIWC establishes identity only; it does not prove workspace membership. Use the
Sites hosting platform's access policy controls for workspace-wide restrictions,
or enforce explicit server-side membership or allowlist checks.

Use SIWC for account pages, user-specific dashboards, saved records, and write
actions tied to the current ChatGPT user. Leave public content anonymous.

## Useful Commands

- `npm run dev`: start local development
- `npm run build`: verify the vinext build output
- `npm test`: build the starter and verify its rendered loading skeleton
- `npm run db:generate`: generate Drizzle migrations after schema changes

## Learn More

- [vinext Documentation](https://github.com/cloudflare/vinext)
- [Drizzle D1 Guide](https://orm.drizzle.team/docs/get-started/d1-new)
