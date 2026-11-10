import { createResetPasswordHandler } from "./handler.ts";

Deno.serve(createResetPasswordHandler({
  url: Deno.env.get("SUPABASE_URL"),
  publicKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
}));
