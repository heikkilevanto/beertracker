# Plan: Beer Board Redesign — Collapsible Controls, JS Filtering, Historical Datetime

**Status: Done**

## Problem

The beer board controls are inline with the beer list. The user wants:
1. "Beer List" text + location selector kept visible; rest of controls in a hidden section.
2. Client-side JS text filter (board-only, like main list), plus PA filter.
3. Clicking a beer style opens controls and filters by that style.
4. A datetime field (`bd` param) defaulting to now; supports `HH`, `HH:MM`,
   `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, `-N`, `Y`, `YY`. "Show" reloads via GET.
5. Location-level external links (www, untappd) moved into the hidden controls section, on one line.
6. A "Clr" button to clear board filtering.

## Key Design Decisions (confirmed by user)

- **Historical data**: Query `tap_beers` where
  `FirstSeen <= <datetime> AND (Gone IS NULL OR Gone >= <datetime>)`.
- **Parameter name**: `bd` (beerboard datetime).
- **Filter scope**: Board-only, client-side JS. No URL params for filtering.
  Datetime "Show" is a GET reload that clears JS filters.
- **Datetime format**: Combined `YYYY-MM-DD HH:MM` in one field.
  Date-only input uses current time (not 00:00).
- **extlink_html**: Stays in expanded row only (compact row too long for mobile).
- **Location links (www/untappd)**: Move from control line into hidden section, one line.
- **PA button**: Sets filter text to "PA" (not a toggle).
- **Clr button**: Clears the filter text and resets to show all beers.

## Implementation Steps

### Step 1: `code/util.pm` — Add `parse_beerboard_date()`

Parse user-entered datetime strings into SQL-safe `YYYY-MM-DD HH:MM:SS` string:
- Empty/missing → return `undef` (means "now / current taps")
- `YYYY-MM-DD HH:MM` → as-is (padded to seconds)
- `YYYY-MM-DD HH` → `YYYY-MM-DD HH:00:00`
- `YYYY-MM-DD` → today's time + that date
- `HH:MM` → today at that time (local)
- `HH` → today at that hour
- `YY` → day before yesterday, at now's time
- `Y` → yesterday, at now's time
- `-N` → N days ago, at now's time (N from `^-\d+$` or `^-(\d+)d$`)

### Step 2: `code/beerboard.pm` — `load_beerlist_from_db()` add `$as_of` param

When `$as_of` is set, query `tap_beers` directly (not `current_taps`):
```sql
SELECT ... (same columns)
FROM tap_beers tb
  JOIN brews b ON tb.Brew = b.Id
  LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
  LEFT JOIN (...) ur ON ur.Brew = tb.Brew
  LEFT JOIN (...) ug ON ug.Brew = tb.Brew
WHERE tb.Location = ?
  AND tb.FirstSeen <= ?
  AND (tb.Gone IS NULL OR tb.Gone >= ?)
  AND tb.Tap IS NOT NULL AND tb.Brew IS NOT NULL
ORDER BY tb.Tap
```
Pass `$as_of` as two params (for FirstSeen and Gone comparison).

### Step 3: `code/beerboard.pm` — Restructure controls

**Visible (always)**: "Beer List" label (clickable → toggle controls) + location dropdown.

**Hidden section** (`#board-controls`, initially `display:none`):
- Datetime input + "Show" button (GET form to `?o=Board&loc=XX&bd=VALUE`)
- Text filter input + PA button + Clr button (JS)
- Location www/untappd links on one line (moved from control line)
- Reload button (existing scrapeboard::post_form)
- (Exp) / (Collapse All) links

### Step 4: `code/beerboard.pm` — Row rendering changes

- Add `data-style`, `data-maker`, `data-name` attributes to beer row `<tr>` for JS filtering.
- Make `styles::brewstyledisplay()` output clickable: `<a href='#' onclick='openControlsAndFilter("STYLE")'>...</a>`.
- Remove hardcoded `q=PA` server-side special case.

### Step 5: `static/beerboard.js` — Add JS functions

- `toggleControls()` — toggle `#board-controls` visibility.
- `applyBoardFilter(query)` — tokenize, hide non-matching rows by data attributes.
- `openControlsAndFilter(query)` — show controls + apply filter.
- `applyPAFilter()` — `applyBoardFilter("PA")`.
- `clearBoardFilter()` — clear filter input, show all rows.

## URL Flow

- `o=Board&loc=Ølbaren` — current board
- `o=Board&loc=Ølbaren&bd=2026-08-20` — as of Aug 20
- `o=Board&loc=Ølbaren&bd=14:00` — today at 14:00
- `o=Board&loc=Ølbaren&bd=Y` — yesterday
- Filtering (text/PA/style clicks) is JS-only. `bd` GET reload clears JS filters.
