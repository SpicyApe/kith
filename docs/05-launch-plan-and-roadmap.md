# Kith — Launch Plan, Growth Loop, Metrics, and 90-Day Roadmap

---

## 1. Build schedule (10 weeks, one iOS engineer + one part-time backend/content person)

| Week | Deliverable | Exit criterion |
|---|---|---|
| 1 | Supabase project, schema, RLS, phone OTP working in a bare app | Sign in on a real device with a real number |
| 2 | `LineupEngine` with unit tests, puzzle screen, local scoring | Play a hardcoded puzzle offline, feels good at 120 Hz |
| 3 | Result submission, results screen, share text, countdown | Share a grid into a real group chat |
| 4 | Contacts pre-prompt, hashing, `match-contacts`, Friends board | Two phones with each other's numbers see each other |
| 5 | Circles, join codes, `kith.app` landing site, universal links | Join a circle from a link on a fresh install |
| 6 | Reactions, taunts, rank movement, Everyone board | Board feels alive with 5 test accounts |
| 7 | Push pipeline, three notification types, settings | Streak-at-risk push arrives at 20:00 local in two timezones |
| 8 | Profile, heatmap, delete account, privacy manifest, policy page | App Store privacy label filled out truthfully |
| 9 | Puzzle generator, admin review page, 45 approved puzzles | Content queue covers launch + 6 weeks |
| 10 | TestFlight with one real group chat (~30 people), fix, submit | Approval; first-review rejection risk is the contacts purpose string, already written |

Weeks 11–12 are buffer. Cut order if the schedule slips: taunts → Everyone board → reactions → circles admin (never cut circles themselves; they are the fallback).

---

## 2. Retention and growth loop, spelled out

```
Day 1   Alex installs (from the App Store, a friend's link, or a share grid)
        → phone OTP → contacts pre-prompt → grants
        → plays Lineup #142 in 70 s → sees "0 of your contacts play yet"
        → shares the grid to the family group chat (link carries ?r=ALEX)

Day 1   Sam taps the link → landing page → App Store → installs
        → OTP → grants contacts → plays #142
        → contact sync finds Alex (mutual: both have each other's numbers)
        → results screen: "You're #1 of 1 friends today" → Alex gets no push yet
        → Alex opens the app that evening: Friends board now shows Sam, ▲NEW

Day 2   08:00 push to both: "Today's Lineup is up. 1 friend has already played."
        → Sam beats Alex → 12:00 "Sam just passed you" push to Alex
        → Alex reacts 🙄, writes a taunt → Sam sees it next open
        → both share to the same chat → Mum installs → three-person board

Day 3+  Streak counters climb. 20:00 streak-at-risk push catches anyone who forgot.
        Rank arrows give a reason to open even after playing (did I hold #1?).
        Week view resets Monday and gives the loser a fresh start.
```

The loop has no step that depends on a stranger, an algorithm, or a marketing budget. Each share is targeted at a chat where the sender already has social capital, and each install auto-connects to the sender without any "add friend" action.

### Why no ads at v1

- The product asks for the most sensitive permission on the phone. An ad SDK in the same binary makes "we only use contacts to find friends" impossible to say with a straight face, and the privacy label would have to admit tracking.
- At launch scale (say 20k DAU) ad revenue is roughly $30–60/day. That does not pay for the retention hit of an interstitial in a 90-second session.
- The subscription (below) needs a trustworthy, quiet product to sell against. Ads spend that trust down before it exists.

### Monetization design (built later, designed now)

**Kith Plus**, $2.99/month or $19.99/year, StoreKit 2, introduced around day 75 once D30 is measured.

| Included | Why people pay |
|---|---|
| Puzzle archive (replay any past day, unranked) | Missed-day guilt; travel |
| Second daily puzzle (see roadmap) | More time with friends on the board |
| Streak freeze (1 per month) | Loss aversion, the single most requested feature in every streak product |
| Circle upgrades: 50 → 250 members, co-admins, custom emoji set | Offices and extended families |
| Detailed stats, head-to-head history with any friend | Bragging material |

The free game stays complete: one puzzle, full boards, circles up to 50, all social features. Nothing that makes a friend's board worse if they don't pay. Target: 4–6% of D30-retained users on Plus within 60 days of launch, which at 50k MAU covers infra and one salary.

---

## 3. Notification strategy summary

| Strategy | Trigger | Guardrail |
|---|---|---|
| Daily drop | User-chosen time | Off by default if the user said "No thanks" at onboarding; re-offered once after day 7 |
| Streak at risk | 20:00 local, unplayed, streak ≥ 2 | Never for streak 0–1 (nothing to lose yet) |
| Passed on the board | Friend's score exceeds yours today | Once per day, batched ("Sam and 2 others passed you") |

