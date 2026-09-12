// Tests for games/common.ts, written strictly against its contract doc
// comments (docs/07-games-hub.md). Pure functions only — no store, no I/O.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert";
import { rng } from "../../generate-puzzles/handler.ts";
import {
  gameDifficultyFor,
  gameSeedFor,
  gameShareText,
  GAME_TITLES,
  type GameKind,
  gridSizeFor,
  MAX_PENALTY_SECONDS,
  scoreFor,
  shuffleWith,
} from "./common.ts";

// ---------------------------------------------------------------------------
// gameDifficultyFor
// ---------------------------------------------------------------------------

Deno.test("gameDifficultyFor - Monday 2026-09-14 is easy", () => {
  assertEquals(gameDifficultyFor("2026-09-14"), "easy");
});

Deno.test("gameDifficultyFor - Wednesday 2026-09-16 is medium", () => {
  assertEquals(gameDifficultyFor("2026-09-16"), "medium");
});

Deno.test("gameDifficultyFor - Friday 2026-09-18 is hard", () => {
  assertEquals(gameDifficultyFor("2026-09-18"), "hard");
});

Deno.test("gameDifficultyFor - Saturday 2026-09-19 is medium", () => {
  assertEquals(gameDifficultyFor("2026-09-19"), "medium");
});

// ---------------------------------------------------------------------------
// gridSizeFor
// ---------------------------------------------------------------------------

Deno.test("gridSizeFor - stars: 7 easy, 8 medium, 9 hard", () => {
  assertEquals(gridSizeFor("stars", "easy"), 7);
  assertEquals(gridSizeFor("stars", "medium"), 8);
  assertEquals(gridSizeFor("stars", "hard"), 9);
});

Deno.test("gridSizeFor - trail: 5 easy, 6 medium, 7 hard", () => {
  assertEquals(gridSizeFor("trail", "easy"), 5);
  assertEquals(gridSizeFor("trail", "medium"), 6);
  assertEquals(gridSizeFor("trail", "hard"), 7);
});

Deno.test("gridSizeFor - duo is always 6, regardless of difficulty", () => {
  assertEquals(gridSizeFor("duo", "easy"), 6);
  assertEquals(gridSizeFor("duo", "medium"), 6);
  assertEquals(gridSizeFor("duo", "hard"), 6);
});

// ---------------------------------------------------------------------------
// scoreFor
// ---------------------------------------------------------------------------

Deno.test("scoreFor - 0 ms -> 1000", () => {
  assertEquals(scoreFor(0, false), 1000);
});

Deno.test("scoreFor - 10,000 ms -> 980", () => {
  assertEquals(scoreFor(10_000, false), 980);
});

Deno.test("scoreFor - 450,000 ms (the cap) -> 100", () => {
  assertEquals(scoreFor(450_000, false), 100);
});

Deno.test("scoreFor - 900,000 ms (past the cap) -> 100", () => {
  assertEquals(scoreFor(900_000, false), 100);
});

Deno.test("scoreFor - gaveUp -> 100 even at 0 ms elapsed", () => {
  assertEquals(scoreFor(0, true), 100);
});

Deno.test("scoreFor - negative elapsed is treated as 0 -> 1000", () => {
  assertEquals(scoreFor(-5_000, false), 1000);
});

Deno.test("scoreFor - non-finite elapsed is treated as 0 -> 1000", () => {
  assertEquals(scoreFor(NaN, false), 1000);
  assertEquals(scoreFor(Infinity, false), 1000);
});

Deno.test("MAX_PENALTY_SECONDS is 450 (sanity for the cap fixtures above)", () => {
  assertEquals(MAX_PENALTY_SECONDS, 450);
});

// ---------------------------------------------------------------------------
// gameShareText
// ---------------------------------------------------------------------------

Deno.test("gameShareText - exact block, no refCode, non-empty rows", () => {
  const text = gameShareText("stars", 12, 83_000, false, [
    "⭐️⬛️⬛️⬛️⬛️⬛️⬛️⬛️",
    "⬛️⬛️⬛️⭐️⬛️⬛️⬛️⬛️",
  ]);
  assertEquals(
    text,
    [
      "Kith Stars #12 · 1:23",
      "⭐️⬛️⬛️⬛️⬛️⬛️⬛️⬛️",
      "⬛️⬛️⬛️⭐️⬛️⬛️⬛️⬛️",
      "kith.app/g/stars/12",
    ].join("\n"),
  );
});

Deno.test("gameShareText - refCode present appends ?r=<refCode>", () => {
  const text = gameShareText("stars", 12, 83_000, false, ["row"], "7F3Q");
  assertEquals(
    text,
    ["Kith Stars #12 · 1:23", "row", "kith.app/g/stars/12?r=7F3Q"].join("\n"),
  );
});

