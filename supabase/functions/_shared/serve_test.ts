// Tests for serve.ts, written strictly against its doc comments.
// verifyCaller's happy/error paths need a live Supabase auth call, so only the
// no-Authorization-header short-circuit (which returns before any network
// call) is covered here.

import { assertEquals } from "jsr:@std/assert";
import { constantTimeEqual, jsonResponse, parseJsonBody, verifyCaller } from "./serve.ts";

// ---------------------------------------------------------------------------
// parseJsonBody
// ---------------------------------------------------------------------------

Deno.test("parseJsonBody - empty body yields ok:true value:{}", async () => {
  const req = new Request("http://x", { method: "POST", body: "" });
  assertEquals(await parseJsonBody(req), { ok: true, value: {} });
});

Deno.test("parseJsonBody - malformed JSON yields ok:false", async () => {
  const req = new Request("http://x", { method: "POST", body: "{" });
  assertEquals(await parseJsonBody(req), { ok: false });
});

Deno.test("parseJsonBody - valid JSON yields ok:true with the parsed value", async () => {
  const req = new Request("http://x", { method: "POST", body: '{"a":1}' });
  assertEquals(await parseJsonBody(req), { ok: true, value: { a: 1 } });
});

Deno.test("parseJsonBody - a body over 1MB yields ok:false", async () => {
  const req = new Request("http://x", { method: "POST", body: "a".repeat(1_000_001) });
  assertEquals(await parseJsonBody(req), { ok: false });
});

// ---------------------------------------------------------------------------
// jsonResponse
// ---------------------------------------------------------------------------

Deno.test("jsonResponse - sets the status and a JSON content-type", () => {
  const res = jsonResponse(201, { x: 1 });
  assertEquals(res.status, 201);
  assertEquals(res.headers.get("content-type"), "application/json");
});

// ---------------------------------------------------------------------------
// verifyCaller
// ---------------------------------------------------------------------------

Deno.test("verifyCaller - no Authorization header returns null", async () => {
  const req = new Request("http://x");
  assertEquals(await verifyCaller(req, "", ""), null);
});

// ---------------------------------------------------------------------------
// constantTimeEqual
// ---------------------------------------------------------------------------

Deno.test("constantTimeEqual - equal strings are equal", async () => {
  assertEquals(await constantTimeEqual("secret-token", "secret-token"), true);
});

Deno.test("constantTimeEqual - different strings of the same length are not equal", async () => {
  assertEquals(await constantTimeEqual("secret-token", "secret-tokeN"), false);
});

Deno.test("constantTimeEqual - strings of different length are not equal", async () => {
  assertEquals(await constantTimeEqual("short", "a-much-longer-string"), false);
});
