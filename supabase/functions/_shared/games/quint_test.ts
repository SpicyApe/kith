// Tests for games/quint.ts, written strictly against its contract doc comments
// (docs/07-games-hub.md §"Quint").

import { assert, assertEquals } from "jsr:@std/assert";
import { ALLOWED, ANSWERS } from "./words.ts";
import { gameSeedFor } from "./common.ts";
import { rng } from "../../generate-puzzles/handler.ts";
import {
  generateQuint,
  markGuess,
  quintScore,
  quintShareRows,
  type QuintSpec,
  validateQuint,
} from "./quint.ts";

const SPEC: QuintSpec = { n: 5, guesses: 6, answer: "crane" };

// ---------------------------------------------------------------------------
// markGuess — duplicate-letter handling
// ---------------------------------------------------------------------------

Deno.test("markGuess - all hits when guess equals answer", () => {
  assertEquals(markGuess("crane", "crane"), ["hit", "hit", "hit", "hit", "hit"]);
});

Deno.test("markGuess - all miss when no letters overlap", () => {
  assertEquals(markGuess("bulky", "trend"), ["miss", "miss", "miss", "miss", "miss"]);
});

Deno.test("markGuess - 'eerie' vs 'there': hits first, then nears while copies remain", () => {
  // answer "there" = t,h,e,r,e. guess "eerie" = e,e,r,i,e.
  // idx4 hits (e==e). Remaining unaccounted answer letters (idx0..3): t,h,e,r.
  // Near pass left-to-right over the rest: idx0 'e' consumes the one remaining
  // 'e' -> near; idx1 'e' has no 'e' left -> miss; idx2 'r' consumes the
  // remaining 'r' -> near; idx3 'i' -> miss.
  assertEquals(markGuess("eerie", "there"), ["near", "miss", "near", "miss", "hit"]);
});

Deno.test("markGuess - 'allee' vs 'eagle': hits first, then nears while copies remain", () => {
  // answer "eagle" = e,a,g,l,e. guess "allee" = a,l,l,e,e.
  // idx4 hits (e==e). Remaining unaccounted answer letters (idx0..3): e,a,g,l.
  // Near pass left-to-right: idx0 'a' -> near (consumes the 'a'); idx1 'l' ->
  // near (consumes the 'l'); idx2 'l' -> miss (no 'l' left); idx3 'e' -> near
  // (consumes the remaining 'e').
  assertEquals(markGuess("allee", "eagle"), ["near", "near", "miss", "near", "hit"]);
});

Deno.test("markGuess - extra duplicate copies beyond the answer's count are miss, not near", () => {
  // answer "abbbb" has exactly one 'a' (hit at index 0); guess "aaaaa" has four
  // more 'a's than the answer has anywhere, none of which can be near.
  assertEquals(markGuess("aaaaa", "abbbb"), ["hit", "miss", "miss", "miss", "miss"]);
});

// ---------------------------------------------------------------------------
// validateQuint
// ---------------------------------------------------------------------------

Deno.test("validateQuint - shape: not an object -> shape", () => {
  assertEquals(validateQuint(SPEC, null), { ok: false, reason: "shape" });
  assertEquals(validateQuint(SPEC, "nope"), { ok: false, reason: "shape" });
});

Deno.test("validateQuint - shape: guesses missing or empty -> shape", () => {
  assertEquals(validateQuint(SPEC, {}), { ok: false, reason: "shape" });
  assertEquals(validateQuint(SPEC, { guesses: [] }), { ok: false, reason: "shape" });
});

Deno.test("validateQuint - shape: wrong length or case -> shape", () => {
  assertEquals(validateQuint(SPEC, { guesses: ["crn"] }), { ok: false, reason: "shape" });
  assertEquals(validateQuint(SPEC, { guesses: ["CRANE"] }), { ok: false, reason: "shape" });
  assertEquals(validateQuint(SPEC, { guesses: [123] }), { ok: false, reason: "shape" });
});

Deno.test("validateQuint - too_many: more than 6 guesses", () => {
  const guesses = ["slate", "slate", "slate", "slate", "slate", "slate", "slate"];
  assertEquals(validateQuint(SPEC, { guesses }), { ok: false, reason: "too_many" });
});

Deno.test("validateQuint - not_a_word: a guess outside ALLOWED", () => {
  assertEquals(validateQuint(SPEC, { guesses: ["zzzzz"] }), { ok: false, reason: "not_a_word" });
});

Deno.test("validateQuint - after_solved: a guess submitted after the solving one", () => {
  assertEquals(validateQuint(SPEC, { guesses: ["crane", "slate"] }), { ok: false, reason: "after_solved" });
});

Deno.test("validateQuint - solved on the first guess: wrongGuesses 0", () => {
  assertEquals(validateQuint(SPEC, { guesses: ["crane"] }), { ok: true, solved: true, wrongGuesses: 0 });
});

Deno.test("validateQuint - solved on the third guess: wrongGuesses 2", () => {
  assertEquals(
    validateQuint(SPEC, { guesses: ["slate", "grape", "crane"] }),
    { ok: true, solved: true, wrongGuesses: 2 },
  );
});

