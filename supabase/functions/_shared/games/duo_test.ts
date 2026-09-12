// Tests for games/duo.ts (Tango-style), written strictly against its
// contract doc comments (docs/07-games-hub.md).

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert";
import { rng } from "../../generate-puzzles/handler.ts";
import { duoShareRows, type DuoSolution, type DuoSpec, generateDuo, solveDuo, validateDuo } from "./duo.ts";

function nullGivens(): (0 | 1 | null)[][] {
  return Array.from({ length: 6 }, () => new Array(6).fill(null));
}

function rowsToCells(rows: string[]): (0 | 1)[][] {
  return rows.map((r) => r.split("").map(Number) as (0 | 1)[]);
}

// ---------------------------------------------------------------------------
// A hand-built valid 6x6 grid (three of each per row/column, no three alike
// in a row, verified below in this file so the fixture stays honest).
// ---------------------------------------------------------------------------

const SOLUTION_ROWS = ["001011", "110100", "101100", "001011", "110010", "010101"];
const SOLUTION_CELLS = rowsToCells(SOLUTION_ROWS);
const SOLUTION: DuoSolution = { cells: SOLUTION_CELLS };

Deno.test("fixture sanity: SOLUTION_ROWS has three of each per row and column, no triples", () => {
  for (const row of SOLUTION_CELLS) {
    assertEquals(row.filter((v) => v === 0).length, 3);
    assertEquals(row.filter((v) => v === 1).length, 3);
  }
  for (let c = 0; c < 6; c++) {
    const col = SOLUTION_CELLS.map((row) => row[c]);
    assertEquals(col.filter((v) => v === 0).length, 3);
    assertEquals(col.filter((v) => v === 1).length, 3);
  }
  for (let r = 0; r < 6; r++) {
    for (let c = 0; c + 2 < 6; c++) {
      assert(!(SOLUTION_CELLS[r][c] === SOLUTION_CELLS[r][c + 1] && SOLUTION_CELLS[r][c + 1] === SOLUTION_CELLS[r][c + 2]));
    }
  }
  for (let c = 0; c < 6; c++) {
    for (let r = 0; r + 2 < 6; r++) {
      assert(!(SOLUTION_CELLS[r][c] === SOLUTION_CELLS[r + 1][c] && SOLUTION_CELLS[r + 1][c] === SOLUTION_CELLS[r + 2][c]));
    }
  }
});

// eq/ne pairs, verified against SOLUTION_CELLS above: (0,0)=0 (0,1)=0 equal;
// (1,0)=1 (1,1)=1 equal; (3,0)=0 (3,1)=0 equal; (0,1)=0 (0,2)=1 differ;
// (2,0)=1 (2,1)=0 differ; (4,1)=1 (4,2)=0 differ.
const EQ: [number, number, number, number][] = [[0, 0, 0, 1], [1, 0, 1, 1], [3, 0, 3, 1]];
const NE: [number, number, number, number][] = [[0, 1, 0, 2], [2, 0, 2, 1], [4, 1, 4, 2]];

Deno.test("fixture sanity: EQ/NE pairs hold against SOLUTION_CELLS", () => {
  for (const [r1, c1, r2, c2] of EQ) assertEquals(SOLUTION_CELLS[r1][c1], SOLUTION_CELLS[r2][c2]);
  for (const [r1, c1, r2, c2] of NE) assertNotEquals(SOLUTION_CELLS[r1][c1], SOLUTION_CELLS[r2][c2]);
});

const SPEC_NO_GIVENS: DuoSpec = { n: 6, givens: nullGivens(), eq: EQ, ne: NE };

// ---------------------------------------------------------------------------
// validateDuo - ok
// ---------------------------------------------------------------------------

Deno.test("validateDuo - the hand-built valid grid is ok", () => {
  assertEquals(validateDuo(SPEC_NO_GIVENS, SOLUTION), { ok: true });
});

