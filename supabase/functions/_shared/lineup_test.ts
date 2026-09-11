// Tests for lineup.ts, written strictly against its doc comments.
// Run with `deno test` once the bodies are implemented; `deno check` only for now.

import { assertEquals, assertNotEquals, assertThrows } from "jsr:@std/assert";
import {
  type AttemptLog,
  type EvaluatedAttempt,
  type Evaluation,
  type Feedback,
  evaluate,
  feedbackFor,
  LineupError,
  type LineupErrorCode,
  score,
  shareText,
} from "./lineup.ts";

const CORRECT_ORDER = [1, 2, 3, 4, 5];

function attemptLog(order: number[], elapsedMs: number): AttemptLog {
  return { order, elapsedMs };
}

/** Builds an already-evaluated attempt (server output), feedback included, for
 * shareText tests that render a pre-built `Evaluation` directly. */
function resultAttempt(order: number[], feedback: Feedback[], elapsedMs: number): EvaluatedAttempt {
  return { order, feedback, elapsedMs };
}

function assertErrorCode(fn: () => void, expected: LineupErrorCode) {
  const err = assertThrows(fn, LineupError);
  assertEquals(err.code, expected);
}

// ---------------------------------------------------------------------------
// feedbackFor
// ---------------------------------------------------------------------------

Deno.test("feedbackFor - all correct", () => {
  assertEquals(
    feedbackFor([1, 2, 3, 4, 5], CORRECT_ORDER),
    ["correct", "correct", "correct", "correct", "correct"],
  );
});

Deno.test("feedbackFor - all wrong (rotate by 2)", () => {
  assertEquals(
    feedbackFor([3, 4, 5, 1, 2], CORRECT_ORDER),
    ["wrong", "wrong", "wrong", "wrong", "wrong"],
  );
});

Deno.test("feedbackFor - near miss above and below, interior", () => {
  assertEquals(
    feedbackFor([1, 3, 2, 4, 5], CORRECT_ORDER),
    ["correct", "near", "near", "correct", "correct"],
  );
});

Deno.test("feedbackFor - near miss at edge position 0", () => {
  assertEquals(
    feedbackFor([2, 1, 3, 4, 5], CORRECT_ORDER),
    ["near", "near", "correct", "correct", "correct"],
  );
});

Deno.test("feedbackFor - near miss at edge position 4", () => {
  assertEquals(
    feedbackFor([1, 2, 3, 5, 4], CORRECT_ORDER),
    ["correct", "correct", "correct", "near", "near"],
  );
});

Deno.test("feedbackFor - wrong when two positions away", () => {
  assertEquals(
    feedbackFor([1, 4, 3, 2, 5], CORRECT_ORDER),
    ["correct", "wrong", "correct", "wrong", "correct"],
  );
});

// ---------------------------------------------------------------------------
// score
// ---------------------------------------------------------------------------

Deno.test("score - solved try 1 at zero elapsed = 1000", () => {
  assertEquals(score(1, true, 0), 1000);
});

Deno.test("score - solved try 2 at zero elapsed = 700", () => {
  assertEquals(score(2, true, 0), 700);
});

Deno.test("score - solved try 3 at zero elapsed = 400", () => {
  assertEquals(score(3, true, 0), 400);
});

Deno.test("score - penalty at 1500ms is 2 points", () => {
  assertEquals(score(1, true, 1_500), 1000 - 2);
});

Deno.test("score - penalty at 48210ms is 96 points", () => {
  assertEquals(score(1, true, 48_210), 1000 - 96);
});

Deno.test("score - penalty caps at 240 at 200000ms", () => {
  assertEquals(score(1, true, 200_000), 1000 - 240);
});

Deno.test("score - penalty cap holds just past 120s", () => {
  assertEquals(score(2, true, 121_000), 700 - 240);
});

Deno.test("score - not solved is flat 100 regardless of time", () => {
  assertEquals(score(1, false, 0), 100);
  assertEquals(score(3, false, 500_000), 100);
});

Deno.test("score - tries 0 clamped to 1", () => {
  assertEquals(score(0, true, 0), score(1, true, 0));
});

Deno.test("score - tries 7 clamped to 3", () => {
  assertEquals(score(7, true, 0), score(3, true, 0));
});

Deno.test("score - negative tries clamped to 1", () => {
  assertEquals(score(-5, true, 0), score(1, true, 0));
});

Deno.test("score - negative elapsed treated as 0", () => {
  assertEquals(score(1, true, -500), score(1, true, 0));
});

// ---------------------------------------------------------------------------
// evaluate - happy path
// ---------------------------------------------------------------------------

