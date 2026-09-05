# Google OAuth y autoregistro público

## Supabase Auth

1. En **Authentication → Providers → Google**, habilitar Google.
2. Copiar de Supabase la URL de callback indicada para Google. Normalmente es:
   `https://zzxicsaqslzyewvslvfd.supabase.co/auth/v1/callback`.
3. Registrar el Client ID y Client Secret creados en Google Cloud. El secreto se guarda únicamente en Supabase.
4. En **Authentication → URL Configuration**, configurar como Site URL:
   `https://crc-conecta-prototipo.johnnatan-trujillo.chatgpt.site`
5. Agregar estas Redirect URLs:
   - `https://crc-conecta-prototipo.johnnatan-trujillo.chatgpt.site/registro`
   - `http://localhost:3000/registro` solo para desarrollo local.

## Google Cloud

1. Crear o seleccionar un proyecto y configurar la pantalla de consentimiento OAuth.
2. Crear credenciales **OAuth client ID → Web application**.
3. En **Authorized JavaScript origins**, agregar el origen público de CRC Conecta.
4. En **Authorized redirect URIs**, agregar exclusivamente la callback de Supabase del paso 2.
5. Copiar Client ID y Client Secret en el proveedor Google de Supabase.

## Variables

- Públicas en el cliente: `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- Secretas: Google Client Secret y cualquier `service_role` de Supabase. No deben agregarse a `.env.local`, al código cliente ni al repositorio.

El registro por correo/contraseña existente se conserva. Google se agrega como proveedor adicional.
