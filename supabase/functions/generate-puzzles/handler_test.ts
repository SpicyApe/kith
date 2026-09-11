// Tests for generate-puzzles/handler.ts, written strictly against its
// contract doc comments. Store is FakeGenerateStore (in-memory); no real DB.

import { assert, assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert";
import { FakeGenerateStore } from "../_shared/test_fakes.ts";
import {
  difficultyFor,
  gapsOk,
  generatePuzzle,
  handleGenerate,
  type ItemRow,
  LIST_COOLDOWN_DAYS,
  type ListRow,
  maxNicheItems,
  rng,
  seedFor,
  type Usage,
} from "./handler.ts";

// ---------------------------------------------------------------------------
// difficultyFor
// ---------------------------------------------------------------------------

// 2026-09-14 is a Monday (given).
Deno.test("difficultyFor - Monday is easy", () => assertEquals(difficultyFor("2026-09-14"), "easy"));
Deno.test("difficultyFor - Tuesday is easy", () => assertEquals(difficultyFor("2026-09-15"), "easy"));
Deno.test("difficultyFor - Wednesday is medium", () => assertEquals(difficultyFor("2026-09-16"), "medium"));
Deno.test("difficultyFor - Thursday is medium", () => assertEquals(difficultyFor("2026-09-17"), "medium"));
Deno.test("difficultyFor - Friday is hard", () => assertEquals(difficultyFor("2026-09-18"), "hard"));
Deno.test("difficultyFor - Saturday is medium", () => assertEquals(difficultyFor("2026-09-19"), "medium"));
Deno.test("difficultyFor - Sunday is medium", () => assertEquals(difficultyFor("2026-09-20"), "medium"));

// ---------------------------------------------------------------------------
// maxNicheItems
// ---------------------------------------------------------------------------

Deno.test("maxNicheItems - easy 1, medium 2, hard 3", () => {
  assertEquals(maxNicheItems("easy"), 1);
  assertEquals(maxNicheItems("medium"), 2);
  assertEquals(maxNicheItems("hard"), 3);
});

// ---------------------------------------------------------------------------
// rng
// ---------------------------------------------------------------------------

Deno.test("rng - deterministic for the same seed", () => {
  const a = rng(42);
  const b = rng(42);
  const seqA = [a(), a(), a(), a()];
  const seqB = [b(), b(), b(), b()];
  assertEquals(seqA, seqB);
});

Deno.test("rng - different for a different seed", () => {
  assertNotEquals(rng(42)(), rng(43)());
});

Deno.test("rng - values are always in [0, 1)", () => {
  const r = rng(12345);
  for (let i = 0; i < 200; i++) {
    const v = r();
    assert(v >= 0 && v < 1, `value ${v} out of [0,1)`);
  }
});

// ---------------------------------------------------------------------------
// seedFor
// ---------------------------------------------------------------------------

Deno.test("seedFor - deterministic for the same date+attempt", () => {
  assertEquals(seedFor("2026-09-14", 0), seedFor("2026-09-14", 0));
});

Deno.test("seedFor - differs across attempts", () => {
  assertNotEquals(seedFor("2026-09-14", 0), seedFor("2026-09-14", 1));
});

Deno.test("seedFor - differs across dates", () => {
  assertNotEquals(seedFor("2026-09-14", 0), seedFor("2026-09-15", 0));
});

Deno.test("seedFor - returns a uint32", () => {
  for (const [date, attempt] of [["2026-09-14", 0], ["2026-01-01", 5], ["2099-12-31", 99]] as const) {
    const s = seedFor(date, attempt);
    assert(Number.isInteger(s), `${s} not an integer`);
    assert(s >= 0 && s <= 0xffffffff, `${s} out of uint32 range`);
  }
});

// ---------------------------------------------------------------------------
// gapsOk
// ---------------------------------------------------------------------------

Deno.test("gapsOk - passes when every adjacent ratio is >= MIN_ADJACENT_GAP (8%)", () => {
  assertEquals(gapsOk([100, 110, 122]), true);
});

Deno.test("gapsOk - fails on an adjacent gap around 5% (below the 8% threshold)", () => {
  assertEquals(gapsOk([100, 105]), false);
});

Deno.test("gapsOk - fails on equal adjacent values", () => {
  assertEquals(gapsOk([100, 100, 200]), false);
});

Deno.test("gapsOk - fails when both values in a pair are 0", () => {
  assertEquals(gapsOk([0, 0]), false);
});

Deno.test("gapsOk - passes with negative values, using |max| for the ratio", () => {
  // |-110 - (-100)| = 10; max(|-110|,|-100|) = 110; 10/110 ~= 9.09% >= 8%.
  assertEquals(gapsOk([-110, -100]), true);
});

// ---------------------------------------------------------------------------
// generatePuzzle
// ---------------------------------------------------------------------------

const MONDAY = "2026-09-14"; // easy
const FRIDAY = "2026-09-18"; // hard

function emptyUsage(): Usage {
  return { listUses: [], itemUses: [] };
}

const LIST_ASC: ListRow = {
  id: 1,
  promptTemplate: "Order by year",
  direction: "Earliest first",
  ascending: true,
  enabled: true,
};
const LIST_ASC_ITEMS: ItemRow[] = [100, 200, 300, 400, 500, 600, 700, 800].map((v, i) => ({
  id: 100 + i,
  listId: 1,
  label: `asc-item-${i}`,
  value: v,
  familiarity: 1,
}));

const LIST_DESC: ListRow = {
  id: 2,
  promptTemplate: "Order by height",
  direction: "Tallest first",
  ascending: false,
  enabled: true,
};
const LIST_DESC_ITEMS: ItemRow[] = [100, 200, 300, 400, 500, 600, 700, 800].map((v, i) => ({
  id: 200 + i,
  listId: 2,
  label: `desc-item-${i}`,
  value: v,
  familiarity: 1,
}));

Deno.test("generatePuzzle - non-null for a well-formed list with enough eligible items", () => {
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assert(p !== null);
  assertEquals(p!.date, MONDAY);
  assertEquals(p!.listId, 1);
  assertEquals(p!.seed, seedFor(MONDAY, 0));
});

Deno.test("generatePuzzle - correctOrder sorted ascending by value for an ascending list", () => {
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assert(p !== null);
  const values = p!.correctOrder.map((id) => LIST_ASC_ITEMS.find((it) => it.id === id)!.value);
  const sorted = [...values].sort((a, b) => a - b);
  assertEquals(values, sorted);
});

Deno.test("generatePuzzle - correctOrder sorted descending by value for a descending list", () => {
  const p = generatePuzzle(MONDAY, [LIST_DESC], LIST_DESC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assert(p !== null);
  const values = p!.correctOrder.map((id) => LIST_DESC_ITEMS.find((it) => it.id === id)!.value);
  const sorted = [...values].sort((a, b) => b - a);
  assertEquals(values, sorted);
});

Deno.test("generatePuzzle - itemIds is a permutation of correctOrder and not equal to it", () => {
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assert(p !== null);
  assertEquals([...p!.itemIds].sort((a, b) => a - b), [...p!.correctOrder].sort((a, b) => a - b));
  assertNotEquals(p!.itemIds, p!.correctOrder);
});

Deno.test("generatePuzzle - 5 distinct ids, all from the same list", () => {
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assert(p !== null);
  assertEquals(new Set(p!.itemIds).size, 5);
  for (const id of p!.itemIds) {
    assert(LIST_ASC_ITEMS.some((it) => it.id === id), `${id} not from list 1`);
  }
});

Deno.test("generatePuzzle - deterministic for the same seed", () => {
  const seed = seedFor(MONDAY, 0);
  const p1 = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seed);
  const p2 = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), seed);
  assertEquals(p1, p2);
});

