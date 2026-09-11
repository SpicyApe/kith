# Kith — Technical Architecture

Designed for a 1–3 person team shipping iOS in 8–12 weeks. The bias throughout is toward fewer moving parts, with the puzzle rules living in data so a future Android client is a thin renderer.

---

## 1. Client: native SwiftUI, iOS 17+

**Decision: native Swift/SwiftUI, not React Native.**

| Concern | Native SwiftUI | React Native / Expo |
|---|---|---|
| Contacts framework, incl. iOS 18 `limited` state | First-class, no bridge lag | `expo-contacts` works but lags OS changes by months |
| SMS OTP autofill, haptics, share sheet | Free | Free via modules, occasional version churn |
| Drag-to-reorder puzzle UI at 120 Hz | `List` + custom gesture, native feel | Achievable, needs a gesture library and tuning |
| Widgets / Live Activities (Day 30–60 roadmap) | WidgetKit, SwiftUI-only anyway | Requires a native target regardless |
| App Clip for invite links (Day 60+) | Supported | Not supported |
| Android later | Rewrite the client (~4–6 weeks, backend unchanged) | Reuse most of the client |
| Team fit | One iOS engineer builds the whole client | Same, if the team is JS-native |

The features that most differentiate the product on the roadmap (widgets, Live Activity countdown, App Clip, Game Center if ever) all require native code even under React Native. Android is explicitly post-PMF, and the backend holds every rule that matters (scoring, matching, ranking), so an Android rewrite is a rendering job. If the team were two JS engineers with no Swift, Expo would be defensible, but the Contacts and permission surface is exactly where a bridge causes subtle bugs, and it is the trust-critical path.

**Client structure**

- `Auth` — phone/OTP via Supabase Auth SDK, session in Keychain.
- `Contacts` — normalization (PhoneNumberKit), hashing (CryptoKit SHA-256), local hash→name map in an encrypted on-device store, diff sync.
- `Puzzle` — a pure `LineupEngine` (state machine: reveal → attempt → lock → solved/failed) with no UI dependencies, unit-tested. Scoring is duplicated here for instant feedback; the server is authoritative.
- `Board`, `Circles`, `Profile` — SwiftUI views over a small repository layer.
- `Push` — APNs token registration, notification categories.
- Local persistence: SwiftData for cached puzzle, last results, and the friend list, so the app opens instantly offline.

---

## 2. Backend: Supabase (Postgres + Auth + Edge Functions + pg_cron)

**Decision: Supabase on the Pro plan.** One managed Postgres, phone OTP auth via Twilio Verify built in, row-level security, Deno edge functions for the few endpoints that need a secret, and `pg_cron` for scheduled jobs. Total infra at launch: about $25/month plus roughly $0.05 per OTP and $99/year for Apple.

Alternative considered: a Hono/TypeScript API on Railway with a Railway Postgres. Equivalent capability, but phone auth, RLS, and cron are hand-built there. Worth revisiting only if edge-function cold starts or vendor lock-in become real problems.

### Services (logical; all live in one Supabase project)

| Service | Implementation | Notes |
|---|---|---|
| **Auth** | Supabase Auth, phone provider, Twilio Verify | Rate-limited by Supabase; one account per E.164 |
| **Contact matching** | Edge function `match-contacts` | Holds the HMAC pepper; the only code path that touches contact hashes |
| **Puzzle delivery** | Direct table read via RLS, `GET puzzles?date=eq.YYYY-MM-DD` | Date validated to ±14 h of UTC now by a Postgres policy |
| **Result submission** | Edge function `submit-result` | Validates the attempt log, recomputes score, enforces one-per-date |
| **Leaderboard** | SQL views + RPC `board(kind, scope_id, period, date)` | Friends ≤ a few hundred rows; computed per request, no cache at v1 |
| **Reactions / taunts** | Tables with RLS | Insert allowed only where a mutual match or shared circle exists |
| **Notifications** | `pg_cron` every 15 min → edge function `send-pushes` → APNs (HTTP/2, token auth) | Timezone-bucketed; see below |
| **Puzzle generator + review** | `pg_cron` nightly → edge function `generate-puzzles`; a tiny Next.js admin page behind Supabase auth for approval | Author-only |
| **Invite landing** | Static site at `kith.app` (Cloudflare Pages) with `/p/:id`, `/c/:code`, `/i/:code` → App Store + Universal Links | Also hosts the privacy policy |

### Data model (Postgres)

