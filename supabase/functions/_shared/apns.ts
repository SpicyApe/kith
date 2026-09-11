// apns.ts — Apple Push Notification service over HTTP/2 with token (JWT) auth.
//
// CONTRACT FILE. Pure crypto and request building; the only network call is in
// `sendApns`, which takes `fetch` as a parameter so tests inject a fake.
// Reference: Apple "Sending notification requests to APNs" (token-based).

export interface ApnsConfig {
  /** 10-char Key ID from the Apple developer portal. */
  keyId: string;
  /** 10-char Team ID. */
  teamId: string;
  /** Contents of the .p8 file (PEM, PKCS#8, P-256). */
  privateKeyPem: string;
  /** App bundle id, used as the `apns-topic`. */
  bundleId: string;
}

export interface ApnsPayload {
  title: string;
  body: string;
  /** Deep link the app opens, e.g. "kith://board" or "kith://today". */
  url: string;
  /** Notification kind; also sent as `apns-collapse-id` so a second push of the same kind replaces the first. */
  kind: string;
}

export type ApnsResult =
  | { ok: true }
  /** 400 BadDeviceToken / 410 Unregistered: the token must be deleted. */
  | { ok: false; reason: "bad_token" }
  /** Anything else (403 auth, 429, 5xx, network). */
  | { ok: false; reason: "error"; status?: number; detail?: string };

/** Base64url without padding of raw bytes. */
export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlEncodeString(s: string): string {
  return base64url(new TextEncoder().encode(s));
}

/**
 * Imports a PKCS#8 PEM P-256 private key for ES256 signing. Strips the PEM header/
 * footer and whitespace, base64-decodes, and calls `crypto.subtle.importKey("pkcs8", ...)`.
 * Throws on a malformed PEM.
 */
export async function importP8(privateKeyPem: string): Promise<CryptoKey> {
  const stripped = privateKeyPem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  if (stripped.length === 0) throw new Error("malformed PEM: empty key");
  const binary = atob(stripped);
  const der = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) der[i] = binary.charCodeAt(i);
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/**
 * ES256 JWT for APNs: header `{ alg: "ES256", kid }`, claims `{ iss: teamId, iat }`.
 * The signature is the raw 64-byte (r||s) ECDSA output that WebCrypto produces, base64url encoded.
 * `iat` is `Math.floor(now.getTime() / 1000)`.
 */
export async function makeApnsJwt(key: CryptoKey, keyId: string, teamId: string, now: Date): Promise<string> {
  const header = { alg: "ES256", kid: keyId };
  const claims = { iss: teamId, iat: Math.floor(now.getTime() / 1000) };
  const signingInput = `${base64urlEncodeString(JSON.stringify(header))}.${base64urlEncodeString(JSON.stringify(claims))}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/** Refresh window: Apple rejects tokens older than 60 minutes; refresh at 50. */
const APNS_JWT_MAX_AGE_MS = 50 * 60 * 1000;

/**
 * Caches one JWT per (keyId, teamId) and refreshes it when older than 50 minutes
 * (Apple rejects tokens older than 60). `get(now)` returns a valid token.
 */
export class ApnsTokenCache {
  private key: CryptoKey;
  private keyId: string;
  private teamId: string;
  private cached: { jwt: string; issuedAt: Date } | null = null;

  constructor(key: CryptoKey, keyId: string, teamId: string) {
    this.key = key;
    this.keyId = keyId;
    this.teamId = teamId;
  }

  async get(now: Date): Promise<string> {
    if (this.cached === null || now.getTime() - this.cached.issuedAt.getTime() > APNS_JWT_MAX_AGE_MS) {
      const jwt = await makeApnsJwt(this.key, this.keyId, this.teamId, now);
      this.cached = { jwt, issuedAt: now };
    }
    return this.cached.jwt;
  }

  /**
   * Forces the next `get()` to mint a fresh JWT instead of reusing the cached
   * one. Call this when APNs rejects the cached token (e.g. 403
   * ExpiredProviderToken) so the immediate retry doesn't resend the same
   * stale JWT.
   */
  invalidate(): void {
    this.cached = null;
  }
}

/** APNs host for the device's environment. */
export function apnsHost(env: "sandbox" | "production"): string {
  return env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
}

/**
 * Body sent to APNs:
 * `{ aps: { alert: { title, body }, sound: "default", "thread-id": kind }, url }`
 */
export function buildApnsBody(p: ApnsPayload): Record<string, unknown> {
  return {
    aps: { alert: { title: p.title, body: p.body }, sound: "default", "thread-id": p.kind },
    url: p.url,
  };
}

/**
 * POST https://<host>/3/device/<token> with headers:
 *   authorization: bearer <jwt>, apns-topic: <bundleId>, apns-push-type: alert,
 *   apns-priority: 10, apns-collapse-id: <kind>, content-type: application/json
 * Maps responses: 200 → ok; 400 with reason BadDeviceToken or 410 → bad_token;
 * everything else → error with status and the response body's `reason` if JSON.
 * A thrown fetch error → error with detail = message. Never throws.
 */
export async function sendApns(
  fetchFn: typeof fetch,
  host: string,
  jwt: string,
  bundleId: string,
  deviceToken: string,
  payload: ApnsPayload,
): Promise<ApnsResult> {
  let res: Response;
  try {
    res = await fetchFn(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-collapse-id": payload.kind,
        "content-type": "application/json",
      },
      body: JSON.stringify(buildApnsBody(payload)),
    });
  } catch (e) {
    return { ok: false, reason: "error", detail: (e as Error).message };
  }

  if (res.status === 200) {
    // Drain the body to avoid leaking the connection; APNs sends none on success.
    try {
      await res.text();
    } catch {
      // ignore
    }
    return { ok: true };
  }

  let parsed: { reason?: string } | null = null;
  try {
    const text = await res.text();
    if (text.length > 0) parsed = JSON.parse(text);
  } catch {
    parsed = null;
  }

  if (res.status === 410 || (res.status === 400 && parsed?.reason === "BadDeviceToken")) {
    return { ok: false, reason: "bad_token" };
  }

  return { ok: false, reason: "error", status: res.status, detail: parsed?.reason };
}
