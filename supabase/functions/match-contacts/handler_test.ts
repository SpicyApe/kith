// Tests for match-contacts/handler.ts, written strictly against its contract
// doc comments. `handleMatch` is currently a stub, so these type-check but
// won't pass until the body lands. Store is FakeMatchStore (in-memory).

import { assertEquals, assertRejects } from "jsr:@std/assert";
import type { ErrorBody, Outcome, RequestContext } from "../_shared/context.ts";
import { hmacSha256Hex } from "../_shared/hashing.ts";
import { FakeMatchStore } from "../_shared/test_fakes.ts";
import {
  handleMatch,
  MAX_HASHES_PER_DAY,
  MAX_HASHES_PER_REQUEST,
  MAX_SYNCS_PER_HOUR,
  type MatchResponse,
} from "./handler.ts";

const PEPPER = "test-pepper";
const USER_ID = "user-1";
const NOW = new Date("2026-09-11T12:00:00Z");

function ctx(overrides: Partial<RequestContext> = {}): RequestContext {
  return { userId: USER_ID, now: NOW, ...overrides };
}

/** A deterministic, valid 64-char lowercase hex string (looks like a
 * sha256hex value) that varies with `i`. Cheap: no WebCrypto needed for bulk
 * tests (too_many, daily budget). */
function fakeHash(i: number): string {
  return i.toString(16).padStart(64, "0");
}

function assertOk(outcome: Outcome<MatchResponse>, status: 200 | 201): MatchResponse {
  if (outcome.status !== status) {
    throw new Error(`expected status ${status}, got ${outcome.status}: ${JSON.stringify(outcome.body)}`);
  }
  return outcome.body as MatchResponse;
}

function assertErr(
  outcome: Outcome<MatchResponse>,
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
// body shape validation
// ---------------------------------------------------------------------------

Deno.test("handleMatch - bad_request: added is not an array", async () => {
  const store = new FakeMatchStore();
  const outcome = await handleMatch({ added: "nope" }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleMatch - bad_request: an element is not valid hex", async () => {
  const store = new FakeMatchStore();
  const outcome = await handleMatch({ added: ["g".repeat(64)] }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleMatch - bad_request: an element is uppercase hex (must be lowercase)", async () => {
  const store = new FakeMatchStore();
  // fakeHash(1) is all digits (no a-f), so it would survive toUpperCase()
  // unchanged; pick an index whose hex form actually contains letters.
  const hexWithLetters = fakeHash(0xabcdef);
  const outcome = await handleMatch({ added: [hexWithLetters.toUpperCase()] }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleMatch - too_many: added + removed exceeds MAX_HASHES_PER_REQUEST", async () => {
  const store = new FakeMatchStore();
  const added = Array.from({ length: MAX_HASHES_PER_REQUEST + 1 }, (_, i) => fakeHash(i));
  const outcome = await handleMatch({ added }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "too_many");
});

Deno.test("handleMatch - the size check fires before per-element hex validation", async () => {
  const store = new FakeMatchStore();
  // Every element is invalid hex, but there are more of them than
  // MAX_HASHES_PER_REQUEST allows: too_many must win, not bad_request.
  const added = Array.from({ length: MAX_HASHES_PER_REQUEST + 1 }, () => "not-hex");
  const outcome = await handleMatch({ added }, ctx(), store, PEPPER);
  assertErr(outcome, 400, "too_many");
});

// ---------------------------------------------------------------------------
// registration / discoverability
// ---------------------------------------------------------------------------

Deno.test("handleMatch - not_registered: 403 when the user row is missing", async () => {
  const store = new FakeMatchStore();
  const outcome = await handleMatch({ added: [fakeHash(1)] }, ctx(), store, PEPPER);
  assertErr(outcome, 403, "not_registered");
});

Deno.test("handleMatch - not_discoverable: 403 when discoverable is false", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, false);
  const outcome = await handleMatch({ added: [fakeHash(1)] }, ctx(), store, PEPPER);
  assertErr(outcome, 403, "not_discoverable");
});

// ---------------------------------------------------------------------------
// rate limits
// ---------------------------------------------------------------------------

Deno.test("handleMatch - rate_limited: a full sync within the last hour blocks another", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  store.seedSyncLog(USER_ID, new Date(NOW.getTime() - 30 * 60_000), 10, true);

  const outcome = await handleMatch({ added: [fakeHash(1)], full: true }, ctx(), store, PEPPER);
  assertErr(outcome, 429, "rate_limited");
});

Deno.test("handleMatch - rate_limited: daily hash budget exceeded", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  store.seedSyncLog(USER_ID, new Date(NOW.getTime() - 60 * 60_000), MAX_HASHES_PER_DAY - 1, false);

  const outcome = await handleMatch({ added: [fakeHash(1), fakeHash(2)] }, ctx(), store, PEPPER);
  assertErr(outcome, 429, "rate_limited");
});

Deno.test("handleMatch - rate_limited: removed hashes count toward the daily budget too", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  // Outside the 1h window (so it doesn't trip the requests-per-hour gate) but
  // inside the 24h window (so it counts toward the daily hash budget).
  store.seedSyncLog(USER_ID, new Date(NOW.getTime() - 20 * 3600_000), MAX_HASHES_PER_DAY - 1, false);

  const outcome = await handleMatch({ added: [], removed: [fakeHash(1), fakeHash(2)] }, ctx(), store, PEPPER);
  assertErr(outcome, 429, "rate_limited");
});

Deno.test("handleMatch - rate_limited: requests-per-hour budget exceeded", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  for (let i = 0; i < MAX_SYNCS_PER_HOUR; i++) {
    store.seedSyncLog(USER_ID, new Date(NOW.getTime() - i * 60_000), 1, false);
  }

  const outcome = await handleMatch({ added: [fakeHash(1)] }, ctx(), store, PEPPER);
  assertErr(outcome, 429, "rate_limited");
});

