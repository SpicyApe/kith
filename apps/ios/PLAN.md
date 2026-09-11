# Kith iOS app target — build plan

This is the only part of the repo that cannot be compiled on the Windows machine
the backend was built on. Everything that can be unit-tested lives in
`packages/KithCore` and `packages/LineupEngine`; this target is views, OS
integrations, and one observable app model. Keep it that way.

## Files (all under `apps/ios/Kith/`)

| File | Responsibility |
|---|---|
| `KithApp.swift` | `@main`. Creates `AppModel`, injects it via `.environment`, handles `onOpenURL` (kith:// and universal links) by calling `model.route(url)`. Registers the push delegate. |
| `Config/AppConfig.swift` | Reads `Config.plist` (SUPABASE_URL, SUPABASE_ANON_KEY, WEB_BASE = https://kith.app). Fails loudly in DEBUG when missing. |
| `Config/Config.example.plist` | Template; the real `Config.plist` is gitignored. |
| `Model/AppModel.swift` | `@MainActor @Observable final class`. Owns: `session` (signed out / needs register / ready), `profile`, `today` (date string, recomputed on foreground and at midnight via a timer), `engine: LineupEngine?`, `result: StoredResult?`, `streak`, boards cache keyed by (kind, scope, period, date), circles, directory (`ContactDirectory` persisted as JSON in Application Support), friends, `lastSyncedHashes` (persisted), `onboarding: OnboardingFlow`, `toast`. All network goes through `KithAPI`. Every method is `async` and sets an `isBusy`/error pair the views read. |
| `Model/Session.swift` | Wraps supabase-swift `SupabaseClient.auth`: `signInWithOTP(phone)`, `verify(phone, code)`, `signOut()`, and conforms to `AuthTokenProvider` by returning `session.accessToken` (refreshing via the SDK). |
| `Model/URLSessionHTTPClient.swift` | `HTTPClient` over `URLSession.shared` with a 20 s timeout. |
| `Model/Persistence.swift` | Tiny JSON file store for `ContactDirectory`, last-synced hashes, cached puzzle, and queued offline result. |
| `Services/ContactsService.swift` | `CNContactStore` wrapper: authorization status (`authorized`, `limited` on iOS 18, `denied`, `notDetermined`), `requestAccess()`, `fetchAll() -> [RawContact]` reading given/family names and phone numbers, region from `Locale.current.region`. Builds the directory with `BasicPhoneNormalizer`, plans the sync with `ContactSyncPlanner`, calls `api.matchContacts`, stores `lastSyncedHashes` only on success. Runs at onboarding, on foreground at most once per 24 h, and on pull-to-refresh. |
| `Services/PushService.swift` | `UNUserNotificationCenter` pre-prompt gating, `registerForRemoteNotifications`, forwards the token to `api.registerDevice(token, env)` where env is `sandbox` for DEBUG and `production` otherwise. Notification taps deep-link via the `url` key in the payload. |
| `Services/MidnightTimer.swift` | Fires at local midnight (uses `LocalDay.secondsUntilMidnight`) so Today flips without a relaunch. |
| `Views/RootView.swift` | Switches between `OnboardingView` and the `TabView` (Today · Board · Circles · You). |
| `Views/Onboarding/*.swift` | `PhoneStep`, `CodeStep`, `NameStep`, `ContactsPromptStep`, `FriendsFoundStep`, `NotificationsPromptStep`; driven by `model.onboarding.step`. Copy exactly as in docs/03-wireframes.md §1. |
| `Views/Today/TodayView.swift` | Puzzle screen (docs/03 §2): prompt card, `TileList`, tries dots, timer label, "Lock in". Uses `engine.move(from:to:)` from a `List` with `.onMove` restricted to unlocked positions (locked rows have `.moveDisabled(true)`). After play: compact results card + countdown + top three friend rows. |
| `Views/Today/TileList.swift` | The five tiles; green/yellow/grey states, haptics via `UINotificationFeedbackGenerator`. |
| `Views/Results/ResultsView.swift` | docs/03 §3: headline, score, grid, reveal strip (fetched from `list_items` after submit via `api`... v1: values/facts are shown from the `results`-gated `list_items` select), streak, rank teaser, taunt field, Share (`ShareLink` with the text from `ResultsPresenter`), Copy. |
| `Views/Board/BoardView.swift` | docs/03 §4: segmented Friends/Circles/Everyone, Today/Week/All-time, rows from `BoardPresenter.rows`, pinned "me" row, reaction picker popover, empty state with Invite + Create circle. |
| `Views/Circles/CirclesView.swift` | Chips, create sheet (name → `api.createCircle`), join sheet (code → `api.joinCircle`), share code via `ShareLink`, leave. |
| `Views/Profile/ProfileView.swift` | docs/03 §5: header, `HeatmapView` (56 cells from `ProfilePresenter.heatmap`), stats grid, invite code, settings list (notifications, contacts status + sync now + discoverable toggle, circles, privacy links, delete account with confirm sheet). |
| `Views/Shared/*.swift` | `MovementChip`, `MiniGrid`, `AvatarView`, `Toast`. |
| `Resources/Assets.xcassets` | App icon placeholder, accent colour `#E4593F`. |

## Rules for whoever implements this

- No logic in views that could live in KithCore. If you find yourself formatting a
  date or computing a rank in SwiftUI, move it into a presenter and add a test.
- The engine is a value type: keep it in `AppModel` and mutate through methods so
  SwiftUI sees the change.
- Offline: `startPuzzle` failure with a cached puzzle for today → play from cache;
  `submitResult` failure → queue the attempt log and retry on foreground.
- Never show the OS contacts or notification prompt without the pre-prompt screen.
- Free-team builds (3uTools sideload): push registration fails with an entitlement
  error; catch it and continue. Universal links will not open the app; the `kith://`
  scheme still works.

## CI

`.github/workflows/ios.yml` runs on `macos-14`: install xcodegen, `xcodegen generate`,
`xcodebuild -scheme Kith -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO
build`, then packages `Kith.app` into `Payload/` and zips it to `Kith-unsigned.ipa` as
a workflow artifact. Also runs `swift test` for both packages on the same runner.