```
users            id, phone_hmac (unique), display_name, tz, discoverable bool,
                 created_at, last_open_at
devices          user_id, apns_token, env, updated_at
contact_hashes   owner_id, contact_hmac            -- no names, no raw numbers
matches          user_a, user_b (a<b), mutual bool, updated_at   -- materialized
circles          id, code (unique), name, owner_id, created_at
circle_members   circle_id, user_id, joined_at
lists            id, prompt_template, unit, direction, difficulty_hint
list_items       id, list_id, label, value numeric, source_url, familiarity 1..3
puzzles          date (pk), list_id, item_ids int[5], correct_order int[5],
                 facts text[5], status approved|pending, difficulty
results          user_id, puzzle_date, attempts jsonb, tries int, solved bool,
                 elapsed_ms, score int, submitted_at, tz     -- pk (user_id, puzzle_date)
reactions        from_user, to_user, puzzle_date, emoji         -- pk (from,to,date)
taunts           user_id, puzzle_date, text, hidden_by uuid[]   -- pk (user_id, date)
notification_log user_id, kind, sent_at                          -- enforces daily caps
```

Streak is derived (a SQL function over `results` for a user), not stored; cheap at this scale and never drifts.

**Access rules that fell out of review** (all in `supabase/migrations/0001_init.sql`, verified by `supabase/tests/schema_check.mjs`, which runs the migration in an in-process Postgres with an `auth` shim and a non-superuser role):

- Every policy is scoped `to authenticated`; `anon` can read nothing, including puzzles (the row carries the answer key).
- Helper functions that take an arbitrary user id (`can_see(a, b)`, `streak(u)`, `friend_ids(u)`) are revoked from clients. Clients get only caller-scoped wrappers: `can_see(target)`, `my_streak()`, `is_circle_member(circle)`. Without this, any signed-in user could walk the entire mutual-contacts graph.
- `users` uses column-level grants: clients can never read `phone_hmac` and can update only `display_name`, `tz`, `discoverable`, `last_open_at`.
- `invite_code` and `circles.code` are server-generated (10 uppercase hex chars, format-checked). Clients cannot choose or change a code. `join_circle` is limited to 10 attempts per hour per user so codes cannot be walked.
- Circle membership is checked through a `security definer` function, never by a policy that queries its own table (Postgres rejects that as infinite recursion).
- `events` accepts only the 15 declared names plus `circle_join_attempt`, capped at 60 rows per user per minute through the `track` RPC; direct inserts are not allowed.
- `users.tz` is validated against `pg_timezone_names` so a bad value can never break `streak` or the push scheduler.
- Turning off "Let contacts find me" is a database trigger, not an app promise: the update deletes the user's stored contact hashes and recomputes every match edge involving them in the same transaction, so they drop off friends' boards immediately.
- Contact sync is capped three ways: 5,000 hashes per request, 20,000 per day, one full sync and 12 requests per hour. A request with no hashes returns the current friend list without touching the graph.

### Daily unlock, timezone-aware

No unlock job exists. Puzzles are addressed by date and pre-generated 30 days ahead. The client asks for its local date; the RLS policy allows reads where `date BETWEEN (now() - 14h)::date AND (now() + 14h)::date`. Every timezone on Earth gets its puzzle at local midnight with zero scheduling.

### Notifications

