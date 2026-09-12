# Kith — Games Hub: Stars, Duo, Trail

Adds a daily games hub alongside Lineup, modelled on the LinkedIn Games experience
but with original implementations, names, and art. Mechanics are not protectable;
LinkedIn's names (Queens, Tango, Zip), icons, and copy are, so none of them appear here.

## Product rules

- Every day has four games: **Lineup** (existing), **Stars**, **Duo**, **Trail**. Play any or all.
- The Today tab becomes the hub: a list of today's games with status (unplayed / solved
  in m:ss / gave up), streak, countdown to the next day. Tapping a game opens it.
- **Scoring** for the grid games is time-based, one attempt, no partial credit:
  `score = max(100, 1000 − 2 × min(elapsed_seconds, 450))`; giving up (revealing the
  solution) scores 100. Mistakes are shown on the results screen but do not change the score.
- **Boards**: the Friends / Circles / Everyone boards get a game picker: Lineup, Stars, Duo,
  Trail, and **Total** (sum of the four daily scores; unplayed games count 0). Week and
  All-time sum totals. Rank movement is per picker value.
- **Streak** counts a day when at least one game was played.
- **Share** text per game, same shape as Lineup:
  ```
  Kith Stars #12 · 1:23
  ⭐️⬛️⬛️⬛️⬛️⬛️⬛️⬛️
  ...one row per grid row, ⭐️ for a star, ⬛️ otherwise (Stars)
  kith.app/g/stars/12?r=7F3Q
  ```
  Duo shares the grid as ●/○ rows; Trail shares `n×n` and time only plus a 🟩 bar of
  length = waypoints. Lineup unchanged.
- **Push copy** unchanged; "friends have already played" counts any game.
- Onboarding unchanged: the first puzzle after sign-in is still Lineup.

## The three games

### Stars (Queens-style)
- `n × n` grid (7 on Mon–Tue, 8 Wed–Thu and weekends, 9 Fri) divided into `n` coloured regions.
- Place exactly one star in every row, column, and region; no two stars touch, including diagonally.
- Interaction: tap cycles empty → ✕ (note) → ★ → empty. Drag paints ✕ across cells.
- Live validation: a row/column/region with two stars, or two touching stars, highlights red.
- Complete when the placement satisfies all constraints (the puzzle has a unique solution).

### Duo (Tango-style)
- `6 × 6` grid; each cell is ● or ○. Every row and column has three of each; never three
  of the same symbol in a row horizontally or vertically. Some cells are given (locked).
  Constraints between adjacent cells: `=` (same) and `×` (different).
- Interaction: tap cycles empty → ● → ○ → empty.
- Live validation highlights violated rows/columns/constraints.
- Complete when full and valid (unique solution).

### Trail (Zip-style)
- `n × n` grid (5 Mon–Tue, 6 Wed–Thu and weekends, 7 Fri) with numbered waypoints `1…k`.
- Draw one continuous path through every cell exactly once, visiting waypoints in
  ascending order, starting at 1 and ending at k.
- Interaction: drag from the current path end into orthogonally adjacent cells; dragging
  back over the path retracts it; tapping a cell on the path retracts to it.
- Complete when the path covers all cells and the waypoint order holds (unique solution).

## Content generation

All three are procedurally generated with a uniqueness solver, nightly, 30 days ahead,
alongside Lineup, by `generate-puzzles`. No human review needed for correctness (the
solver proves a unique solution); the admin page shows them read-only with a Reseed button.
Seeds: `gameSeedFor(date, game, attempt)` so each game is independent and reseedable.

Two generator refinements were needed in practice (both in the code's doc comments):
Stars region maps grown from the star cells are essentially never unique, so a "sharpen"
step moves single non-star cells between adjacent regions until the solver reports one
solution (≈22% of attempts succeed at 7×7); Trail waypoints are added preferring cells
that contradict the current alternative path rather than at random. Measured generation
time per puzzle: Stars ≤ 84 ms, Duo ≤ 4 ms, Trail ≤ 474 ms.

## Data model

```
daily_games   date, game ('stars'|'duo'|'trail'), number, spec jsonb, solution jsonb,
              status, difficulty, seed bigint            -- pk (date, game)
game_starts   user_id, date, game, started_at            -- pk (user_id, date, game)
game_results  user_id, date, game, elapsed_ms, elapsed_source, mistakes, solved,
              gave_up, score, submitted_at               -- pk (user_id, date, game)
```
`puzzles` / `results` stay as they are for Lineup. `board(kind, scope_id, period, for_date, game)`
gains a fifth parameter (`'lineup'` default, or `'stars'|'duo'|'trail'|'total'`).
`streak(u)` counts a date if `results` or `game_results` has a row.
`start_game(d, game)` records the start and returns `{ game, number, date, spec }` (never the
solution). Edge function `submit-game` validates the client's answer by the rules and against
the stored solution, then clamps elapsed against `game_starts` exactly like `submit-result` —
returning 409 `no_start` if the player never called `start_game` for that (date, game) — and
inserts.

## Wire formats

- Stars spec `{ "n": 8, "regions": [[0,0,1,...],...] }`; solution `{ "stars": [c0, c1, ..., c(n-1)] }`
  (column of the star in each row). Client submits `{ "stars": [...] }`.
- Duo spec `{ "n": 6, "givens": [[null,0,...],...], "eq": [[r1,c1,r2,c2],...], "ne": [...] }`
  where 0 = ●, 1 = ○; solution `{ "cells": [[0,1,...],...] }`. Client submits `{ "cells": ... }`.
- Trail spec `{ "n": 6, "waypoints": [[r,c],...] }`; solution `{ "path": [[r,c],...] }`
  (n² entries). Client submits `{ "path": ... }`.
- `submit-game` body: `{ "date", "game", "tz", "elapsedMs", "mistakes", "gaveUp", "answer": <per game> }`.
  Response: `{ "result": { date, game, elapsedMs, elapsedSource, mistakes, solved, gaveUp, score, submittedAt }, "streak" }`.

## Client

- `packages/GridGames` (Swift, platform-neutral, tested on Windows): `StarsEngine`, `DuoEngine`,
  `TrailEngine` — state, moves, live validation, completion, share text. Mirrors the TS
  validators via a shared golden fixture.
- `KithCore`: `startGame`, `submitGame`, `myGameResults`, board `game` parameter, `GameKind`.
- App: `TodayView` becomes `HubView`; `StarsView`, `DuoView`, `TrailView`; results screen
  shared; board picker; profile stats per game.

## Apple Human Interface Guidelines pass

Applied across the app in the same round: system type styles with Dynamic Type everywhere,
SF Symbols for every icon, standard navigation (large titles on hub/board/profile), inset
grouped lists, `.tint` from the accent, standard haptics (selection on tile moves, success
on solve), full dark mode, VoiceOver labels and values on every grid cell ("row 3 column 5,
star"), `accessibilityDifferentiateWithoutColor` handled by adding glyphs to region colours,
Reduce Motion respected, minimum 44-pt targets, safe-area-correct layouts on all iPhones.
