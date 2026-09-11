# Kith — v1 Feature Spec (MVP)

Scope rule: if a feature is not on this page it is not in v1. The cut list at the bottom is explicit so nobody re-litigates it in week 6.

---

## 1. The daily puzzle: "Lineup"

### Format

Five tiles, one ordering rule, three tries.

- The prompt names a hidden attribute and a direction: *"Order these by the year they were invented, earliest at the top."*
- Five tiles appear shuffled. Each tile is a short label (2–4 words), optional small icon.
- The player drags tiles into order and taps **Lock in**.
- After each submission, tiles in the correct position turn **green and lock**. Tiles exactly one position off flash **yellow** then return to neutral. Everything else stays **grey**. No values are revealed.
- Solved when all five are green. Three submissions maximum. After the third, the correct order and the values are revealed.
- Timer starts when the tiles are revealed and stops on the winning submission (or the third).

Target solve time: 45–110 seconds. Green-locks mean the second and third tries are fast.

### Why this format

- **Original but instantly legible.** Drag-to-order needs no tutorial; the Wordle-shaped three-row emoji grid is already understood by the group chat.
- **Granular scoring** (tries × time) ranks 30 contacts without mass ties. Wordle's 1–6 guess count produces too many ties for a leaderboard to feel alive.
- **Data-driven content** (see below) means a solo developer can pre-generate a year of puzzles from curated lists instead of hand-authoring 365 of them.
- **Ties into conversation.** "How did you not know the Eiffel Tower came before the Titanic" is a better group-chat prompt than "I got it in 4".

### Scoring

| Outcome | Base points |
|---|---|
| Solved on try 1 | 1000 |
| Solved on try 2 | 700 |
| Solved on try 3 | 400 |
| Not solved (3 tries used) | 100 |

Time penalty: `2 × min(elapsed_seconds, 120)`, so at most −240. Not-solved is a flat 100 with no time penalty.

- Solved on try 3 at 120 s → 400 − 240 = **160**, always above a fail. Playing badly beats not playing.
- Tie-break for equal scores: elapsed milliseconds, then earlier submission time.
- **Daily score** is the number above. **Weekly** = sum Mon–Sun in the viewer's local week. **All-time** = sum. Missed days score 0.

The client computes the score for instant display; the server recomputes from the submitted attempt log and is authoritative.

### Share output

```
Kith #142 · 2/3 · 0:48 🔥12
⬜🟨🟩⬜🟨
🟩🟩🟩🟩🟩
kith.app/p/142?r=7F3Q
```

One row per try, five squares per row, streak flame with count, permalink with the sender's invite ref appended. Copy is plain text so it pastes cleanly into iMessage, WhatsApp, Slack. No image share in v1.

### Content pipeline

**Source of truth: hand-curated lists, procedurally combined, human-approved.**

- A **list** is a category with a prompt template, a unit, a direction, and 20–60 **items**, each with a numeric value, a source URL, and a familiarity tag (1 = everyone knows it, 3 = niche).
  Examples: year first released (consumer products), height in metres (landmarks), distance from the Sun, year founded (companies), runtime in minutes (films), average adult weight (animals), number of letters in a capital city.
- Only **static attributes** qualify (years, physical dimensions, distances). Volatile ones (populations, prices, follower counts) are excluded so puzzles never go stale.
- **Generator** (runs 30 days ahead, nightly):
  1. Pick a list not used in the last 21 days, honouring a weekday difficulty rhythm (Mon–Tue easy, Wed–Thu medium, Fri hard, Sat–Sun medium).
  2. Pick 5 items not used in the last 90 days.
  3. Enforce constraints: every adjacent pair of values differs by at least 8% (no coin-flip pairs); at most one familiarity-3 item on easy days, at most three on hard days.
  4. Emit a puzzle row with items, correct order, and a one-line reveal fact per item.
- **Review queue:** a minimal admin web page listing the next 30 puzzles with Approve / Reseed / Edit. Nothing ships unreviewed. About one evening of the author's time per month.
- **LLM use:** allowed for *drafting* new lists and reveal facts, which a human source-checks before they enter the dataset. Never used to generate a live puzzle. Facts on screen always carry a source.
- **Seed content at launch:** 60 lists × ~25 items ≈ 1,500 items, enough for 2+ years without repetition.

