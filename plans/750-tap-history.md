# Plan: Tap Timeline - Location Tap History Visualization

**Status: Planning (refined after building an HTML mock)**

## Problem

The `tap_beers` table stores when each beer came on and went off each tap at each
location, but there is no way to see the full picture at a location level over
time. The beer board shows only current taps; the brew edit page shows tap
history for a single brew. We need an overview of a location's tap evolution.

## Solution (simplified, post-mock)

A new "Tap Timeline" page (`o=Taps`) rendered as an HTML table:

- **Rows**: tap numbers (one row per tap that has any data in the range)
- **Columns**: one column per **day** (daily granularity only — no weekly/monthly)
- **Column order**: **most recent day on the left**, earlier days to the right
- **Cells**: each day-column shows the **single most recent beer** that was on
  that tap that day (see "Resolve most-recent beer" below). Consecutive days
  with the **same beer** are merged into one cell with `colspan > 1` for a clean
  Gantt-like look. Empty days render as empty cells.
- **Coloring**: cell background uses the shared `styles::brewcolor` helper
   (`code/styles.pm`), called with `"$BrewType,$SubType"`, so colors match the
   beer board and main list. The color covers the whole cell and the text fills
   it (clipped at the cell edge, no ellipsis marker).
- **Interaction**: click a cell → details panel + highlight all cells of the
  same brew across the whole table. "X" closes the panel and clears highlights.

This deliberately drops bin-packing / layering (see "Lessons learned"). The
per-day single-beer rule removes the need for multiple stacked layers.

## Entry Points

- New "Tap History" menu item under **Stats** → `o=Taps`
- "History" link on the Beer Board page, next to the location selector → `o=Taps&loc=<name>`
- "Tap History" link on location edit pages → `o=Taps&loc=<name>`

## URL Parameters

```
o=Taps&loc=<location_name>                    # location timeline (default: last-visited scraper location)
o=Taps&loc=<name>&tap=<N>                     # single-tap chronological detail
o=Taps&loc=<name>&days=14|30|60|90            # number of daily columns (default: 30)
```

- `loc` uses the location **name** (same as beerboard), not the ID, for
  human-readable URLs. Resolve via `db::findrecord` with `collate nocase`.
- `days` replaces the old range+granularity presets. Only daily granularity is
  supported now, so a single integer is enough.
- `tap=<N>` opens the Single-Tap Detail View (Section below).

## Rendering Algorithm

### 1. Fetch tap periods
Query `tap_beers` **directly** (no dedicated view — this query is only used by
this one module, so a migration/view is not worth it). Join `brews` for the name
and `locations` for the producer:

```sql
SELECT tb.Id, tb.Tap, tb.Brew, b.Name AS BrewName, b.ShortName,
       b.BrewType, b.SubType, b.BrewStyle,
       tb.FirstSeen, tb.Gone,
       pl.Name AS ProducerName, pl.Id AS ProducerId,
       tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL
FROM tap_beers tb
LEFT JOIN brews b  ON tb.Brew = b.Id
LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
WHERE tb.Location = ?
  AND tb.FirstSeen <= ?      -- end of range
  AND (tb.Gone IS NULL OR tb.Gone >= ?)  -- start of range
  AND tb.Tap IS NOT NULL AND tb.Brew IS NOT NULL
ORDER BY tb.Tap, tb.FirstSeen
```

### 2. Build daily buckets
Compute `N` day-buckets between `start` and `end` (inclusive). A day-bucket is
the half-open interval `[YYYY-MM-DD 00:00:00, next day 00:00:00)`. Store each as
`(bucket_start, bucket_end, label)`.

Reference "now" = `max(LastSeen)` for the location (the same point the scraper
last wrote). `end = now`, `start = end - days`.

### 3. Resolve most-recent beer per (tap, day)
For each fetched period and each day-bucket it overlaps, record the period for
that (tap, day). If several periods overlap the **same** day on the same tap
(this happens when a beer goes off and the next comes on within the same
calendar day — e.g. one ends `08-06 17:24` and the next starts `08-06 17:24`),
keep only the one with the **latest `FirstSeen`** (the most recent beer). This is
the rule that removes the need for layered bin-packing.

Day-bucket overlap test (half-open, strict `<`, matches the adjacency decision):

```
period overlaps day  iff  period.FirstSeen < day_end
                         AND day_start < coalesce(period.Gone, 'now')
```

### 4. Merge consecutive same-brew cells (display only)
For each tap, walk the per-day array in **display order** (most recent day
first) and merge runs of identical `Brew` (and runs of empty days) into a single
cell with `colspan = run length`. Empty runs may also be merged to reduce noise.

### 5. Render the table

