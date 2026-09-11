// submit-result — the untrusted boundary for a day's play.
//
// CONTRACT FILE. Pure handler over SubmitStore. Recomputes everything from the raw
// attempt orders via _shared/lineup.ts, clamps elapsed time against the server-
// observed start, enforces one result per date, and returns the streak.
// See docs/02 §1 (scoring, streak) and docs/04 §5 (cheat resistance).

import type { Outcome, RequestContext } from "../_shared/context.ts";
import type { AttemptLog, EvaluatedAttempt } from "../_shared/lineup.ts";
import { asObject, dateWithinWindow, err, isValidTimeZone, requireString } from "../_shared/context.ts";
import { evaluate, LineupError, score } from "../_shared/lineup.ts";

export interface SubmitRequest {
  /** The client's local calendar date for this puzzle, YYYY-MM-DD. */
  puzzleDate: string;
  /** IANA zone the client was in when it played. */
  tz: string;
  /** Raw attempts; `feedback` is ignored if present. */
  attempts: AttemptLog[];
}

export interface StoredResult {
  puzzleDate: string;
  tries: number;
  solved: boolean;
  elapsedMs: number;
  score: number;
  attempts: EvaluatedAttempt[];
  /** "server" when clamped against a start row, "client" when no start row existed. */
  elapsedSource: "server" | "client";
  submittedAt: string; // ISO
}

export interface SubmitResponse {
  result: StoredResult;
  /** Current streak after this result, in the user's tz. */
  streak: number;
}

export interface SubmitStore {
  /** Approved puzzle for the date, or null if none / not approved. */
  getPuzzle(date: string): Promise<{ correctOrder: number[] } | null>;
  /** When this user first revealed this date's puzzle (from `puzzle_starts`), or null. */
  getStart(userId: string, date: string): Promise<Date | null>;
  getResult(userId: string, date: string): Promise<StoredResult | null>;
  /** Insert; throws `SubmitStoreError("duplicate")` if a row already exists for (user, date). */
  insertResult(userId: string, row: Omit<StoredResult, "submittedAt"> & { tz: string; submittedAt: Date }): Promise<void>;
  /** `public.streak(userId)`. */
  streak(userId: string): Promise<number>;
  /** Update users.tz and users.last_open_at. Must tolerate a tz the DB rejects by leaving tz unchanged. */
  touchUser(userId: string, tz: string, now: Date): Promise<void>;
}

export class SubmitStoreError extends Error {
  constructor(public code: "duplicate", message = code) {
    super(message);
    this.name = "SubmitStoreError";
  }
}

/** Network + app-switch allowance subtracted from the server-observed elapsed before comparing. */
export const LATENCY_GRACE_MS = 3_000;
/** Hard ceiling on any stored elapsed value (24 h), matching lineup.evaluate. */
export const MAX_ELAPSED_MS = 86_400_000;

/**
 * Elapsed time to persist. `clientMs` is the last attempt's elapsedMs; `serverMs` is
 * `now - start` or null when no start row exists.
 * - null server → `{ elapsedMs: min(max(clientMs, 0), MAX_ELAPSED_MS), source: "client" }`
 * - else `{ elapsedMs: min(max(clientMs, serverMs - LATENCY_GRACE_MS), MAX_ELAPSED_MS), source: "server" }`
 *   (a client can report *more* time than the server saw, never less than server minus grace).
 * Never returns a negative value.
 */
export function clampElapsed(clientMs: number, serverMs: number | null): { elapsedMs: number; source: "server" | "client" } {
  if (serverMs === null) {
    return { elapsedMs: Math.min(Math.max(clientMs, 0), MAX_ELAPSED_MS), source: "client" };
  }
  const lower = Math.max(clientMs, serverMs - LATENCY_GRACE_MS);
  const elapsedMs = Math.min(Math.max(lower, 0), MAX_ELAPSED_MS);
  return { elapsedMs, source: "server" };
}

