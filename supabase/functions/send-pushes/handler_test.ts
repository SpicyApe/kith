// Tests for send-pushes/handler.ts, written strictly against its contract doc
// comments. Store is FakePushStore (in-memory); the sender is a local fake
// (PushSender isn't a Store, so it isn't in test_fakes.ts).

import { assertEquals, assertRejects } from "jsr:@std/assert";
import type { ApnsPayload, ApnsResult } from "../_shared/apns.ts";
import { FakePushStore } from "../_shared/test_fakes.ts";
import { handleSendPushes, pushCopy, type PushCandidate, type PushSender } from "./handler.ts";

// ---------------------------------------------------------------------------
// fake sender
// ---------------------------------------------------------------------------

class FakeSender implements PushSender {
  /** Per-apnsToken override; falls back to `default`. */
  results = new Map<string, ApnsResult>();
  default: ApnsResult = { ok: true };
  calls: Array<{ env: "sandbox" | "production"; apnsToken: string; payload: ApnsPayload }> = [];

  send(env: "sandbox" | "production", apnsToken: string, payload: ApnsPayload): Promise<ApnsResult> {
    this.calls.push({ env, apnsToken, payload });
    return Promise.resolve(this.results.get(apnsToken) ?? this.default);
  }
}

function candidate(overrides: Partial<PushCandidate> = {}): PushCandidate {
  return {
    userId: "user-1",
    kind: "daily_drop",
    apnsToken: "tok-1",
    env: "sandbox",
    payload: { friendsPlayed: 0 },
    ...overrides,
  };
}

const NOW = new Date("2026-09-11T12:00:00Z");

// ---------------------------------------------------------------------------
// pushCopy - daily_drop
// ---------------------------------------------------------------------------

Deno.test("pushCopy - daily_drop friendsPlayed 0", () => {
  assertEquals(pushCopy("daily_drop", { friendsPlayed: 0 }), {
    title: "Today's Lineup is up.",
    body: "Be the first of your friends to play.",
    url: "kith://today",
    kind: "daily_drop",
  });
});

Deno.test("pushCopy - daily_drop friendsPlayed 1", () => {
  const p = pushCopy("daily_drop", { friendsPlayed: 1 });
  assertEquals(p.body, "1 friend has already played.");
  assertEquals(p.title, "Today's Lineup is up.");
  assertEquals(p.url, "kith://today");
  assertEquals(p.kind, "daily_drop");
});

Deno.test("pushCopy - daily_drop friendsPlayed n (3)", () => {
  assertEquals(pushCopy("daily_drop", { friendsPlayed: 3 }).body, "3 friends have already played.");
});

Deno.test("pushCopy - daily_drop missing friendsPlayed treated as 0", () => {
  assertEquals(pushCopy("daily_drop", {}).body, "Be the first of your friends to play.");
});

Deno.test("pushCopy - daily_drop invalid (non-number) friendsPlayed treated as 0", () => {
  assertEquals(pushCopy("daily_drop", { friendsPlayed: "lots" }).body, "Be the first of your friends to play.");
});

// ---------------------------------------------------------------------------
// pushCopy - streak_risk
// ---------------------------------------------------------------------------

Deno.test("pushCopy - streak_risk hoursLeft 1 (<=1 boundary)", () => {
  const p = pushCopy("streak_risk", { streak: 5, hoursLeft: 1 });
  assertEquals(p, {
    title: "5-day streak on the line.",
    body: "Less than an hour left.",
    url: "kith://today",
    kind: "streak_risk",
  });
});

Deno.test("pushCopy - streak_risk hoursLeft 5", () => {
  const p = pushCopy("streak_risk", { streak: 5, hoursLeft: 5 });
  assertEquals(p.title, "5-day streak on the line.");
  assertEquals(p.body, "5 hours left.");
});

Deno.test("pushCopy - streak_risk missing streak/hoursLeft treated as 0", () => {
  const p = pushCopy("streak_risk", {});
  assertEquals(p.title, "0-day streak on the line.");
  assertEquals(p.body, "Less than an hour left.");
});

// ---------------------------------------------------------------------------
// pushCopy - passed
// ---------------------------------------------------------------------------

Deno.test("pushCopy - passed others 0", () => {
  const p = pushCopy("passed", { by: "Sam", others: 0, rank: 2 });
  assertEquals(p, {
    title: "Sam just passed you.",
    body: "You're #2 among friends.",
    url: "kith://board",
    kind: "passed",
  });
});

Deno.test("pushCopy - passed others 1", () => {
  const p = pushCopy("passed", { by: "Sam", others: 1, rank: 3 });
  assertEquals(p.body, "Sam and 1 other passed you. You're #3 among friends.");
});

