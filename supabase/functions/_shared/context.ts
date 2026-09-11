// context.ts — types shared by every edge-function handler.
//
// Handlers are pure: (request body, RequestContext, Store) → Outcome. All I/O goes
// through a Store interface so tests use in-memory fakes and index.ts wires the
// real Supabase client. Handlers never read env vars or the clock directly.

export interface RequestContext {
  /** auth.uid() of the caller, already verified by index.ts from the JWT. */
  userId: string;
  /** Verified phone from the auth provider, digits with or without a leading '+'. Only `register` needs it. */
  phone?: string;
  /** Server clock. */
  now: Date;
}

export interface ErrorBody {
  error: string;
  /** Stable machine code, e.g. "bad_request", "already_played", "bad_order". */
  code: string;
  /** Optional structured detail (for 409 already_played this carries the existing result). */
  detail?: unknown;
}

export type Outcome<T> =
  | { status: 200 | 201; body: T }
  | { status: 400 | 403 | 404 | 409 | 422 | 429; body: ErrorBody };

export function err(
  status: 400 | 403 | 404 | 409 | 422 | 429,
  code: string,
  error: string,
  detail?: unknown,
): Outcome<never> {
  return { status, body: detail === undefined ? { error, code } : { error, code, detail } };
}

/** `body` narrowed to a plain object, or null when it isn't one (including `null` itself). */
export function asObject(body: unknown): Record<string, unknown> | null {
  return typeof body === "object" && body !== null ? body as Record<string, unknown> : null;
}

/** `o[k]` when it is a string, else null. */
export function requireString(o: Record<string, unknown>, k: string): string | null {
  return typeof o[k] === "string" ? o[k] as string : null;
}

/** `YYYY-MM-DD` strict shape check (not a calendar validity check). */
export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** True when `date` (a calendar date) is within ±14 h of `now`, the same rule as the puzzles RLS policy. */
export function dateWithinWindow(date: string, now: Date): boolean {
  if (!DATE_RE.test(date)) return false;
  const lo = new Date(now.getTime() - 14 * 3600_000).toISOString().slice(0, 10);
  const hi = new Date(now.getTime() + 14 * 3600_000).toISOString().slice(0, 10);
  return date >= lo && date <= hi;
}

/** True when `tz` is an IANA zone the runtime knows. */
export function isValidTimeZone(tz: string): boolean {
  if (typeof tz !== "string" || tz.length === 0 || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}
