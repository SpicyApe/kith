// Tests for games/generate.ts, the single entry point the nightly generator
// and the admin Reseed use. Written strictly against its contract doc
// comments (docs/07-games-hub.md).

import { assert, assertEquals } from "jsr:@std/assert";
import { gameDifficultyFor, gridSizeFor } from "./common.ts";
import { generateDailyGame, shareRowsFor, validateAnswer } from "./generate.ts";
import { validateDuo } from "./duo.ts";
import { validateStars } from "./stars.ts";
import { validateTrail } from "./trail.ts";

const MONDAY = "2026-09-14"; // easy

// ---------------------------------------------------------------------------
// generateDailyGame
// ---------------------------------------------------------------------------

Deno.test("generateDailyGame - stars on 2026-09-14: non-null, easy, n=7", () => {
  const g = generateDailyGame("stars", MONDAY, 0);
  assert(g !== null);
  assertEquals(g!.game, "stars");
  assertEquals(g!.difficulty, gameDifficultyFor(MONDAY));
  assertEquals(g!.difficulty, "easy");
  assertEquals((g!.spec as { n: number }).n, gridSizeFor("stars", "easy"));
  assertEquals((g!.spec as { n: number }).n, 7);
});

Deno.test("generateDailyGame - duo on 2026-09-14: non-null, easy, n=6", () => {
  const g = generateDailyGame("duo", MONDAY, 0);
  assert(g !== null);
  assertEquals(g!.game, "duo");
  assertEquals(g!.difficulty, "easy");
  assertEquals((g!.spec as { n: number }).n, 6);
});

Deno.test("generateDailyGame - trail on 2026-09-14: non-null, easy, n=5", () => {
  const g = generateDailyGame("trail", MONDAY, 0);
  assert(g !== null);
  assertEquals(g!.game, "trail");
  assertEquals(g!.difficulty, "easy");
  assertEquals((g!.spec as { n: number }).n, gridSizeFor("trail", "easy"));
  assertEquals((g!.spec as { n: number }).n, 5);
});

Deno.test("generateDailyGame - deterministic for the same (game, date, attempt)", () => {
  for (const game of ["stars", "duo", "trail"] as const) {
    const a = generateDailyGame(game, MONDAY, 0);
    const b = generateDailyGame(game, MONDAY, 0);
    assertEquals(a, b);
  }
});

Deno.test("generateDailyGame - each game's solution validates ok against its spec", () => {
  for (const game of ["stars", "duo", "trail"] as const) {
    const g = generateDailyGame(game, MONDAY, 0);
    assert(g !== null, `${game} generation failed`);
    assertEquals(validateAnswer(game, g!.spec, g!.solution), { ok: true });
  }
});

Deno.test("generateDailyGame - each game's seed is a uint32 derived deterministically", () => {
  for (const game of ["stars", "duo", "trail"] as const) {
    const g = generateDailyGame(game, MONDAY, 0);
    assert(g !== null);
    assert(Number.isInteger(g!.seed));
    assert(g!.seed >= 0 && g!.seed <= 0xffffffff);
  }
});

// ---------------------------------------------------------------------------
// validateAnswer - dispatch
// ---------------------------------------------------------------------------

Deno.test("validateAnswer - dispatches to validateStars", () => {
  const g = generateDailyGame("stars", MONDAY, 0);
  assert(g !== null);
  assertEquals(validateAnswer("stars", g!.spec, g!.solution), validateStars(g!.spec as never, g!.solution));
});

Deno.test("validateAnswer - dispatches to validateDuo", () => {
  const g = generateDailyGame("duo", MONDAY, 0);
  assert(g !== null);
  assertEquals(validateAnswer("duo", g!.spec, g!.solution), validateDuo(g!.spec as never, g!.solution));
});

Deno.test("validateAnswer - dispatches to validateTrail", () => {
  const g = generateDailyGame("trail", MONDAY, 0);
  assert(g !== null);
  assertEquals(validateAnswer("trail", g!.spec, g!.solution), validateTrail(g!.spec as never, g!.solution));
});

Deno.test("validateAnswer - unknown game -> shape", () => {
  // deno-lint-ignore no-explicit-any
  const v = validateAnswer("bogus" as any, {}, {});
  assertEquals(v.ok, false);
  assertEquals(v.reason, "shape");
});

// ---------------------------------------------------------------------------
// shareRowsFor - dispatch
// ---------------------------------------------------------------------------

Deno.test("shareRowsFor - dispatches per game and returns rows for each", () => {
  for (const game of ["stars", "duo", "trail"] as const) {
    const g = generateDailyGame(game, MONDAY, 0);
    assert(g !== null);
    const rows = shareRowsFor(game, g!.spec, g!.solution);
    assert(Array.isArray(rows));
    assert(rows.length >= 1);
    for (const row of rows) assertEquals(typeof row, "string");
  }
});

Deno.test("shareRowsFor - trail always returns exactly one row", () => {
  const g = generateDailyGame("trail", MONDAY, 0);
  assert(g !== null);
  const rows = shareRowsFor("trail", g!.spec, g!.solution);
  assertEquals(rows.length, 1);
});

Deno.test("shareRowsFor - stars/duo return one row per grid row", () => {
  const stars = generateDailyGame("stars", MONDAY, 0);
  assert(stars !== null);
  assertEquals(shareRowsFor("stars", stars!.spec, stars!.solution).length, (stars!.spec as { n: number }).n);

  const duo = generateDailyGame("duo", MONDAY, 0);
  assert(duo !== null);
  assertEquals(shareRowsFor("duo", duo!.spec, duo!.solution).length, 6);
});
