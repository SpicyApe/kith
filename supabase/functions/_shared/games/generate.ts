// games/generate.ts — one entry point the nightly generator and the admin Reseed use.
// CONTRACT FILE.

import type { GameKind, GeneratedGame } from "./common.ts";
import { gameDifficultyFor, gameSeedFor, gridSizeFor } from "./common.ts";
import { rng } from "../../generate-puzzles/handler.ts";
import { duoShareRows, generateDuo, validateDuo, type DuoSolution, type DuoSpec } from "./duo.ts";
import { generateStars, starsShareRows, validateStars, type StarsSolution, type StarsSpec } from "./stars.ts";
import { generateTrail, trailShareRows, validateTrail, type TrailSpec } from "./trail.ts";

/**
 * Deterministic per (date, game, attempt): seed = gameSeedFor(date, game, attempt), rng(seed),
 * difficulty = gameDifficultyFor(date), size = gridSizeFor(game, difficulty), then the game's
 * generator. Returns null when the generator gives up (caller may bump `attempt`).
 */
export function generateDailyGame(game: GameKind, date: string, attempt: number): GeneratedGame | null {
  const seed = gameSeedFor(date, game, attempt);
  const rand = rng(seed);
  const difficulty = gameDifficultyFor(date);
  const n = gridSizeFor(game, difficulty);

  const built = game === "stars"
    ? generateStars(n, rand)
    : game === "duo"
    ? generateDuo(rand)
    : game === "trail"
    ? generateTrail(n, rand)
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
    default:
      return { ok: false, reason: "shape" };
  }
}

/** Share rows for a game's solution, dispatching per game. */
export function shareRowsFor(game: GameKind, spec: unknown, solution: unknown): string[] {
  switch (game) {
    case "stars":
      return starsShareRows(spec as StarsSpec, solution as StarsSolution);
    case "duo":
      return duoShareRows(solution as DuoSolution);
    case "trail":
      return trailShareRows(spec as TrailSpec);
    default:
      return [];
  }
}