Global rules: max 2 pushes/day, silence after 14 days of inactivity, every push deep-links to the exact screen it mentions, and every push type is toggleable from the notification itself (iOS notification settings link).

---

## 4. Measuring success

### Retention targets

| Window | D1 | D7 | D30 | Rationale |
|---|---|---|---|---|
| Days 0–30 | ≥ 35% | ≥ 20% | — | Launch cohort is friends-of-friends, motivated |
| Days 30–60 | ≥ 40% | ≥ 25% | ≥ 12% | Onboarding tuned from cohort 1 |
| Days 60–90 | ≥ 40% | ≥ 25% | ≥ 15% | Second puzzle type and widgets in market |

Segment every retention chart by **matched ≥ 1 friend on day 1** vs. **matched 0**. The gap between those lines is the product thesis. If the matched cohort is not at least 1.5× the unmatched cohort on D7, the contacts graph is not doing the work and the roadmap changes.

### Growth targets

| Metric | Definition | Day 30 | Day 90 |
|---|---|---|---|
| Share rate | `share_complete` / `puzzle_submit` (daily) | 25% | 35% |
| Invite conversion | Installs attributed to `?r=` links / share completes | 8% | 12% |
| Viral coefficient (K) | new users from shares per existing user, 7-day window | 0.25 | 0.5 |
| % installs via graph | New users who match ≥ 1 friend on day 1, or arrive via a link/code | 50% | 65% |
| Contacts grant rate | `contacts_granted` + `contacts_limited` / pre-prompt views | 65% | 70% |
| Circle adoption | Users in ≥ 1 circle | 20% | 35% |

Attribution: the `?r=` ref lands on the web page, which sets a first-party cookie and forwards to the App Store; on first launch the app asks "Have a code?" (prefilled from the pasteboard only if the user pastes). Deferred deep linking is intentionally not built; a matched contact on day 1 is a good enough proxy for "came from a friend".

### Health metrics (weekly review)

- Median solve time (target 60–100 s; drift outside means difficulty is off).
- Try distribution per day (target roughly 30/40/20/10 across 1/2/3/✗; a day with 60% first-try is too easy, 30% fail is too hard). Feeds back into the generator's gap threshold.
- Push open rate by type; kill any type under 8% open.
- Delete-account count and "contacts" mentions in App Store reviews (trust leading indicators).

---

## 5. 90-day post-launch roadmap

### Days 0–30: stabilise and instrument
- Fix what the first cohort hits; expect the OTP and contacts edge cases (limited access, dual-SIM, numbers stored without country codes) to dominate.
- Ship the **image share card** (rendered grid with the prompt) once text-share rate is known, and A/B it.
- **Nudge a friend** who hasn't played (one push per friend per day, sender-initiated).
- **Home Screen widget**: today's status and countdown; **Lock Screen widget**: streak.
- Difficulty tuning from try-distribution data.
- Decision gate at day 30: matched vs. unmatched D7 gap.

### Days 30–60: deepen circles and the board
- **Circles v2**: co-admins, member cap 250 (Plus), weekly circle digest push ("Family board: Mum won the week"), circle invite via QR.
- **Head-to-head** view between you and one friend (record, streaks, average).
- **Live Activity** countdown to the next puzzle on the Lock Screen.
- **App Clip** for `kith.app/p/:id`: play today's puzzle from the link without installing, then convert. This is the largest expected lift to invite conversion.
- Localization scaffolding (strings only; content stays English).

### Days 60–90: second puzzle and monetization
- **Second daily puzzle type**, chosen by then from prototype testing. Leading candidate: **"Pairs"**, eight tiles, four hidden pairs joined by a rule that changes daily (rhymes, compounds, anagrams, category), scored by wrong pairings and time, sharing a 4-square emoji row. It reuses the tile engine, scoring shape, and board.
- Free users get one of the two puzzles per day (alternating); Plus unlocks both, plus the archive and streak freeze.
- **Kith Plus** launch: StoreKit 2, paywall shown only from the archive, streak-freeze, and circle-limit touchpoints. No launch-day paywall.
- Everyone board gets weekly leagues of 30 (Duolingo-style) only if the unmatched cohort is large and retaining poorly.
- **Android go/no-go**: proceed if D30 ≥ 15%, K ≥ 0.4, and > 15% of share-link taps are from Android user agents on the landing page.

### Deliberately not on the 90-day roadmap
Comment threads, public profiles, user-generated puzzles, a feed of any kind, web play beyond the App Clip, and any ad SDK.