// ---------------------------------------------------------------------------
// happy paths
// ---------------------------------------------------------------------------

Deno.test("handleMatch - a non-full request with no deduped hashes short-circuits with the current state", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  const hmacA = await hmacSha256Hex(PEPPER, fakeHash(1));
  store.seedFriends(USER_ID, [{ userId: "friend-a", displayName: "Friendly A", phoneHmac: hmacA }]);
  store.seedContactHmacs(USER_ID, [hmacA]);

  const outcome = await handleMatch({ added: [] }, ctx(), store, PEPPER);
  const body = assertOk(outcome, 200);

  assertEquals(body.matches, []);
  assertEquals(body.friends.map((f) => f.userId), ["friend-a"]);
  assertEquals(body.stored, 1);
  assertEquals(store.logSyncCalls.length, 0);
  assertEquals(store.recomputeMatchesCalls.length, 0);
});

Deno.test("handleMatch - happy diff sync: matches, friends, stored count, hmac-only writes", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);

  const hA = fakeHash(101);
  const hB = fakeHash(102);
  const hZ = fakeHash(103);
  const hmacA = await hmacSha256Hex(PEPPER, hA);
  const hmacB = await hmacSha256Hex(PEPPER, hB);
  const hmacZ = await hmacSha256Hex(PEPPER, hZ);

  store.seedFriends(USER_ID, [
    { userId: "friend-a", displayName: "Friendly A", phoneHmac: hmacA },
    { userId: "friend-other", displayName: "Other Friend", phoneHmac: "unrelated-hmac" },
  ]);

  const outcome = await handleMatch(
    { added: [hA, hB], removed: [hZ] },
    ctx(),
    store,
    PEPPER,
  );

  const body = assertOk(outcome, 200);

  // Only friend-a's hmac was among this request's hashes.
  assertEquals(body.matches.length, 1);
  assertEquals(body.matches[0].userId, "friend-a");
  assertEquals(body.matches[0].hash, hA);

  // All mutual friends come back, without phoneHmac.
  assertEquals(body.friends.length, 2);
  const friendIds = body.friends.map((f) => f.userId).sort();
  assertEquals(friendIds, ["friend-a", "friend-other"]);
  for (const f of body.friends) {
    assertEquals(Object.hasOwn(f, "phoneHmac"), false);
  }

  const storedCount = await store.countContactHmacs(USER_ID);
  assertEquals(body.stored, storedCount);

  // Only HMACs ever reach the store, never the plain client hashes.
  assertEquals(store.upsertCalls.length, 1);
  assertEquals(new Set(store.upsertCalls[0].hmacs), new Set([hmacA, hmacB]));
  assertEquals(store.upsertCalls[0].hmacs.includes(hA), false);
  assertEquals(store.upsertCalls[0].hmacs.includes(hB), false);

  assertEquals(store.deleteCalls.length, 1);
  assertEquals(store.deleteCalls[0].hmacs, [hmacZ]);

  assertEquals(store.logSyncCalls.length, 1);
  assertEquals(store.logSyncCalls[0].hashes, 3);
  assertEquals(store.logSyncCalls[0].full, false);

  assertEquals(store.recomputeMatchesCalls, [USER_ID]);
});

Deno.test("handleMatch - full sync replaces the whole set and logs full:true", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  const hA = fakeHash(201);
  const hB = fakeHash(202);

  const outcome = await handleMatch({ added: [hA, hB], full: true }, ctx(), store, PEPPER);
  assertOk(outcome, 200);

  assertEquals(store.replaceCalls.length, 1);
  assertEquals(store.replaceCalls[0].hmacs.length, 2);
  assertEquals(store.upsertCalls.length, 0);

  assertEquals(store.logSyncCalls.length, 1);
  assertEquals(store.logSyncCalls[0].full, true);
});

Deno.test("handleMatch - a matched contact never carries a phoneHmac key", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  const hA = fakeHash(401);
  const hmacA = await hmacSha256Hex(PEPPER, hA);
  store.seedFriends(USER_ID, [{ userId: "friend-a", displayName: "Friendly A", phoneHmac: hmacA }]);

  const outcome = await handleMatch({ added: [hA] }, ctx(), store, PEPPER);
  const body = assertOk(outcome, 200);

  assertEquals(body.matches.length, 1);
  assertEquals(Object.hasOwn(body.matches[0], "phoneHmac"), false);
});

Deno.test("handleMatch - duplicates in added are collapsed before storing", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  const h = fakeHash(301);

  const outcome = await handleMatch({ added: [h, h] }, ctx(), store, PEPPER);
  assertOk(outcome, 200);

  assertEquals(store.upsertCalls.length, 1);
  assertEquals(store.upsertCalls[0].hmacs.length, 1);
});

Deno.test("handleMatch - empty added with full:true clears the stored set", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  store.seedContactHmacs(USER_ID, ["stale-hmac"]);

  const outcome = await handleMatch({ added: [], full: true }, ctx(), store, PEPPER);
  assertOk(outcome, 200);

  assertEquals(store.replaceCalls.length, 1);
  assertEquals(store.replaceCalls[0].hmacs, []);
});

// ---------------------------------------------------------------------------
// misconfiguration
// ---------------------------------------------------------------------------

Deno.test("handleMatch - empty pepper throws (misconfiguration, not a 4xx)", async () => {
  const store = new FakeMatchStore();
  store.seedRegistered(USER_ID, true);
  await assertRejects(
    () => handleMatch({ added: [fakeHash(1)] }, ctx(), store, ""),
    Error,
  );
});
