// Tests for submit-game/handler.ts, written strictly against its contract
// doc comments. Store is FakeSubmitGameStore (in-memory); no real DB.

import { assertEquals } from "jsr:@std/assert";
import type { ErrorBody, Outcome, RequestContext } from "../_shared/context.ts";
import { clampElapsed } from "../submit-result/handler.ts";
import { scoreFor } from "../_shared/games/common.ts";
import type { StarsSolution, StarsSpec } from "../_shared/games/stars.ts";
import { FakeSubmitGameStore } from "../_shared/test_fakes.ts";
import { handleSubmitGame, type StoredGameResult, type SubmitGameResponse } from "./handler.ts";

// A tiny Stars spec/solution (same shape as _shared/games/stars_test.ts's
// fixture, kept small and self-contained here): 5x5, stars at columns
// [1,3,0,2,4], regions grown around them.
const STARS_SPEC: StarsSpec = {
  n: 5,
  regions: [
    [0, 0, 0, 1, 1],
    [0, 0, 1, 1, 1],
    [2, 2, 1, 1, 1],
    [2, 3, 3, 3, 3],
    [3, 3, 3, 3, 4],
  ],
};
const STARS_SOLUTION: StarsSolution = { stars: [1, 3, 0, 2, 4] };
const GAME_NUMBER = 12;

const NOW = new Date("2026-09-11T12:00:00Z");

function ctx(overrides: Partial<RequestContext> = {}): RequestContext {
  return { userId: "user-1", now: NOW, ...overrides };
}

function seedGame(store: FakeSubmitGameStore, date: string): void {
  store.seedGame(date, "stars", STARS_SPEC, STARS_SOLUTION, GAME_NUMBER);
}

function assertOk(outcome: Outcome<SubmitGameResponse>, status: 200 | 201): SubmitGameResponse {
  if (outcome.status !== status) {
    throw new Error(`expected status ${status}, got ${outcome.status}: ${JSON.stringify(outcome.body)}`);
  }
  return outcome.body as SubmitGameResponse;
}

function assertErr(
  outcome: Outcome<SubmitGameResponse>,
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
// Body shape validation
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - bad_request: body is not an object", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame("nope", ctx(), store);
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: date missing", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: game not in GAME_KINDS", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "bogus", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: {} },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: tz missing", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "stars", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: elapsedMs negative", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "stars", tz: "UTC", elapsedMs: -5, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: elapsedMs non-finite", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "stars", tz: "UTC", elapsedMs: NaN, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - bad_request: gaveUp not boolean", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: "nope", answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_request");
});

Deno.test("handleSubmitGame - mistakes out of range is clamped, not rejected: 1234 -> 999", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);
  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 1234, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.result.mistakes, 999);
});

Deno.test("handleSubmitGame - negative mistakes is clamped to 0", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);
  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: -5, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.result.mistakes, 0);
});

// ---------------------------------------------------------------------------
// date / tz validation
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - bad_date: date outside the +/-14h window", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2000-01-01", game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_date");
});

Deno.test("handleSubmitGame - bad_tz: not a valid IANA zone", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    {
      date: "2026-09-11",
      game: "stars",
      tz: "Mars/Olympus",
      elapsedMs: 1000,
      mistakes: 0,
      gaveUp: false,
      answer: STARS_SOLUTION,
    },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_tz");
});

Deno.test("handleSubmitGame - validation order: an out-of-window date beats a bad tz", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    {
      date: "2000-01-01",
      game: "stars",
      tz: "Mars/Olympus",
      elapsedMs: 1000,
      mistakes: 0,
      gaveUp: false,
      answer: STARS_SOLUTION,
    },
    ctx(),
    store,
  );
  assertErr(outcome, 400, "bad_date");
});

// ---------------------------------------------------------------------------
// already_played / no_puzzle
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - already_played: 409 with the existing stored result as detail", async () => {
  const store = new FakeSubmitGameStore();
  const userId = "user-played";
  const date = "2026-09-11";
  seedGame(store, date);
  const existing: StoredGameResult = {
    date,
    game: "stars",
    elapsedMs: 90_000,
    elapsedSource: "client",
    mistakes: 3,
    solved: false,
    gaveUp: true,
    score: 100,
    submittedAt: new Date("2026-09-11T09:00:00Z").toISOString(),
  };
  store.seedResult(userId, existing);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx({ userId }),
    store,
  );
  const err = assertErr(outcome, 409, "already_played");
  assertEquals(err.detail, existing);
});

Deno.test("handleSubmitGame - no_puzzle: 404 when no game row exists for the date", async () => {
  const store = new FakeSubmitGameStore();
  const outcome = await handleSubmitGame(
    { date: "2026-09-11", game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 404, "no_puzzle");
});

// ---------------------------------------------------------------------------
// wrong_answer (422) via validateAnswer
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - wrong_answer: 422 with code wrong_answer and the validation reason as error", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  const badAnswer = { stars: [1, 3, 0, 2, 1] }; // duplicate column -> rule:column

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: badAnswer },
    ctx(),
    store,
  );
  const err = assertErr(outcome, 422, "wrong_answer");
  assertEquals(err.error, "rule:column");
});

Deno.test("handleSubmitGame - wrong_answer: 422 'mismatch' when the answer passes the rules but doesn't match the stored solution (B4)", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  // Deliberately stored solution differs from what a rules-valid submission
  // will look like; store.getGame's `solution` is opaque to validateAnswer
  // (which only checks STARS_SPEC's rules), so this doesn't need to be a
  // genuinely valid arrangement itself.
  const differentSolution: StarsSolution = { stars: [0, 0, 0, 0, 0] };
  store.seedGame(date, "stars", STARS_SPEC, differentSolution, GAME_NUMBER);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const err = assertErr(outcome, 422, "wrong_answer");
  assertEquals(err.error, "mismatch");
});