Deno.test("evaluate - two-try solve recomputes feedback and ignores client feedback", () => {
  // Deliberately wrong client-supplied feedback for both attempts.
  const wrongClientFeedback: Feedback[] = ["wrong", "wrong", "wrong", "wrong", "wrong"];

  const attempt1 = attemptLog([1, 2, 4, 3, 5], 10_000);
  const attempt2 = attemptLog([1, 2, 3, 4, 5], 15_000);

  const ev = evaluate([attempt1, attempt2], CORRECT_ORDER);

  assertEquals(ev.tries, 2);
  assertEquals(ev.solved, true);
  assertEquals(ev.elapsedMs, 15_000);
  assertEquals(ev.score, score(2, true, 15_000));

  const expectedFeedback1 = feedbackFor(attempt1.order, CORRECT_ORDER);
  const expectedFeedback2 = feedbackFor(attempt2.order, CORRECT_ORDER);
  assertEquals(ev.attempts[0].feedback, expectedFeedback1);
  assertEquals(ev.attempts[1].feedback, expectedFeedback2);
  assertEquals(ev.attempts[1].feedback, ["correct", "correct", "correct", "correct", "correct"]);
  // The recomputed feedback is NOT what the client sent.
  assertNotEquals(ev.attempts[0].feedback, wrongClientFeedback);
});

// ---------------------------------------------------------------------------
// evaluate - error codes
// ---------------------------------------------------------------------------

Deno.test("evaluate - bad_correct_order: duplicate id", () => {
  assertErrorCode(() => evaluate([], [1, 2, 3, 4, 4]), "bad_correct_order");
});

Deno.test("evaluate - bad_correct_order: wrong length", () => {
  assertErrorCode(() => evaluate([], [1, 2, 3, 4]), "bad_correct_order");
});

Deno.test("evaluate - no_attempts: empty log with a valid correctOrder", () => {
  assertErrorCode(() => evaluate([], CORRECT_ORDER), "no_attempts");
});

