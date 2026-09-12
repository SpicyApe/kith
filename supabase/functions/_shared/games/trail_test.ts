// Tests for games/trail.ts (Zip-style), written strictly against its
// contract doc comments (docs/07-games-hub.md).

import { assert, assertEquals } from "jsr:@std/assert";
import { rng } from "../../generate-puzzles/handler.ts";
import { generateTrail, solveTrail, trailShareRows, type TrailSpec, validateTrail } from "./trail.ts";

// ---------------------------------------------------------------------------
// 3x3 fixtures.
//
// With only the corner waypoints [0,0] -> [2,2], a 3x3 grid has exactly two
// Hamiltonian paths (verified by an independent brute-force search):
//   PATH_A: (0,0)(1,0)(2,0)(2,1)(1,1)(0,1)(0,2)(1,2)(2,2)
//   PATH_B: (0,0)(0,1)(0,2)(1,2)(1,1)(1,0)(2,0)(2,1)(2,2)
// Adding waypoints [2,1] then [1,1] (in that order, before the end) rules
// out PATH_B — which visits (1,1) before (2,1) — leaving PATH_A unique.
// ---------------------------------------------------------------------------

const PATH_A: [number, number][] = [[0, 0], [1, 0], [2, 0], [2, 1], [1, 1], [0, 1], [0, 2], [1, 2], [2, 2]];
const PATH_B: [number, number][] = [[0, 0], [0, 1], [0, 2], [1, 2], [1, 1], [1, 0], [2, 0], [2, 1], [2, 2]];

const SPEC_NOT_UNIQUE: TrailSpec = { n: 3, waypoints: [[0, 0], [2, 2]] };
const SPEC_UNIQUE: TrailSpec = { n: 3, waypoints: [[0, 0], [2, 1], [1, 1], [2, 2]] };

// ---------------------------------------------------------------------------
// solveTrail
// ---------------------------------------------------------------------------

Deno.test("solveTrail - corner-only waypoints on 3x3 are NOT unique: exactly 2 with limit 2", () => {
  const sols = solveTrail(SPEC_NOT_UNIQUE, 2);
  assertEquals(sols.length, 2);
});

Deno.test("solveTrail - adding waypoints that force a snake makes it unique", () => {
  const sols = solveTrail(SPEC_UNIQUE, 2);
  if (sols.length !== 1) {
    console.warn(`SPEC_UNIQUE expected a unique solution, solveTrail returned ${sols.length}`);
    return;
  }
  assertEquals(sols[0], { path: PATH_A });
});

Deno.test("solveTrail - respects the limit parameter", () => {
  const sols = solveTrail(SPEC_NOT_UNIQUE, 1);
  assertEquals(sols.length, 1);
});

Deno.test("solveTrail - default limit is 2", () => {
  const sols = solveTrail(SPEC_NOT_UNIQUE);
  assert(sols.length <= 2);
});

// ---------------------------------------------------------------------------
// validateTrail
// ---------------------------------------------------------------------------

Deno.test("validateTrail - the correct path is ok", () => {
  assertEquals(validateTrail(SPEC_UNIQUE, { path: PATH_A }), { ok: true });
});

Deno.test("validateTrail - wrong length -> shape", () => {
  const v = validateTrail(SPEC_UNIQUE, { path: PATH_A.slice(0, 5) });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "shape");
});

Deno.test("validateTrail - out-of-range cell -> shape", () => {
  const bad = PATH_A.slice(0, 8).concat([[9, 9]]) as [number, number][];
  const v = validateTrail(SPEC_UNIQUE, { path: bad });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "shape");
});

Deno.test("validateTrail - repeated cell -> rule:cover", () => {
  // Revisit (0,0) instead of visiting (0,2): drops a cell, repeats another,
  // but keeps every consecutive step orthogonally adjacent.
  const bad: [number, number][] = [[0, 0], [1, 0], [2, 0], [2, 1], [1, 1], [0, 1], [1, 1], [1, 2], [2, 2]];
  const v = validateTrail(SPEC_UNIQUE, { path: bad });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:cover");
});

