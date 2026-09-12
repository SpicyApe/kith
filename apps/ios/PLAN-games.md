# Kith iOS — Games hub and HIG pass (build plan)

Spec: `docs/07-games-hub.md`. Engines: `packages/GridGames`. API: `KithCore/Games.swift`
and the four new `KithAPI` methods (`startGame`, `submitGame`, `myGameResults`, `dailyGames`)
plus `board(..., game:)`.

## Screens

| File | Responsibility |
|---|---|
| `Views/Today/HubView.swift` (replaces `TodayView` as the Today tab) | Large-title "Today" with the date; a `List(.insetGrouped)` of four rows: Lineup, Stars, Duo, Trail. Each row: SF Symbol, title, subtitle = status ("Not played", "Solved · 1:23", "Gave up", "Solved in 2 tries · 940" for Lineup), a chevron. Header card: streak (flame + count) and countdown ("Next games in 9h 12m"). Rows for games missing on the server show "Not available today" and are disabled. Tapping pushes the game screen (`NavigationStack`). |
| `Views/Today/TodayView.swift` | Unchanged Lineup play screen, now pushed from the hub. |
| `Views/Games/GameHostView.swift` | Shared chrome for the three grid games: timer in the navigation bar (`TimelineView`), a "Give up" toolbar item behind a confirmation dialog, a "Reset" item, "Done" appears only when the engine reports complete. Owns the game session state in `AppModel` (`activeGame`), calls `submitGame` on completion or give-up, then presents `GameResultsView`. |
| `Views/Games/StarsView.swift` | Grid of `n×n` cells coloured by region (a fixed palette of 12 muted region colours with a small distinct SF Symbol per region for `accessibilityDifferentiateWithoutColor`). Tap cycles a cell; drag paints ✕ across empty cells. Conflicting stars get a red ring. Stars drawn with `star.fill`, crosses with `xmark` at reduced opacity. Cells are ≥ 44 pt where the width allows; the grid fills the width minus 32 pt padding. |
| `Views/Games/DuoView.swift` | 6×6 grid; givens have a filled background and are not tappable; tap cycles. Constraints drawn as small `=` / `×` badges centred on the shared edge. Violated cells get a red ring. Symbols `circle.fill` and `circle`. |
| `Views/Games/TrailView.swift` | `n×n` grid with numbered waypoint badges. A `DragGesture(minimumDistance: 0)` on the grid maps the touch to a cell and calls `engine.extend(to:)` as the finger crosses cell centres; the path is drawn as a rounded polyline through cell centres over the grid with the accent colour; tapping a path cell calls `retract(to:)`. Selection haptic on every accepted step. |
| `Views/Games/GameResultsView.swift` | Same layout as `ResultsView`: headline ("Solved" / "Gave up"), time, score, share rows preview, streak, rank teaser from the Friends board for that game, `ShareLink` with `GameShareText.render`, Copy. |
| `Views/Board/BoardView.swift` | Adds a third segmented control, `board.game`: Lineup · Stars · Duo · Trail · Total (a `Menu` on narrow widths). Rows show time instead of the mini grid for grid games; Total rows show the summed score only. |
| `Views/Profile/ProfileView.swift` | Stats section gains a per-game breakdown (days played, best time) from `myGameResults`. Heatmap counts any game. |

## AppModel additions

- `dailyGames: [DailyGameRow]`, `gameResults: [String: StoredGameResult]` keyed `"\(date)#\(game)"`,
  loaded in `loadToday()` (best effort; the hub renders Lineup even if these fail).
- `activeGame: ActiveGame?` where `ActiveGame` holds `StartedGame`, the engine (an enum
  `GameEngine { case stars(StarsEngine), duo(DuoEngine), trail(TrailEngine) }`), `revealedAt`,
  `mistakes` (incremented when a move creates a new conflict), `isFinishing`.
