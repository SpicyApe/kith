// test_fakes.ts — in-memory Store fakes for the register / submit-result /
// match-contacts contract tests. Each fake is faithful to its Store
// interface's doc comments (see the corresponding handler.ts) and nothing
// more: no extra validation, no hidden business rules. Handlers own the
// rules; these fakes just remember what they were told and hand it back,
// while recording calls so tests can assert on them.

import { RegisterStoreError, type RegisterStore } from "../register/handler.ts";
import { SubmitStoreError, type StoredResult, type SubmitStore } from "../submit-result/handler.ts";
import type { MatchStore } from "../match-contacts/handler.ts";

// ---------------------------------------------------------------------------
// register
// ---------------------------------------------------------------------------

export interface FakeUserRow {
  displayName: string;
  inviteCode: string;
}

export class FakeRegisterStore implements RegisterStore {
  users = new Map<string, FakeUserRow>();
  /** phoneHmac -> userId, mirrors the `users_phone_hmac_key` unique index. */
  phoneHmacToUserId = new Map<string, string>();
  insertUserCalls: Array<{ userId: string; phoneHmac: string; displayName: string; tz: string }> = [];
  private inviteCodeCounter = 0;
  /** Override to control the invite code insertUser hands back. */
  nextInviteCode: (() => string) | null = null;

  /** Seed an already-registered user (also registers their phoneHmac). */
  seedUser(userId: string, row: FakeUserRow & { phoneHmac: string }): void {
    this.users.set(userId, { displayName: row.displayName, inviteCode: row.inviteCode });
    this.phoneHmacToUserId.set(row.phoneHmac, userId);
  }

  getUser(userId: string): Promise<{ displayName: string; inviteCode: string } | null> {
    return Promise.resolve(this.users.get(userId) ?? null);
  }

  insertUser(
    row: { userId: string; phoneHmac: string; displayName: string; tz: string },
  ): Promise<{ inviteCode: string }> {
    this.insertUserCalls.push(row);
    const existingOwner = this.phoneHmacToUserId.get(row.phoneHmac);
    if (existingOwner !== undefined && existingOwner !== row.userId) {
      throw new RegisterStoreError("phone_taken");
    }
    const inviteCode = this.nextInviteCode ? this.nextInviteCode() : `INVITE${++this.inviteCodeCounter}`;
    this.users.set(row.userId, { displayName: row.displayName, inviteCode });
    this.phoneHmacToUserId.set(row.phoneHmac, row.userId);
    return Promise.resolve({ inviteCode });
  }
}

// ---------------------------------------------------------------------------
// submit-result
// ---------------------------------------------------------------------------

export type InsertResultRow = Omit<StoredResult, "submittedAt"> & { tz: string; submittedAt: Date };

export class FakeSubmitStore implements SubmitStore {
  puzzles = new Map<string, { correctOrder: number[] }>();
  starts = new Map<string, Date>();
  results = new Map<string, StoredResult>();
  streaks = new Map<string, number>();
  insertResultCalls: Array<{ userId: string; row: InsertResultRow }> = [];
  touchUserCalls: Array<{ userId: string; tz: string; now: Date }> = [];
  /**
   * When true, the NEXT insertResult call throws `duplicate` (simulating a
   * concurrent writer) and, if `raceResult` is set, plants it under the same
   * key first so a subsequent getResult "re-read" sees the row the other
   * request supposedly inserted.
   */
  forceDuplicateOnce = false;
  raceResult: StoredResult | null = null;
  /** When set, the NEXT touchUser/streak call rejects with this error instead of succeeding. */
  touchUserError: Error | null = null;
  streakError: Error | null = null;

  private key(userId: string, date: string): string {
    return `${userId}|${date}`;
  }

  seedPuzzle(date: string, correctOrder: number[]): void {
    this.puzzles.set(date, { correctOrder });
  }

  seedStart(userId: string, date: string, startedAt: Date): void {
    this.starts.set(this.key(userId, date), startedAt);
  }

  seedResult(userId: string, result: StoredResult): void {
    this.results.set(this.key(userId, result.puzzleDate), result);
  }

  setStreak(userId: string, n: number): void {
    this.streaks.set(userId, n);
  }

  getPuzzle(date: string): Promise<{ correctOrder: number[] } | null> {
    return Promise.resolve(this.puzzles.get(date) ?? null);
  }

  getStart(userId: string, date: string): Promise<Date | null> {
    return Promise.resolve(this.starts.get(this.key(userId, date)) ?? null);
  }

  getResult(userId: string, date: string): Promise<StoredResult | null> {
    return Promise.resolve(this.results.get(this.key(userId, date)) ?? null);
  }