- Users store `tz` (IANA) at signup and on every open.
- `pg_cron` runs every 15 minutes and calls `send-pushes`, which selects users whose local time is within the current 15-minute window for each kind (daily drop at the user's chosen time, streak-at-risk at 20:00 local if `results` has no row for today and streak ≥ 2, "passed" after 12:00 local if a friend's score today exceeded the user's and no "passed" push was sent today).
- `notification_log` enforces the 2/day cap and 14-day-inactive pause.
- APNs via HTTP/2 with a `.p8` token, no third-party push vendor at v1.

### Leaderboard computation

```sql
-- friends, today
select u.id, u.display_name, r.score, r.tries, r.elapsed_ms, r.attempts
from matches m
join users u on u.id = case when m.user_a = $me then m.user_b else m.user_a end
left join results r on r.user_id = u.id and r.puzzle_date = $date
where ($me in (m.user_a, m.user_b)) and m.mutual
order by r.score desc nulls last, r.elapsed_ms asc nulls last;
```

Rank movement runs the same query for `$date - 1` over the same friend set and diffs positions. With friend lists in the tens to low hundreds this is sub-millisecond. "Everyone" uses a materialized view refreshed every 5 minutes (`rank() over (order by score desc, elapsed_ms)`), limited to the top 100 plus a percentile lookup for the caller.

---

## 3. Contact matching: privacy by design

This is the part of the system that decides whether the product is trusted. The design goals, in priority order:

1. Raw phone numbers of non-users never reach the server.
2. Names and any other contact fields never leave the device.
3. A database leak reveals nothing about who is in whose contacts.
4. Nobody can enumerate who uses the app.
5. Users can see, revoke, and delete everything, immediately.

### Flow

```
Device                                        Edge function (holds PEPPER)             Postgres
------                                        ----------------------------             --------
E.164 normalize each number
h = sha256(e164)          --- TLS, batch ---> for each h: c = HMAC_SHA256(PEPPER, h)
keep {h -> name} locally                      upsert contact_hashes(owner, c)   -----> stored: c only
                                              lookup users where phone_hmac = c ----> matched user ids
                                              recompute matches.mutual for owner
                       <--- {user_id, h} ---  return matches (echoing the client's h
                                               so it can render the local name)
```

- `users.phone_hmac` is computed the same way from the verified sign-in number, so a match is `HMAC(PEPPER, sha256(number)) = HMAC(PEPPER, sha256(number))`.
- The plain `sha256(e164)` that the client sends is **not** considered secret (the phone-number space is small enough to brute-force) and is therefore never written anywhere server-side. It exists only in the request body in memory.
- The **pepper** lives in the edge-function secret store, never in Postgres. Without it, a stored HMAC cannot be brute-forced back to a number, and two databases cannot be joined on it.

### What is stored, and why

| Data | Stored? | Where | Why |
|---|---|---|---|
| Contact names, emails, photos | Never | — | Not needed; rendered from the local address book |
| Raw phone numbers of contacts | Never | — | Hashed on device |
| `sha256(number)` of contacts | Never persisted | Request memory only | Brute-forceable, so not kept |
| `HMAC(pepper, sha256(number))` of contacts | Yes | `contact_hashes` | Required for the **mutual** check: A appears on B's board only if B is in A's list *and* A is in B's list |
| The user's own verified number | Yes, as HMAC | `users.phone_hmac` | Login identity; raw E.164 is held by the auth provider under its own policy |
| Matches | Yes | `matches` | The friend graph; only mutual rows are ever readable |

Storing peppered hashes of non-users' numbers is the one deliberate tradeoff. Without it, mutuality cannot be enforced and a one-sided match would let anyone who saves your number see your scores. The stored value is unlinkable without the pepper, carries no name, and is deleted on account deletion, on revoking contacts access, or on turning off "Let contacts find me".

### Abuse controls

- Match uploads limited to 5,000 hashes per request, 20,000 per user per day, one full sync per hour. A user with more than 20,000 contacts is not a user.
- Match responses only ever include users who are mutual with the caller, so uploading a hash list cannot be used to test "does +1 555 0100 use Kith?" — the target would also have to have the attacker's number saved.
- `discoverable = false` removes the user from all match computations and deletes their `contact_hashes`.

### Deletion

- Revoke contacts in iOS Settings: on next open the client detects `denied`, calls `delete-contact-hashes`, and the server drops the user's rows in `contact_hashes` and recomputes affected `matches` to non-mutual.
- Delete account (in app, no email): one SQL function, `delete_account(u)`, run by the `delete-account` edge function with the service role. It hands owned circles to their oldest member (or deletes empty ones), scrubs the user's id from other users' taunt hide-lists, then deletes the `auth.users` row, which cascades through `users` to devices, contact hashes, matches, results, reactions, taunts, memberships, puzzle starts, sync and notification logs; `events` keeps rows with the user id set to null. All in one transaction, confirmed on screen. The admin-API delete runs afterwards as a no-op safety net. Backups age out in 30 days; the policy says so.

### App Store representation

**Privacy manifest (`PrivacyInfo.xcprivacy`)**: declares Contacts collected, linked to user, purpose App Functionality; Phone Number collected, linked, purposes App Functionality; User ID linked; no tracking, `NSPrivacyTracking = false`; required-reason APIs: UserDefaults (CA92.1), file timestamp (C617.1) if used.

**App Store privacy label ("Data Linked to You")**

| Category | Data | Purpose |
|---|---|---|
| Contact Info | Phone Number | App Functionality |
| Contacts | Contacts (hashed) | App Functionality |
| Identifiers | User ID | App Functionality |
| Usage Data | Product Interaction (puzzle results) | App Functionality, Analytics |
| User Content | Other (taunts, reactions) | App Functionality |

Data Not Collected: location, purchases, browsing, health, financial, diagnostics beyond crash logs (if a crash reporter is added, add Diagnostics → Crash Data, not linked).

**Info.plist purpose string** (`NSContactsUsageDescription`): "Kith uses your contacts only to find friends who already play. Numbers are hashed on your phone; names never leave it."

**Guideline compliance**

- 5.1.1(ii): contacts are optional; the app is fully functional after "Not now".
- 5.1.1(iii): no data is used for a purpose other than the one stated; contacts are never used to send invitations on the user's behalf.
- 5.1.2(i): no sharing with third parties; the privacy policy says so in one sentence.
- 5.1.1(v): account deletion available in-app.
- 4.8: no third-party login offered, so Sign in with Apple is not required.

**Privacy policy** (plain-language sections, each under 100 words): what we collect, how matching works (the diagram above in words), what we never store, how to turn it off, how to delete, retention (30-day backups), no ads, no data sales, contact address.

---

## 4. Game Center / Play Games vs. custom leaderboards

| | Game Center leaderboards | Custom (this design) |
|---|---|---|
| Rank against phone contacts | Not possible; GC friends only, and the friends list requires its own permission | Native to the design |
| Circles / private groups | Not supported | Yes |
| Rank movement vs. yesterday | Not exposed | Trivial |
| Reactions and taunts | No | Yes |
| Anti-cheat | Server-signed submissions, good | Recompute from attempt log, adequate |
| Cost / setup | Free, some App Store Connect config | Part of the backend already needed for matching |
| Android parity | Play Games is a separate system with a separate graph | One backend |
| Distribution | GC achievements/leaderboards appear in the Games app on iOS 26+ | None |

Verdict: build custom. Game Center cannot express the product's core idea (the contacts graph) and would add a second friends concept that confuses the trust story. Mirroring daily scores to a GC leaderboard later is an afternoon of work if the Games app ever becomes a discovery channel worth having.

---

## 5. Cheat resistance (proportionate to v1)

- Results are submitted as an attempt log (each try's permutation and elapsed time); the server recomputes feedback, tries, solve state, and score with `supabase/functions/_shared/lineup.ts`, which is a behavioural twin of the Swift engine and is held in lock-step by a shared golden-vector fixture that both test suites read. The log is rejected if it is unsolved with fewer than three tries, repeats an order, moves a locked tile, has non-monotonic or absurd elapsed times, or continues after a solve.
- Elapsed time has a server-side floor. The client calls `start_puzzle(date)` at reveal, which records the first start in `puzzle_starts`. On submit, the stored elapsed is `max(client, server − 3 s grace)`, so a client cannot claim 3 seconds for a 90-second solve, while an honest client that reports more time than the server saw is taken at its word. If no start row exists (played offline), the client value is stored and `results.elapsed_source` says so.
- One result per user per date, enforced by primary key.
- The puzzle payload carries labels and the correct order (required for offline play and instant green/yellow feedback) but not values or reveal facts; those are readable only for dates the user has already played. Someone proxying their own traffic to read the order is accepted, same as asking a friend.
- Everything else (screenshot-and-ask-a-friend) is accepted. The leaderboard is among people who will call you out at dinner.

---

## 6. Observability and analytics

- Crash reporting: MetricKit + Apple's crash logs at v1; add Sentry only if MetricKit proves insufficient.
- Product analytics: a single `events` table written via one RPC (`track(name, props)`), 15 event names max (`onboard_step`, `contacts_granted`, `contacts_limited`, `puzzle_start`, `puzzle_submit`, `share_tap`, `share_complete`, `match_found`, `circle_create`, `circle_join`, `push_open`, `board_view`, `react`, `taunt`, `delete_account`). Dashboards are SQL. No third-party analytics SDK, which keeps the privacy label honest.

---

## 7. Build order (dependency-driven)

1. Supabase project, schema, RLS, phone auth. Content tables seeded with 60 lists.
2. `LineupEngine` + puzzle screen + local scoring (playable offline against a hardcoded puzzle by end of week 2).
3. `submit-result`, results screen, share text.
4. Contacts pre-prompt, normalization, hashing, `match-contacts`, Friends board.
5. Circles, join codes, landing site, universal links.
6. Reactions, taunts, rank movement, Everyone board.
7. Push pipeline, notification settings, `pg_cron` jobs.
8. Profile, heatmap, delete account, privacy manifest, privacy policy.
9. Generator + admin review page, 30 days of approved puzzles.
10. TestFlight with ~30 people from one real group chat. Fix what they hit. Submit.
