// games/quint.ts — Quint (Wordle-style): one hidden five-letter word, six guesses,
// hit/near/miss marks with standard duplicate handling (docs/07-games-hub.md §"Quint").
// CONTRACT FILE: signatures and doc comments are frozen; implementers fill bodies.
// Pure: no I/O, no Date.now().

import { ALLOWED, ANSWERS } from "./words.ts";
import { gameSeedFor } from "./common.ts";
import { rng } from "../../generate-puzzles/handler.ts";

export const QUINT_GUESSES = 6;
export const QUINT_LETTERS = 5;
/** Time cap for the scoring penalty, in seconds (docs/07 §"Quint" scoring). */
export const QUINT_MAX_PENALTY_SECONDS = 300;

export interface QuintSpec {
  n: 5;
  guesses: 6;
  /** The word is embedded in the spec (docs/07 "Wire formats") for offline play. Lowercase. */
  answer: string;
}

/** Client submits `{ guesses: [...] }` (docs/07 "Wire formats"), lowercase, 1..6 entries. */
export interface QuintAnswer {
  guesses: string[];
}

export type Mark = "hit" | "near" | "miss";

export interface QuintValidation {
  ok: boolean;
  /** "shape" | "not_a_word" | "too_many" | "after_solved" when !ok. */
  reason?: "shape" | "not_a_word" | "too_many" | "after_solved";
  /** Present when ok: true iff the last guess equals the word. */
  solved?: boolean;
  /** Present when ok: wrong guesses (solved ? index of the solving guess : guesses.length). */
  wrongGuesses?: number;
}

/**
 * Marks each letter of `guess` against `answer` (same length, lowercase): hit when the
 * letter is in the right place; otherwise near/miss with the standard duplicate-letter
 * handling — hits are resolved first, then remaining guess letters are checked left to
 * right against whatever copies of that letter are still unaccounted for in `answer`.
 */
export function markGuess(guess: string, answer: string): Mark[] {
  const n = answer.length;
  const marks: Mark[] = new Array(n).fill("miss");
  const remaining = new Map<string, number>();

  for (let i = 0; i < n; i++) {
    if (guess[i] === answer[i]) {
      marks[i] = "hit";
    } else {
      const c = answer[i];
      remaining.set(c, (remaining.get(c) ?? 0) + 1);
    }
  }
  for (let i = 0; i < n; i++) {
    if (marks[i] === "hit") continue;
    const c = guess[i];
    const left = remaining.get(c) ?? 0;
    if (left > 0) {
      marks[i] = "near";
      remaining.set(c, left - 1);
    }
  }
  return marks;
}

/**
 * Shape: `answer` is `{ guesses: string[] }`, 1..spec.guesses entries, each a lowercase
 * string of length spec.n → else `{ok:false, reason:"shape"}`.
 * More than spec.guesses entries → `{ok:false, reason:"too_many"}`.
 * Any guess after the one that already equals spec.answer → `{ok:false, reason:"after_solved"}`.
 * Any guess not in ALLOWED → `{ok:false, reason:"not_a_word"}`.
 * Otherwise ok: true, solved = last relevant guess equals the word, wrongGuesses = the
 * index of the solving guess when solved, else guesses.length.
 */
export function validateQuint(spec: QuintSpec, answer: unknown): QuintValidation {
  const a = answer as { guesses?: unknown } | null;
  if (typeof a !== "object" || a === null) return { ok: false, reason: "shape" };
  const guesses = a.guesses;
  if (!Array.isArray(guesses) || guesses.length < 1) return { ok: false, reason: "shape" };
  if (guesses.length > spec.guesses) return { ok: false, reason: "too_many" };
  for (const g of guesses) {
    if (typeof g !== "string" || g.length !== spec.n || g !== g.toLowerCase()) {
      return { ok: false, reason: "shape" };
    }
  }

  const word = spec.answer.toLowerCase();
  let solvedAt = -1;
  for (let i = 0; i < guesses.length; i++) {
    if (solvedAt !== -1) return { ok: false, reason: "after_solved" };
    const g = guesses[i] as string;
    if (!ALLOWED.has(g)) return { ok: false, reason: "not_a_word" };
    if (g === word) solvedAt = i;
  }

  const solved = solvedAt !== -1;
  const wrongGuesses = solved ? solvedAt : guesses.length;
  return { ok: true, solved, wrongGuesses };
}

/**
 * Picks `ANSWERS[start % ANSWERS.length]` where `start` is derived from
 * `rng(gameSeedFor(date, "quint", attempt))`, stepping forward one word at a time
 * (wrapping) until one is not in `recentWords` (used in the previous 365 days).
 * Deterministic for the same (date, attempt); falls back to the first candidate if
 * every word in ANSWERS is somehow recent.
 */
export function generateQuint(
  date: string,
  attempt: number,
  recentWords: Set<string>,
): { spec: QuintSpec; solution: { word: string } } {
  const seed = gameSeedFor(date, "quint", attempt);
  const rand = rng(seed);
  const start = Math.floor(rand() * ANSWERS.length) % ANSWERS.length;

  let idx = start;
  for (let i = 0; i < ANSWERS.length; i++) {
    const word = ANSWERS[idx];
    if (!recentWords.has(word)) {
      return { spec: { n: QUINT_LETTERS, guesses: QUINT_GUESSES, answer: word }, solution: { word } };
    }
    idx = (idx + 1) % ANSWERS.length;
  }
  const word = ANSWERS[start];
  return { spec: { n: QUINT_LETTERS, guesses: QUINT_GUESSES, answer: word }, solution: { word } };
}

/** One row per guess: ⬛️ miss, 🟨 near, 🟩 hit. */
export function quintShareRows(spec: QuintSpec, guesses: string[]): string[] {
  const word = spec.answer.toLowerCase();
  return guesses.map((g) =>
    markGuess(g.toLowerCase(), word).map((m) => (m === "hit" ? "🟩" : m === "near" ? "🟨" : "⬛️")).join("")
  );
}

/**
 * `score = max(100, 1000 − 100 × (guesses − 1) − min(elapsed_seconds, 300))`, so one
 * guess is 1000 before time, six guesses 500. A fail (`!solved`) or give-up scores 100.
 */
export function quintScore(elapsedMs: number, guesses: number, solved: boolean, gaveUp: boolean): number {
  if (gaveUp || !solved) return 100;
  const ms = Number.isFinite(elapsedMs) && elapsedMs > 0 ? elapsedMs : 0;
  const seconds = Math.min(Math.floor(ms / 1000), QUINT_MAX_PENALTY_SECONDS);
  const g = Math.max(1, Math.floor(guesses));
  return Math.max(100, 1000 - 100 * (g - 1) - seconds);
}
