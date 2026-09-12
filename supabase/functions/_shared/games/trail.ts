// games/trail.ts — Trail (Zip-style): one continuous orthogonal path through every cell
// exactly once, visiting numbered waypoints in order, starting at 1 and ending at the
// last. CONTRACT FILE.

import type { Validation } from "./common.ts";
import { shuffleWith } from "./common.ts";

export interface TrailSpec {
  n: number;
  /** waypoints[i] = [row, col] of waypoint number i+1; the first is the path start, the last its end. */
  waypoints: [number, number][];
}

export interface TrailSolution {
  /** n² cells in visiting order, each [row, col]. */
  path: [number, number][];
}

const DR = [-1, 1, 0, 0];
const DC = [0, 0, -1, 1];

function isIntIn(v: unknown, lo: number, hi: number): boolean {
  return typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
}

/**
 * Shape: `{ path }` with exactly n² entries of in-range integer pairs → else "shape".
 * Rules: every cell exactly once ("rule:cover"), consecutive entries orthogonally adjacent
 * ("rule:adjacent"), path starts at waypoint 1 and ends at the last ("rule:ends"),
 * waypoints visited in ascending order ("rule:order").
 */
export function validateTrail(spec: TrailSpec, answer: unknown): Validation {
  const a = answer as { path?: unknown } | null;
  if (typeof a !== "object" || a === null) return { ok: false, reason: "shape" };
  const raw = a.path;
  const n = spec.n;
  if (!Array.isArray(raw) || raw.length !== n * n) return { ok: false, reason: "shape" };
  const path: [number, number][] = [];
  for (const entry of raw) {
    if (!Array.isArray(entry) || entry.length !== 2) return { ok: false, reason: "shape" };
    if (!isIntIn(entry[0], 0, n - 1) || !isIntIn(entry[1], 0, n - 1)) return { ok: false, reason: "shape" };
    path.push([entry[0] as number, entry[1] as number]);
  }

  const seen = new Set<number>();
  for (const [r, c] of path) {
    const key = r * n + c;
    if (seen.has(key)) return { ok: false, reason: "rule:cover" };
    seen.add(key);
  }
  if (seen.size !== n * n) return { ok: false, reason: "rule:cover" };

  for (let i = 0; i + 1 < path.length; i++) {
    const d = Math.abs(path[i][0] - path[i + 1][0]) + Math.abs(path[i][1] - path[i + 1][1]);
    if (d !== 1) return { ok: false, reason: "rule:adjacent" };
  }

  const wps = spec.waypoints ?? [];
  if (wps.length > 0) {
    const first = wps[0];
    const last = wps[wps.length - 1];
    if (path[0][0] !== first[0] || path[0][1] !== first[1]) return { ok: false, reason: "rule:ends" };
    const end = path[path.length - 1];
    if (end[0] !== last[0] || end[1] !== last[1]) return { ok: false, reason: "rule:ends" };

    const indexOf = new Map<number, number>();
    for (let i = 0; i < path.length; i++) indexOf.set(path[i][0] * n + path[i][1], i);
    let prev = -1;
    for (const [r, c] of wps) {
      const at = indexOf.get(r * n + c);
      if (at === undefined) return { ok: false, reason: "rule:order" };
      if (at <= prev) return { ok: false, reason: "rule:order" };
      prev = at;
    }
  }

  return { ok: true };
}

/**
 * DFS Hamiltonian-path solver from waypoint 1 with pruning (next required waypoint must
 * still be reachable; a dead-end cell count check), returning up to `limit` solutions
 * (default 2). n ≤ 7 in practice.
 */
