// games/generate.ts — one entry point the nightly generator and the admin Reseed use.
// CONTRACT FILE.

import type { GameKind, GeneratedGame } from "./common.ts";
import { gameDifficultyFor, gameSeedFor, gridSizeFor } from "./common.ts";
import { rng } from "../../generate-puzzles/handler.ts";
import { duoShareRows, generateDuo, validateDuo, type DuoSolution, type DuoSpec } from "./duo.ts";
import { generateQuint, quintShareRows, validateQuint, type QuintSpec } from "./quint.ts";
import { generateStars, starsShareRows, validateStars, type StarsSolution, type StarsSpec } from "./stars.ts";
import { generateTrail, trailShareRows, validateTrail, type TrailSpec } from "./trail.ts";

export interface GenerateDailyGameContext {
  /** Quint only: words used in the previous 365 days, to avoid repeats. */
  recentWords?: Set<string>;
}

/**
 * Deterministic per (date, game, attempt): seed = gameSeedFor(date, game, attempt), rng(seed),
 * difficulty = gameDifficultyFor(date), size = gridSizeFor(game, difficulty), then the game's
 * generator. Returns null when the generator gives up (caller may bump `attempt`).
 *
 * Quint doesn't vary by weekday (a fixed "medium" difficulty, no grid size) and instead needs
 * `context.recentWords` (365-day lookback) to avoid repeating a word; see games/quint.ts.
 */
export function generateDailyGame(
  game: GameKind,
  date: string,
  attempt: number,
  context: GenerateDailyGameContext = {},
): GeneratedGame | null {
  const seed = gameSeedFor(date, game, attempt);
  const rand = rng(seed);
  const difficulty = game === "quint" ? "medium" : gameDifficultyFor(date);

  const built = game === "stars"
    ? generateStars(gridSizeFor(game, difficulty), rand)
    : game === "duo"
    ? generateDuo(rand)
    : game === "trail"
    ? generateTrail(gridSizeFor(game, difficulty), rand)
    : game === "quint"
    ? generateQuint(date, attempt, context.recentWords ?? new Set())
    : null;
  if (built === null) return null;

  return { game, spec: built.spec, solution: built.solution, difficulty, seed };
}

/**
 * Validates a client's answer for a stored game: dispatches to validateStars/Duo/Trail.
 * Unknown game → { ok: false, reason: "shape" }.
 */
export function validateAnswer(game: GameKind, spec: unknown, answer: unknown): { ok: boolean; reason?: string } {
  switch (game) {
    case "stars":
      return validateStars(spec as StarsSpec, answer);
    case "duo":
      return validateDuo(spec as DuoSpec, answer);
    case "trail":
      return validateTrail(spec as TrailSpec, answer);
    case "quint": {
      const v = validateQuint(spec as QuintSpec, answer);
      return { ok: v.ok, reason: v.reason };
    }
    default:
      return { ok: false, reason: "shape" };
  }
}

/**
 * Share rows for a game's solution, dispatching per game. For quint, `solution` is the
 * played answer's wire shape `{ guesses: string[] }` (not the puzzle's `{ word }` solution) —
 * share rows reflect what was actually guessed, one row per guess.
 */
export function shareRowsFor(game: GameKind, spec: unknown, solution: unknown): string[] {
  switch (game) {
    case "stars":
      return starsShareRows(spec as StarsSpec, solution as StarsSolution);
    case "duo":
      return duoShareRows(solution as DuoSolution);
    case "trail":
      return trailShareRows(spec as TrailSpec);
    case "quint":
      return quintShareRows(spec as QuintSpec, (solution as { guesses?: string[] } | null)?.guesses ?? []);
    default:
      return [];
  }
}
