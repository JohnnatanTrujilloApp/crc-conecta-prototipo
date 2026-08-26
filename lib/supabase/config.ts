type PublicVariable =
  | "NEXT_PUBLIC_SUPABASE_URL"
  | "NEXT_PUBLIC_SUPABASE_ANON_KEY";

function requirePublicVariable(name: PublicVariable): string {
  const value = process.env[name];

  if (!value) {
    throw new Error(
      `Falta la variable ${name}. Copie .env.example como .env.local y configure Supabase.`,
    );
  }

  return value;
}

export function getPublicSupabaseConfig() {
  return {
    url: requirePublicVariable("NEXT_PUBLIC_SUPABASE_URL"),
    anonKey: requirePublicVariable("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
  };
}