export function solveTrail(spec: TrailSpec, limit = 2): TrailSolution[] {
  const n = spec.n;
  const solutions: TrailSolution[] = [];
  const wps = spec.waypoints ?? [];
  if (!Number.isInteger(n) || n <= 0 || limit <= 0 || wps.length === 0) return solutions;

  const total = n * n;
  const cells = total;
  // waypointAt[cell] = 1-based waypoint index, or 0.
  const waypointAt = new Int8Array(cells);
  for (let i = 0; i < wps.length; i++) {
    const [r, c] = wps[i];
    if (!isIntIn(r, 0, n - 1) || !isIntIn(c, 0, n - 1)) return solutions;
    waypointAt[r * n + c] = i + 1;
  }
  const startCell = wps[0][0] * n + wps[0][1];
  const endCell = wps[wps.length - 1][0] * n + wps[wps.length - 1][1];
  if (startCell === endCell && wps.length > 1) return solutions;

  // Precomputed neighbour lists.
  const neighbours: number[][] = [];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      const list: number[] = [];
      for (let d = 0; d < 4; d++) {
        const nr = r + DR[d];
        const nc = c + DC[d];
        if (nr >= 0 && nr < n && nc >= 0 && nc < n) list.push(nr * n + nc);
      }
      neighbours.push(list);
    }
  }

  const visited = new Uint8Array(cells);
  const path = new Int32Array(cells);
  const stack = new Int32Array(cells);
  let floodMark = 0;
  const floodSeen = new Int32Array(cells);

  /**
   * True when the remaining unvisited cells are all reachable from `current`, no unvisited
   * cell is already cut off, and at most one unvisited cell is a forced dead end (which must
   * be the final waypoint).
   */
  const feasible = (current: number, remaining: number): boolean => {
    // Degree check over unvisited cells.
    let deadEnds = 0;
    for (let cell = 0; cell < cells; cell++) {
      if (visited[cell]) continue;
      let deg = 0;
      for (const nb of neighbours[cell]) {
        if (!visited[nb] || nb === current) deg++;
      }
      if (deg === 0) return false;
      if (deg === 1) {
        if (cell !== endCell) return false;
        deadEnds++;
        if (deadEnds > 1) return false;
      }
    }

    // Connectivity: every unvisited cell must be reachable from `current` through unvisited cells.
    floodMark++;
    let head = 0;
    let tail = 0;
    stack[tail++] = current;
    floodSeen[current] = floodMark;
    let reached = 0;
    while (head < tail) {
      const cell = stack[head++];
      for (const nb of neighbours[cell]) {
        if (visited[nb] || floodSeen[nb] === floodMark) continue;
        floodSeen[nb] = floodMark;
        reached++;
        stack[tail++] = nb;
      }
    }
    return reached === remaining;
  };

  const step = (depth: number, current: number, nextWaypoint: number): void => {
    if (solutions.length >= limit) return;
    if (depth === total) {
      if (nextWaypoint > wps.length && current === endCell) {
        const out: [number, number][] = [];
        for (let i = 0; i < total; i++) out.push([Math.floor(path[i] / n), path[i] % n]);
        solutions.push({ path: out });
      }
      return;
    }

    const remaining = total - depth;
    if (!feasible(current, remaining)) return;

    for (const nb of neighbours[current]) {
      if (visited[nb]) continue;
      const w = waypointAt[nb];
      if (w !== 0 && w !== nextWaypoint) continue; // a later waypoint reached too early
      // The last cell of the path must be the final waypoint.
      if (depth + 1 === total && nb !== endCell) continue;
      if (nb === endCell && depth + 1 !== total) continue;

      visited[nb] = 1;
      path[depth] = nb;
      step(depth + 1, nb, w !== 0 ? nextWaypoint + 1 : nextWaypoint);
      visited[nb] = 0;
      if (solutions.length >= limit) return;
    }
  };

  visited[startCell] = 1;
  path[0] = startCell;
  step(1, startCell, 2);
  visited[startCell] = 0;
  return solutions;
}

