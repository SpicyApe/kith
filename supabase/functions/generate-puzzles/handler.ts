// generate-puzzles — fills the puzzle calendar 30 days ahead from curated lists.
//
// CONTRACT FILE. `generatePuzzle` is pure and deterministic (seeded RNG) so the
// review page's "Reseed" can produce a different puzzle by bumping the seed.
// Rules from docs/02 §1 "Content pipeline".

import type { GameKind, GeneratedGame } from "../_shared/games/common.ts";
import { GAME_KINDS, gameSeedFor } from "../_shared/games/common.ts";
import { generateDailyGame } from "../_shared/games/generate.ts";

/**
 * Wall-clock budget for the grid-games fill pass. Kept well under the edge runtime's
 * per-request compute limit (a 60 s pass was killed with WORKER_RESOURCE_LIMIT on the live
 * project after ~40 puzzles); whatever is left over is picked up by the next nightly run,
 * and the initial 30-day backfill is done by invoking the function repeatedly.
 */
const GAMES_TIME_BUDGET_MS = 8_000;

export interface ListRow {
  id: number;
  // Unused by generatePuzzle itself; carried through for the admin review page.
  promptTemplate: string;
  direction: string;
  ascending: boolean;
  enabled: boolean;
}

export interface ItemRow {
  id: number;
  listId: number;
  // Unused by generatePuzzle itself; carried through for the admin review page.
  label: string;
  value: number;
  familiarity: 1 | 2 | 3;
}

export interface Usage {
  /** Dates (YYYY-MM-DD) each list was used, most recent first. */
  listUses: { listId: number; date: string }[];
  /** Dates each item was used. */
  itemUses: { itemId: number; date: string }[];
}

export type Difficulty = "easy" | "medium" | "hard";

export interface GeneratedPuzzle {
  date: string;
  listId: number;
  /** Presentation order (shuffled). Never equal to correctOrder. */
  itemIds: [number, number, number, number, number];
  /** Sorted by value in the list's direction. */
  correctOrder: [number, number, number, number, number];
  difficulty: Difficulty;
  /** Which seed produced it, so a reseed can use seed + 1. */
  seed: number;
}

export const LIST_COOLDOWN_DAYS = 21;
export const ITEM_COOLDOWN_DAYS = 90;
/** Adjacent values must differ by at least this ratio of the larger one. */
export const MIN_ADJACENT_GAP = 0.08;

/** Mon–Tue easy, Wed–Thu medium, Fri hard, Sat–Sun medium. `date` is YYYY-MM-DD, weekday computed in UTC. */
export function difficultyFor(date: string): Difficulty {
  const weekday = new Date(`${date}T00:00:00Z`).getUTCDay(); // 0=Sun..6=Sat
  if (weekday === 1 || weekday === 2) return "easy";
  if (weekday === 3 || weekday === 4) return "medium";
  if (weekday === 5) return "hard";
  return "medium"; // Sat/Sun
}

/** Max number of familiarity-3 items allowed: easy 1, medium 2, hard 3. */
export function maxNicheItems(d: Difficulty): number {
  return d === "easy" ? 1 : d === "medium" ? 2 : 3;
}

