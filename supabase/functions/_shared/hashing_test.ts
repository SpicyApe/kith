// Tests for hashing.ts, written strictly against its doc comments.
// Run with `deno test` once the bodies are implemented; `deno check` only for now.

import { assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert";
import {
  canonicalPhone,
  hmacSha256Hex,
  isSha256Hex,
  phoneToHmac,
  sha256Hex,
} from "./hashing.ts";

// ---------------------------------------------------------------------------
// canonicalPhone
// ---------------------------------------------------------------------------

Deno.test("canonicalPhone - already canonical E.164 passes through unchanged", () => {
  assertEquals(canonicalPhone("+15551234567"), "+15551234567");
});

Deno.test("canonicalPhone - missing leading '+' is added", () => {
  assertEquals(canonicalPhone("15551234567"), "+15551234567");
});

Deno.test("canonicalPhone - US formatted number with parens/space/dash canonicalises", () => {
  assertEquals(canonicalPhone("1 (555) 123-4567"), "+15551234567");
});

Deno.test("canonicalPhone - international number with spaces canonicalises", () => {
  assertEquals(canonicalPhone("+44 20 7946 0958"), "+442079460958");
});

Deno.test("canonicalPhone - too few digits (7) returns null", () => {
  assertEquals(canonicalPhone("1234567"), null);
});

Deno.test("canonicalPhone - too many digits (16) returns null", () => {
  assertEquals(canonicalPhone("1234567890123456"), null);
});

Deno.test("canonicalPhone - stray letters return null", () => {
  assertEquals(canonicalPhone("+1555abc"), null);
});

Deno.test("canonicalPhone - empty string returns null", () => {
  assertEquals(canonicalPhone(""), null);
});

// ---------------------------------------------------------------------------
// sha256Hex
// ---------------------------------------------------------------------------

Deno.test("sha256Hex - matches an independently computed WebCrypto digest", async () => {
  const text = "+15551234567";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  const expected = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  assertEquals(await sha256Hex(text), expected);
});

Deno.test("sha256Hex - well-known vector for 'abc'", async () => {
  assertEquals(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  );
});

// ---------------------------------------------------------------------------
// hmacSha256Hex
// ---------------------------------------------------------------------------

Deno.test("hmacSha256Hex - RFC 4231 test case 2", async () => {
  assertEquals(
    await hmacSha256Hex("Jefe", "what do ya want for nothing?"),
    "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

Deno.test("hmacSha256Hex - empty pepper throws", async () => {
  await assertRejects(() => hmacSha256Hex("", "message"), Error, "empty pepper");
});

Deno.test("hmacSha256Hex - different peppers give different outputs", async () => {
  const a = await hmacSha256Hex("pepper-a", "same-message");
  const b = await hmacSha256Hex("pepper-b", "same-message");
  assertNotEquals(a, b);
});

Deno.test("hmacSha256Hex - deterministic for the same inputs", async () => {
  const a = await hmacSha256Hex("pepper", "message");
  const b = await hmacSha256Hex("pepper", "message");
  assertEquals(a, b);
});

// ---------------------------------------------------------------------------
// isSha256Hex
// ---------------------------------------------------------------------------

Deno.test("isSha256Hex - 64 lowercase hex chars is valid", () => {
  assertEquals(isSha256Hex("a".repeat(64)), true);
  assertEquals(isSha256Hex("0123456789abcdef".repeat(4)), true);
});

Deno.test("isSha256Hex - uppercase hex is rejected", () => {
  assertEquals(isSha256Hex("A".repeat(64)), false);
});

Deno.test("isSha256Hex - 63 characters is rejected", () => {
  assertEquals(isSha256Hex("a".repeat(63)), false);
});

Deno.test("isSha256Hex - a non-string value is rejected", () => {
  assertEquals(isSha256Hex(12345 as unknown as string), false);
  assertEquals(isSha256Hex(null as unknown as string), false);
});

// ---------------------------------------------------------------------------
// phoneToHmac
// ---------------------------------------------------------------------------

Deno.test("phoneToHmac - equals hmacSha256Hex(pepper, sha256Hex(canonical))", async () => {
  const pepper = "test-pepper";
  const raw = "+1 555 123 4567";
  const expected = await hmacSha256Hex(pepper, await sha256Hex("+15551234567"));
  assertEquals(await phoneToHmac(pepper, raw), expected);
});

Deno.test("phoneToHmac - null when the phone cannot be canonicalised", async () => {
  assertEquals(await phoneToHmac("test-pepper", "12"), null);
});
