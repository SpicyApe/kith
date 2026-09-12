// games/stars.ts — Stars (Queens-style): one star per row, column and region; stars
// never touch, including diagonally. CONTRACT FILE.

import type { Validation } from "./common.ts";
import { shuffleWith } from "./common.ts";

export interface StarsSpec {
  n: number;
  /** n×n region ids in 0..n-1; every id appears at least once and regions are 4-connected. */
  regions: number[][];
}

export interface StarsSolution {
  /** stars[row] = column of the star in that row. */
  stars: number[];
}

function isIntIn(v: unknown, lo: number, hi: number): boolean {
  return typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
}

/**
 * Shape: `answer` is `{ stars: number[] }` of length n with integers in 0..n-1 → else `{ok:false, reason:"shape"}`.
 * Rules: columns all distinct ("rule:column"), one star per region ("rule:region"),
 * no two stars in adjacent rows within one column of each other ("rule:touch").
 */
export function validateStars(spec: StarsSpec, answer: unknown): Validation {
  const a = answer as { stars?: unknown } | null;
  if (typeof a !== "object" || a === null) return { ok: false, reason: "shape" };
  const stars = a.stars;
  const n = spec.n;
  if (!Array.isArray(stars) || stars.length !== n) return { ok: false, reason: "shape" };
  for (const c of stars) {
    if (!isIntIn(c, 0, n - 1)) return { ok: false, reason: "shape" };
  }
  const cols = stars as number[];

  const seenCol = new Set<number>();
  for (const c of cols) {
    if (seenCol.has(c)) return { ok: false, reason: "rule:column" };
    seenCol.add(c);
  }

  const seenRegion = new Set<number>();
  for (let r = 0; r < n; r++) {
    const region = spec.regions[r]?.[cols[r]];
    if (typeof region !== "number") return { ok: false, reason: "shape" };
    if (seenRegion.has(region)) return { ok: false, reason: "rule:region" };
    seenRegion.add(region);
  }
  if (seenRegion.size !== n) return { ok: false, reason: "rule:region" };

  for (let r = 0; r + 1 < n; r++) {
    if (Math.abs(cols[r] - cols[r + 1]) <= 1) return { ok: false, reason: "rule:touch" };
  }

  return { ok: true };
}

/**
 * Backtracking solver, row by row, returning up to `limit` solutions (default 2, which is
 * enough to prove uniqueness). Pure and deterministic.
 */
export function solveStars(spec: StarsSpec, limit = 2): StarsSolution[] {
  const n = spec.n;
  const solutions: StarsSolution[] = [];
  if (!Number.isInteger(n) || n <= 0 || limit <= 0) return solutions;

  const usedCol = new Uint8Array(n);
  const usedRegion = new Map<number, boolean>();
  const cols: number[] = new Array(n).fill(-1);

  const place = (row: number): void => {
    if (solutions.length >= limit) return;
    if (row === n) {
      solutions.push({ stars: cols.slice() });
      return;
    }
    const rowRegions = spec.regions[row] ?? [];
    for (let c = 0; c < n; c++) {
      if (usedCol[c]) continue;
      if (row > 0 && Math.abs(cols[row - 1] - c) <= 1) continue;
      const region = rowRegions[c];
      if (usedRegion.get(region)) continue;
      usedCol[c] = 1;
      usedRegion.set(region, true);
      cols[row] = c;
      place(row + 1);
      cols[row] = -1;
      usedRegion.set(region, false);
      usedCol[c] = 0;
      if (solutions.length >= limit) return;
    }
  };

  place(0);
  return solutions;
}

/** A random permutation of columns where no two consecutive rows are within 1 of each other. */
function placeStars(n: number, rand: () => number): number[] | null {
  const base: number[] = [];
  for (let i = 0; i < n; i++) base.push(i);
  for (let tries = 0; tries < 2000; tries++) {
    const p = shuffleWith(base, rand);
    let ok = true;
    for (let r = 0; r + 1 < n; r++) {
      if (Math.abs(p[r] - p[r + 1]) <= 1) {
        ok = false;
        break;
      }
    }
    if (ok) return p;
  }
  return null;
}

/** Grow n connected regions outward from the star cells until the grid is covered. */
function growRegions(n: number, cols: number[], rand: () => number): number[][] {
  const regions: number[][] = [];
  for (let r = 0; r < n; r++) regions.push(new Array(n).fill(-1));

  // Region i is seeded at the star of row i.
  const frontier: { r: number; c: number }[][] = [];
  for (let i = 0; i < n; i++) {
    regions[i][cols[i]] = i;
    frontier.push([{ r: i, c: cols[i] }]);
  }

  let remaining = n * n - n;
  const dr = [-1, 1, 0, 0];
  const dc = [0, 0, -1, 1];

  while (remaining > 0) {
    // Regions that still have an unassigned neighbour.
    const live: number[] = [];
    for (let i = 0; i < n; i++) {
      const cells = frontier[i];
      let has = false;
      for (const cell of cells) {
        for (let d = 0; d < 4; d++) {
          const nr = cell.r + dr[d];
          const nc = cell.c + dc[d];
          if (nr >= 0 && nr < n && nc >= 0 && nc < n && regions[nr][nc] === -1) {
            has = true;
            break;
          }
        }
        if (has) break;
      }
      if (has) live.push(i);
    }
    if (live.length === 0) break; // unreachable on a connected grid
    const i = live[Math.floor(rand() * live.length)];

    const options: { r: number; c: number }[] = [];
    for (const cell of frontier[i]) {
      for (let d = 0; d < 4; d++) {
        const nr = cell.r + dr[d];
        const nc = cell.c + dc[d];
        if (nr >= 0 && nr < n && nc >= 0 && nc < n && regions[nr][nc] === -1) {
          options.push({ r: nr, c: nc });
        }
      }
    }
    const pick = options[Math.floor(rand() * options.length)];
    regions[pick.r][pick.c] = i;
    frontier[i].push(pick);
    remaining--;
  }

  return regions;
}

