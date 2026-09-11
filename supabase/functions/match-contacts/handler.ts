// match-contacts — the only code path that touches contact hashes.
//
// CONTRACT FILE. Pure handler over MatchStore. The pepper never leaves this
// function; the plain client hashes never reach the store. See docs/04 §3.

import type { Outcome, RequestContext } from "../_shared/context.ts";
import { asObject, err } from "../_shared/context.ts";
import { hmacSha256Hex, isSha256Hex } from "../_shared/hashing.ts";

export interface MatchRequest {
  /** sha256hex(E.164) values to add (or, when `full`, the complete set). */
  added: string[];
  /** sha256hex values to remove. Ignored when `full` is true. */
  removed?: string[];
  /** True = replace the caller's whole stored set with `added`. */
  full?: boolean;
}

export interface MatchedContact {
  userId: string;
  displayName: string;
  /** The client's own sha256hex that matched, echoed so the client can render the local contact name. */
  hash: string;
}

export interface MatchResponse {
  /** Mutual matches among the hashes sent in THIS request (added, or the full set). */
  matches: MatchedContact[];
  /** Every mutual friend after recompute, so the client can prune stale entries. */
  friends: { userId: string; displayName: string }[];
  /** Number of contact hashes now stored for the caller. */
  stored: number;
}

export interface MatchStore {
  /** Caller's `discoverable` flag; null if the user row is missing (not registered). */
  getDiscoverable(userId: string): Promise<boolean | null>;
  /** Count of requests, full syncs, and total hashes uploaded by this user since `since`. */
  syncUsage(userId: string, since: Date): Promise<{ fullSyncs: number; hashes: number; requests: number }>;
  logSync(userId: string, at: Date, hashes: number, full: boolean): Promise<void>;
  /** Replace the caller's whole set. */
  replaceContactHmacs(userId: string, hmacs: string[]): Promise<void>;
  upsertContactHmacs(userId: string, hmacs: string[]): Promise<void>;
  deleteContactHmacs(userId: string, hmacs: string[]): Promise<void>;
  countContactHmacs(userId: string): Promise<number>;
  /** `public.recompute_matches(userId)`: rebuilds every `matches` row involving the user. */
  recomputeMatches(userId: string): Promise<void>;
  /** All mutual friends of the user with their `phone_hmac`, so the handler can map back to the request's hashes. */
  mutualFriends(userId: string): Promise<{ userId: string; displayName: string; phoneHmac: string }[]>;
}

export const MAX_HASHES_PER_REQUEST = 5_000;
export const MAX_HASHES_PER_DAY = 20_000;
export const MAX_FULL_SYNCS_PER_HOUR = 1;
/** Caps total requests (of any kind) per user per hour, independent of how many hashes each carries. */
export const MAX_SYNCS_PER_HOUR = 12;

/**
 * Behaviour, in order:
 * 1. Body shape: `added` array (may be empty), optional `removed` array, optional boolean `full`.
 *    `added.length + removed.length > MAX_HASHES_PER_REQUEST` → 400 `too_many` (checked before any
 *    per-element validation). Every element must then satisfy hashing.isSha256Hex → else 400 `bad_request`.
 * 2. Not registered (getDiscoverable null) → 403 `not_registered`.
 *    Discoverable false → 403 `not_discoverable` (a user who opted out cannot match; their hashes were deleted).
 * 3. Dedupe `added`/`removed`. A non-full request whose deduped `added` + `removed` count is zero
 *    short-circuits here, before any rate-limit call: 200 `{ matches: [], friends: mutualFriends(userId)
 *    (without phoneHmac), stored: countContactHmacs(userId) }`. Neither logSync nor recomputeMatches runs.
 * 4. Rate limits via syncUsage, called exactly twice — once with `since = now - 1h`, once with
 *    `since = now - 24h` — in this order:
 *    a. the 1h call's `requests` ≥ MAX_SYNCS_PER_HOUR → 429 `rate_limited`.
 *    b. when `full`: the 1h call's `fullSyncs` ≥ MAX_FULL_SYNCS_PER_HOUR → 429 `rate_limited`.
 *    c. the 24h call's `hashes` + this request's deduped count > MAX_HASHES_PER_DAY → 429 `rate_limited`.
 * 5. hmac each deduped hash with hmacSha256Hex(pepper, h); keep a map hmac → h for `added`.
 * 6. full ? replaceContactHmacs(added) : (upsert added; delete removed).
 * 7. logSync; recomputeMatches(userId).
 * 8. friends = mutualFriends(userId). matches = friends whose phoneHmac is in this request's map, with `hash` = the mapped client hash.
 * 9. 200 `{ matches, friends (without phoneHmac), stored: countContactHmacs }`.
 * Empty pepper → throw (misconfiguration).
 */
