// index.ts — HTTP entrypoint for `generate-puzzles`. Invoked either by pg_cron
// (service-role bearer, nightly — see migrations/0002_cron.sql) or by an admin
// user from the review page ("Reseed").

import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { handleGenerate } from "./handler.ts";
import type { GenerateRequest } from "./handler.ts";
import { GAME_KINDS, type GameKind } from "../_shared/games/common.ts";
import { SupabaseGenerateStore } from "./store.ts";
import {
  badJson,
  constantTimeEqual,
  internalError,
  jsonResponse,
  methodNotAllowed,
  parseJsonBody,
  verifyCaller,
} from "../_shared/serve.ts";

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function forbidden(): Response {
  return jsonResponse(403, { error: "forbidden", code: "forbidden" });
}

function badDate(): Response {
  return jsonResponse(400, { error: "bad date", code: "bad_request" });
}

function badGame(): Response {
  return jsonResponse(400, { error: "bad game", code: "bad_request" });
}

function gameWithoutDate(): Response {
  return jsonResponse(400, { error: "game requires date", code: "game_without_date" });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return methodNotAllowed();
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = (Deno.env.get("KITH_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

    const authHeader = req.headers.get("Authorization") ?? "";
    // pg_cron calls with KITH_CRON_SECRET as the bearer (plus the anon key as `apikey`
    // for the gateway); the injected service key is accepted as well.
    const cronSecret = Deno.env.get("KITH_CRON_SECRET") ?? "";
    const isCron = (serviceRoleKey.length > 0 && (await constantTimeEqual(authHeader, `Bearer ${serviceRoleKey}`))) ||
      (cronSecret.length > 0 && (await constantTimeEqual(authHeader, `Bearer ${cronSecret}`)));

    let isAdmin = false;
    if (!isCron) {
      const caller = await verifyCaller(req, supabaseUrl, anonKey);
      if (caller) {
        const callerClient = createClient(supabaseUrl, anonKey, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data, error } = await callerClient.rpc("is_admin");
        isAdmin = !error && data === true;
      }
    }
    if (!isCron && !isAdmin) return forbidden();

    const parsed = await parseJsonBody(req);
    if (!parsed.ok) return badJson();
    const raw = typeof parsed.value === "object" && parsed.value !== null
      ? parsed.value as Record<string, unknown>
      : {};
    const body: GenerateRequest = {};
    if (typeof raw.date === "string") {
      if (!DATE_RE.test(raw.date)) return badDate();
      body.date = raw.date;
    }
    if (raw.game !== undefined && raw.game !== null) {
      if (typeof raw.game !== "string" || !GAME_KINDS.includes(raw.game as GameKind)) return badGame();
      body.game = raw.game as GameKind;
    }
    if (body.game !== undefined && body.date === undefined) return gameWithoutDate();
    if (typeof raw.daysAhead === "number") {
      // Clamp to [1, 90] so a client-supplied daysAhead can't force an
      // unbounded (or zero/negative) generation run; a non-finite value
      // (NaN/Infinity) falls back to the handler's own 30-day default.
      body.daysAhead = Number.isFinite(raw.daysAhead)
        ? Math.min(90, Math.max(1, Math.trunc(raw.daysAhead)))
        : 30;
    }

    const store = new SupabaseGenerateStore(supabaseUrl, serviceRoleKey);
    const report = await handleGenerate(body, new Date(), store);
    return jsonResponse(200, report);
  } catch (e) {
    const pe = e as { code?: string; message?: string };
    if (pe.code === "not_pending") {
      return jsonResponse(409, { error: "not pending", code: "not_pending" });
    }
    if (pe.code === "not_found") {
      return jsonResponse(404, { error: "not found", code: "not_found" });
    }
    if (pe.code === "has_results") {
      return jsonResponse(409, { error: "has results", code: "has_results" });
    }
    console.error("handler_error", { code: pe.code, message: pe.message?.slice(0, 200) });
    return internalError();
  }
});