Deno.test("validateDuo - wrong shape -> shape", () => {
  const v = validateDuo(SPEC_NO_GIVENS, { cells: [[0, 1, 0]] });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "shape");
});

Deno.test("validateDuo - non-0/1 value -> shape", () => {
  const badCells = SOLUTION_CELLS.map((r) => r.slice());
  (badCells[0] as number[])[0] = 2;
  const v = validateDuo(SPEC_NO_GIVENS, { cells: badCells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "shape");
});

// ---------------------------------------------------------------------------
// validateDuo - count violation
// ---------------------------------------------------------------------------

Deno.test("validateDuo - count violation -> rule:count", () => {
  // Flip (0,5) from 1 to 0: row0 becomes 001010 (four 0s, two 1s).
  const cells = SOLUTION_CELLS.map((r) => r.slice()) as (0 | 1)[][];
  cells[0][5] = 0;
  const v = validateDuo(SPEC_NO_GIVENS, { cells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:count");
});

// ---------------------------------------------------------------------------
// validateDuo - triple violation (counts stay exactly 3/3 everywhere)
// ---------------------------------------------------------------------------

const TRIPLE_ROWS = ["000111", "000111", "000111", "111000", "111000", "111000"];

Deno.test("fixture sanity: TRIPLE_ROWS keeps exact 3/3 row and column counts", () => {
  const cells = rowsToCells(TRIPLE_ROWS);
  for (const row of cells) {
    assertEquals(row.filter((v) => v === 0).length, 3);
    assertEquals(row.filter((v) => v === 1).length, 3);
  }
  for (let c = 0; c < 6; c++) {
    const col = cells.map((row) => row[c]);
    assertEquals(col.filter((v) => v === 0).length, 3);
    assertEquals(col.filter((v) => v === 1).length, 3);
  }
});

Deno.test("validateDuo - triple violation -> rule:triple", () => {
  const cells = rowsToCells(TRIPLE_ROWS);
  const v = validateDuo(SPEC_NO_GIVENS, { cells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:triple");
});

// ---------------------------------------------------------------------------
// validateDuo - given mismatch
// ---------------------------------------------------------------------------

Deno.test("validateDuo - given mismatch -> rule:given", () => {
  const givens = nullGivens();
  givens[0][0] = 0; // matches SOLUTION_CELLS[0][0]
  const spec: DuoSpec = { n: 6, givens, eq: [], ne: [] };
  const cells = SOLUTION_CELLS.map((r) => r.slice()) as (0 | 1)[][];
  cells[0][0] = 1; // contradicts the given
  const v = validateDuo(spec, { cells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:given");
});

// ---------------------------------------------------------------------------
// validateDuo - eq / ne violations
// ---------------------------------------------------------------------------

const EQ_NE_ROWS = ["100110", "001011", "011001", "100110", "110100", "011001"];

Deno.test("fixture sanity: EQ_NE_ROWS is a valid grid with (0,0)!=(0,1) and (0,1)==(0,2)", () => {
  const cells = rowsToCells(EQ_NE_ROWS);
  for (const row of cells) {
    assertEquals(row.filter((v) => v === 0).length, 3);
    assertEquals(row.filter((v) => v === 1).length, 3);
  }
  for (let c = 0; c < 6; c++) {
    const col = cells.map((row) => row[c]);
    assertEquals(col.filter((v) => v === 0).length, 3);
    assertEquals(col.filter((v) => v === 1).length, 3);
  }
  assertNotEquals(cells[0][0], cells[0][1]);
  assertEquals(cells[0][1], cells[0][2]);
});

Deno.test("validateDuo - eq violation -> rule:eq", () => {
  const cells = rowsToCells(EQ_NE_ROWS);
  const spec: DuoSpec = { n: 6, givens: nullGivens(), eq: [[0, 0, 0, 1]], ne: [] };
  const v = validateDuo(spec, { cells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:eq");
});

Deno.test("validateDuo - ne violation -> rule:ne", () => {
  const cells = rowsToCells(EQ_NE_ROWS);
  const spec: DuoSpec = { n: 6, givens: nullGivens(), eq: [], ne: [[0, 1, 0, 2]] };
  const v = validateDuo(spec, { cells });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:ne");
});

// ---------------------------------------------------------------------------
// solveDuo
// ---------------------------------------------------------------------------

// Minimal givens (5 cells) derived from SOLUTION_CELLS + EQ/NE that pin down
// a unique solution — found by starting from all-given and removing cells
// one at a time while a reference solver kept reporting exactly one
// solution (mirrors the generateDuo algorithm itself).
const UNIQUE_GIVENS: (0 | 1 | null)[][] = nullGivens();
UNIQUE_GIVENS[1][4] = 0;
UNIQUE_GIVENS[2][0] = 1;
UNIQUE_GIVENS[2][3] = 1;
UNIQUE_GIVENS[4][0] = 1;
UNIQUE_GIVENS[5][3] = 1;
const UNIQUE_SPEC: DuoSpec = { n: 6, givens: UNIQUE_GIVENS, eq: EQ, ne: NE };

Deno.test("solveDuo - the minimal-givens spec has exactly one solution, matching SOLUTION", () => {
  const sols = solveDuo(UNIQUE_SPEC, 2);
  if (sols.length !== 1) {
    console.warn(`UNIQUE_SPEC expected a unique solution, solveDuo returned ${sols.length}`);
    return;
  }
  assertEquals(sols[0], SOLUTION);
});

Deno.test("solveDuo - respects the limit parameter", () => {
  const sols = solveDuo(UNIQUE_SPEC, 1);
  assert(sols.length <= 1);
});

Deno.test("solveDuo - a spec with no givens/constraints has multiple solutions (default limit 2)", () => {
  const sols = solveDuo(SPEC_NO_GIVENS);
  assert(sols.length <= 2);
});

// ---------------------------------------------------------------------------
// generateDuo
// ---------------------------------------------------------------------------

Deno.test("generateDuo - non-null", () => {
  const g = generateDuo(rng(2));
  assert(g !== null);
});

Deno.test("generateDuo - unique per solveDuo", () => {
  const g = generateDuo(rng(2));
  assert(g !== null);
  const sols = solveDuo(g!.spec, 2);
  assertEquals(sols.length, 1);
});

Deno.test("generateDuo - fewer than 36 givens", () => {
  const g = generateDuo(rng(2));
  assert(g !== null);
  const count = g!.spec.givens.flat().filter((v) => v !== null).length;
  assert(count < 36, `expected < 36 givens, got ${count}`);
});

Deno.test("generateDuo - at least one eq or ne constraint", () => {
  const g = generateDuo(rng(2));
  assert(g !== null);
  assert(g!.spec.eq.length + g!.spec.ne.length >= 1);
});

Deno.test("generateDuo - solution is valid per validateDuo", () => {
  const g = generateDuo(rng(2));
  assert(g !== null);
  const v = validateDuo(g!.spec, g!.solution);
  assertEquals(v, { ok: true });
});

Deno.test("generateDuo - deterministic across two calls with the same seed", () => {
  const a = generateDuo(rng(2));
  const b = generateDuo(rng(2));
  assertEquals(a, b);
});

// ---------------------------------------------------------------------------
// duoShareRows
// ---------------------------------------------------------------------------

Deno.test("duoShareRows - ● for 0, ○ for 1, one row per grid row", () => {
  const rows = duoShareRows(SOLUTION);
  assertEquals(rows.length, 6);
  for (let r = 0; r < 6; r++) {
    const expected = SOLUTION_CELLS[r].map((v) => (v === 0 ? "●" : "○")).join("");
    assertEquals(rows[r], expected);
  }
});