Deno.test("handleSubmitGame - answer required unless gaveUp: missing answer -> wrong_answer (shape)", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false },
    ctx(),
    store,
  );
  assertErr(outcome, 422, "wrong_answer");
});

Deno.test("handleSubmitGame - a 422 (rules or mismatch) never writes a result row", async () => {
  const store = new FakeSubmitGameStore();
  const userId = "user-422";
  const date = "2026-09-11";
  seedGame(store, date);
  const badAnswer = { stars: [1, 3, 0, 2, 1] }; // duplicate column -> rule:column

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: badAnswer },
    ctx({ userId }),
    store,
  );
  assertErr(outcome, 422, "wrong_answer");
  assertEquals(await store.getResult(userId, date, "stars"), null);
});

// ---------------------------------------------------------------------------
// gaveUp path: no answer needed, solved false, score 100
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - gaveUp: answer is ignored, solved=false, gaveUp=true, score=100", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 5_000, mistakes: 2, gaveUp: true },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.result.solved, false);
  assertEquals(body.result.gaveUp, true);
  assertEquals(body.result.score, 100);
  assertEquals(body.result.score, scoreFor(body.result.elapsedMs, true));
});

// ---------------------------------------------------------------------------
// Happy path: elapsed clamping, score, streak
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - happy path: start 60s before now, client 48210ms -> elapsedMs 57000, source server", async () => {
  const store = new FakeSubmitGameStore();
  const userId = "user-happy";
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart(userId, date, "stars", new Date(NOW.getTime() - 60_000));
  store.setStreak(userId, 7);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 48_210, mistakes: 3, gaveUp: false, answer: STARS_SOLUTION },
    ctx({ userId }),
    store,
  );
  const body = assertOk(outcome, 201);

  const expectedClamp = clampElapsed(48_210, 60_000);
  assertEquals(expectedClamp, { elapsedMs: 57_000, source: "server" });
  assertEquals(body.result.elapsedMs, 57_000);
  assertEquals(body.result.elapsedSource, "server");
  assertEquals(body.result.solved, true);
  assertEquals(body.result.gaveUp, false);
  assertEquals(body.result.mistakes, 3);
  assertEquals(body.result.score, scoreFor(57_000, false));
  assertEquals(body.streak, 7);
});

Deno.test("handleSubmitGame - no_start: 409 when there is no game_starts row (A1)", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 12_345, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  assertErr(outcome, 409, "no_start");
  assertEquals(await store.getResult("user-1", date, "stars"), null);
});

Deno.test("handleSubmitGame - no_start: 409 even when gaveUp is true (no answer to validate)", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 5_000, mistakes: 0, gaveUp: true },
    ctx(),
    store,
  );
  assertErr(outcome, 409, "no_start");
});

Deno.test("handleSubmitGame - clamp: elapsedMs far beyond the server elapsed is clamped per clampElapsed rules", async () => {
  const store = new FakeSubmitGameStore();
  const userId = "user-clamp";
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart(userId, date, "stars", new Date(NOW.getTime() - 60_000));

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 200_000_000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx({ userId }),
    store,
  );
  const body = assertOk(outcome, 201);
  const expectedClamp = clampElapsed(200_000_000, 60_000);
  assertEquals(body.result.elapsedMs, expectedClamp.elapsedMs);
  assertEquals(body.result.elapsedSource, expectedClamp.source);
  assertEquals(body.result.score, scoreFor(expectedClamp.elapsedMs, false));
});

// ---------------------------------------------------------------------------
// Duplicate race
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - duplicate race: insertResult throws duplicate -> 409 with the raced row", async () => {
  const store = new FakeSubmitGameStore();
  const userId = "user-race";
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart(userId, date, "stars", NOW);

  const raced: StoredGameResult = {
    date,
    game: "stars",
    elapsedMs: 20_000,
    elapsedSource: "client",
    mistakes: 1,
    solved: true,
    gaveUp: false,
    score: scoreFor(20_000, false),
    submittedAt: new Date("2026-09-11T11:59:00Z").toISOString(),
  };
  store.forceDuplicateOnce = true;
  store.raceResult = raced;

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 5_000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx({ userId }),
    store,
  );
  const err = assertErr(outcome, 409, "already_played");
  assertEquals(err.detail, raced);
});

// ---------------------------------------------------------------------------
// touchUser / streak best-effort
// ---------------------------------------------------------------------------

Deno.test("handleSubmitGame - touchUser failure does not block the 201, result already committed", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);
  store.touchUserError = new Error("touch failed");
  store.setStreak("user-1", 4);

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.streak, 4);
});

Deno.test("handleSubmitGame - streak failure defaults to 0 but still 201", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);
  store.streakError = new Error("streak failed");

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.streak, 0);
});

Deno.test("handleSubmitGame - both touchUser and streak failing still returns 201 with streak 0", async () => {
  const store = new FakeSubmitGameStore();
  const date = "2026-09-11";
  seedGame(store, date);
  store.seedStart("user-1", date, "stars", NOW);
  store.touchUserError = new Error("touch failed");
  store.streakError = new Error("streak failed");

  const outcome = await handleSubmitGame(
    { date, game: "stars", tz: "UTC", elapsedMs: 1000, mistakes: 0, gaveUp: false, answer: STARS_SOLUTION },
    ctx(),
    store,
  );
  const body = assertOk(outcome, 201);
  assertEquals(body.streak, 0);
  assertEquals(body.result.solved, true);
});
