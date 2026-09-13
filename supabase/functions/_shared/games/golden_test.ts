// golden_test.ts — shared golden vectors for the grid games, mirrored with
// packages/GridGames/Tests/GridGamesTests/GoldenVectorTests.swift (same
// fixture file). Verifies that the TS side's validateAnswer, shareRowsFor and
// gameShareText agree with the fixture's wire formats and expected output —
// the same guarantee lineup_test.ts's "golden vectors" test gives Lineup.

import { assert, assertEquals } from "jsr:@std/assert";
import type { GameKind } from "./common.ts";
import { gameShareText } from "./common.ts";
import { shareRowsFor, validateAnswer } from "./generate.ts";

interface GoldenCase {
  game: GameKind;
  spec: unknown;
  answer: unknown;
  shareRows: string[];
  number: number;
  elapsedMs: number;
  gaveUp: boolean;
  refCode: string | null;
  quintProgress?: string;
  shareText: string;
}

/** Wraps a golden case's raw `answer` in the wire-format envelope validateAnswer expects. */
function wrapAnswer(game: GameKind, answer: unknown): unknown {
  switch (game) {
    case "stars":
      return { stars: answer };
    case "duo":
      return { cells: answer };
    case "trail":
      return { path: answer };
    case "quint":
      // Already in wire-format shape ({ guesses: [...] }) in the fixture.
      return answer;
  }
}

/**
 * Builds the `solution` shape shareRowsFor expects, from the case's raw
 * answer. Trail's shareRowsFor only reads the spec (waypoints), not the
 * solution, so any value is fine there.
 */
function solutionFor(game: GameKind, answer: unknown): unknown {
  switch (game) {
    case "stars":
      return { stars: answer };
    case "duo":
      return { cells: answer };
    case "trail":
      return null;
    case "quint":
      // shareRowsFor's quint case reads `{ guesses }` from the played answer, not the
      // puzzle's `{ word }` solution.
      return answer;
  }
}

Deno.test("golden vectors: validateAnswer, shareRowsFor and gameShareText agree with the shared fixture", async () => {
  const url = new URL(
    "../../../../packages/GridGames/Tests/GridGamesTests/Fixtures/golden.json",
    import.meta.url,
  );
  const raw = await Deno.readTextFile(url);
  const cases = JSON.parse(raw) as GoldenCase[];

  if (cases.length < 6) {
    throw new Error(`expected at least 6 golden cases, got ${cases.length}`);
  }
  const quintCases = cases.filter((c) => c.game === "quint");
  if (quintCases.length < 3) {
    throw new Error(`expected at least 3 quint golden cases (solved, fail, give-up), got ${quintCases.length}`);
  }

  for (const c of cases) {
    const verdict = validateAnswer(c.game, c.spec, wrapAnswer(c.game, c.answer));
    assert(verdict.ok, `${c.game} #${c.number}: validateAnswer should accept the golden answer, got ${JSON.stringify(verdict)}`);

    const rows = shareRowsFor(c.game, c.spec, solutionFor(c.game, c.answer));
    assertEquals(rows, c.shareRows, `${c.game} #${c.number}: shareRowsFor mismatch`);

    const text = gameShareText(c.game, c.number, c.elapsedMs, c.gaveUp, rows, c.refCode, c.quintProgress);
    assertEquals(text, c.shareText, `${c.game} #${c.number}: gameShareText mismatch`);
  }
});
