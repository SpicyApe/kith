// index.ts — HTTP entrypoint for `send-pushes`. Invoked by pg_cron every 15
// minutes (see migrations/0002_cron.sql), not by a user, so auth is a bearer
// match against the service role key rather than `verifyCaller`.

import { handleSendPushes } from "./handler.ts";
import type { PushSender } from "./handler.ts";
import { SupabasePushStore } from "./store.ts";
import { apnsHost, ApnsTokenCache, importP8, sendApns } from "../_shared/apns.ts";
import { constantTimeEqual, internalError, jsonResponse, methodNotAllowed, unauthorized } from "../_shared/serve.ts";

// Module-scope so a warm isolate reuses the same cache (and therefore the
// same JWT, refreshed only every ~50 minutes) across invocations instead of
// re-importing the APNs key and minting a fresh token on every 15-minute run.
let cache: ApnsTokenCache | null = null;

async function getCache(): Promise<ApnsTokenCache> {
  if (cache) return cache;
  const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
  const privateKeyPemRaw = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
  const privateKeyPem = privateKeyPemRaw.replace(/\\n/g, "\n");
  const key = await importP8(privateKeyPem);
  cache = new ApnsTokenCache(key, keyId, teamId);
  return cache;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return methodNotAllowed();
  try {
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    // Callers (pg_cron via pg_net) authenticate with KITH_CRON_SECRET as the bearer and the
    // anon key as `apikey` for the gateway; the injected service key is accepted too.
    const cronSecret = Deno.env.get("KITH_CRON_SECRET") ?? "";
    const authHeader = req.headers.get("authorization") ?? "";
    const isService = serviceRoleKey.length > 0 && (await constantTimeEqual(authHeader, `Bearer ${serviceRoleKey}`));
    const isCronSecret = cronSecret.length > 0 && (await constantTimeEqual(authHeader, `Bearer ${cronSecret}`));
    if (!serviceRoleKey || (!isService && !isCronSecret)) {
      return unauthorized();
    }

    const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
    const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
    const privateKeyPemRaw = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
    const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";
    if (!keyId || !teamId || !privateKeyPemRaw || !bundleId) {
      return jsonResponse(500, { error: "apns_not_configured", code: "apns_not_configured" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const tokenCache = await getCache();

    const sender: PushSender = {
      async send(env, apnsToken, payload) {
        const jwt = await tokenCache.get(new Date());
        const result = await sendApns(fetch, apnsHost(env), jwt, bundleId, apnsToken, payload);
        // A cached JWT that APNs now considers expired: mint a fresh one and
        // retry exactly once, so a stale warm-isolate token doesn't fail an
        // entire run's worth of sends.
        if (!result.ok && result.reason === "error" && result.status === 403 && result.detail === "ExpiredProviderToken") {
          tokenCache.invalidate();
          const freshJwt = await tokenCache.get(new Date());
          return await sendApns(fetch, apnsHost(env), freshJwt, bundleId, apnsToken, payload);
        }
        return result;
      },
    };

    const store = new SupabasePushStore(supabaseUrl, serviceRoleKey);
    const report = await handleSendPushes(new Date(), store, sender);
    return jsonResponse(200, report);
  } catch (e) {
    const pe = e as { code?: string; message?: string };
    console.error("handler_error", { code: pe.code, message: pe.message?.slice(0, 200) });
    return internalError();
  }
});