### Daily reset and timezones

- A puzzle is addressed by **calendar date** (`2026-09-11`), the same worldwide, Wordle-style.
- The client requests the puzzle for its **local date**. The server accepts any date within ±14 h of UTC now; anything else is rejected.
- Results are stored against the puzzle date. "Today" on the leaderboard is the viewer's local date.
- Cross-timezone spoilers exist (a friend in Sydney plays 14 h before New York). Mitigation at v1: taunts and reveal facts are hidden from anyone who has not played that date yet. Accept the rest.
- Countdown to the next puzzle is computed client-side from local midnight.

### Streaks

- **Streak** = consecutive local dates with a submitted result (solved or not).
- One play per date per user, enforced server-side.
- **Streak-at-risk** push at 20:00 local if today's puzzle is unplayed and streak ≥ 2. One per day, never more.
- Streak shown on results screen, share text, and profile.
- Streak freeze: **cut** (candidate Plus feature).

---

## 2. Contacts and matching

### Pre-prompt (before the OS dialog)

Full-screen, one illustration, copy along these lines:

> **See which of your contacts already play.**
> Kith only uses contacts to find friends who have the app. Numbers are hashed on your phone before they leave it, names never leave your phone, and we never message anyone for you.
> [Find my friends]  [Not now]

"Not now" is a real option, same size as the primary button minus the fill. The app is fully usable without contacts.

### Authorization states

| CNContactStore state | Behaviour |
|---|---|
| `authorized` | Full sync |
| `limited` (iOS 18+) | Sync the shared subset; Friends tab shows "Sharing N contacts · Add more" |
| `denied` | Friends tab shows invite + join-code fallback; Settings deep link to re-enable |
| `notDetermined` | Pre-prompt dismissed with "Not now"; ask again once, after the 3rd day played |

### Sync

- Normalize every phone number to E.164 with the device region as default; drop anything that fails to parse.
- Client computes `sha256(e164)` per number and keeps a local map from hash to contact display name (on device only).
- Upload the hash set to the matching endpoint (see the architecture doc for the server-side HMAC step). Diff-based after the first sync: only added or removed hashes.
- Triggers: onboarding, app foreground at most once per 24 h, pull-to-refresh on Friends.
- Server returns matched `{user_id, client_hash}` pairs. The client renders the **local contact name** ("Mom", "Dev from work") in preference to the user's chosen display name, because that is the name that makes the row feel like a person you know.

### Visibility rule

**Mutual matches only.** You appear on someone's Friends board only if you have each other's numbers. This is the single most important trust property of the product and it is not configurable at v1.

- Discoverability toggle in settings: "Let contacts find me" (default on). Off = you never appear in anyone's matches and your contact hashes are deleted.

---

## 3. Circles and join codes

Circles are the private-group feature **and** the no-contacts fallback, so v1 builds one thing, not two.

- Create a circle: name (≤ 24 chars) → server issues a code like `KITH-7F3Q` and a link `kith.app/c/7F3Q`.
- Join: enter the code on the Circles tab, or open the link (universal link → app if installed, else App Store via a web landing page).
- Limits: 50 members per circle, 10 circles per user. Creator can rename, remove a member, or delete the circle. That is the entire admin surface.
- A circle has its own leaderboard (same Today / Week / All-time views).
- Circle members see each other by display name, not contact name, unless they are also mutual contacts.

---

## 4. Leaderboard

Three top-level tabs: **Friends · Circles · Everyone**. Within each: **Today · Week · All-time**.

- **Row:** rank, movement arrow (▲2 / ▼1 / – / NEW) vs. yesterday's final rank (Today) or last week's (Week), avatar or initials, name, score, mini emoji grid (Today only), reaction button.
- **Your row** is pinned at the bottom of the viewport if it scrolls off.
- **Not played yet** rows sit below the played rows, greyed, with "hasn't played yet".
- **Friends empty state:** "None of your contacts play yet. Be the one who started it." → Share invite / Create a circle.
- **Everyone:** global board, visually separated (different header colour, display names only, top 100 plus your row and percentile). Exists so a user with zero matches still sees a board. Never the default tab once a user has at least one friend.
- Rank movement is computed at read time from yesterday's results over the *current* friend set. No nightly snapshot needed at v1 scale.