Deno.test("generatePuzzle - varies across seeds: at least two distinct correctOrders across seeds 0..10", () => {
  const seen = new Set<string>();
  for (let s = 0; s <= 10; s++) {
    const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, emptyUsage(), s);
    if (p) seen.add(JSON.stringify(p.correctOrder));
  }
  assert(seen.size >= 2, `expected at least 2 distinct correctOrders across seeds 0..10, got ${seen.size}`);
});

Deno.test("generatePuzzle - a list used 10 days ago is skipped (within LIST_COOLDOWN_DAYS=21)", () => {
  const usage: Usage = { listUses: [{ listId: 1, date: "2026-09-04" }], itemUses: [] }; // 10 days before MONDAY
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, usage, seedFor(MONDAY, 0));
  assertEquals(p, null);
});

Deno.test("generatePuzzle - a list used 22 days ago (past cooldown) is allowed", () => {
  const usage: Usage = { listUses: [{ listId: 1, date: "2026-08-23" }], itemUses: [] }; // 22 days before MONDAY
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, usage, seedFor(MONDAY, 0));
  assert(p !== null);
});

Deno.test("LIST_COOLDOWN_DAYS is 21 (sanity for the cooldown fixtures above)", () => {
  assertEquals(LIST_COOLDOWN_DAYS, 21);
});