/** True when region `g` stays 4-connected (and non-empty) after removing (exR, exC). */
function connectedWithout(regions: number[][], n: number, g: number, exR: number, exC: number): boolean {
  const members: number[] = [];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (regions[r][c] === g && !(r === exR && c === exC)) members.push(r * n + c);
    }
  }
  if (members.length === 0) return false;
  const set = new Set(members);
  const seen = new Set<number>([members[0]]);
  const stack = [members[0]];
  const dr = [-1, 1, 0, 0];
  const dc = [0, 0, -1, 1];
  while (stack.length > 0) {
    const cur = stack.pop()!;
    const r = Math.floor(cur / n);
    const c = cur % n;
    for (let d = 0; d < 4; d++) {
      const nr = r + dr[d];
      const nc = c + dc[d];
      const key = nr * n + nc;
      if (nr >= 0 && nr < n && nc >= 0 && nc < n && set.has(key) && !seen.has(key)) {
        seen.add(key);
        stack.push(key);
      }
    }
  }
  return seen.size === members.length;
}

/**
 * Sharpens a grown region map until the intended placement is the only solution: while the
 * solver finds an alternative, move one cell carrying an alternative star into an adjacent
 * region (keeping every region connected and its own intended star), which invalidates that
 * alternative without touching the intended one. Returns true when the map became unique.
 * Mutates `regions`.
 */
function sharpenRegions(n: number, cols: number[], regions: number[][], rand: () => number): boolean {
  const dr = [-1, 1, 0, 0];
  const dc = [0, 0, -1, 1];
  for (let iter = 0; iter < 300; iter++) {
    const sols = solveStars({ n, regions }, 2);
    if (sols.length === 1) return true;
    if (sols.length === 0) return false;
    const alt = sols.find((s) => s.stars.some((v, i) => v !== cols[i]));
    if (alt === undefined) return false;

    const altRegions = new Set(alt.stars.map((c, r) => regions[r][c]));
    const rows = shuffleWith(
      alt.stars.map((_unused, i) => i).filter((i) => alt.stars[i] !== cols[i]),
      rand,
    );

    let moved = false;
    for (const r of rows) {
      const c = alt.stars[r];
      const g0 = regions[r][c];
      const neighbourRegions: number[] = [];
      for (let d = 0; d < 4; d++) {
        const nr = r + dr[d];
        const nc = c + dc[d];
        if (nr >= 0 && nr < n && nc >= 0 && nc < n && regions[nr][nc] !== g0) {
          neighbourRegions.push(regions[nr][nc]);
        }
      }
      if (neighbourRegions.length === 0) continue;
      if (!connectedWithout(regions, n, g0, r, c)) continue;

      // Prefer a region that already holds another of the alternative's stars: the move then
      // makes that alternative violate the one-star-per-region rule outright.
      const preferred = shuffleWith(neighbourRegions.filter((g) => altRegions.has(g)), rand);
      const fallback = shuffleWith(neighbourRegions.filter((g) => !altRegions.has(g)), rand);
      regions[r][c] = preferred.length > 0 ? preferred[0] : fallback[0];
      moved = true;
      break;
    }
    if (!moved) return false;
  }
  return solveStars({ n, regions }, 2).length === 1;
}

/**
 * Generates a puzzle with a unique solution:
 * 1. Place stars: a random permutation of columns per row rejected until no two consecutive
 *    rows have columns within 1 of each other (rejection sampling with `rand`).
 * 2. Grow n regions from the n star cells by repeatedly adding a random unassigned
 *    4-neighbour of a random region until the grid is covered (each region is connected and
 *    contains exactly its own star).
 * 3. If `solveStars(spec, 2)` returns exactly one solution, return it; otherwise retry from step 1.
 * Up to 500 attempts; returns null if none succeeds. `rand` is a `() => number` in [0, 1).
 *
 * Implementation note: a freshly grown region map is essentially never unique on its own
 * (measured: 0 in 3000 for n = 7), so between steps 2 and 3 the map is sharpened by
 * `sharpenRegions`, which only moves non-star cells between adjacent regions and therefore
 * preserves every property step 2 establishes (connected regions, one intended star each).
 */
export function generateStars(n: number, rand: () => number): { spec: StarsSpec; solution: StarsSolution } | null {
  for (let attempt = 0; attempt < 500; attempt++) {
    const cols = placeStars(n, rand);
    if (cols === null) return null;
    const regions = growRegions(n, cols, rand);
    let covered = true;
    for (let r = 0; r < n && covered; r++) {
      for (let c = 0; c < n; c++) {
        if (regions[r][c] === -1) {
          covered = false;
          break;
        }
      }
    }
    if (!covered) continue;

    if (!sharpenRegions(n, cols, regions, rand)) continue;

    const spec: StarsSpec = { n, regions };
    const solutions = solveStars(spec, 2);
    if (solutions.length === 1) {
      return { spec, solution: { stars: cols } };
    }
  }
  return null;
}

/** One string per row: ⭐️ at the star's column, ⬛️ elsewhere. */
export function starsShareRows(spec: StarsSpec, solution: StarsSolution): string[] {
  const rows: string[] = [];
  for (let r = 0; r < spec.n; r++) {
    let line = "";
    for (let c = 0; c < spec.n; c++) {
      line += solution.stars[r] === c ? "⭐️" : "⬛️";
    }
    rows.push(line);
  }
  return rows;
}