  insertResult(userId: string, row: InsertResultRow): Promise<void> {
    this.insertResultCalls.push({ userId, row });
    const key = this.key(userId, row.puzzleDate);
    if (this.forceDuplicateOnce) {
      this.forceDuplicateOnce = false;
      if (this.raceResult) this.results.set(key, this.raceResult);
      throw new SubmitStoreError("duplicate");
    }
    if (this.results.has(key)) {
      throw new SubmitStoreError("duplicate");
    }
    const { tz: _tz, submittedAt, ...rest } = row;
    this.results.set(key, { ...rest, submittedAt: submittedAt.toISOString() });
    return Promise.resolve();
  }

  streak(userId: string): Promise<number> {
    if (this.streakError) return Promise.reject(this.streakError);
    return Promise.resolve(this.streaks.get(userId) ?? 0);
  }

  touchUser(userId: string, tz: string, now: Date): Promise<void> {
    this.touchUserCalls.push({ userId, tz, now });
    if (this.touchUserError) return Promise.reject(this.touchUserError);
    return Promise.resolve();
  }
}

// ---------------------------------------------------------------------------
// match-contacts
// ---------------------------------------------------------------------------

export interface FakeFriend {
  userId: string;
  displayName: string;
  phoneHmac: string;
}

export class FakeMatchStore implements MatchStore {
  /** Absent = user row missing (not registered); present = discoverable flag. */
  discoverable = new Map<string, boolean>();
  contactHmacs = new Map<string, Set<string>>();
  friends = new Map<string, FakeFriend[]>();
  syncLog: Array<{ userId: string; at: Date; hashes: number; full: boolean }> = [];

  replaceCalls: Array<{ userId: string; hmacs: string[] }> = [];
  upsertCalls: Array<{ userId: string; hmacs: string[] }> = [];
  deleteCalls: Array<{ userId: string; hmacs: string[] }> = [];
  logSyncCalls: Array<{ userId: string; at: Date; hashes: number; full: boolean }> = [];
  recomputeMatchesCalls: string[] = [];

  seedRegistered(userId: string, discoverable = true): void {
    this.discoverable.set(userId, discoverable);
  }

  seedContactHmacs(userId: string, hmacs: string[]): void {
    this.contactHmacs.set(userId, new Set(hmacs));
  }

  seedFriends(userId: string, friends: FakeFriend[]): void {
    this.friends.set(userId, friends);
  }

  /** Directly append a past sync-log row (bypasses logSync/logSyncCalls). */
  seedSyncLog(userId: string, at: Date, hashes: number, full: boolean): void {
    this.syncLog.push({ userId, at, hashes, full });
  }

  private hmacsFor(userId: string): Set<string> {
    let set = this.contactHmacs.get(userId);
    if (!set) {
      set = new Set();
      this.contactHmacs.set(userId, set);
    }
    return set;
  }

  getDiscoverable(userId: string): Promise<boolean | null> {
    return Promise.resolve(this.discoverable.has(userId) ? this.discoverable.get(userId)! : null);
  }

  syncUsage(userId: string, since: Date): Promise<{ fullSyncs: number; hashes: number; requests: number }> {
    const relevant = this.syncLog.filter((e) => e.userId === userId && e.at >= since);
    return Promise.resolve({
      fullSyncs: relevant.filter((e) => e.full).length,
      hashes: relevant.reduce((sum, e) => sum + e.hashes, 0),
      requests: relevant.length,
    });
  }

  logSync(userId: string, at: Date, hashes: number, full: boolean): Promise<void> {
    this.logSyncCalls.push({ userId, at, hashes, full });
    this.syncLog.push({ userId, at, hashes, full });
    return Promise.resolve();
  }

  replaceContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    this.replaceCalls.push({ userId, hmacs });
    this.contactHmacs.set(userId, new Set(hmacs));
    return Promise.resolve();
  }

  upsertContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    this.upsertCalls.push({ userId, hmacs });
    const set = this.hmacsFor(userId);
    for (const h of hmacs) set.add(h);
    return Promise.resolve();
  }

  deleteContactHmacs(userId: string, hmacs: string[]): Promise<void> {
    this.deleteCalls.push({ userId, hmacs });
    const set = this.hmacsFor(userId);
    for (const h of hmacs) set.delete(h);
    return Promise.resolve();
  }

  countContactHmacs(userId: string): Promise<number> {
    return Promise.resolve(this.hmacsFor(userId).size);
  }

  recomputeMatches(userId: string): Promise<void> {
    this.recomputeMatchesCalls.push(userId);
    return Promise.resolve();
  }

  mutualFriends(userId: string): Promise<FakeFriend[]> {
    return Promise.resolve(this.friends.get(userId) ?? []);
  }
}
