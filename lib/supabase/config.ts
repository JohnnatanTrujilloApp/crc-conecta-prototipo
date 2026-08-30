const publicSupabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const publicSupabasePublishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

type PublicVariable =
  | "NEXT_PUBLIC_SUPABASE_URL"
  | "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY";

function requirePublicVariable(
  name: PublicVariable,
  value: string | undefined,
): string {
  if (!value) {
    throw new Error(
      `Falta la variable ${name}. Copie .env.example como .env.local y configure Supabase.`,
    );
  }

  return value;
}

export function isSupabaseConfigured(): boolean {
  return Boolean(
    publicSupabaseUrl &&
      publicSupabasePublishableKey &&
      !publicSupabaseUrl.includes("example.supabase.co") &&
      !publicSupabasePublishableKey.startsWith("replace-"),
  );
}

export function getPublicSupabaseConfig() {
  return {
    url: requirePublicVariable(
      "NEXT_PUBLIC_SUPABASE_URL",
      publicSupabaseUrl,
    ),
    anonKey: requirePublicVariable(
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
      publicSupabasePublishableKey,
    ),
  };
}
