// games/duo.ts — Duo (Tango-style): 6×6 grid of two symbols (0 = ●, 1 = ○), three of
// each per row and column, never three alike in a row, plus = and × constraints
// between orthogonally adjacent cells. CONTRACT FILE.

import type { Validation } from "./common.ts";
import { shuffleWith } from "./common.ts";

export interface DuoSpec {
  n: 6;
  /** Given cells (locked), null where the player fills. */
  givens: (0 | 1 | null)[][];
  /** [r1, c1, r2, c2] pairs of adjacent cells that must be equal. */
  eq: [number, number, number, number][];
  /** Pairs that must differ. */
  ne: [number, number, number, number][];
}

export interface DuoSolution {
  cells: (0 | 1)[][];
}

const N = 6;
const HALF = 3;

/**
 * Shape: `{ cells }` 6×6 of 0/1 → else "shape". Givens must match ("rule:given").
 * Rules: each row and column has exactly three of each ("rule:count"), no three equal
 * consecutive horizontally or vertically ("rule:triple"), eq/ne satisfied ("rule:eq" / "rule:ne").
 */
export function validateDuo(spec: DuoSpec, answer: unknown): Validation {
  if (spec?.n !== N) return { ok: false, reason: "shape" };
  const a = answer as { cells?: unknown } | null;
  if (typeof a !== "object" || a === null) return { ok: false, reason: "shape" };
  const raw = a.cells;
  if (!Array.isArray(raw) || raw.length !== N) return { ok: false, reason: "shape" };
  const cells: (0 | 1)[][] = [];
  for (const row of raw) {
    if (!Array.isArray(row) || row.length !== N) return { ok: false, reason: "shape" };
    for (const v of row) {
      if (v !== 0 && v !== 1) return { ok: false, reason: "shape" };
    }
    cells.push(row as (0 | 1)[]);
  }

  for (let r = 0; r < N; r++) {
    for (let c = 0; c < N; c++) {
      const g = spec.givens?.[r]?.[c];
      if (g === 0 || g === 1) {
        if (cells[r][c] !== g) return { ok: false, reason: "rule:given" };
      }
    }
  }

  for (let i = 0; i < N; i++) {
    let rowOnes = 0;
    let colOnes = 0;
    for (let j = 0; j < N; j++) {
      rowOnes += cells[i][j];
      colOnes += cells[j][i];
    }
    if (rowOnes !== HALF || colOnes !== HALF) return { ok: false, reason: "rule:count" };
  }

  for (let r = 0; r < N; r++) {
    for (let c = 0; c < N; c++) {
      if (c + 2 < N && cells[r][c] === cells[r][c + 1] && cells[r][c] === cells[r][c + 2]) {
        return { ok: false, reason: "rule:triple" };
      }
      if (r + 2 < N && cells[r][c] === cells[r + 1][c] && cells[r][c] === cells[r + 2][c]) {
        return { ok: false, reason: "rule:triple" };
      }
    }
  }

  for (const [r1, c1, r2, c2] of spec.eq ?? []) {
    const x = cells[r1]?.[c1], y = cells[r2]?.[c2];
    if (x === undefined || y === undefined) return { ok: false, reason: "shape" };
    if (x !== y) return { ok: false, reason: "rule:eq" };
  }
  for (const [r1, c1, r2, c2] of spec.ne ?? []) {
    const x = cells[r1]?.[c1], y = cells[r2]?.[c2];
    if (x === undefined || y === undefined) return { ok: false, reason: "shape" };
    if (x === y) return { ok: false, reason: "rule:ne" };
  }

  return { ok: true };
}

interface PairConstraint {
  r: number;
  c: number;
  or: number;
  oc: number;
  same: boolean;
}

/** Constraints indexed by the cell they apply to (both directions). */
function constraintsByCell(spec: DuoSpec): PairConstraint[][][] {
  const byCell: PairConstraint[][][] = [];
  for (let r = 0; r < N; r++) {
    byCell.push([]);
    for (let c = 0; c < N; c++) byCell[r].push([]);
  }
  const add = (pairs: [number, number, number, number][] | undefined, same: boolean) => {
    for (const [r1, c1, r2, c2] of pairs ?? []) {
      if (byCell[r1]?.[c1] === undefined || byCell[r2]?.[c2] === undefined) continue;
      byCell[r1][c1].push({ r: r1, c: c1, or: r2, oc: c2, same });
      byCell[r2][c2].push({ r: r2, c: c2, or: r1, oc: c1, same });
    }
  };
  add(spec.eq, true);
  add(spec.ne, false);
  return byCell;
}

/** Backtracking solver with the rules as pruning; up to `limit` solutions (default 2). */
export function solveDuo(spec: DuoSpec, limit = 2): DuoSolution[] {
  return solveDuoOrdered(spec, limit, null);
}

/**
 * Shared engine: fills cells in row-major order. When `rand` is provided the two candidate
 * values are tried in a random order (used to build a random full grid).
 */
