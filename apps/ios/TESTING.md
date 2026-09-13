# Kith iOS — automated testing contract

Goal: every test the project has runs on GitHub Actions. Backend suites run on Linux;
everything Apple runs on the macOS runner: the two Swift packages, an in-process app
unit-test bundle (`KithTests`), and simulator UI tests (`KithUITests`) that drive the
real views against an in-memory fake backend. No network, no Supabase project needed.

## 1. Test seam in the app target

- `AuthProviding` protocol (new, `Model/AuthProviding.swift`), refining `KithCore.AuthTokenProvider`:
  `sendCode(phone:) async throws`, `verify(phone:code:) async throws -> String?` (user id),
  `signOut() async`, `currentUserId() async -> String?`. `AuthSession` conforms; `AppModel.init`
  takes `any AuthProviding`.
- `AppModel.init(auth:api:store:)` stays the single entry; `KithApp` chooses the wiring:
  `if ProcessInfo.processInfo.arguments.contains("-uiTesting")` → fakes (below) with a
  `FileStore` rooted in a fresh temporary directory, else the real Supabase wiring.
  Gate the fake wiring with `#if DEBUG`.
- `-uiTestingState <name>` picks the fake's starting state (see §2). Default `fresh`.
- `-uiTesting` also renders a ▲ / ▼ button pair on each unlocked tile (identifiers
  `today.tile.<i>.up` / `today.tile.<i>.down`) so UI tests can reorder deterministically
  without long-press drags. A step skips locked tiles and lands on the next unlocked slot;
  a button is disabled when there is no such slot in its direction (after two tries that is
  common, so a test's third round must try the other direction). Outside UI-testing mode those buttons are not rendered, but every
  tile always exposes accessibility actions named "Move up" and "Move down" (good for
  VoiceOver users regardless).

## 2. Fakes (`Kith/Testing/`, all `#if DEBUG`)

`FakeKithAPI: KithAPI` — deterministic, in-memory, no delays, records every call in
`calls: [String]` for unit tests. Data:

| Thing | Value |
|---|---|
| Me | user id `u-me`, display name `Alex`, invite code `KITH7F3Q`, tz `UTC` |
| Puzzle | date = today (UTC), number 142, prompt "Order these by the year they were invented", direction "Earliest at the top"; items (id, label, value, fact): 1 Bicycle 1817 "The first version had no pedals", 2 Telephone 1876 "Bell's patent came in March 1876", 3 Light bulb 1879 "Edison's carbon-filament lamp", 4 Zipper 1913 "Sundback's design is the one still used", 5 Microwave oven 1946 "Invented after a radar magnetron melted a chocolate bar"; `correctOrder` `[1,2,3,4,5]`; presentation order `[2,1,3,4,5]` (one swap from correct) |
| Friends board (today) | Mum (`u-mum`) 948 solved 1 try, Sam (`u-sam`) 610 solved 2 tries with taunt "took me 40 seconds", Dev (`u-dev`) 160 solved 3 tries; ranks 1,2,3 with prev 3,1,nil; me: unplayed in `returning`, 520 rank 3 in `played` |
| Board rows, all games (docs/07 "Boards (revised 2026-09-13)") | `board(game:)` now returns per-game data: on Lineup, Stars, Duo, Trail and Quint alike, Mum and Sam solve today (Mum faster on Lineup, Stars, Duo, Trail; both close on Quint) with `solved_count`/`played_count`/`prev_*` set from migration 0008; Dev gives up on Stars/Duo/Trail/Quint (`played_count` 1, `solved_count` 0 — the "gave up"/"failed" row) after solving those same games yesterday, but solves Lineup outright; Jo and I have never played any of them. Yesterday's numbers swap Mum and Sam's order on every game, so the client's rank-movement arrow has both directions to show. `total` is summed from the other five, not a separate fixture. |
| Everyone board | 5 rows with display names only; the protocol still has `board(kind: .everyone, ...)` but no view calls it since the revised boards dropped the Everyone board |
| Circles | `Family` code `ABC123`, owner `u-mum`, members mum/me |
| Reactions | Sam → me 🔥 in `played` |
| Match response | matches for hashes the test sends: map the first three hashes to Mum/Sam/Dev |
| Streak | 12 |
| Results history | 20 days ending yesterday, tries 1/2/3 cycling, for the heatmap |

Behaviour: `submitResult` recomputes tries/solved/score from the attempts using
`LineupEngine.Scoring` and stores the result; a second call the same day throws
`KithError.api(status: 409, code: "already_played", message:)`. `failNextSubmit: Bool` makes the
next `submitResult` throw `KithError.network("offline")`. `setTaunt` is write-once (409 after).
`react` upserts; `unreact` removes. `joinCircle("KITH-ABC123")` and `("ABC123")` both succeed
and add a chip; unknown codes throw `KithError.api(404, "no_circle")`. `deleteAccount` clears
everything. `reveal` returns the five items with values and facts.

States (`-uiTestingState`): `fresh` (signed out; onboarding starts at phone),
`returning` (signed in, registered, today unplayed), `played` (today already played, score 520).

`FakeAuth: AuthProviding` — `sendCode` no-op; `verify` succeeds only with code `123456`
and returns `u-me`; `accessToken` returns an unsigned JWT whose `sub` is `u-me`; `currentUserId`
reflects sign-in state.

## 3. Accessibility identifiers (contract for `KithUITests`)

| Screen | Identifiers |
|---|---|
| Tabs | `tab.today`, `tab.board`, `tab.circles`, `tab.you` |
| Onboarding | `onboarding.phone.field`, `onboarding.phone.continue`, `onboarding.code.field`, `onboarding.code.resend`, `onboarding.name.field`, `onboarding.name.continue`, `onboarding.contacts.allow`, `onboarding.contacts.notNow`, `onboarding.friends.seeBoard`, `onboarding.friends.invite`, `onboarding.friends.createCircle`, `onboarding.notifications.yes`, `onboarding.notifications.no` |
| Today | `today.prompt`, `today.tile.<i>` (i = 0…4; accessibility label = the item label), `today.tile.<i>.up`, `today.tile.<i>.down`, `today.lockIn`, `today.timer`, `today.tries`, `today.countdown`, `today.playedCard` |
| Results | `results.headline`, `results.score`, `results.time`, `results.share`, `results.copy`, `results.taunt.field`, `results.rankTeaser`, `results.showFacts` |
| Board | `board.kind` (Picker), `board.header`, `board.row.<userId>`, `board.empty.invite`, `board.empty.createCircle` |
| Circles | `circles.new`, `circles.join`, `circles.join.field`, `circles.join.submit`, `circles.chip.<code>` |
| Profile | `profile.streak`, `profile.heatmap`, `profile.inviteCode`, `profile.discoverable`, `profile.deleteAccount`, `profile.deleteConfirm` |
| Global | `banner.configMissing`, `toast` |

Games hub (`apps/ios/PLAN-games.md`, docs/07). The Today tab is `HubView`; the Lineup
identifiers above now live on the screen it pushes.

| Screen | Identifiers |
|---|---|
| Hub | `hub.row.lineup`, `hub.row.stars`, `hub.row.duo`, `hub.row.trail`, `hub.row.quint`, `hub.streak`, `hub.countdown` |
| Game host | `game.timer`, `game.giveUp`, `game.giveUp.confirm`, `game.reset` (not shown for Quint — a guess cannot be undone), `game.done`, `game.retry` (a failed `startGame`'s "Try again"), `game.showResult` (on an already-played game's card, reopens `GameResultsView`) |
| Grids | `stars.cell.<r>.<c>`, `duo.cell.<r>.<c>`, `trail.cell.<r>.<c>` (accessibility label "row r column c, <state>") |
| Quint | `quint.tile.<r>.<c>` (accessibility label "row r letter c, <LETTER>, <hit\|near\|miss>"), `quint.key.<letter>`, `quint.key.enter`, `quint.key.backspace` |
| Game results | `gameResults.headline`, `gameResults.time`, `gameResults.score`, `gameResults.share` |
| Board | `board.section.<slug>` — one per row of the expandable list, `<slug>` a `BoardGame` raw value: `total` ("All games", expanded by default), `lineup`, `stars`, `duo`, `trail`, `quint` (collapsed by default; tapping toggles and, the first time, loads that game's rows) |

`<r>` and `<c>` in the grid identifiers are the engine's **0-based** coordinates, matching
`today.tile.<i>`; the spoken label numbers them from 1 ("row 1 column 2, empty"), which is
what VoiceOver users expect.

Two documented exceptions to the "44 pt targets everywhere" rule (docs/08-visual-design.md
§Accessibility): the ≥ 9×9 grids, where `GridMetrics.spacing(for:base:)` and
`GameHostView.hostHorizontalPadding` tighten spacing/padding so the board still fits
(apps/ios/Kith/README.md "Known gotchas" #3); and Quint's on-screen keyboard keys, which
stay narrower than 44 pt so all ten letters of the top row fit one screen width — only the
46 pt `minHeight` is held to the target size.

Under `-uiTesting` the fake puzzles are tiny so UI tests can solve them by tapping cells in
a known order:

- **Stars** 5×5, regions = the five rows, solution columns `[1, 3, 0, 2, 4]`. Tap each of
  `stars.cell.0.1`, `stars.cell.1.3`, `stars.cell.2.0`, `stars.cell.3.2`, `stars.cell.4.4`
  **twice** (empty → ✕ → ★).
- **Duo** 6×6, a real Tango solution with all 30 off-diagonal cells given; the six blanks
  are the leading diagonal `duo.cell.<i>.<i>`. One `=` badge on (0,0)–(0,1) and one `×`
  badge on (1,0)–(1,1).
- **Trail** 3×3, waypoints `[[0,0],[1,1],[2,2]]`, solved by the snake
  (0,0) (0,1) (0,2) (1,2) (1,1) (1,0) (2,0) (2,1) (2,2). The path always starts at
  waypoint 1, `(0,0)`, so a test only taps the remaining eight cells in that order.
- **Quint** answer `"crane"`, puzzle number 3. A test types `slate` (a real word, wrong)
  then `crane` via `quint.key.<letter>` and `quint.key.enter`; the second, solving guess
  submits on its own (no `game.done` tap) and lands on the results screen.

`dailyGames` returns all four every day; `submitGame` records the call (`gameSubmissions`)
and scores with `GameScoring.score` (`GameScoring.quintScore` for Quint, which also
recomputes `solved` and `mistakes` from the submitted `guesses` rather than trusting the
client, exactly like the real `submit-game` per docs/07); `failNextGameSubmit` is the
grid-game twin of
`failNextSubmit`. `failNextGameSubmitWithNoStart` makes the next `submitGame` throw
`KithError.api(status: 409, code: "no_start", message:)` once — the backend's answer when
`start_game` was never called for that date/game; `AppModel`'s submit path replays
`start_game` and retries the submit exactly once before falling back to the offline queue.

`AppModel.activeGames: [GameKind: ActiveGame]` holds every grid game's session, not just
one: opening Duo while Stars is unfinished keeps the Stars session in the dictionary rather
than discarding it. `activeGame` (singular) is a computed convenience that follows whichever
kind `startGame` opened most recently; `GameHostView` and `GameResultsView` read
`activeGames[kind]` directly instead, so a screen always shows its own kind's session.

## 4. `KithTests` (unit, in-process, `@MainActor`, XCTest, host app Kith)

Use `AppModel(auth: FakeAuth(), api: FakeKithAPI(state:), store: FileStore(directory: temp))`.

1. `testFreshBootstrapIsSignedOut` → `stage == .signedOut`, onboarding step `.phone`.
2. `testVerifyThenSaveNameLoadsToday` → after `sendCode`, `verifyCode("123456")`, `saveName("Alex")`: `engine != nil`, `puzzle?.number == 142`, `stage == .ready`.
3. `testReturningBootstrapLoadsPuzzleAndBoard` (`returning`) → `engine?.phase == .playing`, friends board cached with 4 rows.
4. `testSolveOnFirstTrySubmitsAndReveals` → move tile 0 down one (`moveRows`), `lockIn()`; `result?.tries == 1`, `result?.score == 1000 − penalty`, `reveal.count == 5`, share text starts with `"Kith #142 · 1/3"`.
5. `testOfflineSubmitQueuesAndReplays` → `api.failNextSubmit = true`, solve; `result` set locally, `toast` mentions sync, queue file exists; `onForeground()` → `api.calls` contains a second `submitResult`, queue cleared.
6. `testAlreadyPlayedIsTreatedAsSuccess` → submit twice (simulate by calling `lockIn` on a fresh engine after `played` state) → no error, `result` present.
7. `testReactSwapUnreactsFirst` (`played`) → `react(to: "u-sam", "😂")` after existing 🔥 → `api.calls` has `unreact` before `react`.
8. `testMoveRowsClampsToUnlocked` → after a submission that locks positions {0,4}, `moveRows(from: 1, to: 4)` lands at 3.
9. `testLoadTodayDuringPlayKeepsEngine` → mutate order, `loadToday()`, order unchanged.
10. `testDiscoverableToggleUpdatesProfile` → `setDiscoverable(false)` → `api.calls` contains `updateProfile(discoverable:false)`.
11. `testDeleteAccountResetsState` → `stage == .signedOut`, `engine == nil`, auth signed out.
12. `testLimitedContactsSyncNeverRemoves` → run the sync planner path with `limited` → the `matchContacts` call has empty `removed`.
13. `testTauntIsWriteOnce` → `saveTaunt("gg")` twice → second is a no-op, `tauntSaved == true`.
14. `testMidnightFlipReloadsPuzzle` → set `today` to yesterday, call the midnight handler → `today` is the current date and a new `startPuzzle` call was made.

Method names above are the intent; match whatever `AppModel` actually exposes and add small
`internal` hooks only where needed (e.g. `func applyMidnight()`).

## 5. `KithUITests` (simulator, XCUITest)

`app.launchArguments = ["-uiTesting", "-uiTestingState", "<state>"]`. 5-second existence waits.

1. `testOnboardingToFirstPuzzle` (`fresh`): type `+15551234567` → continue → type `123456` → name `Alex` → continue → contacts **Not now** → `today.prompt` exists and `today.tile.0` … `today.tile.4` exist; `today.lockIn` is disabled until a tile moves.
2. `testSolveInOneTry` (`returning`): tap `today.tile.0.down` (Telephone moves below Bicycle) → `today.lockIn` enabled → tap → `results.headline` label is `Solved in 1`, `results.share` exists, `results.rankTeaser` exists.
3. `testBoardShowsFriends` (`played`): tap `tab.board` → (the "All games" section is expanded by default) `board.row.u-mum`, `board.row.u-sam`, `board.row.u-dev` exist; `board.header` label contains `Friends`; a row labelled `You` exists.
4. `testAlreadyPlayedShowsCountdown` (`played`): `today.playedCard` and `today.countdown` exist.
5. `testJoinCircleByCode` (`returning`): `tab.circles` → `circles.join` → type `KITH-ABC123` → `circles.join.submit` → `circles.chip.ABC123` exists.
6. `testProfileShowsStreak` (`played`): `tab.you` → `profile.streak` label contains `12`, `profile.inviteCode` label contains `KITH7F3Q`.
7. `testBoardSectionsExpand` (`played`): `tab.board` → `board.section.total` ("All games") is expanded by default with rows already visible → tap `board.section.stars` → `board.row.*` rows appear under it.

## 6. CI

- `.github/workflows/backend.yml` (ubuntu): `deno check` + `deno test --allow-read` in `supabase/functions`; `npm install && npm test` in `supabase/tests`.
- `.github/workflows/ios.yml`: jobs `packages` (swift test ×2), `simulator-tests` (`xcodebuild test` on the `Kith` scheme, iPhone 16 simulator, uploads the `.xcresult` on failure), and `app` (unsigned IPA) which needs both.

## 7. Live end-to-end test (`KithLiveTests`, real backend)

Separate UI-test target and scheme (`KithLive`) so the hermetic suites above never
touch the network. Launches the app WITHOUT `-uiTesting`, so it uses the real
`Config.plist` (live Supabase project), with `-uiTestingControls` to render the per-tile
▲/▼ buttons without swapping the backend.

Inputs (test-runner environment, passed by xcodebuild as `TEST_RUNNER_*`):
`KITH_TEST_PHONE` (an E.164 number registered under Supabase Auth → Phone → Test Phone
Numbers) and `KITH_TEST_OTP` (its fixed code). If either is missing the test is skipped
with `XCTSkip`, never failed.

`testLiveSignInPlayAndDelete`, one test, in this order, every wait 20 s:
1. Launch. If `onboarding.phone.field` exists: type the phone → `onboarding.phone.continue`
   → type the OTP into `onboarding.code.field` (auto-submits). Then EITHER
   `onboarding.name.field` (new user: type `CI Tester`, tap `onboarding.name.continue`, then
   `onboarding.contacts.notNow`) OR the Today screen directly (returning user).
2. Today: if `today.playedCard` exists, skip to step 4. Otherwise, up to three rounds: tap the
   first enabled button among `today.tile.0.down` … `today.tile.3.down`, then `today.lockIn`;
   stop as soon as `results.headline` exists (solved or failed both end on the results screen).
3. Results: `results.score` exists. If the onboarding tail appears (`onboarding.friends.seeBoard`
   or `onboarding.friends.invite`, then `onboarding.notifications.no`), dismiss it: tap
   `onboarding.friends.seeBoard` if present, then `onboarding.notifications.no` if present.
4. `tab.board`: `board.header` exists and a row labelled `You` exists (or `board.row.<my id>`;
   `You` is enough).
5. `tab.you`: `profile.streak` exists and its label contains a digit; `profile.inviteCode` exists.
6. Delete: `profile.deleteAccount` → `profile.deleteConfirm` → `onboarding.phone.field` appears
   again (signed out). This leaves the backend clean for the next run.
Assertion messages must say which step failed. Screenshots are attached at each step
(`XCTAttachment(screenshot:)`, lifetime `.keepAlways`) so a failure is diagnosable from the
`.xcresult`.

CI: job `live-e2e` in `.github/workflows/ios.yml` runs only when the repository variable
`KITH_LIVE_E2E` is `true` (or on manual dispatch with `live=true`), after `simulator-tests`,
with `Config.plist` written from the `SUPABASE_URL`/`SUPABASE_ANON_KEY` secrets and the
phone/OTP from the `KITH_TEST_PHONE`/`KITH_TEST_OTP` secrets.