Deno.test("evaluate - too_many_attempts: more than MAX_TRIES", () => {
  const attempts = [
    attemptLog([1, 2, 3, 4, 5], 1_000),
    attemptLog([1, 2, 3, 4, 5], 2_000),
    attemptLog([1, 2, 3, 4, 5], 3_000),
    attemptLog([1, 2, 3, 4, 5], 4_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "too_many_attempts");
});

Deno.test("evaluate - too_many_attempts takes precedence over a bad order within the log", () => {
  const attempts = [
    attemptLog([1, 2, 3], 1_000), // wrong length, would otherwise be bad_order
    attemptLog([1, 2, 3, 4, 5], 2_000),
    attemptLog([1, 2, 3, 4, 5], 3_000),
    attemptLog([1, 2, 3, 4, 5], 4_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "too_many_attempts");
});

Deno.test("evaluate - bad_order: wrong length", () => {
  const attempts = [attemptLog([1, 2, 3, 4], 0)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_order");
});

Deno.test("evaluate - bad_order: duplicate id", () => {
  const attempts = [attemptLog([1, 1, 3, 4, 5], 0)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_order");
});

Deno.test("evaluate - bad_order: foreign id not in correctOrder", () => {
  const attempts = [attemptLog([1, 2, 3, 4, 6], 0)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_order");
});

Deno.test("evaluate - bad_elapsed: negative", () => {
  const attempts = [attemptLog([1, 2, 3, 4, 5], -1)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_elapsed");
});

Deno.test("evaluate - bad_elapsed: non-integer", () => {
  const attempts = [attemptLog([1, 2, 3, 4, 5], 1_000.5)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_elapsed");
});

Deno.test("evaluate - bad_elapsed: decreasing across attempts", () => {
  const attempts = [
    attemptLog([1, 2, 4, 3, 5], 5_000),
    attemptLog([2, 1, 4, 3, 5], 4_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_elapsed");
});

Deno.test("evaluate - played_past_end: attempts continue after a solved attempt", () => {
  const attempts = [
    attemptLog([1, 2, 3, 4, 5], 1_000),
    attemptLog([2, 1, 3, 4, 5], 2_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "played_past_end");
});

Deno.test("evaluate - locked_moved: a correct tile moves in the next attempt", () => {
  // Attempt 1: [1,2,4,3,5] -> correct at positions 0, 1, 4 (ids 1, 2, 5).
  // Attempt 2 moves id 1 away from position 0.
  const attempts = [
    attemptLog([1, 2, 4, 3, 5], 1_000),
    attemptLog([2, 1, 4, 3, 5], 2_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "locked_moved");
});

Deno.test("evaluate - unchanged_order: attempt repeats the previous order exactly", () => {
  const attempts = [
    attemptLog([1, 2, 4, 3, 5], 1_000),
    attemptLog([1, 2, 4, 3, 5], 2_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "unchanged_order");
});

// ---------------------------------------------------------------------------
// shareText
// ---------------------------------------------------------------------------

function evaluation(
  tries: number,
  solved: boolean,
  elapsedMs: number,
  attempts: EvaluatedAttempt[],
): Evaluation {
  return {
    tries,
    solved,
    elapsedMs,
    score: score(tries, solved, elapsedMs),
    attempts,
  };
}

const ALL_CORRECT: Feedback[] = ["correct", "correct", "correct", "correct", "correct"];

Deno.test("shareText - canonical example from the doc comment", () => {
  const ev = evaluation(2, true, 48_210, [
    resultAttempt([1, 2, 3, 4, 5], ["wrong", "near", "correct", "wrong", "near"], 10_000),
    resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 48_210),
  ]);

  const text = shareText(ev, 142, 12, "7F3Q");

  assertEquals(
    text,
    "Kith #142 · 2/3 · 0:48 🔥12\n⬜🟨🟩⬜🟨\n🟩🟩🟩🟩🟩\nkith.app/p/142?r=7F3Q",
  );
});

Deno.test("shareText - no trailing newline", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 1, 0, null);
  assertEquals(text.endsWith("\n"), false);
});

Deno.test("shareText - shows X/3 when not solved", () => {
  const wrong: Feedback[] = ["wrong", "near", "wrong", "near", "wrong"];
  const ev = evaluation(3, false, 65_000, [
    resultAttempt([1, 2, 3, 4, 5], wrong, 20_000),
    resultAttempt([1, 2, 3, 4, 5], wrong, 40_000),
    resultAttempt([1, 2, 3, 4, 5], wrong, 65_000),
  ]);
  const text = shareText(ev, 7, 5, null);
  assertEquals(text.startsWith("Kith #7 · X/3 · 1:05 🔥5\n"), true);
});

Deno.test("shareText - no flame when streak is 0", () => {
  const ev = evaluation(1, true, 10_000, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 10_000)]);
  const text = shareText(ev, 9, 0, null);
  assertEquals(text.startsWith("Kith #9 · 1/3 · 0:10\n"), true);
  assertEquals(text.includes("🔥"), false);
});

Deno.test("shareText - flame shown when streak is 1", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 1, 1, null);
  assertEquals(text.startsWith("Kith #1 · 1/3 · 0:00 🔥1\n"), true);
});

Deno.test("shareText - no ?r= when refCode is null", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 55, 0, null);
  assertEquals(text.endsWith("kith.app/p/55"), true);
  assertEquals(text.includes("?r="), false);
});

Deno.test("shareText - no ?r= when refCode is undefined", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 55, 0);
  assertEquals(text.endsWith("kith.app/p/55"), true);
  assertEquals(text.includes("?r="), false);
});

Deno.test("shareText - no ?r= when refCode is an empty string", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 55, 0, "");
  assertEquals(text.endsWith("kith.app/p/55"), true);
  assertEquals(text.includes("?r="), false);
});

Deno.test("shareText - ?r= appended when refCode is present", () => {
  const ev = evaluation(1, true, 0, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 0)]);
  const text = shareText(ev, 55, 0, "AB12");
  assertEquals(text.endsWith("kith.app/p/55?r=AB12"), true);
});

Deno.test("shareText - time formatting 0:05", () => {
  const ev = evaluation(1, true, 5_000, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 5_000)]);
  const text = shareText(ev, 1, 0, null);
  assertEquals(text.startsWith("Kith #1 · 1/3 · 0:05\n"), true);
});

Deno.test("shareText - time formatting 1:02", () => {
  const ev = evaluation(1, true, 62_000, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 62_000)]);
  const text = shareText(ev, 1, 0, null);
  assertEquals(text.startsWith("Kith #1 · 1/3 · 1:02\n"), true);
});

Deno.test("shareText - time formatting 12:00", () => {
  const ev = evaluation(1, true, 720_000, [resultAttempt([1, 2, 3, 4, 5], ALL_CORRECT, 720_000)]);
  const text = shareText(ev, 1, 0, null);
  assertEquals(text.startsWith("Kith #1 · 1/3 · 12:00\n"), true);
});

Deno.test("shareText - rendered from a real evaluate() result", () => {
  const ev = evaluate(
    [
      { order: [1, 2, 4, 3, 5], elapsedMs: 10_000 },
      { order: [1, 2, 3, 4, 5], elapsedMs: 48_210 },
    ],
    [1, 2, 3, 4, 5],
  );

  const text = shareText(ev, 142, 12, "7F3Q");

  assertEquals(
    text,
    "Kith #142 · 2/3 · 0:48 🔥12\n🟩🟩🟨🟨🟩\n🟩🟩🟩🟩🟩\nkith.app/p/142?r=7F3Q",
  );
});

