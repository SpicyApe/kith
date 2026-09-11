// Tests for submit-result/handler.ts, written strictly against its contract
// doc comments. `clampElapsed` is already implemented (real logic); only
// `handleSubmit` is a stub right now, so its tests type-check but won't pass
// until the body lands. Store is FakeSubmitStore (in-memory); no real DB.

import { assertEquals } from "jsr:@std/assert";
import type { ErrorBody, Outcome, RequestContext } from "../_shared/context.ts";
import { type AttemptLog, evaluate, LineupError, score } from "../_shared/lineup.ts";
import { FakeSubmitStore } from "../_shared/test_fakes.ts";
import {
  clampElapsed,
  handleSubmit,
  MAX_ELAPSED_MS,
  type StoredResult,
  type SubmitResponse,
} from "./handler.ts";

const CORRECT_ORDER = [1, 2, 3, 4, 5];
const NOW = new Date("2026-09-11T12:00:00Z");

function ctx(overrides: Partial<RequestContext> = {}): RequestContext {
  return { userId: "user-1", now: NOW, ...overrides };
}

function assertOk(outcome: Outcome<SubmitResponse>, status: 200 | 201): SubmitResponse {
  if (outcome.status !== status) {
    throw new Error(`expected status ${status}, got ${outcome.status}: ${JSON.stringify(outcome.body)}`);
  }
  return outcome.body as SubmitResponse;
}

function assertErr(
  outcome: Outcome<SubmitResponse>,
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

/** The message a bare `evaluate()` call would throw for this input, so we can
 * assert the handler forwards the LineupError's own message verbatim. */
function expectedLineupMessage(attempts: AttemptLog[], correctOrder: number[]): string {
  try {
    evaluate(attempts, correctOrder);
  } catch (e) {
    if (e instanceof LineupError) return e.message;
    throw e;
  }
  throw new Error("expected evaluate() to throw for this fixture");
}

// ---------------------------------------------------------------------------
// clampElapsed (already implemented — these should pass today)
// ---------------------------------------------------------------------------

Deno.test("clampElapsed - null server returns the client value verbatim, source client", () => {
  assertEquals(clampElapsed(7_777, null), { elapsedMs: 7_777, source: "client" });
});

Deno.test("clampElapsed - client 5000 server 9000 clamps up to 6000 (server minus grace)", () => {
  assertEquals(clampElapsed(5_000, 9_000), { elapsedMs: 6_000, source: "server" });
});

Deno.test("clampElapsed - client 8000 server 9000 keeps the client value", () => {
  assertEquals(clampElapsed(8_000, 9_000), { elapsedMs: 8_000, source: "server" });
});

Deno.test("clampElapsed - client may exceed server: client 50000 server 9000 keeps 50000", () => {
  assertEquals(clampElapsed(50_000, 9_000), { elapsedMs: 50_000, source: "server" });
});

Deno.test("clampElapsed - never negative: server 2000 client 0 floors to 0", () => {
  assertEquals(clampElapsed(0, 2_000), { elapsedMs: 0, source: "server" });
});

Deno.test("clampElapsed - server branch clamps to MAX_ELAPSED_MS", () => {
  const huge = MAX_ELAPSED_MS + 1_000_000;
  assertEquals(clampElapsed(huge, huge), { elapsedMs: MAX_ELAPSED_MS, source: "server" });
});

Deno.test("clampElapsed - client branch clamps to MAX_ELAPSED_MS", () => {
  assertEquals(clampElapsed(1_000_000_000, null), { elapsedMs: MAX_ELAPSED_MS, source: "client" });
});

// ---------------------------------------------------------------------------
// handleSubmit - body validation
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - bad_request: body is not an object", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit("nope", ctx(), store);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmit - bad_request: puzzleDate missing", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit({ tz: "UTC", attempts: [] }, ctx(), store);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmit - bad_request: tz missing", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit({ puzzleDate: "2026-09-11", attempts: [] }, ctx(), store);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmit - bad_request: attempts is not an array", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit(
    { puzzleDate: "2026-09-11", tz: "UTC", attempts: "nope" },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

// ---------------------------------------------------------------------------
// handleSubmit - date / tz validation and their ordering
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - bad_date: puzzleDate outside the +/-14h window", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit({ puzzleDate: "2000-01-01", tz: "UTC", attempts: [] }, ctx(), store);
  assertErr(outcome, 400, "bad_date");
});

Deno.test("handleSubmit - bad_tz: not a valid IANA zone", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit(
    { puzzleDate: "2026-09-11", tz: "Mars/Olympus", attempts: [] },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_tz");
});

Deno.test("handleSubmit - validation order: an out-of-window date beats a bad tz", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit(
    { puzzleDate: "2000-01-01", tz: "Mars/Olympus", attempts: [] },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_date");
});

// ---------------------------------------------------------------------------
// handleSubmit - already_played / no_puzzle
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - already_played: 409 with the existing stored result as detail", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-played";
  const date = "2026-09-11";
  const existing: StoredResult = {
    puzzleDate: date,
    tries: 3,
    solved: false,
    elapsedMs: 90_000,
    score: 100,
    attempts: [],
    elapsedSource: "client",
    submittedAt: new Date("2026-09-11T09:00:00Z").toISOString(),
  };
  store.seedResult(userId, existing);

  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts: [] }, ctx({ userId }), store);
  const err = assertErr(outcome, 409, "already_played");
  assertEquals(err.detail, existing);
});

Deno.test("handleSubmit - no_puzzle: 404 when no puzzle exists for the date", async () => {
  const store = new FakeSubmitStore();
  const outcome = await handleSubmit({ puzzleDate: "2026-09-11", tz: "UTC", attempts: [] }, ctx(), store);
  assertErr(outcome, 404, "no_puzzle");
});