Deno.test("gameShareText - refCode null/undefined omits the query string", () => {
  const withNull = gameShareText("duo", 5, 1_000, false, ["row"], null);
  const withUndefined = gameShareText("duo", 5, 1_000, false, ["row"], undefined);
  assertEquals(withNull, ["Kith Duo #5 · 0:01", "row", "kith.app/g/duo/5"].join("\n"));
  assertEquals(withUndefined, withNull);
});

Deno.test("gameShareText - gaveUp shows '· gave up' instead of a time", () => {
  const text = gameShareText("trail", 3, 999_999, true, ["row"]);
  assertEquals(text, ["Kith Trail #3 · gave up", "row", "kith.app/g/trail/3"].join("\n"));
});

Deno.test("gameShareText - empty rows still produce a well-formed block", () => {
  const text = gameShareText("duo", 1, 0, false, []);
  assertEquals(text, ["Kith Duo #1 · 0:00", "kith.app/g/duo/1"].join("\n"));
});

Deno.test("gameShareText - seconds are zero-padded in m:ss", () => {
  const text = gameShareText("duo", 1, 65_000, false, []); // 1:05
  assertEquals(text.split("\n")[0], "Kith Duo #1 · 1:05");
});

Deno.test("gameShareText - time is floor(elapsedMs/1000), not rounded", () => {
  const text = gameShareText("duo", 1, 1_999, false, []); // floor(1.999) = 1s -> 0:01
  assertEquals(text.split("\n")[0], "Kith Duo #1 · 0:01");
});

Deno.test("gameShareText - no trailing newline", () => {
  const text = gameShareText("duo", 1, 0, false, ["a", "b"]);
  assert(!text.endsWith("\n"));
});

Deno.test("gameShareText - uses GAME_TITLES for the display name", () => {
  for (const game of Object.keys(GAME_TITLES) as GameKind[]) {
    const text = gameShareText(game, 1, 0, false, []);
    assert(text.startsWith(`Kith ${GAME_TITLES[game]} #1`));
  }
});

// ---------------------------------------------------------------------------
// gameSeedFor
// ---------------------------------------------------------------------------

Deno.test("gameSeedFor - deterministic for the same date/game/attempt", () => {
  assertEquals(gameSeedFor("2026-09-14", "stars", 0), gameSeedFor("2026-09-14", "stars", 0));
});

Deno.test("gameSeedFor - differs across games for the same date/attempt", () => {
  const a = gameSeedFor("2026-09-14", "stars", 0);
  const b = gameSeedFor("2026-09-14", "duo", 0);
  const c = gameSeedFor("2026-09-14", "trail", 0);
  assertNotEquals(a, b);
  assertNotEquals(b, c);
  assertNotEquals(a, c);
});

Deno.test("gameSeedFor - differs across attempts", () => {
  assertNotEquals(gameSeedFor("2026-09-14", "stars", 0), gameSeedFor("2026-09-14", "stars", 1));
});

Deno.test("gameSeedFor - differs across dates", () => {
  assertNotEquals(gameSeedFor("2026-09-14", "stars", 0), gameSeedFor("2026-09-15", "stars", 0));
});

Deno.test("gameSeedFor - returns a uint32", () => {
  const s = gameSeedFor("2026-09-14", "trail", 3);
  assert(Number.isInteger(s));
  assert(s >= 0 && s <= 0xffffffff);
});

// ---------------------------------------------------------------------------
// shuffleWith
// ---------------------------------------------------------------------------

Deno.test("shuffleWith - returns a permutation of the input (same multiset, same length)", () => {
  const items = [1, 2, 3, 4, 5, 6, 7, 8];
  const shuffled = shuffleWith(items, rng(1));
  assertEquals(shuffled.length, items.length);
  assertEquals([...shuffled].sort((a, b) => a - b), items);
});

Deno.test("shuffleWith - does not mutate the input array", () => {
  const items = [1, 2, 3, 4, 5];
  const copy = [...items];
  shuffleWith(items, rng(1));
  assertEquals(items, copy);
});

Deno.test("shuffleWith - deterministic for the same rng seed", () => {
  const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const a = shuffleWith(items, rng(42));
  const b = shuffleWith(items, rng(42));
  assertEquals(a, b);
});

Deno.test("shuffleWith - different seeds produce different orders (overwhelmingly likely for 10 items)", () => {
  const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const a = shuffleWith(items, rng(42));
  const b = shuffleWith(items, rng(43));
  assertNotEquals(a, b);
});