// ---------------------------------------------------------------------------
// evaluate - malformed untrusted input (must throw LineupError, never a raw TypeError)
// ---------------------------------------------------------------------------

Deno.test("evaluate - no_attempts: attempts is null", () => {
  assertErrorCode(() => evaluate(null as unknown as AttemptLog[], CORRECT_ORDER), "no_attempts");
});

Deno.test("evaluate - no_attempts: attempts is not an array", () => {
  assertErrorCode(() => evaluate({} as unknown as AttemptLog[], CORRECT_ORDER), "no_attempts");
});

Deno.test("evaluate - bad_order: null entry inside the attempts array", () => {
  assertErrorCode(() => evaluate([null] as unknown as AttemptLog[], CORRECT_ORDER), "bad_order");
});

// ---------------------------------------------------------------------------
// evaluate - incomplete_log
// ---------------------------------------------------------------------------

Deno.test("evaluate - incomplete_log: a single unsolved attempt is rejected", () => {
  const attempts = [attemptLog([2, 1, 3, 4, 5], 1_000)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "incomplete_log");
});

Deno.test("evaluate - incomplete_log: two unsolved attempts (fewer than MAX_TRIES) is rejected", () => {
  const attempts = [
    attemptLog([2, 3, 4, 5, 1], 10_000),
    attemptLog([3, 4, 5, 1, 2], 20_000),
  ];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "incomplete_log");
});

Deno.test("evaluate - three-attempt solve on the final try scores 400 minus the time penalty", () => {
  const attempts = [
    attemptLog([2, 3, 1, 4, 5], 1_000),
    attemptLog([3, 1, 2, 4, 5], 2_000),
    attemptLog([1, 2, 3, 4, 5], 3_000),
  ];
  const ev = evaluate(attempts, CORRECT_ORDER);
  assertEquals(ev.tries, 3);
  assertEquals(ev.solved, true);
  const penalty = 2 * Math.floor(3_000 / 1000);
  assertEquals(ev.score, 400 - penalty);
});

// ---------------------------------------------------------------------------
// evaluate - bad_elapsed bounds
// ---------------------------------------------------------------------------

Deno.test("evaluate - bad_elapsed: absurdly large elapsedMs (1e21) is rejected", () => {
  const attempts = [attemptLog([1, 2, 3, 4, 5], 1e21)];
  assertErrorCode(() => evaluate(attempts, CORRECT_ORDER), "bad_elapsed");
});

// ---------------------------------------------------------------------------
// score - edge cases
// ---------------------------------------------------------------------------

Deno.test("score - fractional tries are truncated before clamping", () => {
  assertEquals(score(2.5, true, 0), 700);
});

// ---------------------------------------------------------------------------
// golden vectors — shared with packages/LineupEngine/Tests/LineupEngineTests/GoldenVectorTests.swift
// ---------------------------------------------------------------------------

interface GoldenCase {
  name: string;
  correctOrder: number[];
  attempts: Array<{ order: number[]; elapsedMs: number; feedback: Feedback[] }>;
  tries: number;
  solved: boolean;
  elapsedMs: number;
  score: number;
  share: { puzzleNumber: number; streak: number; refCode: string | null; text: string };
}

Deno.test("golden vectors", async () => {
  const url = new URL(
    "../../../packages/LineupEngine/Tests/LineupEngineTests/Fixtures/golden.json",
    import.meta.url,
  );
  const raw = await Deno.readTextFile(url);
  const fixture = JSON.parse(raw) as { cases: GoldenCase[] };

  if (fixture.cases.length < 6) {
    throw new Error(`expected at least 6 golden cases, got ${fixture.cases.length}`);
  }

  for (const c of fixture.cases) {
    const attempts: AttemptLog[] = c.attempts.map((a) => ({ order: a.order, elapsedMs: a.elapsedMs }));
    const ev = evaluate(attempts, c.correctOrder);

    assertEquals(ev.tries, c.tries, `${c.name}: tries`);
    assertEquals(ev.solved, c.solved, `${c.name}: solved`);
    assertEquals(ev.elapsedMs, c.elapsedMs, `${c.name}: elapsedMs`);
    assertEquals(ev.score, c.score, `${c.name}: score`);
    c.attempts.forEach((a, i) => {
      assertEquals(ev.attempts[i].feedback, a.feedback, `${c.name}: attempt ${i} feedback`);
    });

    const text = shareText(ev, c.share.puzzleNumber, c.share.streak, c.share.refCode);
    assertEquals(text, c.share.text, `${c.name}: shareText`);
  }
});
