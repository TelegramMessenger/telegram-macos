# Native macOS Settings Rows for Telegram

## Goal
Make the Telegram macOS settings screens look like native macOS System Settings (SwiftUI `Form` with `.formStyle(.grouped)`). The current settings rows are inconsistent in height, icon size, insets and separators. Define a small set of row styles and apply them consistently.

## Source of truth
- macOS System Settings
- Tinycast (third-party app that follows the same conventions)

## Core rule
Row height is determined by the row's **content type**, never by how many rows are in the card. A card is just its rows stacked; a single-row card is exactly one row tall. There is no "compact single row" or "extra padding on first/last row" variant.

The **page** decides which icon-row style is used. Never mix hub rows and standard icon rows on the same page.

## Measured values (2026-11-12, macOS 27, dark mode)
Pixel-measured from 2x captures of System Settings itself, ±0.5pt. These replace the estimates further down.

Rows. Pitch = row + 1pt separator band. A single-row card is exactly one row tall, with no separator.

| Row | Row height | Pitch in a card | Icon | Icon x / text x (from card edge) | Example |
|---|---|---|---|---|---|
| Hub icon row | 48 | 49 | 23pt | ~12.5 / 48 | General |
| Standard icon row (basic) | 42 | 43 | 20pt | ~10.5 / 40 | Accessibility, Apple Account |
| Two-line row | 52 | 53 | 26pt (Network) or 20pt (Privacy) | ~11 / 48 with 26pt, 40 with 20pt | Network, Privacy |
| Text + popup | ~37 | ~38 | none | — / 10 | Desktop & Dock |
| Text + toggle | ~36.5 | ~37.5 | none | — / 10 | Desktop & Dock |

Cards and separators:
- Card corner radius: **12pt** (circular fit, not 10)
- Gap between cards: **10pt**
- Separator: 1pt band, inset 10pt from both card edges
- Trailing toggle ends 10pt from the card edge
- Toggle is the mini `NSSwitch`, 36×16. Rendered on macOS 27: regular 54×24, small 44×20, mini 36×16, large 64×28
- Section headers are sentence case ("Power saving", not "POWER SAVING"), 13pt bold, primary text colour

Fonts:
- Row title 13pt regular; subtitle 11pt regular, secondary color
- Section header ("Vision") 13pt semibold or bold (measured 38.0pt wide: semibold renders 37.5, bold 38.7; macOS `.headline` is bold), 10pt in from the card edge
- **Text is drawn with font smoothing.** Ink coverage of native text matches `setShouldSmoothFonts(true)` and not the default 2x rendering: "VoiceOver" measures 848 native vs 870 smoothed and 643 unsmoothed. Use `TextView.smoothFonts` from commit `3b18070b` on `feature/native-context-menus`

Sidebar (System Settings sidebar):
- Row pitch 32pt; selection fills the full 32pt and runs from x=10 to x=222 (10pt side insets), **8pt** corner radius
- Icon 20pt at 9pt inside the selection; text 8pt after the icon
- Text 13pt regular; **selected text 13pt semibold** (measured 52.0pt wide for "Network": semibold renders 52.07, bold 53.6, medium 51.0)

## Original estimates
Measured from 2x screenshots of System Settings, ±1pt. Superseded by "Measured values" above.

| Style | Used for | Height | Icon | Notes |
|---|---|---|---|---|
| Hub row | Top-level list where every row opens a whole sub-screen (System Settings > General) | ~49pt | ~23-24pt squircle | Text starts ~8pt further right than the standard row |
| Standard icon row | Icon + one line on normal content pages (System Settings > Accessibility) | ~43pt | 20pt squircle | |
| Text-only row | Label with optional trailing value, popup button, toggle or (i) button | ~38pt | none | Trailing control (~22pt) does not change the height |
| Two-line row | Icon + title + subtitle (Privacy > Passkeys / Photos) | ~53pt | 20pt | Subtitle in secondary color |

Reference measurements (2x px at the same scale):
- General: row pitch 98px, icon ~46px, icon left x≈641, text x≈712, card left x≈617
- Accessibility: row pitch 86px, icon ~40px, icon left x≈636, text x≈696, card left x≈617

## Layout rules
- Card horizontal content inset: ~10pt from card edge
- Gap between cards: ~10-11pt
- Section header (e.g. "Vision", "Physical and Motor") sits above its card, bold secondary-weight title, smaller gap to its card than between sections
- Separators: start at the content inset (the icon's left edge, not the text's), end at the right content inset. This differs from iOS, which insets separators to the text
- Trailing elements (value text, chevron, count, (i), popup, toggle) are vertically centered and never affect row height
- Hub pages use a large centered hero (icon, title, description) with no section titles; groups are separated only by card gaps
- Standard pages use a compact header card (icon + title + description + link) and section titles above cards
- Do not change window or panel corner radii; fix alignment through size and position only

## Mapping to Telegram
- Top-level Telegram Settings list: hub rows
- All sub-screens: standard icon rows, text-only rows, two-line rows
- Audit existing rows in `GeneralRows` (`GeneralRowItem` and common rows) and `SettingsUI`; replace ad-hoc heights and insets with constants for the four styles above
- Keep the constants in one place so every screen picks them up; mind the hub-package rule in `AGENTS.md` (changes to `GeneralRows` recompile many packages)

## Verification
The numbers above are eyeballed from screenshots. Before hard-coding them:
1. Build a tiny SwiftUI test app with a `Form` + `.formStyle(.grouped)` containing: a hub-style page and a standard page; text + toggle, text + popup, icon + chevron, icon + subtitle, and a single-row card
2. Read exact heights, insets, separator positions and card gaps with Accessibility Inspector or a 1x screenshot
3. Use those values as the constants, then compare Telegram side by side with System Settings in light and dark mode

## Done when
- Every settings row in Telegram uses one of the four styles
- Row heights, icon sizes, insets, separators and card gaps match System Settings within 1pt
- No page mixes hub and standard icon rows
