// test_fakes.ts — in-memory Store fakes for the register / submit-result /
// match-contacts contract tests. Each fake is faithful to its Store
// interface's doc comments (see the corresponding handler.ts) and nothing
// more: no extra validation, no hidden business rules. Handlers own the
// rules; these fakes just remember what they were told and hand it back,
// while recording calls so tests can assert on them.

import { RegisterStoreError, type RegisterStore } from "../register/handler.ts";
import { SubmitStoreError, type StoredResult, type SubmitStore } from "../submit-result/handler.ts";
import type { MatchStore } from "../match-contacts/handler.ts";
import type { DeleteStore } from "../delete-account/handler.ts";
import type { PushCandidate, PushKind, PushStore } from "../send-pushes/handler.ts";
import type {
  GenerateStore,
  GeneratedPuzzle,
  ItemRow,
  ListRow,
  Usage,
} from "../generate-puzzles/handler.ts";
import type { GameKind, GeneratedGame } from "./games/common.ts";
import { SubmitGameStoreError, type StoredGameResult, type SubmitGameStore } from "../submit-game/handler.ts";

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

// ---------------------------------------------------------------------------
// delete-account
// ---------------------------------------------------------------------------

export class FakeDeleteStore implements DeleteStore {
  /** Ordered log of every call, e.g. "prepare:u1", "deleteAuthUser:u1". */
  calls: string[] = [];
  prepareCalls: string[] = [];
  deleteAuthUserCalls: string[] = [];
  /** When set, the NEXT prepare() call rejects with this error instead of succeeding. */
  prepareError: Error | null = null;
  /** When set, the NEXT deleteAuthUser() call rejects with this error instead of succeeding. */
  deleteAuthUserError: Error | null = null;

  prepare(userId: string): Promise<void> {
    this.calls.push(`prepare:${userId}`);
    this.prepareCalls.push(userId);
    if (this.prepareError) {
      const err = this.prepareError;
      this.prepareError = null;
      return Promise.reject(err);
    }
    return Promise.resolve();
  }

  deleteAuthUser(userId: string): Promise<void> {
    this.calls.push(`deleteAuthUser:${userId}`);
    this.deleteAuthUserCalls.push(userId);
    if (this.deleteAuthUserError) {
      const err = this.deleteAuthUserError;
      this.deleteAuthUserError = null;
      return Promise.reject(err);
    }
    return Promise.resolve();
  }
}

// ---------------------------------------------------------------------------
// send-pushes
// ---------------------------------------------------------------------------

export class FakePushStore implements PushStore {
  candidatesResult: PushCandidate[] = [];
  /** When set, the NEXT candidates() call rejects with this error. */
  candidatesError: Error | null = null;
  candidatesCalls: Date[] = [];
  logCalls: Array<{ userId: string; kind: PushKind; at: Date }> = [];
  deleteDeviceCalls: Array<{ userId: string; apnsToken: string }> = [];
  /** When set, the NEXT log() call rejects with this error instead of succeeding. */
  logError: Error | null = null;
  /** When set, the NEXT deleteDevice() call rejects with this error instead of succeeding. */
  deleteDeviceError: Error | null = null;

  candidates(at: Date): Promise<PushCandidate[]> {
    this.candidatesCalls.push(at);
    if (this.candidatesError) {
      const err = this.candidatesError;
      this.candidatesError = null;
      return Promise.reject(err);
    }
    return Promise.resolve(this.candidatesResult);
  }

  log(userId: string, kind: PushKind, at: Date): Promise<void> {
    this.logCalls.push({ userId, kind, at });
    if (this.logError) {
      const err = this.logError;
      this.logError = null;
      return Promise.reject(err);
    }
    return Promise.resolve();
  }

  deleteDevice(userId: string, apnsToken: string): Promise<void> {
    this.deleteDeviceCalls.push({ userId, apnsToken });
    if (this.deleteDeviceError) {
      const err = this.deleteDeviceError;
      this.deleteDeviceError = null;
      return Promise.reject(err);
    }
    return Promise.resolve();
  }
}