```
Controls (location selector, days selector)
Details panel (hidden until click, "X" closes + clears highlights)
Timeline table:
  thead: [Tap] [oldest-day-label ... most-recent-day-label]   # reversed: recent left
  tbody: for each tap:
           <td class="tapcol">N</td>
           for each merged run:
             empty run  -> <td colspan=K></td>
              beer run   -> <td colspan=K style="background-color:#COLOR">
                              <span class="tap-cell" title="..." data-brewid=B
                                    onclick="showDetails(...)">FullBrewName</span></td>
Scrape times footer
```

Cell CSS (already validated in the mock):

```css
.tap-cell { display:block; box-sizing:border-box; width:100%;
  white-space:nowrap; overflow:hidden;
  padding:1px 2px; cursor:pointer; line-height:1.3; }
```

The background color is set on the `<td>` (via inline `style`), so it covers the
entire `colspan`; the inner `<span>` fills the cell width.

### 5b. Cell sizing and header (refined in mock)

- **Narrow fixed-width day columns.** Force every day column to a constant width
  with a `<colgroup>` using the `width` *attribute* (not `style=`, which browsers
  ignore on `<col>`): `<col width="40">` for the tap column, then
  `<col width="22" span="N">` for the days. Combine with `table-layout: fixed` and
  an explicit pixel `width` on the `<table>` itself (`40 + N*22`px) so the table
  cannot stretch and the columns stay exactly 22px regardless of cell content
  (no variable-width jitter). The table scrolls horizontally inside
  `div.overflow-auto`. A merged (`colspan > 1`) cell is exactly `22px × colspan`
  wide, so a beer on tap for several days gets a proportionally wider cell.
- **Two-row header.** Each day header cell shows the **month abbreviation on top**
  and the **day number below** (`<th class="daycol"><span class="mon">Aug</span>
  <span class="day">25</span></th>`). Month comes from a `mm -> abbr` map.
- **Full beer name, no ellipsis.** The cell renders the *complete* brew name
  (not a truncated short name). The name uses `white-space:nowrap; overflow:hidden`
  and fills `width:100%` of the (possibly merged) cell, so it is clipped at the
  **cell edge without an ellipsis (`…`) marker** — we deliberately do not use
  `text-overflow: ellipsis`. Wider merged cells therefore reveal more of the name;
  a single-day cell simply clips at its narrow edge.
- Cell CSS (validated in the mock):

```css
table.timeline { border-collapse:collapse; table-layout:fixed; /* + explicit width:40+N*22 px */ }
/* column widths are enforced by a <colgroup width=...> : tap=40px, days=22px */
table.timeline th, table.timeline td { border:2px solid #ccc; padding:0; font-size:.72em; }
table.timeline th.daycol { width:22px; }
.daycol .mon { display:block; font-size:.6em; line-height:1; color:#888; }
.daycol .day { display:block; font-size:.82em; line-height:1.1; }
.tap-cell {
  display:block; box-sizing:border-box; width:100%;
  white-space:nowrap; overflow:hidden;   /* clip at cell edge, no ellipsis */
  padding:1px 2px; cursor:pointer; line-height:1.3;
}
```

## Cell coloring

Color is taken from the **existing `styles::brewcolor` helper** (in
`code/styles.pm`), so the timeline matches the beer board and the main list
exactly. The helper is called with the same `"Type,SubType"` string the rest of
the app uses:

```perl
my $color = styles::brewcolor($c, "$BrewType,$SubType");
```

`styles::brewcolor` matches a fixed pattern list to a hex background color (e.g.
Pils/Lager → `#f2f21f`, NEIPA → `#9ec91e`, Sour/Wild → `#1a8d8d`). The cell
background is set to `#$color`. The details-panel style badge reuses the same
color (passed through from the server, so no JS color recomputation is needed).

> Note: do **not** introduce a new hue-hash coloring here — reuse
> `styles::brewcolor` so all beer-colored surfaces stay consistent.

## Single-Tap Detail View

