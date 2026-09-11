// Tests for register/handler.ts, written strictly against its contract doc
// comments. Store is FakeRegisterStore (in-memory); no real DB involved.

import { assertEquals, assertRejects } from "jsr:@std/assert";
import type { ErrorBody, Outcome, RequestContext } from "../_shared/context.ts";
import { phoneToHmac } from "../_shared/hashing.ts";
import { FakeRegisterStore } from "../_shared/test_fakes.ts";
import { handleRegister, type RegisterResponse } from "./handler.ts";

const PEPPER = "test-pepper";
const USER_ID = "11111111-1111-1111-1111-111111111111";

function ctx(overrides: Partial<RequestContext> = {}): RequestContext {
  return {
    userId: USER_ID,
    phone: "+15551234567",
    now: new Date("2026-09-11T12:00:00Z"),
    ...overrides,
  };
}

function assertOk(outcome: Outcome<RegisterResponse>, status: 200 | 201): RegisterResponse {
  if (outcome.status !== status) {
    throw new Error(`expected status ${status}, got ${outcome.status}: ${JSON.stringify(outcome.body)}`);
  }
  return outcome.body as RegisterResponse;
}

function assertErr(
  outcome: Outcome<RegisterResponse>,
  status: 400 | 403 | 404 | 409 | 422 | 429,
  code: string,
): ErrorBody {
  if (outcome.status !== status) {
    throw new Error(`expected status ${status}, got ${outcome.status}: ${JSON.stringify(outcome.body)}`);
  }
  const body = outcome.body as ErrorBody;
  assertEquals(body.code, code);
  return body;
}

// ---------------------------------------------------------------------------
// existing user short-circuit
// ---------------------------------------------------------------------------

Deno.test("handleRegister - existing user returns 200 existing:true and does not insert", async () => {
  const store = new FakeRegisterStore();
  store.seedUser(USER_ID, { displayName: "Alex", inviteCode: "ABCD123456", phoneHmac: "some-other-hmac" });

  // Body is garbage on purpose: the existing-user short-circuit must fire
  // before any body validation runs.
  const outcome = await handleRegister({ garbage: true }, ctx(), store, PEPPER);

  const body = assertOk(outcome, 200);
  assertEquals(body.existing, true);
  assertEquals(body.displayName, "Alex");
  assertEquals(body.inviteCode, "ABCD123456");
  assertEquals(body.userId, USER_ID);
  assertEquals(store.insertUserCalls.length, 0);
});

// ---------------------------------------------------------------------------
// body validation
// ---------------------------------------------------------------------------

Deno.test("handleRegister - bad_request: displayName missing", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister({ tz: "UTC" }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleRegister - bad_request: displayName empty after trim", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister({ displayName: "   ", tz: "UTC" }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleRegister - bad_request: displayName 31 chars is too long", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister({ displayName: "a".repeat(31), tz: "UTC" }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleRegister - bad_tz: not a valid IANA zone", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister({ displayName: "Alex", tz: "Mars/Olympus" }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_tz");
});

Deno.test("handleRegister - bad_phone: ctx.phone is undefined", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister(
    { displayName: "Alex", tz: "UTC" },
    ctx({ phone: undefined }),
    store,
    PEPPER,
  );
  assertErr(outcome, 400, "bad_phone");
});

Deno.test("handleRegister - bad_phone: ctx.phone cannot be canonicalised", async () => {
  const store = new FakeRegisterStore();
  const outcome = await handleRegister(
    { displayName: "Alex", tz: "UTC" },
    ctx({ phone: "123" }),
    store,
    PEPPER,
  );
  assertErr(outcome, 400, "bad_phone");
});

// ---------------------------------------------------------------------------
// happy path
// ---------------------------------------------------------------------------

Deno.test("handleRegister - happy path: 201, trims displayName, invite code from store, correct phoneHmac", async () => {
  const store = new FakeRegisterStore();
  const phone = "+15551234567";
  const newUserId = "new-user";

  const outcome = await handleRegister(
    { displayName: "  Alex  ", tz: "America/New_York" },
    ctx({ userId: newUserId, phone }),
    store,
    PEPPER,
  );

  const body = assertOk(outcome, 201);
  assertEquals(body.existing, false);
  assertEquals(body.displayName, "Alex");
  assertEquals(body.userId, newUserId);

  assertEquals(store.insertUserCalls.length, 1);
  const call = store.insertUserCalls[0];
  assertEquals(call.userId, newUserId);
  assertEquals(call.displayName, "Alex");
  assertEquals(call.tz, "America/New_York");
  assertEquals(call.phoneHmac, await phoneToHmac(PEPPER, phone));

  assertEquals(body.inviteCode, store.users.get(newUserId)?.inviteCode);
});

// ---------------------------------------------------------------------------
// phone_taken
// ---------------------------------------------------------------------------

Deno.test("handleRegister - phone_taken: 409 when phoneHmac already belongs to another user", async () => {
  const store = new FakeRegisterStore();
  const phone = "+15551234567";
  const hmac = await phoneToHmac(PEPPER, phone);
  store.seedUser("other-user", { displayName: "Other", inviteCode: "OTHER123456", phoneHmac: hmac! });

  const outcome = await handleRegister(
    { displayName: "Alex", tz: "UTC" },
    ctx({ userId: "new-user", phone }),
    store,
    PEPPER,
  );

  assertErr(outcome, 409, "phone_taken");
  // The row must not have been created under the new user id.
  assertEquals(await store.getUser("new-user"), null);
});

// ---------------------------------------------------------------------------
// misconfiguration
// ---------------------------------------------------------------------------

Deno.test("handleRegister - empty pepper throws (misconfiguration, not a 4xx)", async () => {
  const store = new FakeRegisterStore();
  await assertRejects(
    () => handleRegister({ displayName: "Alex", tz: "UTC" }, ctx({ userId: "new-user" }), store, ""),
    Error,
  );
});
