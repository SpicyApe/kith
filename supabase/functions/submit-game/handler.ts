// submit-game — the untrusted boundary for the grid games (docs/07-games-hub.md).
//
// CONTRACT FILE. Pure handler over SubmitGameStore. Validates the client's answer
// against the stored spec by the game's rules, clamps elapsed time against
// `game_starts` exactly like submit-result, enforces one result per (date, game).

import type { Outcome, RequestContext } from "../_shared/context.ts";
import type { GameKind } from "../_shared/games/common.ts";
import { asObject, dateWithinWindow, err, isValidTimeZone } from "../_shared/context.ts";
import { GAME_KINDS, scoreFor } from "../_shared/games/common.ts";
import { validateAnswer } from "../_shared/games/generate.ts";
import { quintScore, validateQuint, type QuintSpec } from "../_shared/games/quint.ts";
import { clampElapsed } from "../submit-result/handler.ts";

export interface SubmitGameRequest {
  date: string;        // YYYY-MM-DD, client's local date
  game: GameKind;
  tz: string;
  elapsedMs: number;
  mistakes: number;    // 0..999, informational
  gaveUp: boolean;     // true = solution revealed; answer ignored
  answer?: unknown;    // per game (docs/07 "Wire formats"); required unless gaveUp
}

export interface StoredGameResult {
  date: string;
  game: GameKind;
  elapsedMs: number;
  elapsedSource: "server" | "client";
  mistakes: number;
  solved: boolean;
  gaveUp: boolean;
  score: number;
  submittedAt: string;
}

export interface SubmitGameResponse {
  result: StoredGameResult;
  streak: number;
}

export interface SubmitGameStore {
  /** Approved game for (date, game): spec, solution; null if none. */
  getGame(date: string, game: GameKind): Promise<{ spec: unknown; solution: unknown } | null>;
  getStart(userId: string, date: string, game: GameKind): Promise<Date | null>;
  getResult(userId: string, date: string, game: GameKind): Promise<StoredGameResult | null>;
  /** Insert; throws `SubmitGameStoreError("duplicate")` on an existing (user, date, game). */
  insertResult(userId: string, row: Omit<StoredGameResult, "submittedAt"> & { tz: string; submittedAt: Date }): Promise<void>;
  streak(userId: string): Promise<number>;
  touchUser(userId: string, tz: string, now: Date): Promise<void>;
}

export class SubmitGameStoreError extends Error {
  constructor(public code: "duplicate", message = code) {
    super(message);
    this.name = "SubmitGameStoreError";
  }
}

/**
 * Behaviour, in order:
 * 1. Shape: object with string `date`, `game` in GAME_KINDS, string `tz`, finite non-negative integer
 *    `elapsedMs`, integer `mistakes` 0..999 (clamped, not rejected), boolean `gaveUp` → else 400 `bad_request`.
 * 2. `date` within ±14 h of now → else 400 `bad_date`. 3. `tz` valid → else 400 `bad_tz`.
 * 4. Existing result → 409 `already_played` with `detail` = existing.
 * 5. Game row → else 404 `no_puzzle`.
 * 6. If !gaveUp: for quint, `validateQuint(spec, answer)` — not ok → 422 `wrong_answer` with the
 *    reason as `error`; otherwise solved = verdict.solved and mistakes = verdict.wrongGuesses
 *    (the body's `mistakes` is ignored — quint has no separate "matches stored.solution" check,
 *    since the submitted `{guesses}` shape differs from the stored `{word}` solution and
 *    validateQuint already proves correctness against `spec.answer`). For every other game,
 *    `validateAnswer(game, spec, answer)`; not ok → 422 with code `wrong_answer` and the reason as
 *    `error`. Otherwise (rules pass), the answer must also match `stored.solution` exactly
 *    (`JSON.stringify` equality) → else 422 `wrong_answer` "mismatch". solved = !gaveUp.
 * 7. `store.getStart(...)` → no row → 409 `no_start` "start the game first" (the client must call
 *    `start_game` before submitting). Otherwise elapsed: `clampElapsed(elapsedMs, now − start)`
 *    (import from ../submit-result/handler.ts); score = `scoreFor(clampedMs, gaveUp)`, or for
 *    quint, `quintScore(clampedMs, guesses.length, solved, gaveUp)` (a six-guess fail scores 100
 *    and stores `solved: false, gaveUp: false`, same as any other unsolved quint submission).
 * 8. insertResult; duplicate race → 409 `already_played` (re-read for detail).
 * 9. touchUser and streak, both best-effort (errors logged, streak defaults to 0).
 * 10. 201 `{ result, streak }`.
 */