When `&tap=N` is specified:
- Table: Beer (linked to brew page), Producer (linked), On since, Gone (or "On
  tap"), Days, Volume/Price — one row per period on that tap.
- Sorted by FirstSeen DESC.
- Back link to the location timeline.

This view is unchanged from the original plan and remains useful.

## Details Panel Behavior

- Shown when clicking a beer cell.
- Shows: beer name (linked), producer (linked), style badge, tap number,
  location, First seen, Gone (or "still on tap"), duration, prices.
- "X" button closes the panel and clears highlights.
- All cells with the same `data-brewid` get class `tap-highlighted` (CSS
  brightness boost).
- No click-away-to-clear: user may scroll to see other highlights.

## Scrape Times Footer

Query scrape marker rows for the location (Tap IS NULL, Brew IS NULL):

```sql
SELECT FirstSeen FROM tap_beers
WHERE Location = ? AND Tap IS NULL AND Brew IS NULL
ORDER BY FirstSeen DESC LIMIT 5
```

Display as "Last scraped: 2026-08-20, 2026-08-15, ..." in small gray text.

## Mock

- **Generator**: `plans/gen_tap_timeline_mock.pl` (Perl, DBI/DBD::SQLite). It
  reads the real `beerdata/beertracker.db`, applies the exact algorithm above,
  and writes a self-contained HTML file. The per-tap / per-day logic is written
  to be reusable in the real `code/taphistory.pm`.
- **Output**: `plans/tap-timeline-mock.html` — open directly in a browser (no
  server needed). Uses real Ølbaren data: 28 taps × 31 daily columns.
- Regenerate with: `perl plans/gen_tap_timeline_mock.pl`
- The location and number of days are constants at the top of the script
  (`$LOC`, `$RANGE_DAYS`).

## Lessons learned (from building the mock)

1. **Daily-only + single-beer-per-cell massively simplifies the code.** The
   original bin-packing / layering section is gone. Each (tap, day) has at most
   one beer, so there is never a need to stack periods vertically.
2. **Adjacency must be a clean `<` boundary.** When a beer goes off at exactly
   the moment the next comes on (`B.FirstSeen == A.Gone`), treat them as
   non-overlapping. With the per-day "keep the most recent" rule, the later beer
   simply wins that day's cell. This avoids the extra layer rows that `<=` would
   force (the mock originally rendered every tap as 2 rows under `<=`).
3. **Column reversal needs bucket-aligned placement.** "Most recent on the
   left" means the chronological per-day array is reversed before rendering.
   Compute each period's day-bucket `start_idx`/`colspan` in chronological space,
   then map to display space with `disp_start = N - start_idx - colspan`. Emit
   empty filler cells (`<td colspan=K>`) for gaps *and advance the column
   pointer* when emitting fillers, or the row totals drift past `N` columns.
4. **Same-day tap swaps share a bucket.** A period ending `08-06 17:24` and the
   next starting `08-06 17:24` both claim the `08-06` day-bucket. This is why the
   "most recent wins" resolution (not layered packing) is the right model — they
   genuinely coexist on that day's column.
5. **`gmtime` field order** in Perl is `(sec,min,hour,mday,mon,year)`. A mock bug
   used `(y,m,d,H,M,S)` and produced garbage dates (zero rows). Reuse the fixed
   `fmt_dt`/`parse_dt` helpers in the real code.
6. **Color by SubType**, not BrewStyle (too many near-unique values to be useful
   for grouping). Deterministic hue hashing keeps colors stable across renders.

## Files to Create/Modify

| File | Action | Notes |
|------|--------|-------|
| `code/taphistory.pm` | **New module**: dispatch, fetch (direct `tap_beers` join), per-day resolve, render | ~150 lines |
| `code/index.fcgi` | Add `require` + GET dispatch + asset links | +3 / +2 |
| `code/util.pm` (`showmenu`) | Add "Tap History" to Stats submenu | +1 |
| `code/beerboard.pm` | Add "History" link next to location selector | +2 |
| `code/locations.pm` | Add "Tap History" link on location edit page | +2 |
| `static/tap_timeline.js` | **New**: highlighting, details panel, days-selector URL builder | ~50 lines |
| `static/tap_timeline.css` | **New**: timeline table styles, cell clipping, details panel | ~30 lines |
| `plans/gen_tap_timeline_mock.pl` | **New (mock generator, Perl)** | reusable logic |
| `plans/tap-timeline-mock.html` | **New (generated mock)** | review artifact |

No database migration is needed — the query is a direct `tap_beers` join used
only by this module, so no view is declared.

## Database

No schema migration and **no `location_taps` view**. The fetch query (Section 1)
is a direct `tap_beers` join that is only used by this module, so declaring a
shared view is unnecessary. If later reused elsewhere, revisit this decision.

## Mobile / Scale Handling

- Table wrapped in `div.overflow-auto` for both-direction scrolling.
- Cells: `max-width` not fixed (the span fills the `colspan`); on very narrow
  screens long names clip at the cell edge (no ellipsis marker).
- Tap # column: fixed `width: 42px`.
- Details panel: full-width on mobile (pushes table down when visible).
- Taps with no data in the date range are hidden (no empty rows).
- For 61-tap venues at 30-day daily view: 30 columns × ~28 active taps = manageable.

## Out of Scope

- Weekly/monthly aggregation (dropped — daily only).
- Bin-packing / layered rendering (dropped — single beer per day cell).
- SVG/Gantt chart rendering (keeping it HTML-table based for consistency).
- Editing tap data from this page (tap data is managed via scraping).
- Cross-location beer tracking in this view (brew's own tap history is on the brew page).
