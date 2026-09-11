// lineup.ts — server-side twin of packages/LineupEngine (Swift). Keep in lock-step.
//
// CONTRACT FILE. Implementers fill the function bodies; signatures, types, and the
// documented behaviour are fixed. Pure functions only: no I/O, no Date.now().
// Used by the `submit-result` edge function to recompute a result from the client's
// attempt log, so nothing the client sends is trusted beyond the raw orders.

export type Feedback = "correct" | "near" | "wrong";

/** Wire shape of one attempt, identical to Swift `Attempt`'s JSON. */
export interface AttemptLog {
  order: number[];
  feedback?: Feedback[];
  elapsedMs: number;
}

/** An `AttemptLog` with `feedback` always present — `evaluate()`'s own output shape. */
export type EvaluatedAttempt = AttemptLog & { feedback: Feedback[] };

export interface Evaluation {
  tries: number;
  solved: boolean;
  elapsedMs: number;
  score: number;
  /** Attempts with feedback recomputed server-side (client feedback is ignored). */
  attempts: EvaluatedAttempt[];
}

export const MAX_TRIES = 3;
export const TILE_COUNT = 5;

/** Thrown by `evaluate` for anything malformed. `code` is stable for API responses. */
export class LineupError extends Error {
  constructor(public code: LineupErrorCode, message: string) {
    super(message);
    this.name = "LineupError";
  }
}

export type LineupErrorCode =
  | "bad_correct_order" // not TILE_COUNT unique integers
  | "no_attempts" // empty log, or attempts is not an array
  | "too_many_attempts" // > MAX_TRIES
  | "bad_order" // an attempt's order is not a permutation of correctOrder
  | "bad_elapsed" // negative, non-integer, decreasing, or over 24h across attempts
  | "locked_moved" // a tile that was correct in attempt n is elsewhere in attempt n+1
  | "unchanged_order" // attempt n+1 repeats attempt n's order exactly
  | "played_past_end" // attempts continue after a solved attempt
  | "incomplete_log"; // log ends unsolved with fewer than MAX_TRIES attempts

/**
 * Per-position feedback. Both arrays are item ids top to bottom, same length.
 * `correct` if equal at i; else `near` if the correct index of order[i] is i±1; else `wrong`.
 */
export function feedbackFor(order: number[], correctOrder: number[]): Feedback[] {
  return order.map((id, i) => {
    if (correctOrder[i] === id) return "correct";
    const correctIndex = correctOrder.indexOf(id);
    if (correctIndex === i - 1 || correctIndex === i + 1) return "near";
    return "wrong";
  });
}

/**
 * Base 1000/700/400 for tries 1/2/3 when solved, minus `2 * min(floor(elapsedMs/1000), 120)`.
 * Not solved → 100 flat. `tries` clamped to 1..3, negative elapsed treated as 0.
 */
export function score(tries: number, solved: boolean, elapsedMs: number): number {
  const clampedTries = Math.min(Math.max(Math.trunc(Number(tries)) || 1, 1), 3);
  if (!solved) return 100;
  const clampedElapsedMs = Math.max(elapsedMs, 0);
  const base = [1000, 700, 400][clampedTries - 1];
  const penalty = 2 * Math.min(Math.floor(clampedElapsedMs / 1000), 120);
  return base - penalty;
}

/**
 * Recompute a result from raw attempts. Validates the whole log and throws
 * `LineupError` on any violation, in this precedence: bad_correct_order, no_attempts,
 * too_many_attempts, then per attempt in order: bad_order, bad_elapsed, played_past_end,
 * locked_moved, unchanged_order, then once after the loop: incomplete_log.
 *
 * - Feedback is recomputed with `feedbackFor`; client-provided feedback is discarded.
 * - `solved` is true iff the last attempt is all-correct. If an earlier attempt is
 *   all-correct and more attempts follow → played_past_end.
 * - `elapsedMs` must be a non-negative integer and non-decreasing across attempts.
 * - Positions that were `correct` in attempt n must hold the same id in attempt n+1.
 * - A log that ends unsolved must contain all `MAX_TRIES` attempts → incomplete_log.
 * - `tries` = attempts.length; `elapsedMs` = last attempt's; `score` via `score()`.
 */
