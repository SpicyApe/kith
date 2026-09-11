# Kith — Wireframe-Level Screen Descriptions

Five core screens. Each is described top-to-bottom as it would appear on an iPhone, with states and copy. Visual language: white/near-black background, one accent colour (a warm coral), system font, generous whitespace, no gradients. The puzzle tiles are the only "designed" object in the app; everything else is native SwiftUI.

Tab bar (after onboarding): **Today · Board · Circles · You**.

---

## Screen 1: Onboarding

A single flow of full-screen steps with a thin progress bar at the top (4 segments). Back is always available. No skip-ahead.

### 1a. Phone
- Wordmark, one line: "One puzzle a day. Ranked against people you actually know."
- Phone field with country flag/prefix picker, keyboard up on appear.
- Primary button "Continue". Footnote: "We'll text you a code. Standard rates apply."
- Legal links: Terms · Privacy (small, below the button).

### 1b. Code
- "Enter the 6-digit code we sent to +1 ••• ••• 4821"
- Six-box OTP field, SMS autofill enabled (`textContentType = .oneTimeCode`).
- "Resend code" (disabled 30 s with countdown). Auto-submits on the 6th digit.

### 1c. Name
- "What should friends call you?"
- Single field, prefilled from the device's "me" card when available. Avatar initials preview updates live.
- "Continue".

### 1d. Contacts pre-prompt
- Illustration: three contact avatars with small rank badges.
- Headline: "See which of your contacts already play."
- Body (three short lines): hashed on device · names never leave your phone · we never message anyone for you.
- Primary: "Find my friends" → fires the OS prompt.
- Secondary (same size, outline): "Not now".
- On iOS 18 the OS sheet offers Limited access; the app handles it silently.

### 1e. Straight into the puzzle
No "you're all set" screen. Step 1d transitions directly to Screen 2 with today's puzzle while the contact sync runs in the background. A small toast at the bottom, "Finding your friends…", resolves to "3 friends found" or disappears.

### Post-play onboarding tail (after Screen 3)
- **Friends found:** "3 of your contacts already play" with their three rows (name, today's score or "hasn't played yet") and a big "See the board" button.
- **No friends found:** "None of your contacts play yet. You're first." Two buttons: "Invite the group chat" (share sheet) and "Create a circle". Small link: "Have a code?"
- Then the notification pre-prompt: "Want a nudge when the next puzzle drops?" with "Yes, at 8:00 AM" (time tappable) and "No thanks". Only the Yes button triggers the OS prompt.

---

## Screen 2: Today (daily puzzle)

### Before playing
- Top: date ("Thursday, Sep 11") and puzzle number ("#142"). Right: streak pill "🔥 12".
- Prompt card, large type: "Order these by the year they were invented", subtitle "Earliest at the top".
- Five tiles stacked vertically, full width, rounded, grey background, drag handle on the right, label centred. Long-press-free drag (drag starts immediately on touch-move).
- Between tiles: no spacing gaps larger than 8 pt so the list reads as one object.
- Bottom: "Lock in" primary button, disabled until the user has moved at least one tile. Above it, tries indicator: three hollow dots.
- Timer is shown small next to the tries indicator ("0:32"), starts on appear.

### After a submission
- Correct tiles turn green and lose their drag handle (locked). One-off tiles pulse yellow once (600 ms) then return to grey. A filled dot replaces a hollow one.
- The remaining grey tiles remain draggable and can only be dropped into unlocked slots.
- Haptic: success pattern on solve, light tick on partial.

### Solved / out of tries
Transitions to Screen 3 after a 400 ms beat so the full green row is seen.

### Already played today
The Today tab shows the results card (Screen 3 content, compact) and a countdown: "Next puzzle in 9h 12m". Below it, the top three rows from Friends and a "See the board" link.

### Edge states
- Offline: puzzle cached at last open; the result is queued and submitted on reconnect. Banner: "Offline. Your score will sync."
- New day while app is open: countdown hits zero, card flips to the new puzzle.

---

## Screen 3: Results and share

- Top: big outcome line: "Solved in 2" or "Not this time". Below: score in large numerals ("520") and time ("0:48").
- The emoji grid rendered as real tiles (two rows in the example), exactly what will be shared.
- Reveal strip: the five items in correct order with their values and a one-line fact each ("Bicycle · 1817 · The first version had no pedals"). Collapsed by default to two lines; "Show facts" expands.
- Streak line: "🔥 12-day streak" with a subtle "+1" animation.
- **Rank teaser** (only if the user has ≥ 1 friend who played): "You're #2 of 5 friends today ▲1". Tapping goes to Board.
- Taunt field: "Say something to the group (optional)", 80-char counter, single line. Save on blur.
- Primary button: "Share". Opens the system share sheet with the text block. Secondary: "Copy".
- After a share completes, the button label becomes "Shared ✓" for that session (no nagging).
- Footer: "Next puzzle in 9h 12m".

---

## Screen 4: Board (leaderboard)

- Segmented control at top: **Friends · Circles · Everyone**. Under it a second, smaller control: **Today · Week · All-time**.
- Friends header line: "5 of 9 friends played today". Pull-to-refresh re-syncs contacts.
- **Row anatomy (Today):** rank number · movement chip (▲2 green, ▼1 red, – grey, NEW accent) · avatar/initials · name (local contact name, falling back to display name) · mini 5-square grid for their final try · score right-aligned · reaction button (shows existing reactions stacked, tap opens a 6-emoji picker).
- Taunts appear as a single grey line under the name, only once the viewer has played.
- Played rows first, sorted by score; then a divider "Haven't played yet" with greyed rows.
- Your own row has an accent left border and is sticky at the bottom if scrolled out of view.
- **Week / All-time:** same rows, score is the sum, movement compares to last week's final rank, no mini grid.
- **Circles tab:** a horizontal picker of circle chips at the top ("Family", "Office", "+ New"). Below, the same board for the selected circle. Circle header shows the code with a copy icon: "KITH-7F3Q ⧉".
- **Everyone tab:** header changes to a muted colour and reads "Everyone playing today · 41,203". Rows show display names only, no reactions, no taunts. Top 100 then a gap then "You · #8,412 · top 21%".
- **Empty state (Friends):** illustration, "None of your contacts play yet. Be the one who started it.", buttons "Invite" and "Create a circle", and a small "Sharing 40 contacts · Add more" line on iOS 18 limited access.

---

## Screen 5: You (profile and streak)

- Header: large avatar initials, display name, "Edit" link. Right side: streak flame with current count, small "Best: 31".
- **Heatmap:** 8 columns × 7 rows of small squares (last 8 weeks), three shades: missed / played / solved in 1. Today outlined.
- **Stats grid (2×2):** Days played · Solve rate · Avg score · Tries distribution (a tiny 4-bar histogram: 1 / 2 / 3 / ✗).
- **Your code:** "KITH-A3K9 · Share" so anyone can add the user to a circle without needing contacts.
- **Settings list** (grouped):
  - Notifications: Daily drop (time), Streak at risk, Passed on the board.
  - Contacts: status line ("Full access · synced 2h ago" / "Limited · 40 shared" / "Off"), "Sync now", toggle "Let contacts find me" with one-line explanation.
  - Circles you're in (manage/leave).
  - Privacy policy · Terms · "How matching works" (a plain-language explainer page, the same content as the privacy section of the architecture doc).
  - Delete account (red, with a confirm sheet that lists exactly what gets deleted and states it is immediate).
- Footer: version, "Made by two people who lose to their mums every day."