Deno.test("generatePuzzle - items used 30 days ago are excluded; a list left with only 4 eligible items is skipped", () => {
  const usedDate = "2026-08-15"; // 30 days before MONDAY, well within ITEM_COOLDOWN_DAYS=90
  const usage: Usage = {
    listUses: [],
    itemUses: [
      { itemId: LIST_ASC_ITEMS[0].id, date: usedDate },
      { itemId: LIST_ASC_ITEMS[1].id, date: usedDate },
      { itemId: LIST_ASC_ITEMS[2].id, date: usedDate },
      { itemId: LIST_ASC_ITEMS[3].id, date: usedDate },
    ],
  };
  const p = generatePuzzle(MONDAY, [LIST_ASC], LIST_ASC_ITEMS, usage, seedFor(MONDAY, 0));
  assertEquals(p, null);
});

// 5 familiarity-3 (niche) items + 3 familiarity-1 items among 8: any 5-item
// subset must include at least 5 - 3 = 2 niche items (pigeonhole), so an
// "easy" day (maxNicheItems 1) can never find a valid combination, while a
// "hard" day (maxNicheItems 3) can (e.g. 2 non-niche + 3 niche).
const NICHE_LIST: ListRow = {
  id: 3,
  promptTemplate: "Order by depth",
  direction: "Deepest first",
  ascending: true,
  enabled: true,
};
const NICHE_ITEMS: ItemRow[] = [
  { id: 300, listId: 3, label: "niche-0", value: 100, familiarity: 3 },
  { id: 301, listId: 3, label: "niche-1", value: 200, familiarity: 3 },
  { id: 302, listId: 3, label: "niche-2", value: 300, familiarity: 3 },
  { id: 303, listId: 3, label: "niche-3", value: 400, familiarity: 3 },
  { id: 304, listId: 3, label: "niche-4", value: 500, familiarity: 3 },
  { id: 305, listId: 3, label: "common-0", value: 600, familiarity: 1 },
  { id: 306, listId: 3, label: "common-1", value: 700, familiarity: 1 },
  { id: 307, listId: 3, label: "common-2", value: 800, familiarity: 1 },
];

Deno.test("generatePuzzle - easy day: a list where any 5 items include >=2 niche items is unusable (null)", () => {
  const p = generatePuzzle(MONDAY, [NICHE_LIST], NICHE_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assertEquals(p, null);
});

Deno.test("generatePuzzle - hard day (Friday, maxNiche 3): the same list succeeds", () => {
  const p = generatePuzzle(FRIDAY, [NICHE_LIST], NICHE_ITEMS, emptyUsage(), seedFor(FRIDAY, 0));
  assert(p !== null);
});

const TIGHT_LIST: ListRow = {
  id: 4,
  promptTemplate: "Order by weight",
  direction: "Heaviest first",
  ascending: true,
  enabled: true,
};
const TIGHT_ITEMS: ItemRow[] = [100, 101, 102, 103, 104, 105].map((v, i) => ({
  id: 400 + i,
  listId: 4,
  label: `tight-${i}`,
  value: v,
  familiarity: 1,
}));

Deno.test("generatePuzzle - gapsOk failures make a list unusable: tightly-packed values (100..105) return null", () => {
  const p = generatePuzzle(MONDAY, [TIGHT_LIST], TIGHT_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assertEquals(p, null);
});

Deno.test("generatePuzzle - returns null when there are no candidate lists at all", () => {
  const p = generatePuzzle(MONDAY, [], [], emptyUsage(), seedFor(MONDAY, 0));
  assertEquals(p, null);
});

Deno.test("generatePuzzle - a disabled list is never a candidate", () => {
  const disabled: ListRow = { ...LIST_ASC, enabled: false };
  const p = generatePuzzle(MONDAY, [disabled], LIST_ASC_ITEMS, emptyUsage(), seedFor(MONDAY, 0));
  assertEquals(p, null);
});

// ---------------------------------------------------------------------------
// handleGenerate
// ---------------------------------------------------------------------------

/** Several plain lists, each with 8 well-separated, non-niche items, so cooldowns
 * (not gaps or niche limits) are the only thing that can cause a skip. */
function plainList(id: number, valueBase: number): { list: ListRow; items: ItemRow[] } {
  const list: ListRow = {
    id,
    promptTemplate: `Order list ${id}`,
    direction: "Ascending",
    ascending: true,
    enabled: true,
  };
  const items: ItemRow[] = [0, 1, 2, 3, 4, 5, 6, 7].map((i) => ({
    id: id * 100 + i,
    listId: id,
    label: `list${id}-item${i}`,
    value: Math.round(valueBase * Math.pow(1.5, i)), // ≥ 8% adjacent gaps for the generator
    familiarity: 1,
  }));
  return { list, items };
}

Deno.test("handleGenerate - fills days from `now`, skipping existing dates; numbers increase from nextNumber", async () => {
  const store = new FakeGenerateStore();
  const lists = [1, 2, 3, 4, 5].map((id) => plainList(id, id * 10_000));
  store.listsData = lists.map((l) => l.list);
  store.itemsData = lists.flatMap((l) => l.items);
  store.nextNumberValue = 500;
  // now = Monday 2026-09-14; skip Wednesday 2026-09-16 (already has a puzzle).
  store.existingDatesData = ["2026-09-16"];

  const now = new Date("2026-09-14T00:00:00Z");
  const report = await handleGenerate({ daysAhead: 5 }, now, store);

  // 5 dates (09-14..09-18) minus the 1 pre-existing = 4 candidate dates.
  assertEquals(report.created.length + report.skipped.length, 4);
  assert(!report.created.includes("2026-09-16"));
  assert(!report.skipped.includes("2026-09-16"));

  // Numbers assigned in insertion order starting at nextNumber.
  assertEquals(store.inserted.map((r) => r.number), store.inserted.map((_, i) => 500 + i));
  for (const r of store.inserted) {
    assertEquals(r.p.itemIds.length, 5);
    assertEquals(r.p.correctOrder.length, 5);
  }
});

Deno.test("handleGenerate - with only one list available, later dates respect its cooldown: exactly one date created, the rest skipped", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;
  store.nextNumberValue = 1;

  // daysAhead <= LIST_COOLDOWN_DAYS+1 so the list, once used on day 0, never
  // comes off cooldown again within the window.
  const now = new Date("2026-09-14T00:00:00Z");
  const report = await handleGenerate({ daysAhead: 21 }, now, store);

  assertEquals(report.created.length, 1);
  assertEquals(report.created[0], "2026-09-14");
  assertEquals(report.skipped.length, 20);
  assertEquals(store.inserted.length, 1);
});

Deno.test("handleGenerate - reseed: seedOf null uses seedFor(date,0)+1 and calls replace", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;
  const date = "2026-09-14";

  const report = await handleGenerate({ date }, new Date("2026-09-14T00:00:00Z"), store);

  assertEquals(report.replaced, [date]);
  assertEquals(report.created, []);
  assertEquals(store.replaced.length, 1);
  assertEquals(store.replaced[0].seed, seedFor(date, 0) + 1);
});

