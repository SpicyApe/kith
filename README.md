# Kith (working title)

A daily puzzle app where the leaderboard is made of the contacts in your phone who also play. iOS-first, native SwiftUI, Supabase backend, no ads.

## Layout

| Path | What it is | Verify with |
|---|---|---|
| `docs/` | Product brief, v1 spec, wireframes, architecture, launch plan | — |
| `packages/LineupEngine/` | Pure Swift state machine for the daily puzzle: rules, scoring, share text. No UI, no I/O. | `swift test` |
| `supabase/functions/_shared/lineup.ts` | Server-side twin of the engine; recomputes a result from an untrusted attempt log | `deno test --allow-read lineup_test.ts` |
| `packages/LineupEngine/Tests/LineupEngineTests/Fixtures/golden.json` | Golden vectors read by both test suites so the twins cannot drift | both of the above |
| `supabase/migrations/0001_init.sql` | Schema, row-level security, board / streak / circle RPCs | `cd supabase/tests && npm install && npm test` (runs the migration in in-process Postgres with an `auth` shim and a non-superuser role) |

Not built yet: the iOS app target, the `match-contacts` / `submit-result` / `send-pushes` edge functions, the puzzle generator and admin page, and the landing site. Build order is in the architecture doc, section 7.

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
