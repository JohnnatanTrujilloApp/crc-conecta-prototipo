type PublicVariable =
  | "NEXT_PUBLIC_SUPABASE_URL"
  | "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY";

function requirePublicVariable(name: PublicVariable): string {
  const value = process.env[name];

  if (!value) {
    throw new Error(
      `Falta la variable ${name}. Copie .env.example como .env.local y configure Supabase.`,
    );
  }

  return value;
}

export function isSupabaseConfigured(): boolean {
  const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  return Boolean(url&&key&&!url.includes("example.supabase.co")&&!key.startsWith("replace-"));
}

export function getPublicSupabaseConfig() {
  return {
    url: requirePublicVariable("NEXT_PUBLIC_SUPABASE_URL"),
    anonKey: requirePublicVariable("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"),
  };
}