/**
 * Behaviour, in order:
 * 1. Body shape: object with string `puzzleDate`, string `tz`, array `attempts` → else 400 `bad_request`.
 * 2. `puzzleDate` within ±14 h of ctx.now (context.dateWithinWindow) → else 400 `bad_date`.
 * 3. `tz` valid → else 400 `bad_tz`.
 * 4. Existing result for (user, date) → 409 `already_played` with `detail` = the existing StoredResult.
 * 5. Puzzle for date → else 404 `no_puzzle`.
 * 6. `evaluate(attempts, correctOrder)`; a LineupError → 422 with `code` = its code and `error` = its message.
 * 7. Elapsed: clampElapsed(ev.elapsedMs, start ? now - start : null); recompute `score` with the clamped value
 *    (lineup.score(tries, solved, clampedMs)).
 * 8. insertResult; a `duplicate` race → 409 `already_played` (re-read the row for `detail`).
 * 9. touchUser(tz, now) and streak = store.streak(userId) are both best-effort: the result is
 *    already committed by this point, so an error from either is logged and swallowed rather than
 *    failing the request (streak defaults to 0 when its call fails).
 * 10. 201 `{ result, streak }`.
 */
export async function handleSubmit(
  body: unknown,
  ctx: RequestContext,
  store: SubmitStore,
): Promise<Outcome<SubmitResponse>> {
  const b = asObject(body);
  const puzzleDate = b === null ? null : requireString(b, "puzzleDate");
  const tz = b === null ? null : requireString(b, "tz");
  const attemptsRaw = b === null ? undefined : b.attempts;
  if (puzzleDate === null || tz === null || !Array.isArray(attemptsRaw)) {
    return err(400, "bad_request", "puzzleDate, tz, attempts are required");
  }
  const attempts = attemptsRaw as AttemptLog[];

  if (!dateWithinWindow(puzzleDate, ctx.now)) {
    return err(400, "bad_date", "puzzleDate is outside the allowed window");
  }
  if (!isValidTimeZone(tz)) {
    return err(400, "bad_tz", "tz must be a valid IANA time zone");
  }

  const existingResult = await store.getResult(ctx.userId, puzzleDate);
  if (existingResult !== null) {
    return err(409, "already_played", "already played this date", existingResult);
  }

  const puzzle = await store.getPuzzle(puzzleDate);
  if (puzzle === null) {
    return err(404, "no_puzzle", "no approved puzzle for this date");
  }

  let ev;
  try {
    ev = evaluate(attempts, puzzle.correctOrder);
  } catch (e) {
    if (e instanceof LineupError) {
      return err(422, e.code, e.message);
    }
    throw e;
  }

  const start = await store.getStart(ctx.userId, puzzleDate);
  const serverMs = start !== null ? ctx.now.getTime() - start.getTime() : null;
  const clamped = clampElapsed(ev.elapsedMs, serverMs);
  const finalScore = score(ev.tries, ev.solved, clamped.elapsedMs);

  const submittedAt = ctx.now;
  const resultToStore: Omit<StoredResult, "submittedAt"> & { tz: string; submittedAt: Date } = {
    puzzleDate,
    tries: ev.tries,
    solved: ev.solved,
    elapsedMs: clamped.elapsedMs,
    score: finalScore,
    attempts: ev.attempts,
    elapsedSource: clamped.source,
    tz,
    submittedAt,
  };

  try {
    await store.insertResult(ctx.userId, resultToStore);
  } catch (e) {
    if (e instanceof SubmitStoreError && e.code === "duplicate") {
      const raced = await store.getResult(ctx.userId, puzzleDate);
      return err(409, "already_played", "already played this date", raced ?? undefined);
    }
    throw e;
  }

  try {
    await store.touchUser(ctx.userId, tz, ctx.now);
  } catch (e) {
    console.error("touch_user_failed", (e as Error).message);
  }
  let streak = 0;
  try {
    streak = await store.streak(ctx.userId);
  } catch (e) {
    console.error("streak_failed", (e as Error).message);
  }

  const result: StoredResult = {
    puzzleDate,
    tries: ev.tries,
    solved: ev.solved,
    elapsedMs: clamped.elapsedMs,
    score: finalScore,
    attempts: ev.attempts,
    elapsedSource: clamped.source,
    submittedAt: submittedAt.toISOString(),
  };

  return { status: 201, body: { result, streak } };
}