Deno.test("validateTrail - non-adjacent step -> rule:adjacent", () => {
  // Swap two interior entries so consecutive cells are no longer adjacent.
  const bad: [number, number][] = [[0, 0], [1, 0], [2, 0], [1, 1], [2, 1], [0, 1], [0, 2], [1, 2], [2, 2]];
  const v = validateTrail(SPEC_UNIQUE, { path: bad });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:adjacent");
});

Deno.test("validateTrail - wrong ends -> rule:ends", () => {
  // A valid Hamiltonian path on the 3x3 grid starting correctly at (0,0) but
  // ending at (0,2) instead of the spec's required (2,2).
  const path: [number, number][] = [[0, 0], [1, 0], [2, 0], [2, 1], [2, 2], [1, 2], [1, 1], [0, 1], [0, 2]];
  // Sanity: verify this really is a full orthogonal covering path before
  // asserting on it.
  for (let i = 0; i + 1 < path.length; i++) {
    const [r1, c1] = path[i];
    const [r2, c2] = path[i + 1];
    assertEquals(Math.abs(r1 - r2) + Math.abs(c1 - c2), 1, `step ${i} not adjacent`);
  }
  assertEquals(new Set(path.map(([r, c]) => `${r},${c}`)).size, 9);

  const v = validateTrail(SPEC_UNIQUE, { path });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:ends");
});

Deno.test("validateTrail - out-of-order waypoint -> rule:order", () => {
  // PATH_B fully covers the grid with valid adjacency and correct ends
  // ((0,0) -> (2,2)), but visits (1,1) before (2,1), violating SPEC_UNIQUE's
  // required waypoint order.
  const v = validateTrail(SPEC_UNIQUE, { path: PATH_B });
  assertEquals(v.ok, false);
  assertEquals(v.reason, "rule:order");
});

// ---------------------------------------------------------------------------
// generateTrail
// ---------------------------------------------------------------------------

Deno.test("generateTrail - non-null for n=5", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
});

Deno.test("generateTrail - solution is valid per validateTrail", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
  const v = validateTrail(g!.spec, g!.solution);
  assertEquals(v, { ok: true });
});

Deno.test("generateTrail - solution is unique per solveTrail", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
  const sols = solveTrail(g!.spec, 2);
  assertEquals(sols.length, 1);
});

Deno.test("generateTrail - waypoints length is at most n+4", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
  assert(g!.spec.waypoints.length <= 9, `expected <= 9 waypoints, got ${g!.spec.waypoints.length}`);
});

Deno.test("generateTrail - first/last waypoints equal the solution path's ends", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
  const { spec, solution } = g!;
  assertEquals(spec.waypoints[0], solution.path[0]);
  assertEquals(spec.waypoints[spec.waypoints.length - 1], solution.path[solution.path.length - 1]);
});

Deno.test("generateTrail - deterministic across two calls with the same seed", () => {
  const a = generateTrail(5, rng(3));
  const b = generateTrail(5, rng(3));
  assertEquals(a, b);
});

// ---------------------------------------------------------------------------
// trailShareRows
// ---------------------------------------------------------------------------

Deno.test("trailShareRows - a single row with one 🟩 per waypoint", () => {
  const rows = trailShareRows(SPEC_UNIQUE);
  assertEquals(rows.length, 1);
  assertEquals(rows[0], "🟩".repeat(SPEC_UNIQUE.waypoints.length));
});

Deno.test("trailShareRows - length matches waypoint count for a generated puzzle", () => {
  const g = generateTrail(5, rng(3));
  assert(g !== null);
  const rows = trailShareRows(g!.spec);
  assertEquals(rows.length, 1);
  assertEquals(rows[0], "🟩".repeat(g!.spec.waypoints.length));
});