/** Randomised Hamiltonian path on the n×n grid via DFS with Warnsdorff ordering. */
function randomHamiltonianPath(n: number, rand: () => number): number[] | null {
  const cells = n * n;
  const neighbours: number[][] = [];
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      const list: number[] = [];
      for (let d = 0; d < 4; d++) {
        const nr = r + DR[d];
        const nc = c + DC[d];
        if (nr >= 0 && nr < n && nc >= 0 && nc < n) list.push(nr * n + nc);
      }
      neighbours.push(list);
    }
  }

  const visited = new Uint8Array(cells);
  const path: number[] = [];
  let budget = 200_000;

  const degreeOf = (cell: number): number => {
    let d = 0;
    for (const nb of neighbours[cell]) if (!visited[nb]) d++;
    return d;
  };

  const step = (current: number): boolean => {
    if (path.length === cells) return true;
    if (budget-- <= 0) return false;
    const options = shuffleWith(neighbours[current].filter((nb) => !visited[nb]), rand)
      .map((nb) => ({ nb, deg: degreeOf(nb) }))
      .sort((a, b) => a.deg - b.deg);
    for (const { nb } of options) {
      visited[nb] = 1;
      path.push(nb);
      if (step(nb)) return true;
      path.pop();
      visited[nb] = 0;
      if (budget <= 0) return false;
    }
    return false;
  };

  const start = Math.floor(rand() * cells);
  visited[start] = 1;
  path.push(start);
  if (step(start)) return path.slice();
  return null;
}

/**
 * Generates a unique-solution puzzle:
 * 1. Build a random Hamiltonian path on the n×n grid: randomised DFS with Warnsdorff
 *    ordering (prefer neighbours with fewer onward options), restarting on dead ends.
 * 2. Waypoints: start and end cells, then add path cells at random positions one at a time
 *    (keeping them sorted by path index) until `solveTrail(spec, 2)` yields exactly one
 *    solution. Cap at n + 4 waypoints; if still not unique, restart from step 1.
 * Up to 200 path builds; returns null if none succeeds.
 */
export function generateTrail(n: number, rand: () => number): { spec: TrailSpec; solution: TrailSolution } | null {
  const total = n * n;
  const maxWaypoints = n + 4;

  for (let build = 0; build < 200; build++) {
    const cellPath = randomHamiltonianPath(n, rand);
    if (cellPath === null) continue;

    const toRC = (cell: number): [number, number] => [Math.floor(cell / n), cell % n];
    const solution: TrailSolution = { path: cellPath.map(toRC) };

    // Waypoint path-indices, always sorted; 0 and total-1 are fixed.
    const chosen: number[] = [0, total - 1];

    for (;;) {
      const spec: TrailSpec = { n, waypoints: chosen.map((i) => toRC(cellPath[i])) };
      const found = solveTrail(spec, 2);
      if (found.length === 1) return { spec, solution };
      if (found.length === 0) break;
      if (chosen.length >= maxWaypoints) break;

      const alt = found.find((s) => s.path.some(([r, c], i) => r !== solution.path[i][0] || c !== solution.path[i][1]));
      if (alt === undefined) break;

      // Where the alternative visits each cell.
      const altIndex = new Int32Array(total);
      for (let i = 0; i < total; i++) altIndex[alt.path[i][0] * n + alt.path[i][1]] = i;

      // A new waypoint only helps when it puts the waypoint sequence out of order for `alt`.
      const chosenSet = new Set(chosen);
      const useful: number[] = [];
      for (let i = 1; i < total - 1; i++) {
        if (chosenSet.has(i)) continue;
        const candidate = chosen.concat(i).sort((a, b) => a - b);
        let breaks = false;
        for (let k = 0; k + 1 < candidate.length; k++) {
          if (altIndex[cellPath[candidate[k]]] >= altIndex[cellPath[candidate[k + 1]]]) {
            breaks = true;
            break;
          }
        }
        if (breaks) useful.push(i);
      }
      // Early on (few waypoints) no single addition can contradict `alt` on its own, so fall
      // back to a random path cell — which still constrains the search for the next round.
      const pool = useful.length > 0
        ? useful
        : Array.from({ length: total - 2 }, (_unused, i) => i + 1).filter((i) => !chosenSet.has(i));
      if (pool.length === 0) break;

      chosen.push(shuffleWith(pool, rand)[0]);
      chosen.sort((a, b) => a - b);
    }
  }
  return null;
}

/** A single row: 🟩 repeated once per waypoint. */
export function trailShareRows(spec: TrailSpec): string[] {
  return ["🟩".repeat(spec.waypoints?.length ?? 0)];
}