/** mulberry32: deterministic 32-bit PRNG. Returns a function yielding floats in [0, 1). */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return function (): number {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Stable numeric seed for a date string plus an attempt number: djb2 over `${date}#${attempt}` as uint32. */
export function seedFor(date: string, attempt: number): number {
  const s = `${date}#${attempt}`;
  let hash = 5381 >>> 0;
  for (let i = 0; i < s.length; i++) {
    hash = (Math.imul(hash, 33) + s.charCodeAt(i)) >>> 0;
  }
  return hash >>> 0;
}

/**
 * True when every adjacent pair in `values` (already in correct order) satisfies
 * EITHER `|a - b| >= MIN_ADJACENT_GAP * max(|a|, |b|)` (the ratio rule) OR
 * `|a - b| >= MIN_ADJACENT_GAP * listSpan` (the span rule), and no two values
 * are equal. Ties (`a === b`) always fail, regardless of `listSpan`. `listSpan`
 * is `max(value) - min(value)` over ALL items of the list (not just the chosen
 * five); a `listSpan <= 0` disables the span clause, leaving only the ratio rule.
 * This makes tightly-clustered-but-large lists (e.g. calendar years) viable:
 * a pair can satisfy either rule even when both absolute values are large and
 * close together.
 */
export function gapsOk(values: number[], listSpan = 0): boolean {
  for (let i = 0; i + 1 < values.length; i++) {
    const a = values[i];
    const b = values[i + 1];
    if (a === b) return false;
    const diff = Math.abs(a - b);
    const maxAbs = Math.max(Math.abs(a), Math.abs(b));
    const ratioOk = maxAbs !== 0 && diff >= MIN_ADJACENT_GAP * maxAbs;
    const spanOk = listSpan > 0 && diff >= MIN_ADJACENT_GAP * listSpan;
    if (!ratioOk && !spanOk) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Internal helpers (not part of the contract). `addDaysUTC` is exported as a
// deliberate exception so store.ts can reuse it instead of duplicating it.
// ---------------------------------------------------------------------------

function shuffle<T>(arr: T[], rand: () => number): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** Whole calendar-day difference between two YYYY-MM-DD strings (UTC), unsigned. */
function daysBetween(a: string, b: string): number {
  const da = Date.parse(`${a}T00:00:00Z`);
  const db = Date.parse(`${b}T00:00:00Z`);
  return Math.round(Math.abs(da - db) / 86_400_000);
}

function usedWithin(uses: { date: string }[], date: string, cooldownDays: number): boolean {
  return uses.some((u) => daysBetween(u.date, date) <= cooldownDays);
}

export function addDaysUTC(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function arraysEqual(a: readonly number[], b: readonly number[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

/**
 * Picks one puzzle for `date` or returns null when no valid combination exists.
 * Algorithm (deterministic given seed):
 * 1. difficulty = difficultyFor(date).
 * 2. Candidate lists: enabled, not used within LIST_COOLDOWN_DAYS of `date` (inclusive of both sides),
 *    with ≥ 5 items not used within ITEM_COOLDOWN_DAYS. Shuffle with rng(seed) (Fisher–Yates).
 * 3. For each candidate list, up to 200 attempts: choose 5 distinct eligible items by shuffling
 *    the eligible item ids, honour maxNicheItems, sort by value (ascending if list.ascending
 *    else descending) → correctOrder; require gapsOk on the sorted values, passing the list's
 *    span (max value - min value across ALL of that list's items, not just the chosen five) so
 *    tightly-clustered-but-large lists (e.g. calendar years) can satisfy the span rule even when
 *    the ratio rule can't. Presentation order:
 *    shuffle correctOrder until it differs from correctOrder (max 20 tries; if it never differs, skip).
 * 4. First success wins. Return null if every list fails.
 * Cooldown comparisons use whole calendar-day differences between YYYY-MM-DD strings (UTC).
 */
export function generatePuzzle(
  date: string,
  lists: ListRow[],
  items: ItemRow[],
  usage: Usage,
  seed: number,
): GeneratedPuzzle | null {
  const difficulty = difficultyFor(date);
  const maxNiche = maxNicheItems(difficulty);
  const rand = rng(seed);

  const itemsByList = new Map<number, ItemRow[]>();
  for (const item of items) {
    const bucket = itemsByList.get(item.listId);
    if (bucket) bucket.push(item);
    else itemsByList.set(item.listId, [item]);
  }

  const spanFor = (listId: number): number => {
    const all = itemsByList.get(listId) ?? [];
    if (all.length === 0) return 0;
    let min = all[0].value;
    let max = all[0].value;
    for (const item of all) {
      if (item.value < min) min = item.value;
      if (item.value > max) max = item.value;
    }
    return max - min;
  };

  const eligibleItemsFor = (listId: number): ItemRow[] =>
    (itemsByList.get(listId) ?? []).filter(
      (item) => !usedWithin(usage.itemUses.filter((u) => u.itemId === item.id), date, ITEM_COOLDOWN_DAYS),
    );

  const candidateLists = shuffle(
    lists.filter((l) => {
      if (!l.enabled) return false;
      const listUsesForThis = usage.listUses.filter((u) => u.listId === l.id);
      if (usedWithin(listUsesForThis, date, LIST_COOLDOWN_DAYS)) return false;
      return eligibleItemsFor(l.id).length >= 5;
    }),
    rand,
  );

  for (const list of candidateLists) {
    const eligibleItems = eligibleItemsFor(list.id);
    const listSpan = spanFor(list.id);

    attempts: for (let attempt = 0; attempt < 200; attempt++) {
      const shuffled = shuffle(eligibleItems, rand);
      const chosen: ItemRow[] = [];
      let nicheCount = 0;
      for (const item of shuffled) {
        if (chosen.length === 5) break;
        if (item.familiarity === 3) {
          if (nicheCount >= maxNiche) continue;
          nicheCount++;
        }
        chosen.push(item);
      }
      if (chosen.length < 5) continue attempts;

      const sorted = chosen.slice().sort((a, b) => (list.ascending ? a.value - b.value : b.value - a.value));
      const values = sorted.map((i) => i.value);
      if (!gapsOk(values, listSpan)) continue attempts;

      const correctOrder = sorted.map((i) => i.id) as [number, number, number, number, number];

      let presentation: number[] | null = null;
      for (let p = 0; p < 20; p++) {
        const candidate = shuffle(correctOrder, rand);
        if (!arraysEqual(candidate, correctOrder)) {
          presentation = candidate;
          break;
        }
      }
      if (presentation === null) continue attempts;

      return {
        date,
        listId: list.id,
        itemIds: presentation as [number, number, number, number, number],
        correctOrder,
        difficulty,
        seed,
      };
    }
  }

  return null;
}

export interface GenerateStore {
  lists(): Promise<ListRow[]>;
  items(): Promise<ItemRow[]>;
  /** Usage from puzzles within the last ITEM_COOLDOWN_DAYS before `from` and any after it. */
  usage(from: string): Promise<Usage>;
  /** Dates that already have a puzzle in [from, to]. */
  existingDates(from: string, to: string): Promise<string[]>;
  /** Next puzzle number to assign (max(number) + 1, or 1). */
  nextNumber(): Promise<number>;
  /** Insert a pending puzzle. */
  insert(p: GeneratedPuzzle, number: number): Promise<void>;
  /** Replace an existing PENDING puzzle for the date (keeps its number). Throws an error with `code: "not_pending"` if it is approved (or missing). */
  replace(p: GeneratedPuzzle): Promise<void>;
  /** Current seed stored for a date's puzzle, to bump on reseed. Null if no puzzle. */
  seedOf(date: string): Promise<number | null>;

  // Grid games (daily_games; docs/07-games-hub.md). Rows are approved on insert:
  // the uniqueness solver proves correctness, so there is no review step.
  /** `${date}#${game}` keys that already exist in [from, to]. */
  existingGames(from: string, to: string): Promise<string[]>;
  /** max(number) + 1 for the game, or 1. */
  nextGameNumber(game: GameKind): Promise<number>;
  insertGame(date: string, g: GeneratedGame, number: number): Promise<void>;
  /**
   * Quint solutions' words (`daily_games.solution->>'word'`) from any row within 365 days
   * before `fromDate`, with no upper bound — a word already scheduled for a future date counts
   * as recent too. When `excludeDate` is given, that date's own row is left out (used by the
   * single-game reseed path, which is about to replace that date's word and shouldn't count it
   * against itself).
   */
  recentQuintWords(fromDate: string, excludeDate?: string): Promise<Set<string>>;
  /**
   * Replace spec/solution/difficulty/seed for an existing (date, game); throws `code: "not_found"`
   * if absent, or `code: "has_results"` if anyone has already played it (`game_results` has a row
   * for that date+game) — reseeding would invalidate a submitted result.
   */
  replaceGame(date: string, g: GeneratedGame): Promise<void>;
  gameSeedOf(date: string, game: GameKind): Promise<number | null>;
}

export interface GenerateRequest {
  /** Reseed exactly this date (Lineup must be pending; grid games may be reseeded any time). */
  date?: string;
  /** With `date`: reseed only this grid game instead of Lineup. */
  game?: GameKind;
  /** Default 30. */
  daysAhead?: number;
}

export interface GenerateReport {
  created: string[];
  replaced: string[];
  /** Dates for which no valid puzzle could be generated. */
  skipped: string[];
  /** Grid games, keyed `${date}#${game}`. */
  games: { created: string[]; replaced: string[]; skipped: string[] };
}

/**
 * Behaviour:
 * - Grid games: when `req.date` and `req.game` are set, reseed that one game: read the current
 *   seed via `gameSeedOf`, then try attempt = 1, 2, … (max 20), skipping any attempt whose
 *   `gameSeedFor(date, game, attempt)` equals the current seed (so a reseed is never a no-op),
 *   until `generateDailyGame` returns non-null, then `replaceGame` and report under
 *   `games.replaced` (or `games.skipped` if every attempt failed or was skipped). A `has_results`
 *   error from `replaceGame` propagates to the caller (mapped to 409 by index.ts). When filling
 *   ahead (no `req.date`), for every date in range and every game in GAME_KINDS whose
 *   `${date}#${game}` is not in existingGames: attempt 0..4 until a game generates, insertGame
 *   with the next number for that game, report under `games.created` / `games.skipped`. Each
 *   `(date, game)` body runs in its own try/catch: a failure is logged and the key pushed to
 *   `games.skipped` rather than aborting the rest of the run, and the whole games pass stops
 *   early (skipping every remaining key) once `GAMES_TIME_BUDGET_MS` has elapsed. Lineup handling
 *   below is unchanged and runs first (also try/catch per date, degrading to `skipped`);
 *   `req.date` without `req.game` reseeds Lineup only.
 * - If `req.date` is set: seed = (seedOf(date) ?? seedFor(date, 0)) + 1; generatePuzzle; replace(); report replaced (or skipped).
 *   Usage for the reseed must EXCLUDE that date's own current puzzle (the store's usage(from) with from = date already
 *   includes it — so the handler filters out uses whose date === req.date).
 * - Else: for each date from today (UTC, `now`) through today + daysAhead - 1 that has no puzzle, in order,
 *   seed = seedFor(date, 0), generate, insert with the next number, and add the new puzzle's list/items to the
 *   in-memory usage so later dates respect cooldowns against it. Report created/skipped.
 */
export async function handleGenerate(
  req: GenerateRequest,
  now: Date,
  store: GenerateStore,
): Promise<GenerateReport> {
  const startedAt = Date.now();
  const games: GenerateReport["games"] = { created: [], replaced: [], skipped: [] };

  // A single grid game reseed: `date` + `game` never touches Lineup.
  if (req.date !== undefined && req.game !== undefined) {
    const date = req.date;
    const game = req.game;
    const key = `${date}#${game}`;
    const cur = await store.gameSeedOf(date, game);
    const context = game === "quint" ? { recentWords: await store.recentQuintWords(date, date) } : undefined;
    let generated: GeneratedGame | null = null;
    for (let attempt = 1; attempt <= 20 && generated === null; attempt++) {
      if (gameSeedFor(date, game, attempt) === cur) continue;
      generated = generateDailyGame(game, date, attempt, context);
    }
    if (generated === null) {
      games.skipped.push(key);
    } else {
      await store.replaceGame(date, generated);
      games.replaced.push(key);
    }
    return { created: [], replaced: [], skipped: [], games };
  }

  const lists = await store.lists();
  const items = await store.items();

  if (req.date !== undefined) {
    const date = req.date;
    const currentSeed = await store.seedOf(date);
    const seed = (currentSeed ?? seedFor(date, 0)) + 1;

    const rawUsage = await store.usage(date);
    const usage: Usage = {
      listUses: rawUsage.listUses.filter((u) => u.date !== date),
      itemUses: rawUsage.itemUses.filter((u) => u.date !== date),
    };

    const generated = generatePuzzle(date, lists, items, usage, seed);
    if (generated === null) {
      return { created: [], replaced: [], skipped: [date], games };
    }
    await store.replace(generated);
    return { created: [], replaced: [date], skipped: [], games };
  }

  // Number.isFinite guards against NaN/Infinity (and undefined) reaching
  // addDaysUTC below, which would otherwise build an invalid Date and throw;
  // Math.max(0, ...) treats a negative daysAhead as "generate nothing" rather
  // than throwing, matching the empty-report behaviour daysAhead: 0 already has.
  const daysAhead = Number.isFinite(req.daysAhead) ? Math.max(0, Math.trunc(req.daysAhead!)) : 30;
  const today = now.toISOString().slice(0, 10);
  const from = today;
  const to = addDaysUTC(today, daysAhead - 1);

  const existing = new Set(await store.existingDates(from, to));
  const rawUsage = await store.usage(from);
  const usage: Usage = {
    listUses: rawUsage.listUses.slice(),
    itemUses: rawUsage.itemUses.slice(),
  };

  let nextNumber = await store.nextNumber();

  const created: string[] = [];
  const skipped: string[] = [];

  for (let i = 0; i < daysAhead; i++) {
    const date = addDaysUTC(today, i);
    if (existing.has(date)) continue;

    try {
      const seed = seedFor(date, 0);
      const generated = generatePuzzle(date, lists, items, usage, seed);
      if (generated === null) {
        skipped.push(date);
        continue;
      }

      await store.insert(generated, nextNumber);
      created.push(date);
      nextNumber++;

      usage.listUses.push({ listId: generated.listId, date });
      for (const itemId of generated.itemIds) {
        usage.itemUses.push({ itemId, date });
      }
    } catch (e) {
      console.error("lineup_failed", date, (e as Error).message);
      skipped.push(date);
    }
  }

  // Grid games: fill every (date, game) in range that has no row yet.
  const existingGameKeys = daysAhead > 0 ? new Set(await store.existingGames(from, to)) : new Set<string>();
  const nextGameNumber = new Map<GameKind, number>();
  if (daysAhead > 0) {
    for (const game of GAME_KINDS) {
      nextGameNumber.set(game, await store.nextGameNumber(game));
    }
  }
  // Quint must not repeat a word used in the last 365 days; grown in-memory as new
  // quint games are generated below so a single fill run doesn't repeat one either.
  const recentQuintWords = daysAhead > 0 ? await store.recentQuintWords(from) : new Set<string>();

  for (let i = 0; i < daysAhead; i++) {
    const date = addDaysUTC(today, i);
    for (const game of GAME_KINDS) {
      const key = `${date}#${game}`;
      if (existingGameKeys.has(key)) continue;

      if (Date.now() - startedAt > GAMES_TIME_BUDGET_MS) {
        games.skipped.push(key);
        continue;
      }

      try {
        const context = game === "quint" ? { recentWords: recentQuintWords } : undefined;
        let generated: GeneratedGame | null = null;
        for (let attempt = 0; attempt < 5 && generated === null; attempt++) {
          generated = generateDailyGame(game, date, attempt, context);
        }
        if (generated === null) {
          games.skipped.push(key);
          continue;
        }
        const number = nextGameNumber.get(game)!;
        await store.insertGame(date, generated, number);
        nextGameNumber.set(game, number + 1);
        games.created.push(key);
        if (game === "quint") {
          recentQuintWords.add((generated.solution as { word: string }).word);
        }
      } catch (e) {
        console.error("game_failed", key, (e as Error).message);
        games.skipped.push(key);
      }
    }
  }

  return { created, replaced: [], skipped, games };
}
