# Kith — Visual design for the games

Why: the first games-hub round was functionally complete but looked like a stock settings
app. Two concrete complaints drove this pass: the boards are not appealing next to the
LinkedIn games or Wordle, and Stars' translucent system tints and Duo's ●/○ marks are hard
to tell apart. This document is the single source of truth for the restyle; the SwiftUI
code and the HTML mockup (`docs/mockups/games-ui.html`) both follow it.

Inspiration, not imitation: flat high-contrast tiles, bold rounded numerals, one strong
colour per game, thick region outlines, almost no chrome. No LinkedIn or NYT names, icons
or copy.

## Tokens

Defined once in `apps/ios/Kith/Views/GameTheme.swift` as `Theme` (colours are dynamic
light/dark via `UIColor { trait in … }`).

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | `#1C1C1E` | `#F2F2F7` | grid lines, star, waypoint discs, headline text |
| `line` | `ink` at 22 % | `ink` at 22 % | Quint's unfilled tile border |
| `paper` | `#FFFFFF` | `#1C1C1E` | empty cell fill |
| `paperMuted` | `#EFEFF3` | `#2C2C2E` | given cells, pills, secondary buttons |
| `danger` | `#D9342B` | `#FF6B5E` | conflicts |
| `dangerWash` | `#FFE3E0` | `#4A2622` | conflicting cell fill in Duo |
| `lineup` | `#3B6FE0` | `#6C93F2` | Lineup's game colour (matches AccentColor) |
| `stars` | `#6E56CF` | `#9B86F0` | Stars' game colour |
| `duo` | `#F5A524` | `#F7B955` | Duo's game colour and its ● mark |
| `duoAlt` | `#4C5BD4` | `#7C8AF0` | Duo's ◆ mark |
| `trail` | `#1F9E89` | `#3FC3AC` | Trail's game colour and its path |
| `quint` | `#C8377B` | `#E85D9B` | Quint's game colour (hub tile, Play, Share) |

## Quint

6 × 5 letter tiles, 58–62 pt on a 390-pt phone with 6 pt gaps, radius 6, `paper` fill and a
2 pt `line` border; a typed letter thickens the border to `ink`. After a guess the row flips
tile by tile (skipped under Reduce Motion) into hit = `trail` fill with white text, near =
`duo` fill with white text, miss = `paperMuted` fill with `ink` text. Letters are rounded
black 900 weight, uppercase. The keyboard is three rows of `paperMuted` keys (46 pt tall,
6-pt radius, ENTER and ⌫ wider) that take each letter's best mark; missed keys fade to 35 %.
A not-a-word guess shakes the row. Hub tile icon: a 3×3 grid of squares in white on `quint`.

