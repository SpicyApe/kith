// games/common.ts — shared types, sizing, scoring and share text for the grid games
// (docs/07-games-hub.md). CONTRACT FILE: signatures and doc comments are frozen;
// implementers fill bodies. Pure: no I/O, no Date.now().

import { difficultyFor } from "../../generate-puzzles/handler.ts";

export type GameKind = "stars" | "duo" | "trail" | "quint";
export type Difficulty = "easy" | "medium" | "hard";

export const GAME_KINDS: readonly GameKind[] = ["stars", "duo", "trail", "quint"];

export interface GeneratedGame {
  game: GameKind;
  spec: unknown;
  solution: unknown;
  difficulty: Difficulty;
  seed: number;
}

/** Same weekday rhythm as Lineup: Mon–Tue easy, Wed–Thu medium, Fri hard, Sat–Sun medium (UTC weekday). */
export function gameDifficultyFor(date: string): Difficulty {
  return difficultyFor(date);
}

/** Grid size per game and difficulty: stars 7/8/9, trail 5/6/7, duo always 6. */
export function gridSizeFor(game: GameKind, difficulty: Difficulty): number {
  if (game === "duo") return 6;
  const base = game === "stars" ? 7 : 5;
  const bump = difficulty === "easy" ? 0 : difficulty === "medium" ? 1 : 2;
  return base + bump;
}

/** Time cap for the penalty, in seconds. */
export const MAX_PENALTY_SECONDS = 450;

/**
 * `gaveUp` → 100. Otherwise `max(100, 1000 − 2 × min(floor(elapsedMs / 1000), 450))`.
 * Negative or non-finite elapsed is treated as 0.
 */
export function scoreFor(elapsedMs: number, gaveUp: boolean): number {
  if (gaveUp) return 100;
  const ms = Number.isFinite(elapsedMs) && elapsedMs > 0 ? elapsedMs : 0;
  const seconds = Math.min(Math.floor(ms / 1000), MAX_PENALTY_SECONDS);
  return Math.max(100, 1000 - 2 * seconds);
}

/** Display names used in share text and copy. */
export const GAME_TITLES: Record<GameKind, string> = { stars: "Stars", duo: "Duo", trail: "Trail", quint: "Quint" };

/** Quint's guess cap, mirrored from games/quint.ts (kept here too so common.ts has no import cycle). */
const QUINT_GUESSES = 6;

/**
 * Share block:
 *   Kith <Title> #<number> · <m:ss>          (or `· gave up` instead of the time)
 *   <rows...>                                (one per element of `rows`, may be empty)
 *   kith.app/g/<game>/<number>[?r=<refCode>]
 * Time is floor(elapsedMs/1000) as m:ss (seconds zero-padded). Lines joined with "\n", no trailing newline.
 *
 * Quint is a variant: the header is `Kith Quint #<number> · <progress> · <m:ss>` when solved
 * or `Kith Quint #<number> · <progress> · gave up` when `gaveUp` — `<progress>` is
 * `quintProgress` if supplied, else `<rows.length>/6`. A six-guess fail (not solved, not
 * given up) still shows the time, with progress `X/6`, via the caller passing that in
 * `quintProgress`.
 */
export function gameShareText(game: GameKind, number: number, elapsedMs: number, gaveUp: boolean,
                              rows: string[], refCode?: string | null, quintProgress?: string): string {
  const totalSeconds = Math.floor(Math.max(Number.isFinite(elapsedMs) ? elapsedMs : 0, 0) / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const time = `${minutes}:${String(seconds).padStart(2, "0")}`;

  let suffix: string;
  if (game === "quint") {
    const progress = quintProgress ?? `${rows.length}/${QUINT_GUESSES}`;
    suffix = gaveUp ? `${progress} · gave up` : `${progress} · ${time}`;
  } else if (gaveUp) {
    suffix = "gave up";
  } else {
    suffix = time;
  }

  const lines = [`Kith ${GAME_TITLES[game]} #${number} · ${suffix}`, ...rows];
  let link = `kith.app/g/${game}/${number}`;
  if (refCode) link += `?r=${refCode}`;
  lines.push(link);
  return lines.join("\n");
}

/** Deterministic seed for a game on a date: djb2 of `${date}#${game}#${attempt}` as uint32. */
export function gameSeedFor(date: string, game: GameKind, attempt: number): number {
  const s = `${date}#${game}#${attempt}`;
  let hash = 5381 >>> 0;
  for (let i = 0; i < s.length; i++) {
    hash = (Math.imul(hash, 33) + s.charCodeAt(i)) >>> 0;
  }
  return hash >>> 0;
}

/** Fisher–Yates with the provided rng (returns a copy). */
export function shuffleWith<T>(items: readonly T[], rand: () => number): T[] {
  const a = items.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export interface Validation {
  ok: boolean;
  /** Stable machine reason when not ok: "shape" | "rule:<detail>" */
  reason?: string;
}
