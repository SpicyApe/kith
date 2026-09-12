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
  without long-press drags. Outside UI-testing mode those buttons are not rendered, but every
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
| Everyone board | 5 rows with display names only |
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
| Board | `board.kind` (Picker), `board.period` (Picker), `board.header`, `board.row.<userId>`, `board.empty.invite`, `board.empty.createCircle` |
| Circles | `circles.new`, `circles.join`, `circles.join.field`, `circles.join.submit`, `circles.chip.<code>` |
| Profile | `profile.streak`, `profile.heatmap`, `profile.inviteCode`, `profile.discoverable`, `profile.deleteAccount`, `profile.deleteConfirm` |
| Global | `banner.configMissing`, `toast` |

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
3. `testBoardShowsFriends` (`played`): tap `tab.board` → `board.row.u-mum`, `board.row.u-sam`, `board.row.u-dev` exist; `board.header` label is `3 of 4 friends played today`; a row labelled `You` exists.
4. `testAlreadyPlayedShowsCountdown` (`played`): `today.playedCard` and `today.countdown` exist.
5. `testJoinCircleByCode` (`returning`): `tab.circles` → `circles.join` → type `KITH-ABC123` → `circles.join.submit` → `circles.chip.ABC123` exists.
6. `testProfileShowsStreak` (`played`): `tab.you` → `profile.streak` label contains `12`, `profile.inviteCode` label contains `KITH7F3Q`.
7. `testEveryoneBoardDisablesPeriod` (`played`): `tab.board` → select Everyone in `board.kind` → `board.period` is disabled.

## 6. CI

- `.github/workflows/backend.yml` (ubuntu): `deno check` + `deno test --allow-read` in `supabase/functions`; `npm install && npm test` in `supabase/tests`.
- `.github/workflows/ios.yml`: jobs `packages` (swift test ×2), `simulator-tests` (`xcodebuild test` on the `Kith` scheme, iPhone 16 simulator, uploads the `.xcresult` on failure), and `app` (unsigned IPA) which needs both.
