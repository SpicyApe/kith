// index.ts — HTTP entrypoint for `delete-account`. Wires the pure handler to Deno.serve.

import { handleDelete } from "./handler.ts";
import { SupabaseDeleteStore } from "./store.ts";
import {
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

    await parseJsonBody(req);

    const ctx = buildContext(caller, new Date());
    const store = new SupabaseDeleteStore(supabaseUrl, serviceRoleKey);
    const outcome = await handleDelete(undefined, ctx, store);
    return jsonResponse(outcome.status, outcome.body);
  } catch (e) {
    const pe = e as { code?: string; message?: string };
    console.error("handler_error", { code: pe.code, message: pe.message?.slice(0, 200) });
    return internalError();
  }
});
