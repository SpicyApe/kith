// Tests for apns.ts, written strictly against its contract doc comments.
// No real network calls: sendApns takes fetch as a parameter, and here it is
// always a fake. Crypto uses the real WebCrypto (Deno's runtime), generating
// throwaway P-256 key pairs so signatures can be verified independently of
// the implementation under test.

import { assert, assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert";
import {
  apnsHost,
  ApnsTokenCache,
  base64url,
  buildApnsBody,
  importP8,
  makeApnsJwt,
  sendApns,
  type ApnsPayload,
} from "./apns.ts";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function pemFromPkcs8(der: ArrayBuffer): string {
  const bytes = new Uint8Array(der);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  const b64 = btoa(binary);
  const lines = b64.match(/.{1,64}/g) ?? [b64];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
}

/** Independent (non-implementation) base64url reference, via btoa/replace. */
function referenceBase64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function genPair(): Promise<CryptoKeyPair> {
  return await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  ) as CryptoKeyPair;
}

function b64urlDecode(s: string): Uint8Array<ArrayBuffer> {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const std = s.replace(/-/g, "+").replace(/_/g, "/") + pad;
  const binary = atob(std);
  const out = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

function jsonFromB64url(s: string): unknown {
  return JSON.parse(new TextDecoder().decode(b64urlDecode(s)));
}

const PAYLOAD: ApnsPayload = {
  title: "Today's Lineup is up.",
  body: "1 friend has already played.",
  url: "kith://today",
  kind: "daily_drop",
};

/** Extracts the request URL/method/headers regardless of whether the
 * implementation calls fetchFn(url, init) or fetchFn(new Request(url, init)). */
function requestDetails(
  input: unknown,
  init?: RequestInit,
): { url: string; method: string; headers: Headers } {
  if (input instanceof Request) {
    return { url: input.url, method: input.method, headers: input.headers };
  }
  const url = typeof input === "string" ? input : String(input);
  return { url, method: init?.method ?? "GET", headers: new Headers(init?.headers) };
}

function fakeFetch(
  status: number,
  body: unknown,
  opts: { throws?: boolean; rawBody?: string } = {},
): { fn: typeof fetch; calls: Array<{ input: unknown; init?: RequestInit }> } {
  const calls: Array<{ input: unknown; init?: RequestInit }> = [];
  const fn = (async (input: unknown, init?: RequestInit) => {
    calls.push({ input, init });
    if (opts.throws) throw new Error("network unreachable");
    const bodyStr = opts.rawBody !== undefined ? opts.rawBody : (body === undefined ? "" : JSON.stringify(body));
    return new Response(bodyStr, { status });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

// ---------------------------------------------------------------------------
// base64url
// ---------------------------------------------------------------------------

Deno.test("base64url - empty input yields empty string", () => {
  assertEquals(base64url(new Uint8Array([])), "");
});

Deno.test("base64url - [0xff, 0xfe] with no padding", () => {
  assertEquals(base64url(new Uint8Array([0xff, 0xfe])), "__4");
});

Deno.test("base64url - matches a manual reference for 'hello'", () => {
  const bytes = new TextEncoder().encode("hello");
  assertEquals(base64url(bytes), referenceBase64url(bytes));
  assertEquals(base64url(bytes), "aGVsbG8");
});

Deno.test("base64url - never contains '+', '/' or '='", () => {
  const bytes = crypto.getRandomValues(new Uint8Array(37));
  const out = base64url(bytes);
  assert(!out.includes("+"));
  assert(!out.includes("/"));
  assert(!out.includes("="));
});

// ---------------------------------------------------------------------------
// importP8
// ---------------------------------------------------------------------------

Deno.test("importP8 - imports a PKCS#8 P-256 PEM into a usable CryptoKey", async () => {
  const pair = await genPair();
  const der = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const pem = pemFromPkcs8(der);

  const key = await importP8(pem);
  assertEquals(key.type, "private");
  assertEquals(key.algorithm.name, "ECDSA");

  // Sanity: the imported key can actually sign, and the signature verifies
  // against the original key pair's public key.
  const data = new TextEncoder().encode("probe");
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, data);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    sig,
    data,
  );
  assert(ok);
});

Deno.test("importP8 - rejects a malformed PEM", async () => {
  await assertRejects(() => importP8("-----BEGIN PRIVATE KEY-----\nnot-base64!!!\n-----END PRIVATE KEY-----\n"));
});

Deno.test("importP8 - rejects garbage that isn't PEM at all", async () => {
  await assertRejects(() => importP8("this is not a pem file"));
});

// ---------------------------------------------------------------------------
// makeApnsJwt
// ---------------------------------------------------------------------------

Deno.test("makeApnsJwt - three dot-separated parts with correct header, claims, and a verifiable signature", async () => {
  const pair = await genPair();
  const now = new Date("2026-09-11T12:00:00Z");

  const jwt = await makeApnsJwt(pair.privateKey, "KEYID12345", "TEAMID1234", now);
  const parts = jwt.split(".");
  assertEquals(parts.length, 3);

  const header = jsonFromB64url(parts[0]) as { alg: string; kid: string };
  assertEquals(header.alg, "ES256");
  assertEquals(header.kid, "KEYID12345");

  const claims = jsonFromB64url(parts[1]) as { iss: string; iat: number };
  assertEquals(claims.iss, "TEAMID1234");
  assertEquals(claims.iat, Math.floor(now.getTime() / 1000));

  const sigBytes = b64urlDecode(parts[2]);
  const signedData = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    sigBytes,
    signedData,
  );
  assert(ok, "signature must verify against the signing key's public key");
});

Deno.test("makeApnsJwt - signature is the raw 64-byte r||s form, not DER", async () => {
  const pair = await genPair();
  const jwt = await makeApnsJwt(pair.privateKey, "KEYID12345", "TEAMID1234", new Date());
  const sigBytes = b64urlDecode(jwt.split(".")[2]);
  assertEquals(sigBytes.length, 64);
});

// ---------------------------------------------------------------------------
// ApnsTokenCache
// ---------------------------------------------------------------------------

Deno.test("ApnsTokenCache - returns the same token within 50 minutes", async () => {
  const pair = await genPair();
  const cache = new ApnsTokenCache(pair.privateKey, "KEYID12345", "TEAMID1234");
  const t0 = new Date("2026-09-11T12:00:00Z");
  const first = await cache.get(t0);
  const later = await cache.get(new Date(t0.getTime() + 50 * 60_000));
  assertEquals(later, first);
});

Deno.test("ApnsTokenCache - refreshes to a different token after 51 minutes", async () => {
  const pair = await genPair();
  const cache = new ApnsTokenCache(pair.privateKey, "KEYID12345", "TEAMID1234");
  const t0 = new Date("2026-09-11T12:00:00Z");
  const first = await cache.get(t0);
  const later = await cache.get(new Date(t0.getTime() + 51 * 60_000));
  assertNotEquals(later, first);
});

Deno.test("ApnsTokenCache - invalidate() forces the next get() to mint a new token even inside the 50-minute freshness window", async () => {
  const pair = await genPair();
  const cache = new ApnsTokenCache(pair.privateKey, "KEYID12345", "TEAMID1234");
  const t0 = new Date("2026-09-11T12:00:00Z");
  const first = await cache.get(t0);
  cache.invalidate();
  // Without invalidate(), get() at t0 + 1 minute would still return the
  // cached `first` token (well inside APNS_JWT_MAX_AGE_MS) — the only reason
  // this mints a new one is the invalidate() call above.
  const afterInvalidate = await cache.get(new Date(t0.getTime() + 60_000));
  assertNotEquals(afterInvalidate, first);

  const claims = jsonFromB64url(afterInvalidate.split(".")[1]) as { iat: number };
  assertEquals(claims.iat, Math.floor((t0.getTime() + 60_000) / 1000));
});

// ---------------------------------------------------------------------------
// apnsHost
// ---------------------------------------------------------------------------

Deno.test("apnsHost - sandbox and production hosts", () => {
  assertEquals(apnsHost("sandbox"), "api.sandbox.push.apple.com");
  assertEquals(apnsHost("production"), "api.push.apple.com");
});

// ---------------------------------------------------------------------------
// buildApnsBody
// ---------------------------------------------------------------------------

Deno.test("buildApnsBody - exact shape", () => {
  const payload: ApnsPayload = { title: "T", body: "B", url: "kith://today", kind: "daily_drop" };
  assertEquals(buildApnsBody(payload), {
    aps: { alert: { title: "T", body: "B" }, sound: "default", "thread-id": "daily_drop" },
    url: "kith://today",
  });
});

// ---------------------------------------------------------------------------
// sendApns
// ---------------------------------------------------------------------------

Deno.test("sendApns - 200 maps to ok", async () => {
  const { fn } = fakeFetch(200, undefined);
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: true });
});

