import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getPublicSupabaseConfig } from "./config";

let browserClient: SupabaseClient | undefined;

export function getSupabaseBrowserClient(): SupabaseClient {
  if (!browserClient) {
    const { url, anonKey } = getPublicSupabaseConfig();
    browserClient = createClient(url, anonKey, {
      auth: { persistSession: true, autoRefreshToken: true },
    });
  }

  return browserClient;
}