---

## 5. Reactions and taunts (the whole social layer)

- **Reactions:** fixed set 🔥 👏 😂 😭 🫡 🙄. One reaction per user per friend per day, toggle on/off. Shown as small stacked emoji on the row. Reacting to someone who is not a mutual contact or circle-mate is impossible by construction.
- **Taunt:** after playing, optional one line, ≤ 80 chars, write-once per day, displayed beside your score to friends and circle-mates who have already played that day. No replies. Report and hide per user.
- No threads, no DMs, no notifications for reactions. They are discovered on the next visit, which is the point.

---

## 6. Onboarding (target: under 60 seconds to first puzzle)

| Step | Screen | Budget |
|---|---|---|
| 1 | Phone number entry (region auto-detected) | 8 s |
| 2 | OTP entry with SMS autofill | 10 s |
| 3 | Display name (prefilled from the "me" contact card if available) | 5 s |
| 4 | Contacts pre-prompt → OS prompt (sync starts in background on grant) | 8 s |
| 5 | **Today's puzzle**, immediately, regardless of match status | — |
| 6 | Results → share prompt | — |
| 7 | "N of your contacts already play" screen with their rows (or the empty state + invite) | — |
| 8 | Notification pre-prompt → OS prompt | — |

Notification permission is asked *after* the user has seen a result and a board, never on launch. Contacts is asked *before* the puzzle because the match must be ready by the time the results screen appears; the sync runs during play.

---

## 7. Notifications

Three types. All opt-in via the OS prompt, individually toggleable, with a hard cap of 2 pushes per day per user.

| Type | When | Default | Copy |
|---|---|---|---|
| Daily drop | User-chosen time, default 08:00 local | On | "Today's Lineup is up. 4 friends have already played." |
| Streak at risk | 20:00 local, only if unplayed and streak ≥ 2 | On | "12-day streak on the line. 4 hours left." |
| Passed on the board | Batched, at most one per day, after 12:00 local | On | "Sam just passed you. You're #4 among friends." |

Never: marketing, "we miss you" after churn, reaction notifications. If a user has not opened the app in 14 days, all pushes pause until the next open.

---

## 8. Profile and streak

- Header: display name, current streak (flame), longest streak.
- 8-week calendar heatmap (played / solved-in-1 / missed).
- Stats: days played, solve rate, average score, distribution of tries (1 / 2 / 3 / ✗).
- Settings: notifications (times and toggles), contacts (status, re-sync, "Let contacts find me"), circles, my join code, privacy policy, **delete account** (immediate, in-app, no email required. Apple requires this and users should see it before they trust the contacts prompt).

---

## 9. Auth and account

- Phone number + SMS OTP only. No email, no passwords, no social login, which keeps Sign in with Apple out of scope under guideline 4.8.
- One account per phone number. Changing number: cut.
- Delete account removes the user row, results, reactions, taunts, contact hashes, device tokens, and circle memberships. Circles the user created pass to the oldest member or are deleted if empty.

---

## 10. Cut from v1 (explicitly)

| Cut | Why | Earliest return |
|---|---|---|
| Second puzzle type | One format must prove retention first | Day 60–90 |
| Puzzle archive / replay past days | Monetization hook, needs Plus | Day 75+ |
| Comment threads | Moderation surface; reactions + one taunt covers 90% of the fun | Post-PMF |
| Image share card | Text pastes everywhere; image needs rendering and testing | Day 30–60 |
| Streak freeze | Plus feature | Day 75+ |
| Nudge a friend | Push-volume risk; wait for organic re-engagement data | Day 30 |
| Circle admin beyond rename/remove/delete | Nobody needs roles for 12 people | Post-PMF |
| Game Center mirroring | No product value at v1 (see architecture doc) | Maybe never |
| Android | After iOS PMF signals | Day 90+ |
| Widgets / Live Activity countdown | High retention value, not on the critical path | Day 30–60 |
| App Clip for invite links | Great for conversion, meaningful extra build | Day 60+ |
| Phone number change, multi-device merge | Rare at launch | Post-PMF |
| Localization | English only; content is English-centric | Post-PMF |
| Any ads | See monetization in the launch plan | Never planned |