Deno.test("sendApns - 400 BadDeviceToken maps to bad_token", async () => {
  const { fn } = fakeFetch(400, { reason: "BadDeviceToken" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: false, reason: "bad_token" });
});

Deno.test("sendApns - 410 maps to bad_token", async () => {
  const { fn } = fakeFetch(410, { reason: "Unregistered" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: false, reason: "bad_token" });
});

Deno.test("sendApns - 400 BadCollapseId maps to error with status 400 and detail BadCollapseId", async () => {
  const { fn } = fakeFetch(400, { reason: "BadCollapseId" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: false, reason: "error", status: 400, detail: "BadCollapseId" });
});

Deno.test("sendApns - 403 ExpiredProviderToken maps to error with status 403 and detail ExpiredProviderToken", async () => {
  const { fn } = fakeFetch(403, { reason: "ExpiredProviderToken" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: false, reason: "error", status: 403, detail: "ExpiredProviderToken" });
});

Deno.test("sendApns - 429 TooManyProviderTokenUpdates maps to error with that detail", async () => {
  const { fn } = fakeFetch(429, { reason: "TooManyProviderTokenUpdates" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result, { ok: false, reason: "error", status: 429, detail: "TooManyProviderTokenUpdates" });
});

Deno.test("sendApns - 500 with an empty body maps to error status 500", async () => {
  const { fn } = fakeFetch(500, undefined, { rawBody: "" });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assert(result.ok === false);
  assert(result.reason === "error");
  assertEquals(result.status, 500);
});

Deno.test("sendApns - a thrown fetch error maps to error with detail = message, never throws", async () => {
  const { fn } = fakeFetch(0, undefined, { throws: true });
  const result = await sendApns(fn, "api.push.apple.com", "jwt-abc", "com.kith.app", "tok1", PAYLOAD);
  assertEquals(result.ok, false);
  assert(result.ok === false);
  assertEquals(result.reason, "error");
  assertEquals((result as { detail?: unknown }).detail, "network unreachable");
});

Deno.test("sendApns - request URL and headers match the contract exactly", async () => {
  const { fn, calls } = fakeFetch(200, undefined);
  await sendApns(fn, "api.push.apple.com", "jwt-xyz", "com.kith.app", "device-token-1", PAYLOAD);

  assertEquals(calls.length, 1);
  const { url, method, headers } = requestDetails(calls[0].input, calls[0].init);
  assertEquals(url, "https://api.push.apple.com/3/device/device-token-1");
  assertEquals(method, "POST");
  assertEquals(headers.get("authorization"), "bearer jwt-xyz");
  assertEquals(headers.get("apns-topic"), "com.kith.app");
  assertEquals(headers.get("apns-push-type"), "alert");
  assertEquals(headers.get("apns-priority"), "10");
  assertEquals(headers.get("apns-collapse-id"), PAYLOAD.kind);
});

Deno.test("sendApns - uses the given host verbatim in the request URL", async () => {
  const { fn, calls } = fakeFetch(200, undefined);
  await sendApns(fn, "api.sandbox.push.apple.com", "jwt-xyz", "com.kith.app", "tokS", PAYLOAD);
  const { url } = requestDetails(calls[0].input, calls[0].init);
  assertEquals(url, "https://api.sandbox.push.apple.com/3/device/tokS");
});