Deno.test("pushCopy - passed others n (2)", () => {
  const p = pushCopy("passed", { by: "Sam", others: 2, rank: 4 });
  assertEquals(p.body, "Sam and 2 others passed you. You're #4 among friends.");
});

Deno.test("pushCopy - passed missing 'by' defaults to 'A friend'", () => {
  const p = pushCopy("passed", { others: 0, rank: 1 });
  assertEquals(p.title, "A friend just passed you.");
});

Deno.test("pushCopy - passed missing numbers treated as 0", () => {
  const p = pushCopy("passed", { by: "Sam" });
  assertEquals(p.body, "You're #0 among friends.");
});

// ---------------------------------------------------------------------------
// handleSendPushes
// ---------------------------------------------------------------------------

Deno.test("handleSendPushes - two devices for one (user,kind) both ok: sent 1, log called once", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ apnsToken: "tokA" }),
    candidate({ apnsToken: "tokB" }),
  ];
  const sender = new FakeSender();

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 1, failed: 0, deadTokens: 0 });
  assertEquals(sender.calls.length, 2);
  assertEquals(store.logCalls.length, 1);
  assertEquals(store.logCalls[0].userId, "user-1");
  assertEquals(store.logCalls[0].kind, "daily_drop");
  assertEquals(store.logCalls[0].at, NOW);
});

Deno.test("handleSendPushes - one ok one bad_token: sent 1, deadTokens 1, deleteDevice called, log once", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ apnsToken: "tokGood" }),
    candidate({ apnsToken: "tokBad" }),
  ];
  const sender = new FakeSender();
  sender.results.set("tokBad", { ok: false, reason: "bad_token" });

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 1, failed: 0, deadTokens: 1 });
  assertEquals(store.deleteDeviceCalls, [{ userId: "user-1", apnsToken: "tokBad" }]);
  assertEquals(store.logCalls.length, 1);
});

Deno.test("handleSendPushes - all devices error: sent 0, failed n, log NOT called", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ apnsToken: "tok1" }),
    candidate({ apnsToken: "tok2" }),
    candidate({ apnsToken: "tok3" }),
  ];
  const sender = new FakeSender();
  sender.default = { ok: false, reason: "error", status: 500 };

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 0, failed: 3, deadTokens: 0 });
  assertEquals(store.logCalls.length, 0);
});

Deno.test("handleSendPushes - two users with different kinds: sent 2, two log rows", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ userId: "u1", kind: "daily_drop", apnsToken: "t1" }),
    candidate({ userId: "u2", kind: "streak_risk", apnsToken: "t2" }),
  ];
  const sender = new FakeSender();

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 2, failed: 0, deadTokens: 0 });
  assertEquals(store.logCalls.length, 2);
  const rows = store.logCalls.map((c) => `${c.userId}:${c.kind}`).sort();
  assertEquals(rows, ["u1:daily_drop", "u2:streak_risk"]);
});

Deno.test("handleSendPushes - candidates() throwing propagates", async () => {
  const store = new FakePushStore();
  store.candidatesError = new Error("db unreachable");
  const sender = new FakeSender();

  await assertRejects(() => handleSendPushes(NOW, store, sender), Error, "db unreachable");
});

Deno.test("handleSendPushes - empty candidates: report is all zeros, no logs", async () => {
  const store = new FakePushStore();
  const sender = new FakeSender();

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 0, failed: 0, deadTokens: 0 });
  assertEquals(store.logCalls.length, 0);
  assertEquals(sender.calls.length, 0);
});

Deno.test("handleSendPushes - store.log rejecting for the first group still counts later groups; the rejection counts as failed", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ userId: "u1", kind: "daily_drop", apnsToken: "t1" }),
    candidate({ userId: "u2", kind: "streak_risk", apnsToken: "t2" }),
  ];
  store.logError = new Error("log boom");
  const sender = new FakeSender();

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 2, failed: 1, deadTokens: 0 });
  assertEquals(store.logCalls.length, 2);
  const rows = store.logCalls.map((c) => `${c.userId}:${c.kind}`).sort();
  assertEquals(rows, ["u1:daily_drop", "u2:streak_risk"]);
});

Deno.test("handleSendPushes - mixed ok/error within one group still counts one sent and the errors as failed", async () => {
  const store = new FakePushStore();
  store.candidatesResult = [
    candidate({ apnsToken: "tokErr1" }),
    candidate({ apnsToken: "tokOk" }),
    candidate({ apnsToken: "tokErr2" }),
  ];
  const sender = new FakeSender();
  sender.results.set("tokErr1", { ok: false, reason: "error", status: 500 });
  sender.results.set("tokErr2", { ok: false, reason: "error", status: 429 });

  const report = await handleSendPushes(NOW, store, sender);

  assertEquals(report, { sent: 1, failed: 2, deadTokens: 0 });
  assertEquals(store.logCalls.length, 1);
});
