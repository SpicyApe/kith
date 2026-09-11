// serve.ts — shared HTTP plumbing for edge function entrypoints. Not a contract
// file (no tests import it directly), but keep it stable since every index.ts
// depends on it.

import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import type { RequestContext } from "./context.ts";

export interface VerifiedCaller {
  userId: string;
  phone?: string;
}

/**
 * Verifies the caller's JWT (from the Authorization header) against Supabase auth
 * using the anon key, and returns the user id + phone. Returns null when the
 * header is missing or the token is invalid/expired.
 */
export async function verifyCaller(
  req: Request,
  supabaseUrl: string,
  anonKey: string,
): Promise<VerifiedCaller | null> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "");

  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data?.user) return null;
  // The caller id flows unescaped into interpolated queries downstream (e.g.
  // match-contacts' `.or()` filter); pin its shape here at the trust boundary.
  if (!/^[0-9a-f-]{36}$/i.test(data.user.id)) return null;

  return { userId: data.user.id, phone: data.user.phone ?? undefined };
}

export function buildContext(caller: VerifiedCaller, now: Date): RequestContext {
  return { userId: caller.userId, phone: caller.phone, now };
}

/** JSON response helper. */
export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function unauthorized(): Response {
  return jsonResponse(401, { error: "unauthorized", code: "unauthorized" });
}

export function methodNotAllowed(): Response {
  return jsonResponse(405, { error: "method_not_allowed", code: "method_not_allowed" });
}

export function badJson(): Response {
  return jsonResponse(400, { error: "bad_json", code: "bad_json" });
}

export function internalError(): Response {
  return jsonResponse(500, { error: "internal", code: "internal" });
}

/**
 * Fixed-time string comparison for bearer-token checks. SHA-256-hashes both
 * UTF-8 strings via `crypto.subtle.digest` (so the two hashes are always the
 * same length, 32 bytes) and compares them byte-by-byte in a loop that never
 * short-circuits, to avoid leaking the token's value through timing.
 */
export async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const ba = new Uint8Array(ha);
  const bb = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < 32; i++) {
    diff |= ba[i] ^ bb[i];
  }
  return diff === 0;
}

/** Parses the request body as JSON. An empty body yields `{}`. Returns `{ ok: false }` on malformed JSON or a body over 1 MB. */
export async function parseJsonBody(req: Request): Promise<{ ok: true; value: unknown } | { ok: false }> {
  try {
    const text = await req.text();
    if (text.length > 1_000_000) return { ok: false };
    if (text.length === 0) return { ok: true, value: {} };
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false };
  }
}