// ---------------------------------------------------------------------------
// handleSubmit - LineupError -> 422
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - LineupError incomplete_log maps to 422 with matching code and message", async () => {
  const store = new FakeSubmitStore();
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  const attempts: AttemptLog[] = [{ order: [2, 1, 3, 4, 5], elapsedMs: 1_000 }];

  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx(), store);
  const err = assertErr(outcome, 422, "incomplete_log");
  assertEquals(err.error, expectedLineupMessage(attempts, CORRECT_ORDER));
});

Deno.test("handleSubmit - LineupError bad_order maps to 422 with matching code and message", async () => {
  const store = new FakeSubmitStore();
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  const attempts: AttemptLog[] = [{ order: [1, 2, 3, 4], elapsedMs: 1_000 }];

  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx(), store);
  const err = assertErr(outcome, 422, "bad_order");
  assertEquals(err.error, expectedLineupMessage(attempts, CORRECT_ORDER));
});

// ---------------------------------------------------------------------------
// handleSubmit - happy paths
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - happy path with a start row: elapsed clamped to server value, scored, streak, touchUser", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-happy";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  // Start was 60s before now; server-observed elapsed is 60000ms, minus the
  // 3000ms grace = 57000ms, which beats the client's reported 48210ms.
  store.seedStart(userId, date, new Date(NOW.getTime() - 60_000));
  store.setStreak(userId, 4);

  const attempts: AttemptLog[] = [
    { order: [1, 2, 4, 3, 5], elapsedMs: 10_000 },
    { order: [1, 2, 3, 4, 5], elapsedMs: 48_210 },
  ];

  const outcome = await handleSubmit(
    { puzzleDate: date, tz: "America/New_York", attempts },
    ctx({ userId }),
    store,
  );

  const body = assertOk(outcome, 201);
  assertEquals(body.result.elapsedMs, 57_000);
  assertEquals(body.result.elapsedSource, "server");
  assertEquals(body.result.tries, 2);
  assertEquals(body.result.solved, true);
  assertEquals(body.result.score, score(2, true, 57_000));
  assertEquals(body.streak, 4);
  assertEquals(
    body.result.attempts[1].feedback,
    ["correct", "correct", "correct", "correct", "correct"],
  );

  assertEquals(store.touchUserCalls.length, 1);
  assertEquals(store.touchUserCalls[0].userId, userId);
  assertEquals(store.touchUserCalls[0].tz, "America/New_York");
  assertEquals(store.touchUserCalls[0].now, NOW);
});

Deno.test("handleSubmit - happy path without a start row: source client, elapsedMs is the raw client value", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-no-start";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);

  const attempts: AttemptLog[] = [
    { order: [1, 2, 4, 3, 5], elapsedMs: 10_000 },
    { order: [1, 2, 3, 4, 5], elapsedMs: 48_210 },
  ];

  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx({ userId }), store);

  const body = assertOk(outcome, 201);
  assertEquals(body.result.elapsedSource, "client");
  assertEquals(body.result.elapsedMs, 48_210);
  assertEquals(body.result.score, score(2, true, 48_210));
});

Deno.test("handleSubmit - duplicate race on insert re-reads the row and returns 409 already_played", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-race";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);

  const raceResult: StoredResult = {
    puzzleDate: date,
    tries: 1,
    solved: true,
    elapsedMs: 9_000,
    score: 940,
    attempts: [
      { order: [1, 2, 3, 4, 5], feedback: ["correct", "correct", "correct", "correct", "correct"], elapsedMs: 9_000 },
    ],
    elapsedSource: "client",
    submittedAt: new Date("2026-09-11T11:59:00Z").toISOString(),
  };
  store.forceDuplicateOnce = true;
  store.raceResult = raceResult;

  const attempts: AttemptLog[] = [{ order: [1, 2, 3, 4, 5], elapsedMs: 5_000 }];
  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx({ userId }), store);

  const err = assertErr(outcome, 409, "already_played");
  assertEquals(err.detail, raceResult);
});

Deno.test("handleSubmit - duplicate race with no re-readable row: 409 body has no detail key", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-race-null";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  store.forceDuplicateOnce = true;
  store.raceResult = null;

  const attempts: AttemptLog[] = [{ order: [1, 2, 3, 4, 5], elapsedMs: 5_000 }];
  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx({ userId }), store);

  assertErr(outcome, 409, "already_played");
  assertEquals(Object.hasOwn((outcome.body as ErrorBody), "detail"), false);
});

// ---------------------------------------------------------------------------
// handleSubmit - touchUser / streak are best-effort
// ---------------------------------------------------------------------------

Deno.test("handleSubmit - touchUser throwing still returns 201", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-touch-fails";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  store.setStreak(userId, 2);
  store.touchUserError = new Error("boom");

  const attempts: AttemptLog[] = [{ order: [1, 2, 3, 4, 5], elapsedMs: 5_000 }];
  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx({ userId }), store);

  const body = assertOk(outcome, 201);
  assertEquals(body.streak, 2);
});

Deno.test("handleSubmit - streak throwing still returns 201 with streak 0", async () => {
  const store = new FakeSubmitStore();
  const userId = "user-streak-fails";
  const date = "2026-09-11";
  store.seedPuzzle(date, CORRECT_ORDER);
  store.setStreak(userId, 5);
  store.streakError = new Error("boom");

  const attempts: AttemptLog[] = [{ order: [1, 2, 3, 4, 5], elapsedMs: 5_000 }];
  const outcome = await handleSubmit({ puzzleDate: date, tz: "UTC", attempts }, ctx({ userId }), store);

  const body = assertOk(outcome, 201);
  assertEquals(body.streak, 0);
  assertEquals(store.insertResultCalls.length, 1);
});
