# Kith (working title)

A daily puzzle app where the leaderboard is made of the contacts in your phone who also play. iOS-first, native SwiftUI, Supabase backend, no ads.

## Layout

| Path | What it is | Verify with |
|---|---|---|
| `docs/` | Product brief, v1 spec, wireframes, architecture, launch plan | — |
| `packages/LineupEngine/` | Pure Swift state machine for the daily puzzle: rules, scoring, share text. No UI, no I/O. | `swift test` |
| `supabase/functions/_shared/lineup.ts` | Server-side twin of the engine; recomputes a result from an untrusted attempt log | `cd supabase/functions && deno test --allow-read` |
| `supabase/functions/{register,submit-result,match-contacts}/` | Edge functions. Each is a pure `handler.ts` over a Store interface, a Supabase-backed `store.ts`, and a thin `index.ts`. Tests use in-memory fakes from `_shared/test_fakes.ts`. | same command |
| `supabase/functions/_shared/hashing.ts` | Phone canonicalisation and the sha256 → peppered HMAC transform for contact matching | same command |
| `packages/LineupEngine/Tests/LineupEngineTests/Fixtures/golden.json` | Golden vectors read by both test suites so the twins cannot drift | both of the above |
| `supabase/migrations/0001_init.sql` | Schema, row-level security, board / streak / circle / push RPCs | `cd supabase/tests && npm install && npm test` (runs the migration in in-process Postgres with an `auth` shim and a non-superuser role) |
| `supabase/migrations/0002_cron.sql` | pg_cron schedules for pushes and puzzle generation (hosted only) | — |
| `supabase/migrations/0003_seed_content.sql` | Seed lists and items, disabled until a human checks each value | schema test loads it |
| `supabase/functions/{delete-account,send-pushes,generate-puzzles}/` | Account deletion, APNs pushes from cron, puzzle generator | `deno test --allow-read` |
| `admin/index.html` | Single-file review queue for the content author | manual |
| `web/` | Landing site, share/circle link fallbacks, privacy policy, terms, AASA (Cloudflare Pages) | manual |
| `packages/GridGames/` | Pure Swift engines for the four grid/word games (Stars, Duo, Trail, Quint): state, live validation, completion, share text. Mirrors the TypeScript validators. | `swift test` |
| `supabase/functions/_shared/games/` | Generators with uniqueness solvers, validators and share rows for Stars, Duo, Trail, Quint; `submit-game` validates answers server-side | `deno test --allow-read` |
| `packages/KithCore/` | Platform-neutral client logic: API client, contact hashing and sync planning, local-day math, screen presenters | `swift test` |
| `apps/ios/` | SwiftUI app target (XcodeGen spec + sources). Builds only on macOS; CI produces an unsigned IPA | `.github/workflows/ios.yml` |
| `docs/06-deployment-runbook.md` | Every step from repo to phone | — |
| `docs/07-games-hub.md` | The games hub: Stars, Duo, Trail, Quint rules, scoring, data model, wire formats, HIG pass | — |

## Status

Every layer exists and everything that can be tested on a Windows machine is tested. What has **not** happened yet, in order of importance:

1. Nothing is deployed. No Supabase project, no Cloudflare Pages site, no GitHub remote. `docs/06-deployment-runbook.md` is the checklist.
2. The SwiftUI target compiles and passes its unit and simulator UI tests on CI (macOS runner), but has not yet been run against a live backend or on a physical device by a person.
3. Seed content values have not been human-verified; lists ship `enabled = false` until checked in the admin page.
4. The edge functions have not been exercised against a live Supabase project (they are tested against in-memory stores and the schema against pglite). Build order is in the architecture doc, section 7.

## Docs

| # | Document | What it answers |
|---|---|---|
| 1 | [Product brief](docs/01-product-brief.md) | Problem, audience, core loop, differentiation vs. NYT Games / LinkedIn Games |
| 2 | [v1 feature spec](docs/02-v1-feature-spec.md) | The "Lineup" puzzle, scoring, contacts matching, circles, board, reactions, onboarding, notifications, and the explicit cut list |
| 3 | [Wireframes](docs/03-wireframes.md) | The five core screens, top to bottom |
| 4 | [Technical architecture](docs/04-technical-architecture.md) | SwiftUI + Supabase, data model, privacy-by-design contact matching, App Store privacy label, Game Center tradeoffs |
| 5 | [Launch plan and roadmap](docs/05-launch-plan-and-roadmap.md) | 10-week build schedule, growth loop, monetization, metrics, 90-day roadmap |

## Working agreements

- Main session owns brainstorming, architecture, specs, root-cause analysis, builds, tests, commits, docs.
- File exploration goes to an Explore subagent; implementation to two Sonnet implementers on disjoint files against headers written in the main session; a read-only Opus reviewer runs before any architecturally significant commit; a Sonnet fixer applies the reviewer's list verbatim.