// ---------------------------------------------------------------------------
// generate-puzzles
// ---------------------------------------------------------------------------

export class FakeGenerateStore implements GenerateStore {
  listsData: ListRow[] = [];
  itemsData: ItemRow[] = [];
  usageData: Usage = { listUses: [], itemUses: [] };
  existingDatesData: string[] = [];
  nextNumberValue = 1;
  /** Current seed for a date, as `seedOf` would report it. Absent = null (no puzzle). */
  seeds = new Map<string, number>();

  inserted: Array<{ p: GeneratedPuzzle; number: number }> = [];
  replaced: GeneratedPuzzle[] = [];
  /** When set, the NEXT replace() call rejects with this error. */
  replaceError: Error | null = null;

  lists(): Promise<ListRow[]> {
    return Promise.resolve(this.listsData);
  }

  items(): Promise<ItemRow[]> {
    return Promise.resolve(this.itemsData);
  }

  usage(_from: string): Promise<Usage> {
    return Promise.resolve(this.usageData);
  }

  existingDates(from: string, to: string): Promise<string[]> {
    return Promise.resolve(this.existingDatesData.filter((d) => d >= from && d <= to));
  }

  nextNumber(): Promise<number> {
    return Promise.resolve(this.nextNumberValue);
  }

  insert(p: GeneratedPuzzle, number: number): Promise<void> {
    this.inserted.push({ p, number });
    this.existingDatesData.push(p.date);
    this.seeds.set(p.date, p.seed);
    return Promise.resolve();
  }

  replace(p: GeneratedPuzzle): Promise<void> {
    if (this.replaceError) {
      const err = this.replaceError;
      this.replaceError = null;
      return Promise.reject(err);
    }
    this.replaced.push(p);
    this.seeds.set(p.date, p.seed);
    return Promise.resolve();
  }

  seedOf(date: string): Promise<number | null> {
    return Promise.resolve(this.seeds.has(date) ? this.seeds.get(date)! : null);
  }

  // --- grid games (daily_games; docs/07-games-hub.md) ---

  gamesData = new Map<string, { g: GeneratedGame; number: number }>(); // key `${date}#${game}`
  nextGameNumberValues = new Map<GameKind, number>();
  gameSeeds = new Map<string, number>(); // key `${date}#${game}`

  insertedGames: Array<{ date: string; g: GeneratedGame; number: number }> = [];
  replacedGames: Array<{ date: string; g: GeneratedGame }> = [];
  /** When set, the NEXT replaceGame() call rejects with this error. */
  replaceGameError: Error | null = null;
  /** `${date}#${game}` keys with an (simulated) existing `game_results` row: replaceGame throws `has_results`. */
  gameResultsExist = new Set<string>();

  private gameKey(date: string, game: GameKind): string {
    return `${date}#${game}`;
  }

  /** Mark a (date, game) as already played, so replaceGame throws `code: "has_results"`. */
  seedGameResult(date: string, game: GameKind): void {
    this.gameResultsExist.add(this.gameKey(date, game));
  }

  existingGames(from: string, to: string): Promise<string[]> {
    return Promise.resolve([...this.gamesData.keys()].filter((k) => {
      const date = k.split("#")[0];
      return date >= from && date <= to;
    }));
  }

  nextGameNumber(game: GameKind): Promise<number> {
    return Promise.resolve(this.nextGameNumberValues.get(game) ?? 1);
  }

  insertGame(date: string, g: GeneratedGame, number: number): Promise<void> {
    this.insertedGames.push({ date, g, number });
    this.gamesData.set(this.gameKey(date, g.game), { g, number });
    this.gameSeeds.set(this.gameKey(date, g.game), g.seed);
    this.nextGameNumberValues.set(g.game, number + 1);
    return Promise.resolve();
  }