Deno.test("validateQuint - a valid non-solving six-guess sequence: ok true, solved false, wrongGuesses 6", () => {
  const guesses = ["slate", "grape", "chase", "brine", "prone", "shale"];
  for (const g of guesses) assert(ALLOWED.has(g), `${g} must be a real word for this test to be meaningful`);
  assertEquals(validateQuint(SPEC, { guesses }), { ok: true, solved: false, wrongGuesses: 6 });
});

Deno.test("validateQuint - a valid unsolved partial sequence (< 6 guesses): ok true, solved false", () => {
  const guesses = ["slate", "grape"];
  assertEquals(validateQuint(SPEC, { guesses }), { ok: true, solved: false, wrongGuesses: 2 });
});

// ---------------------------------------------------------------------------
// generateQuint
// ---------------------------------------------------------------------------

const DATE = "2026-09-14";

Deno.test("generateQuint - deterministic for the same (date, attempt, recentWords)", () => {
  const a = generateQuint(DATE, 0, new Set());
  const b = generateQuint(DATE, 0, new Set());
  assertEquals(a, b);
});

Deno.test("generateQuint - picks a word from ANSWERS, spec shape is n:5, guesses:6", () => {
  const g = generateQuint(DATE, 0, new Set());
  assertEquals(g.spec.n, 5);
  assertEquals(g.spec.guesses, 6);
  assert(ANSWERS.includes(g.spec.answer));
  assertEquals(g.solution, { word: g.spec.answer });
});

Deno.test("generateQuint - skips a recent word, stepping forward deterministically", () => {
  const fresh = generateQuint(DATE, 0, new Set());
  const withoutThatWord = generateQuint(DATE, 0, new Set([fresh.spec.answer]));
  assert(withoutThatWord.spec.answer !== fresh.spec.answer);

  // Stepping forward one word at a time (wrapping) from the same start index.
  const seed = gameSeedFor(DATE, "quint", 0);
  const start = Math.floor(rng(seed)() * ANSWERS.length) % ANSWERS.length;
  assertEquals(ANSWERS[start], fresh.spec.answer);
  assertEquals(ANSWERS[(start + 1) % ANSWERS.length], withoutThatWord.spec.answer);
});

Deno.test("generateQuint - wraps around from the last index back to the first", () => {
  // For this (date, attempt), the rng-derived start index lands on ANSWERS' last
  // element; excluding it as recent must step forward with wraparound to index 0.
  const g = generateQuint("2031-08-18", 0, new Set([ANSWERS.at(-1)!]));
  assertEquals(g.spec.answer, ANSWERS[0]);
});

Deno.test("generateQuint - falls back to the start candidate when every word is recent", () => {
  const seed = gameSeedFor(DATE, "quint", 0);
  const start = Math.floor(rng(seed)() * ANSWERS.length) % ANSWERS.length;
  const g = generateQuint(DATE, 0, new Set(ANSWERS));
  assertEquals(g.spec.answer, ANSWERS[start]);
});

Deno.test("generateQuint - different attempts can produce different words", () => {
  const results = new Set<string>();
  for (let attempt = 0; attempt < 5; attempt++) {
    results.add(generateQuint(DATE, attempt, new Set()).spec.answer);
  }
  assert(results.size > 1, "expected at least some variation across attempts");
});

// ---------------------------------------------------------------------------
// quintShareRows
// ---------------------------------------------------------------------------

Deno.test("quintShareRows - one row per guess, hit/near/miss mapped to emoji", () => {
  const rows = quintShareRows(SPEC, ["slate", "crane"]);
  assertEquals(rows, ["⬛️⬛️🟩⬛️🟩", "🟩🟩🟩🟩🟩"]);
});

Deno.test("quintShareRows - empty guesses -> empty rows", () => {
  assertEquals(quintShareRows(SPEC, []), []);
});

// ---------------------------------------------------------------------------
// quintScore
// ---------------------------------------------------------------------------

Deno.test("quintScore - table for 1..6 guesses at zero elapsed time", () => {
  const expected = [1000, 900, 800, 700, 600, 500];
  for (let guesses = 1; guesses <= 6; guesses++) {
    assertEquals(quintScore(0, guesses, true, false), expected[guesses - 1]);
  }
});

Deno.test("quintScore - elapsed time subtracts seconds, capped at 300", () => {
  assertEquals(quintScore(30_000, 1, true, false), 970); // 1000 - 30
  assertEquals(quintScore(600_000, 1, true, false), 700); // capped at 300s -> 1000-300
});

Deno.test("quintScore - never below 100 even for six guesses plus a long time", () => {
  assertEquals(quintScore(600_000, 6, true, false), 200); // 500 - 300 = 200
});

Deno.test("quintScore - a fail (solved:false) always scores 100, regardless of elapsed/guesses", () => {
  assertEquals(quintScore(1_000, 6, false, false), 100);
  assertEquals(quintScore(0, 1, false, false), 100);
});

Deno.test("quintScore - give-up always scores 100, regardless of solved/elapsed/guesses", () => {
  assertEquals(quintScore(1_000, 3, true, true), 100);
  assertEquals(quintScore(0, 1, false, true), 100);
});
