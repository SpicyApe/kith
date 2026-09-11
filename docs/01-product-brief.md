# Kith — Product Brief

*Working title. "Kith" = the people you actually know ("kith and kin"). Alternates considered: Rally, Circle, Daily.*

## Problem

Daily puzzles (Wordle, Connections, the NYT Games bundle) already have the habit loop nailed. What they don't have is any idea who your friends are. The comparison that makes the game fun happens off-platform: someone pastes a grid into the group chat, three people reply, and by Thursday nobody remembers who's winning. The social layer is the best part of the product and it lives in iMessage, unranked and ephemeral.

The two attempts to fix this picked the wrong graph:

- **LinkedIn Games** ranks you against your professional network. Nobody wants to taunt their skip-level.
- **Duolingo-style leagues** rank you against strangers. Beating "xXsofia_99" means nothing.

The graph that makes a daily score matter is the one already in your phone: family, close friends, the group chat, the people at work you actually like.

## Audience

- **Beachhead:** friend groups and families who already share Wordle/Connections grids in a chat. Ages 18–40, group-chat-native, iPhone-heavy (which is why iOS-first is not a compromise).
- **Secondary:** small teams and offices (5–30 people) who want a low-stakes daily ritual.
- **Not the audience at v1:** hardcore puzzle solvers who want depth, or people looking for a public competitive scene.

## Core loop

1. **Play.** One original puzzle a day ("Lineup", 60–120 seconds), resets at local midnight.
2. **See where you stand** on a leaderboard made only of contacts who also play, with up/down arrows vs. yesterday.
3. **Share** an emoji grid to the group chat. The link carries an invite.
4. **A friend installs**, contact-matches with you in seconds, and appears on your board (and you on theirs).
5. **Streak + rank movement** bring both of you back tomorrow.

Every step of the loop reuses relationships that already exist. There is no "find friends" problem to solve, no follow graph to build, and no feed to moderate.

## Differentiation

| | NYT Games | LinkedIn Games | Duolingo leagues | **Kith** |
|---|---|---|---|---|
| Social graph | None (screenshot to chat) | Professional | Strangers | Phone contacts + private circles |
| Ranking | None | Connections-only board | Random cohort | Mutual contacts, circles, global fallback |
| Rank movement | — | — | Weekly promotion | Daily arrows vs. yesterday |
| Reactions | — | — | — | Emoji react + one-line taunt |
| Distribution | Brand | LinkedIn feed | Push | Share-to-chat → contact match |
| Trust posture | High | Medium | Medium | Hashed contacts, mutual-only visibility, no ads |

The wedge is narrow on purpose: one puzzle, one graph, one board. NYT will not build a contacts-based leaderboard (brand risk, privacy surface, they sell subscriptions to individuals). LinkedIn can't change its graph. That gap is durable enough to build in.

## Why now

- iOS 18 limited-contacts access made the permission feel less all-or-nothing, which lowers the trust cost of asking.
- Phone-OTP auth and hashed contact matching are commodity infrastructure (Supabase/Twilio), not a research project.
- The daily-puzzle habit is mainstream; the "post your grid" behaviour is already learned. Kith just gives it a scoreboard.

## What success looks like

- Retention: D1 ≥ 40%, D7 ≥ 25%, D30 ≥ 15% (daily-puzzle apps run above casual-game benchmarks because the habit is calendar-shaped).
- Growth: ≥ 50% of new installs arrive via a share link or match at least one contact on day one.
- Trust: contact-permission grant rate ≥ 65% on the pre-prompt, and near-zero "why do you need my contacts" reviews.

## Non-goals

Not a social network. No feed, no DMs, no follows, no public profiles. No ads. No user-generated puzzles at v1. Android only after product-market fit signals on iOS.