  replaceGame(date: string, g: GeneratedGame): Promise<void> {
    if (this.replaceGameError) {
      const err = this.replaceGameError;
      this.replaceGameError = null;
      return Promise.reject(err);
    }
    const key = this.gameKey(date, g.game);
    if (this.gameResultsExist.has(key)) {
      return Promise.reject(Object.assign(new Error("has results"), { code: "has_results" }));
    }
    const existing = this.gamesData.get(key);
    this.gamesData.set(key, { g, number: existing?.number ?? 1 });
    this.gameSeeds.set(key, g.seed);
    this.replacedGames.push({ date, g });
    return Promise.resolve();
  }

  gameSeedOf(date: string, game: GameKind): Promise<number | null> {
    const key = this.gameKey(date, game);
    return Promise.resolve(this.gameSeeds.has(key) ? this.gameSeeds.get(key)! : null);
  }
}

// ---------------------------------------------------------------------------
// submit-game
// ---------------------------------------------------------------------------

export type InsertGameResultRow = Omit<StoredGameResult, "submittedAt"> & { tz: string; submittedAt: Date };

export class FakeSubmitGameStore implements SubmitGameStore {
  games = new Map<string, { spec: unknown; solution: unknown; number: number }>(); // key `${date}#${game}`
  starts = new Map<string, Date>(); // key `${userId}|${date}|${game}`
  results = new Map<string, StoredGameResult>(); // key `${userId}|${date}|${game}`
  streaks = new Map<string, number>();
  insertResultCalls: Array<{ userId: string; row: InsertGameResultRow }> = [];
  touchUserCalls: Array<{ userId: string; tz: string; now: Date }> = [];
  /**
   * When true, the NEXT insertResult call throws `duplicate` (simulating a
   * concurrent writer) and, if `raceResult` is set, plants it under the same
   * key first so a subsequent getResult "re-read" sees the row the other
   * request supposedly inserted.
   */
  forceDuplicateOnce = false;
  raceResult: StoredGameResult | null = null;
  /** When set, the NEXT touchUser/streak call rejects with this error instead of succeeding. */
  touchUserError: Error | null = null;
  streakError: Error | null = null;

  private gameKey(date: string, game: GameKind): string {
    return `${date}#${game}`;
  }

  private key(userId: string, date: string, game: GameKind): string {
    return `${userId}|${date}|${game}`;
  }

  seedGame(date: string, game: GameKind, spec: unknown, solution: unknown, number: number): void {
    this.games.set(this.gameKey(date, game), { spec, solution, number });
  }

  seedStart(userId: string, date: string, game: GameKind, startedAt: Date): void {
    this.starts.set(this.key(userId, date, game), startedAt);
  }

  seedResult(userId: string, result: StoredGameResult): void {
    this.results.set(this.key(userId, result.date, result.game), result);
  }

  setStreak(userId: string, n: number): void {
    this.streaks.set(userId, n);
  }

  getGame(date: string, game: GameKind): Promise<{ spec: unknown; solution: unknown } | null> {
    return Promise.resolve(this.games.get(this.gameKey(date, game)) ?? null);
  }

  getStart(userId: string, date: string, game: GameKind): Promise<Date | null> {
    return Promise.resolve(this.starts.get(this.key(userId, date, game)) ?? null);
  }

  getResult(userId: string, date: string, game: GameKind): Promise<StoredGameResult | null> {
    return Promise.resolve(this.results.get(this.key(userId, date, game)) ?? null);
  }

  insertResult(userId: string, row: InsertGameResultRow): Promise<void> {
    this.insertResultCalls.push({ userId, row });
    const key = this.key(userId, row.date, row.game);
    if (this.forceDuplicateOnce) {
      this.forceDuplicateOnce = false;
      if (this.raceResult) this.results.set(key, this.raceResult);
      throw new SubmitGameStoreError("duplicate");
    }
    if (this.results.has(key)) {
      throw new SubmitGameStoreError("duplicate");
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