export function evaluate(attempts: AttemptLog[], correctOrder: number[]): Evaluation {
  const correctIsValid =
    correctOrder.length === TILE_COUNT &&
    correctOrder.every((n) => Number.isInteger(n)) &&
    new Set(correctOrder).size === TILE_COUNT;
  if (!correctIsValid) {
    throw new LineupError(
      "bad_correct_order",
      `correctOrder must be ${TILE_COUNT} unique integers`,
    );
  }
  const sortedCorrect = [...correctOrder].sort((a, b) => a - b);

  if (!Array.isArray(attempts)) {
    throw new LineupError("no_attempts", "attempts must be an array");
  }
  if (attempts.length === 0) {
    throw new LineupError("no_attempts", "no attempts submitted");
  }
  if (attempts.length > MAX_TRIES) {
    throw new LineupError(
      "too_many_attempts",
      `at most ${MAX_TRIES} attempts allowed`,
    );
  }

  const recomputed: EvaluatedAttempt[] = [];
  let prevOrder: number[] | null = null;
  let prevFeedback: Feedback[] | null = null;
  let prevElapsedMs: number | null = null;
  let prevSolved = false;

  for (let i = 0; i < attempts.length; i++) {
    const attempt = attempts[i];

    if (attempt === null || typeof attempt !== "object" || !Array.isArray(attempt.order)) {
      throw new LineupError("bad_order", `attempt ${i} order is not a permutation of correctOrder`);
    }

    const sortedOrder = [...attempt.order].sort((a, b) => a - b);
    const orderIsValid =
      attempt.order.length === TILE_COUNT &&
      attempt.order.every((n) => Number.isInteger(n)) &&
      sortedOrder.every((n, idx) => n === sortedCorrect[idx]);
    if (!orderIsValid) {
      throw new LineupError(
        "bad_order",
        `attempt ${i} order is not a permutation of correctOrder`,
      );
    }

    const elapsedIsValid =
      Number.isInteger(attempt.elapsedMs) &&
      attempt.elapsedMs >= 0 &&
      attempt.elapsedMs <= 86_400_000 &&
      (prevElapsedMs === null || attempt.elapsedMs >= prevElapsedMs);
    if (!elapsedIsValid) {
      throw new LineupError(
        "bad_elapsed",
        `attempt ${i} elapsedMs must be a non-negative, non-decreasing integer`,
      );
    }

    if (prevSolved) {
      throw new LineupError(
        "played_past_end",
        `attempt ${i} follows an already-solved attempt`,
      );
    }

    const feedback = feedbackFor(attempt.order, correctOrder);

    if (prevOrder !== null && prevFeedback !== null) {
      for (let pos = 0; pos < TILE_COUNT; pos++) {
        if (
          prevFeedback[pos] === "correct" &&
          attempt.order[pos] !== prevOrder[pos]
        ) {
          throw new LineupError(
            "locked_moved",
            `attempt ${i} moved a tile locked at position ${pos}`,
          );
        }
      }
    }

    if (
      prevOrder !== null &&
      prevOrder.length === attempt.order.length &&
      prevOrder.every((id, idx) => id === attempt.order[idx])
    ) {
      throw new LineupError(
        "unchanged_order",
        `attempt ${i} repeats the previous attempt's order`,
      );
    }

    recomputed.push({
      order: attempt.order,
      feedback,
      elapsedMs: attempt.elapsedMs,
    });
    prevOrder = attempt.order;
    prevFeedback = feedback;
    prevElapsedMs = attempt.elapsedMs;
    prevSolved = feedback.every((f) => f === "correct");
  }

  const last = recomputed[recomputed.length - 1];
  const solved = last.feedback.every((f) => f === "correct");
  if (!solved && recomputed.length < MAX_TRIES) {
    throw new LineupError("incomplete_log", "an unsolved log must contain all 3 attempts");
  }
  const tries = recomputed.length;
  const elapsedMs = last.elapsedMs;

  return {
    tries,
    solved,
    elapsedMs,
    score: score(tries, solved, elapsedMs),
    attempts: recomputed,
  };
}

/**
 * Plain-text share block, identical to Swift `ShareText.render`:
 *
 *   Kith #142 · 2/3 · 0:48 🔥12
 *   ⬜🟨🟩⬜🟨
 *   🟩🟩🟩🟩🟩
 *   kith.app/p/142?r=7F3Q
 *
 * tries shows `X` when not solved; time is floor(elapsedMs/1000) as m:ss; ` 🔥<streak>`
 * only when streak >= 1; `?r=` only when refCode is a non-empty string; joined by "\n",
 * no trailing newline. Squares: correct 🟩, near 🟨, wrong ⬜.
 */
export function shareText(
  ev: Evaluation,
  puzzleNumber: number,
  streak: number,
  refCode?: string | null,
): string {
  const triesText = ev.solved ? String(ev.tries) : "X";
  const totalSeconds = Math.floor(Math.max(ev.elapsedMs, 0) / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const time = `${minutes}:${String(seconds).padStart(2, "0")}`;
  const streakSuffix = streak >= 1 ? ` 🔥${streak}` : "";

  const squares: Record<Feedback, string> = {
    correct: "🟩",
    near: "🟨",
    wrong: "⬜",
  };

  const lines = [
    `Kith #${puzzleNumber} · ${triesText}/3 · ${time}${streakSuffix}`,
    ...ev.attempts.map((a) => a.feedback.map((f) => squares[f]).join("")),
  ];

  let link = `kith.app/p/${puzzleNumber}`;
  if (refCode) {
    link += `?r=${refCode}`;
  }
  lines.push(link);

  return lines.join("\n");
}