Deno.test("handleGenerate - reseed: an existing seed is bumped by 1", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;
  const date = "2026-09-14";
  store.seeds.set(date, 7);

  const report = await handleGenerate({ date }, new Date("2026-09-14T00:00:00Z"), store);

  assertEquals(report.replaced, [date]);
  assertEquals(store.replaced[0].seed, 8);
});

Deno.test("handleGenerate - reseed excludes the date's own current usage from cooldown/exclusion checks", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;
  const date = "2026-09-14";
  // The store's usage(from=date) includes the puzzle CURRENTLY at `date`
  // itself: its list used on that date, and its 5 items used on that date.
  // If the handler didn't filter these out, the only list would look like
  // it's on cooldown against itself (distance 0) and short on eligible
  // items, making regeneration impossible.
  store.usageData = {
    listUses: [{ listId: 1, date }],
    itemUses: items.slice(0, 5).map((it) => ({ itemId: it.id, date })),
  };

  const report = await handleGenerate({ date }, new Date("2026-09-14T00:00:00Z"), store);

  assertEquals(report.replaced, [date]);
  assertEquals(report.skipped, []);
});

Deno.test("handleGenerate - daysAhead 0 yields an empty report and makes no writes", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;

  const report = await handleGenerate({ daysAhead: 0 }, new Date("2026-09-14T00:00:00Z"), store);

  assertEquals(report, { created: [], replaced: [], skipped: [] });
  assertEquals(store.inserted.length, 0);
});

Deno.test("handleGenerate - a negative daysAhead is treated as 0 iterations: empty report, no writes", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;

  const report = await handleGenerate({ daysAhead: -1 }, new Date("2026-09-14T00:00:00Z"), store);

  assertEquals(report, { created: [], replaced: [], skipped: [] });
  assertEquals(store.inserted.length, 0);
});

Deno.test("handleGenerate - a non-finite daysAhead (NaN) does not throw and produces a report", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;

  const report = await handleGenerate({ daysAhead: NaN }, new Date("2026-09-14T00:00:00Z"), store);

  assert(report !== undefined);
  assert(Array.isArray(report.created) && Array.isArray(report.skipped) && Array.isArray(report.replaced));
});

Deno.test("handleGenerate - replace() throwing propagates", async () => {
  const store = new FakeGenerateStore();
  const { list, items } = plainList(1, 100_000);
  store.listsData = [list];
  store.itemsData = items;
  store.replaceError = new Error("cannot replace an approved puzzle");

  await assertRejects(
    () => handleGenerate({ date: "2026-09-14" }, new Date("2026-09-14T00:00:00Z"), store),
    Error,
    "cannot replace an approved puzzle",
  );
});