export async function handleSubmitGame(
  body: unknown,
  ctx: RequestContext,
  store: SubmitGameStore,
): Promise<Outcome<SubmitGameResponse>> {
  const b = asObject(body);
  if (b === null) return err(400, "bad_request", "date, game, tz, elapsedMs, mistakes, gaveUp are required");

  const date = typeof b.date === "string" ? b.date : null;
  const game = GAME_KINDS.includes(b.game as GameKind) ? b.game as GameKind : null;
  const tz = typeof b.tz === "string" ? b.tz : null;
  const elapsedRaw = b.elapsedMs;
  const mistakesRaw = b.mistakes;
  const gaveUp = b.gaveUp;

  if (
    date === null || game === null || tz === null ||
    typeof elapsedRaw !== "number" || !Number.isInteger(elapsedRaw) || elapsedRaw < 0 ||
    typeof mistakesRaw !== "number" || !Number.isFinite(mistakesRaw) ||
    typeof gaveUp !== "boolean"
  ) {
    return err(400, "bad_request", "date, game, tz, elapsedMs, mistakes, gaveUp are required");
  }
  let mistakes = Math.min(999, Math.max(0, Math.floor(mistakesRaw)));

  if (!dateWithinWindow(date, ctx.now)) {
    return err(400, "bad_date", "date is outside the allowed window");
  }
  if (!isValidTimeZone(tz)) {
    return err(400, "bad_tz", "tz must be a valid IANA time zone");
  }

  const existing = await store.getResult(ctx.userId, date, game);
  if (existing !== null) {
    return err(409, "already_played", "already played this game", existing);
  }

  const stored = await store.getGame(date, game);
  if (stored === null) {
    return err(404, "no_puzzle", "no approved game for this date");
  }

  let solved = !gaveUp;
  let quintGuessCount = 0;

  if (!gaveUp) {
    if (game === "quint") {
      const verdict = validateQuint(stored.spec as QuintSpec, b.answer);
      if (!verdict.ok) {
        return err(422, "wrong_answer", verdict.reason ?? "shape");
      }
      solved = verdict.solved ?? false;
      mistakes = verdict.wrongGuesses ?? 0;
      quintGuessCount = (b.answer as { guesses: string[] }).guesses.length;
    } else {
      const verdict = validateAnswer(game, stored.spec, b.answer);
      if (!verdict.ok) {
        return err(422, "wrong_answer", verdict.reason ?? "shape");
      }
      if (JSON.stringify(b.answer) !== JSON.stringify(stored.solution)) {
        return err(422, "wrong_answer", "mismatch");
      }
    }
  }

  const start = await store.getStart(ctx.userId, date, game);
  if (start === null) {
    return err(409, "no_start", "start the game first");
  }
  const serverMs = ctx.now.getTime() - start.getTime();
  const clamped = clampElapsed(elapsedRaw, serverMs);
  const score = game === "quint"
    ? quintScore(clamped.elapsedMs, quintGuessCount, solved, gaveUp)
    : scoreFor(clamped.elapsedMs, gaveUp);

  const submittedAt = ctx.now;
  try {
    await store.insertResult(ctx.userId, {
      date,
      game,
      elapsedMs: clamped.elapsedMs,
      elapsedSource: clamped.source,
      mistakes,
      solved,
      gaveUp,
      score,
      tz,
      submittedAt,
    });
  } catch (e) {
    if (e instanceof SubmitGameStoreError && e.code === "duplicate") {
      const raced = await store.getResult(ctx.userId, date, game);
      return err(409, "already_played", "already played this game", raced ?? undefined);
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

  const result: StoredGameResult = {
    date,
    game,
    elapsedMs: clamped.elapsedMs,
    elapsedSource: clamped.source,
    mistakes,
    solved,
    gaveUp,
    score,
    submittedAt: submittedAt.toISOString(),
  };

  return { status: 201, body: { result, streak } };
}