export async function handleMatch(
  body: unknown,
  ctx: RequestContext,
  store: MatchStore,
  pepper: string,
): Promise<Outcome<MatchResponse>> {
  if (!pepper) throw new Error("empty pepper");

  const b = asObject(body);
  if (b === null) {
    return err(400, "bad_request", "body must be an object");
  }
  if (!Array.isArray(b.added)) {
    return err(400, "bad_request", "added must be an array");
  }
  const removedRaw = b.removed === undefined ? [] : b.removed;
  if (!Array.isArray(removedRaw)) {
    return err(400, "bad_request", "removed must be an array");
  }
  if (b.full !== undefined && typeof b.full !== "boolean") {
    return err(400, "bad_request", "full must be a boolean");
  }
  const full = b.full === true;

  const added = b.added as unknown[];
  const removed = removedRaw as unknown[];
  if (added.length + removed.length > MAX_HASHES_PER_REQUEST) {
    return err(400, "too_many", "too many hashes in one request");
  }
  for (const h of added) {
    if (!isSha256Hex(h)) return err(400, "bad_request", "added must contain sha256 hex strings");
  }
  for (const h of removed) {
    if (!isSha256Hex(h)) return err(400, "bad_request", "removed must contain sha256 hex strings");
  }

  const discoverable = await store.getDiscoverable(ctx.userId);
  if (discoverable === null) {
    return err(403, "not_registered", "user is not registered");
  }
  if (discoverable === false) {
    return err(403, "not_discoverable", "user has opted out of discovery");
  }

  const dedupedAdded = [...new Set(added as string[])];
  const dedupedRemoved = full ? [] : [...new Set(removed as string[])];
  const requestHashCount = dedupedAdded.length + dedupedRemoved.length;

  // Nothing to sync and nothing to remove: skip logSync/recomputeMatches and every
  // rate-limit call, and just hand back the caller's current state.
  if (!full && requestHashCount === 0) {
    const currentFriends = await store.mutualFriends(ctx.userId);
    const friends = currentFriends.map((f) => ({ userId: f.userId, displayName: f.displayName }));
    const stored = await store.countContactHmacs(ctx.userId);
    return { status: 200, body: { matches: [], friends, stored } };
  }

  const hourAgo = new Date(ctx.now.getTime() - 3600_000);
  const dayAgo = new Date(ctx.now.getTime() - 24 * 3600_000);

  const hourUsage = await store.syncUsage(ctx.userId, hourAgo);
  if (hourUsage.requests >= MAX_SYNCS_PER_HOUR) {
    return err(429, "rate_limited", "too many sync requests");
  }
  if (full && hourUsage.fullSyncs >= MAX_FULL_SYNCS_PER_HOUR) {
    return err(429, "rate_limited", "too many full syncs");
  }
  const dayUsage = await store.syncUsage(ctx.userId, dayAgo);
  if (dayUsage.hashes + requestHashCount > MAX_HASHES_PER_DAY) {
    return err(429, "rate_limited", "too many hashes uploaded today");
  }

  const hmacToHash = new Map<string, string>();
  const addedHmacs: string[] = [];
  for (const h of dedupedAdded) {
    const hmac = await hmacSha256Hex(pepper, h);
    hmacToHash.set(hmac, h);
    addedHmacs.push(hmac);
  }
  const removedHmacs: string[] = [];
  for (const h of dedupedRemoved) {
    removedHmacs.push(await hmacSha256Hex(pepper, h));
  }

  if (full) {
    await store.replaceContactHmacs(ctx.userId, addedHmacs);
  } else {
    if (addedHmacs.length > 0) await store.upsertContactHmacs(ctx.userId, addedHmacs);
    if (removedHmacs.length > 0) await store.deleteContactHmacs(ctx.userId, removedHmacs);
  }

  await store.logSync(ctx.userId, ctx.now, requestHashCount, full);
  await store.recomputeMatches(ctx.userId);

  const friendRows = await store.mutualFriends(ctx.userId);
  const matches: MatchedContact[] = [];
  for (const f of friendRows) {
    const hash = hmacToHash.get(f.phoneHmac);
    if (hash !== undefined) {
      matches.push({ userId: f.userId, displayName: f.displayName, hash });
    }
  }
  const friends = friendRows.map((f) => ({ userId: f.userId, displayName: f.displayName }));
  const stored = await store.countContactHmacs(ctx.userId);

  return { status: 200, body: { matches, friends, stored } };
}