- `startGame(_ kind:)`, `finishGame()` (calls `submitGame` with the engine's `answer`),
  `giveUpGame()` (submits `gaveUp: true`), `resetGame()`. Offline: queue like Lineup results
  (`QueuedGameResult`) and replay on foreground; `already_played` treated as success.
- Board cache key gains the game; `refreshBoard(kind:scopeId:period:game:force:)`.
- `FakeKithAPI` (UI tests) gains all four methods with a deterministic small puzzle per game
  (the fixtures in `packages/GridGames/Tests/GridGamesTests/Fixtures/golden.json`) and
  records submissions; `FakeKithAPI.State` unchanged.

## Accessibility identifiers (append to TESTING.md §3)

| Screen | Identifiers |
|---|---|
| Hub | `hub.row.lineup`, `hub.row.stars`, `hub.row.duo`, `hub.row.trail`, `hub.streak`, `hub.countdown` |
| Game host | `game.timer`, `game.giveUp`, `game.giveUp.confirm`, `game.reset`, `game.done` |
| Grids | `stars.cell.<r>.<c>`, `duo.cell.<r>.<c>`, `trail.cell.<r>.<c>` (accessibility label "row r column c, <state>") |
| Game results | `gameResults.headline`, `gameResults.time`, `gameResults.score`, `gameResults.share` |
| Board | `board.game` (Picker or Menu) |

Under `-uiTesting` the fake puzzles are tiny (Stars 5×5, Duo 6×6 with 30 givens, Trail 3×3
with a forced snake) so UI tests can solve them by tapping cells in a known order.

## Tests

- `KithTests`: hub loads four rows; starting Stars creates `activeGame` with a `StarsEngine`;
  completing the fake Stars puzzle submits `{stars:[...]}` and stores the result; give-up
  submits `gaveUp:true`; mistakes increment on a new conflict; offline queue replay for games;
  board cache keyed by game.
- `KithUITests` (hermetic): `testHubListsFourGames`, `testSolveFakeStars` (tap the five
  star cells → `game.done` → `gameResults.headline` "Solved"), `testGiveUpDuo`,
  `testBoardGamePicker` (select Total, rows exist).
- `KithLiveTests`: after Lineup, open Stars from the hub, tap "Give up" (solving a real
  8×8 blind is not feasible in a test), confirm, assert `gameResults.headline` "Gave up",
  then continue to the board and profile steps.

## HIG checklist (apply everywhere touched, and audit the existing screens)

- Text uses `Font.TextStyle` only (`.largeTitle`, `.title2`, `.headline`, `.body`, `.footnote`);
  no fixed point sizes except the 1-pt debug status line. Dynamic Type up to accessibility sizes
  must not clip: grids scale, lists wrap.
- Navigation: `NavigationStack` per tab, `.navigationTitle` with `.large` on hub/board/profile
  and `.inline` inside a game; toolbar items are SF Symbols with labels for VoiceOver.
- Lists: `.listStyle(.insetGrouped)`; section headers in sentence case; destructive actions
  (Delete account, Give up) use `role: .destructive` and a confirmation dialog.
- Colour: one accent via `.tint`; semantic colours (`.red` for conflicts) never the only cue
  (also a ring/glyph); region palette checked in dark mode; `Color(.systemBackground)`/
  `.secondarySystemGroupedBackground` for surfaces.
- Touch targets ≥ 44 pt; grid cells enlarge to fill width; drag gestures do not fight the
  scroll view (grids are not inside a `ScrollView`).
- Haptics: `.sensoryFeedback(.selection, trigger:)` on cell changes, `.success` on solve,
  `.warning` on a new conflict; none when Reduce Motion is on is not required, but animations are
  wrapped in `withAnimation` only when `!reduceMotion`.
- Every cell has `accessibilityLabel` ("row 2 column 5, empty" / ", star" / ", given ●") and
  `accessibilityAddTraits(.isButton)`; the path in Trail has a summary label ("path 12 of 36 cells").
- Layout uses safe areas; no hard-coded device sizes; test on the smallest supported iPhone
  (iPhone SE width 375 pt) in the simulator run.