function solveDuoOrdered(spec: DuoSpec, limit: number, rand: (() => number) | null): DuoSolution[] {
  const solutions: DuoSolution[] = [];
  if (limit <= 0) return solutions;

  const grid: number[][] = [];
  for (let r = 0; r < N; r++) grid.push(new Array(N).fill(-1));
  const rowCount = [new Int8Array(N), new Int8Array(N)]; // rowCount[v][r]
  const colCount = [new Int8Array(N), new Int8Array(N)];
  const byCell = constraintsByCell(spec);

  const fits = (r: number, c: number, v: number): boolean => {
    if (rowCount[v][r] + 1 > HALF) return false;
    if (colCount[v][c] + 1 > HALF) return false;
    // No three alike horizontally / vertically among already-placed cells.
    if (c >= 2 && grid[r][c - 1] === v && grid[r][c - 2] === v) return false;
    if (r >= 2 && grid[r - 1][c] === v && grid[r - 2][c] === v) return false;
    for (const k of byCell[r][c]) {
      const other = grid[k.or]?.[k.oc];
      if (other === undefined || other === -1) continue;
      if (k.same ? other !== v : other === v) return false;
    }
    return true;
  };

  const step = (idx: number): void => {
    if (solutions.length >= limit) return;
    if (idx === N * N) {
      solutions.push({ cells: grid.map((row) => row.slice() as (0 | 1)[]) });
      return;
    }
    const r = Math.floor(idx / N);
    const c = idx % N;
    const given = spec.givens?.[r]?.[c];
    let candidates: number[] = given === 0 || given === 1 ? [given] : [0, 1];
    if (rand !== null && candidates.length === 2 && rand() < 0.5) candidates = [1, 0];

    for (const v of candidates) {
      if (!fits(r, c, v)) continue;
      grid[r][c] = v;
      rowCount[v][r]++;
      colCount[v][c]++;
      step(idx + 1);
      rowCount[v][r]--;
      colCount[v][c]--;
      grid[r][c] = -1;
      if (solutions.length >= limit) return;
    }
  };

  step(0);
  return solutions;
}

const EMPTY_SPEC: DuoSpec = {
  n: 6,
  givens: Array.from({ length: N }, () => new Array(N).fill(null) as (0 | 1 | null)[]),
  eq: [],
  ne: [],
};

function adjacentPairs(): [number, number, number, number][] {
  const pairs: [number, number, number, number][] = [];
  for (let r = 0; r < N; r++) {
    for (let c = 0; c < N; c++) {
      if (c + 1 < N) pairs.push([r, c, r, c + 1]);
      if (r + 1 < N) pairs.push([r, c, r + 1, c]);
    }
  }
  return pairs;
}

/**
 * Generates a unique-solution puzzle:
 * 1. Build a full valid grid by randomised backtracking.
 * 2. Pick 3–6 adjacent pairs at random: those with equal cells become `eq`, others `ne`
 *    (at least one of each when possible).
 * 3. Start with all cells given; remove givens one at a time in random order while
 *    `solveDuo(spec, 2)` still yields exactly one solution; stop when no further removal keeps uniqueness.
 * Returns null after 100 failed grid builds (should not happen).
 */
export function generateDuo(rand: () => number): { spec: DuoSpec; solution: DuoSolution } | null {
  for (let build = 0; build < 100; build++) {
    const full = solveDuoOrdered(EMPTY_SPEC, 1, rand);
    if (full.length === 0) continue;
    const cells = full[0].cells;

    const shuffled = shuffleWith(adjacentPairs(), rand);
    const count = 3 + Math.floor(rand() * 4); // 3..6
    const chosen = shuffled.slice(0, count);
    const isEq = (p: [number, number, number, number]) => cells[p[0]][p[1]] === cells[p[2]][p[3]];

    // Ensure at least one of each kind when the grid allows it.
    if (!chosen.some(isEq)) {
      const swap = shuffled.slice(count).find(isEq);
      if (swap) chosen[chosen.length - 1] = swap;
    }
    if (chosen.every(isEq)) {
      const swap = shuffled.slice(count).find((p) => !isEq(p));
      if (swap) chosen[0] = swap;
    }

    const eq = chosen.filter(isEq);
    const ne = chosen.filter((p) => !isEq(p));

    const givens: (0 | 1 | null)[][] = cells.map((row) => row.slice() as (0 | 1 | null)[]);
    const spec: DuoSpec = { n: 6, givens, eq, ne };

    const order = shuffleWith(
      Array.from({ length: N * N }, (_unused, i) => i),
      rand,
    );
    for (const idx of order) {
      const r = Math.floor(idx / N);
      const c = idx % N;
      const kept = givens[r][c];
      givens[r][c] = null;
      if (solveDuo(spec, 2).length !== 1) givens[r][c] = kept;
    }

    if (solveDuo(spec, 2).length === 1) {
      return { spec, solution: { cells } };
    }
  }
  return null;
}

/** One string per row: ● for 0, ○ for 1. */
export function duoShareRows(solution: DuoSolution): string[] {
  return solution.cells.map((row) => row.map((v) => (v === 0 ? "●" : "○")).join(""));
}
