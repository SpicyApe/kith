// index.ts — HTTP entrypoint for `submit-game`. Wires the pure handler to Deno.serve.

import { handleSubmitGame } from "./handler.ts";
import { SupabaseSubmitGameStore } from "./store.ts";
import {
  badJson,
  buildContext,
  internalError,
  jsonResponse,
  methodNotAllowed,
  parseJsonBody,
  unauthorized,
  verifyCaller,
} from "../_shared/serve.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return methodNotAllowed();
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = (Deno.env.get("KITH_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

    const caller = await verifyCaller(req, supabaseUrl, anonKey);
    if (!caller) return unauthorized();

    const parsed = await parseJsonBody(req);
    if (!parsed.ok) return badJson();

    const ctx = buildContext(caller, new Date());
    const store = new SupabaseSubmitGameStore(supabaseUrl, serviceRoleKey);
    const outcome = await handleSubmitGame(parsed.value, ctx, store);
    return jsonResponse(outcome.status, outcome.body);
  } catch (e) {
    const pe = e as { code?: string; message?: string };
    console.error("handler_error", { code: pe.code, message: pe.message?.slice(0, 200) });
    return internalError();
  }
});