Corner radius 14 (cards, primary buttons), 10 (pills), 0 inside grids (cells are flush;
only the board's outer corners are rounded, radius 10). Typography is the system font with
`design: .rounded` for every numeral and headline; text styles keep Dynamic Type.

## Stars region palette

Ten opaque fills with distinct hue **and** lightness, so neighbours never blur even for
deuteranopia; a dark-mode twin for each. The 0.28-opacity system tints are gone.

| # | Light | Dark |
|---|---|---|
| 0 lavender | `#C9B8F0` | `#4E3F7A` |
| 1 peach | `#FFC9A3` | `#7A4A2A` |
| 2 sky | `#A9CFFF` | `#2C4A78` |
| 3 mint | `#B5E8B0` | `#2E5E33` |
| 4 lemon | `#F3EC8E` | `#6B6320` |
| 5 rose | `#F5B3C8` | `#7A3A52` |
| 6 sand | `#D9CBA8` | `#5A5040` |
| 7 aqua | `#9EDCE0` | `#23575C` |
| 8 coral | `#FF9C8A` | `#7A3A30` |
| 9 slate | `#CFD4DC` | `#4A5060` |

Region **outlines** are what make Stars readable: a 2.5 pt `ink` line on every edge where
the region changes, a 0.75 pt `ink` at 22 % opacity between cells of the same region, and a
2.5 pt `ink` border around the board. Cells have zero spacing. The
`accessibilityDifferentiateWithoutColor` glyph stays (top-left, `ink` at 35 %).

Marks: ★ is `star.fill` in `ink` at 56 % of the cell; a conflicting star is `danger` with a
2 pt `danger` inner ring on its cell; ✕ is `xmark` semibold in `ink` at 40 % opacity, 34 %
of the cell.

## Duo

White (`paper`) cells with the same line system as Stars (0.75 pt dividers, 2.5 pt border,
no region lines). The two marks differ by shape and colour, never colour alone:

- ● = `circle.fill` in `duo` (amber), 52 % of the cell.
- ◆ = `diamond.fill` in `duoAlt` (indigo), 52 % of the cell.

Givens sit on `paperMuted` and are not tappable. A cell in violation gets `dangerWash` fill
plus a 2 pt `danger` inner ring. Constraint badges are 20 pt `paper` circles with a 1 pt
`ink` 30 % border and a bold `equal` / `xmark` glyph in `ink`, centred on the shared edge and
drawn above the cells. Share text keeps ●/○ (wire format is unchanged).

## Trail

`paper` cells with the divider/border system. The path is drawn under the waypoint discs:
`trail` colour, width 0.42 × cell, round caps and joins, through cell centres, with the
current end capped by a slightly larger dot (0.5 × cell). Visited cells get a `trail` wash
at 14 % opacity. Waypoints are `ink` discs (0.66 × cell) with a white bold rounded number;
the next required waypoint carries a 2.5 pt `trail` ring so the player always knows where
to go. When the path is complete the whole path animates to 100 % opacity with a short
scale bounce (skipped under Reduce Motion).

## Hub (Today tab)

Large title "Today", then a pill row: a streak pill (`flame.fill` + count, `paperMuted`
fill, `ink` text) and a countdown pill ("New games in 7h 12m"). Then one card per game in a
plain list section (no inset-grouped chrome): 56 pt icon tile with the game's colour and a
white SF Symbol (`lineup` `square.stack.3d.up`, `stars` `star.fill`, `duo` `circle.grid.2x2.fill`,
`trail` `point.topleft.down.to.point.bottomright.curvepath.fill`), title in `.title3.bold`,
status line in `.subheadline` secondary, and on the right either a **time badge** (solved:
`m:ss` in a `paperMuted` capsule, monospaced rounded), "Gave up" in secondary, or a filled
"Play" capsule in the game's colour. Cards are 14-radius, `paper` fill, 1 pt `ink` 8 %
border, 12 pt gap. Row identifiers, disabled states and the offline notice are unchanged.

## Game host chrome

Navigation title inline: game name in `.headline`, under it the timer as a `paperMuted`
capsule with monospaced rounded digits (`game.timer`). Trailing toolbar: a `questionmark.circle`
button (`game.help`) that presents a short rules sheet per game (three bullets from
docs/07, and a 3×3 example rendered with the same cell styles). Below the board, a two-button
row: **Reset** (bordered, `paperMuted`) and **Give up** (bordered, `danger` text), 44 pt
tall, 14-radius; Done appears in the accent when the board is complete. Board horizontal
padding 16 (8 at n ≥ 9).

## Results (grid games)

Headline in `.largeTitle` rounded bold ("Solved!", "Gave up"), a one-line subtitle
("Stars #12 · 8×8"), then three stat columns, each a rounded-bold 34 pt number over a
`.caption` label: Time, Score, Mistakes. Then the share preview (emoji rows in a `paperMuted`
14-radius card, monospaced) and a full-width filled **Share** button in the game's colour.
The rank teaser and "Done" stay as they are; identifiers unchanged.

## Lineup

Unchanged mechanics. The tiles pick up the same tokens: `paper` fill, 14 radius, 1 pt `ink`
8 % border, locked tiles in `mint`-ish success wash with a `checkmark.circle.fill`; the
results screen gets the three-column stat layout above.

## Accessibility

Every rule above is colour + shape (or line weight): region lines, glyph shapes, rings.
Contrast of `ink` on every region fill is ≥ 7:1 in light mode and ≥ 6:1 in dark mode (the
palette was chosen by hand for that). 44 pt targets everywhere except the ≥ 9×9 grids
(documented exception), Reduce Motion drops the bounce and the pulse, Dynamic Type applies
to all text outside the board.
