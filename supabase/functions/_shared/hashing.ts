// hashing.ts — phone-number canonicalisation and the two-stage hash used for
// contact matching. See docs/04-technical-architecture.md §3.
//
//   client:  h = sha256hex(e164)                      e.g. "+15551234567" → 64 lowercase hex
//   server:  c = hmacSha256Hex(PEPPER, h)             HMAC over the ASCII hex string of h
//
// `users.phone_hmac` and `contact_hashes.contact_hmac` both hold `c`. The plain `h`
// is never persisted. All functions are pure and use WebCrypto only.
//
// CONTRACT FILE: implement the bodies; keep signatures and documented behaviour.

/** Lowercase 64-char hex. */
export const SHA256_HEX_RE = /^[0-9a-f]{64}$/;

/**
 * Canonical E.164-ish form: a leading '+' followed by 8–15 digits. Accepts input with
 * or without '+', with spaces, dashes, dots, or parentheses, which are stripped.
 * Returns null when the digit count is outside 8..15 or any other character remains.
 * Does NOT apply a default region: a number without a country code is the caller's
 * problem (the auth provider always supplies one).
 */
export function canonicalPhone(raw: string): string | null {
  if (typeof raw !== "string") return null;
  let s = raw.replace(/[ \-.()]/g, "");
  if (s.startsWith("+")) s = s.slice(1);
  if (!/^\d+$/.test(s)) return null;
  if (s.length < 8 || s.length > 15) return null;
  return "+" + s;
}

function bytesToHex(bytes: ArrayBuffer): string {
  return Array.from(new Uint8Array(bytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** SHA-256 of the UTF-8 bytes of `text`, as lowercase hex. */
export async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return bytesToHex(digest);
}

/**
 * HMAC-SHA256 with key = UTF-8 bytes of `pepper`, message = UTF-8 bytes of `message`,
 * as lowercase hex. Throws `Error("empty pepper")` when `pepper` is empty.
 */
export async function hmacSha256Hex(pepper: string, message: string): Promise<string> {
  if (!pepper) throw new Error("empty pepper");
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(pepper),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return bytesToHex(signature);
}

/** True iff `s` matches SHA256_HEX_RE. */
export function isSha256Hex(s: unknown): s is string {
  return typeof s === "string" && SHA256_HEX_RE.test(s);
}

/** Convenience: the full server-side transform for a verified phone: hmac(pepper, sha256(canonical)). Returns null if the phone cannot be canonicalised. */
export async function phoneToHmac(pepper: string, rawPhone: string): Promise<string | null> {
  const canonical = canonicalPhone(rawPhone);
  if (canonical === null) return null;
  const h = await sha256Hex(canonical);
  return hmacSha256Hex(pepper, h);
}
