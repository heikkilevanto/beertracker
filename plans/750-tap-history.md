# Plan: Tap Timeline - Location Tap History Visualization

**Status: Planning**

## Problem

The `tap_beers` table stores when each beer came on and went off each tap at each
location, but there is no way to see the full picture at a location level over
time. The beer board shows only current taps; the brew edit page shows tap
history for a single brew. We need an overview of a location's tap evolution.

## Solution

A new "Tap Timeline" page (`o=Taps`) with an HTML table:
- **Rows**: tap numbers
- **Columns**: time buckets (daily/weekly/monthly)
- **Cells**: colored by beer style, showing abbreviated beer names with CSS clipping
- **Features**: click-to-highlight across the whole table, details panel, bin-packing
  toggle, scrape times footer

## Entry Points

- New "Tap History" menu item under **Stats** → `o=Taps`
- "History" link on the Beer Board page, next to the location selector → `o=Taps&loc=<name>`
- "Tap History" link on location edit pages → `o=Taps&loc=<name>`

## URL Parameters

```
o=Taps&loc=<location_name>                    # location timeline (default: last-visited scraper location)
o=Taps&loc=<name>&tap=<N>                     # single-tap chronological detail
o=Taps&range=d30|d60|d90|d180|y1|all          # combined range+granularity (default: d30)
o=Taps&layered=0|1                            # disable/enable bin-packing (default: 1)
```

### Range+Granularity presets (combined selector)

| Value   | Range       | Granularity |
|---------|-------------|-------------|
| `d30`   | 30 days     | daily       |
| `d60`   | 60 days     | daily       |
| `d90`   | 90 days     | weekly      |
| `d180`  | 180 days    | weekly      |
| `y1`    | 1 year      | monthly     |
| `all`   | full history| monthly     |

If URL has explicit `range=` and `granularity=` params (not from the preset), those
override the preset mapping. This allows manual URL editing for custom views.

`loc` uses the location **name** (same as beerboard), not the ID, for human-readable
URLs. Resolved to a location ID via `db::findrecord` with `collate nocase`.

## Rendering Algorithm

### 1. Fetch tap periods
Query the `location_taps` view for the location, filtered by date range overlap:
```sql
SELECT * FROM location_taps
WHERE Location = ?
  AND FirstSeen <= ?      -- end of range
  AND (Gone IS NULL OR Gone >= ?)  -- start of range
  AND Tap IS NOT NULL AND Brew IS NOT NULL
ORDER BY Tap, FirstSeen
```

### 2. Create time buckets
Based on the granularity, create bucket boundaries between start and end dates.
- Daily: bucket = [start_of_day, end_of_day)
- Weekly: bucket = [Monday 00:00, next Monday 00:00)
- Monthly: bucket = [first of month, first of next month)

### 3. Bin-packing (layer assignment)
For each tap number, sort periods by FirstSeen, then assign to layers:
- Greedy: each period goes on the first layer where it doesn't overlap with
  already-placed periods on that layer.
- If `layered=0`: all periods stack vertically (no overlap checking), one row
  per period. Tap number cell gets rowspan = total periods for that tap.
- If `layered=1` (default): tap number cell gets rowspan = number of layers.

Two periods overlap if: `p1.FirstSeen <= coalesce(p2.Gone, 'now') AND p2.FirstSeen <= coalesce(p1.Gone, 'now')`.

### 4. Calculate colspan per period
For each period, count how many time buckets it overlaps with. That's the colspan.

A period overlaps a bucket if: `period.FirstSeen <= bucket_end AND (period.Gone IS NULL OR period.Gone >= bucket_start)`.

### 5. Render HTML table
```
Controls (location selector, range selector, bin-packing checkbox)
Details panel (hidden until click, "X" closes it and clears highlights)
Timeline table:
  thead: [Tap] [bucket1] [bucket2] ... [bucketN]
  tbody: rows with tap number (rowspan) + beer cells (colspan, colored, data-brewid)
Scrape times footer
```

Cell CSS: `white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 80px`
Cell content: `<span title="Full beer name" data-brewid="123" class="tap-cell" onclick="taphistoryHighlight(123)" style="background-color:#f2f21f">ShortName</span>`

## Single-Tap Detail View

When `&tap=N` is specified:
- Table: Beer (linked to brew page), Producer (linked to producer page), On since, Gone (or "On tap"), Days, Volume/Price
- Sorted by FirstSeen DESC
- Back link to the location timeline

## Details Panel Behavior

- Shown when clicking a beer cell
- Shows: beer name (linked), producer (linked), style badge, tap number, location,
  First seen, Gone (or "still on tap"), duration, prices
- "X" button closes the panel and clears highlights
- All cells with the same `data-brewid` get class `tap-highlighted` (CSS background
  brightness boost)
- No click-away-to-clear: user may scroll to see other highlights

## Scrape Times Footer

Query scrape marker rows for the location (Tap IS NULL, Brew IS NULL):
```sql
SELECT LastSeen FROM tap_beers
WHERE Location = ? AND Tap IS NULL AND Brew IS NULL
ORDER BY LastSeen DESC LIMIT 5
```
Display as "Last scraped: 2026-08-20, 2026-08-15, ..." in small gray text.

## Files to Create/Modify

| File | Action | Lines |
|------|--------|-------|
| `code/migrate.pm` | Add migration #53: `location_taps` view | +20 |
| `code/taphistory.pm` | **New module**: dispatch, fetch, bin-pack, render | ~250 |
| `code/index.fcgi` | Add `require` + GET dispatch + asset links in htmlhead() | +3 / +2 |
| `code/util.pm` (`showmenu`) | Add "Tap History" to Stats submenu | +1 |
| `code/beerboard.pm` | Add "History" link next to location selector | +2 |
| `code/locations.pm` | Add "Tap History" link on location edit page | +2 |
| `static/tap_timeline.js` | **New**: highlighting, details panel, checkbox URL builder | ~60 |
| `static/tap_timeline.css` | **New**: timeline table styles, cell clipping, details panel | ~30 |
| `doc/db.schema` (via `tools/dbdump.sh`) | Update schema dump after migration | auto |

## Migration #53 SQL

```sql
CREATE VIEW location_taps AS
SELECT
    tb.Id, tb.Location, tb.Tap, tb.Brew,
    b.Name AS BrewName, b.BrewType, b.SubType, b.Alc,
    pl.Name AS ProducerName, pl.Id AS ProducerId,
    l.Name AS LocationName,
    tb.FirstSeen, tb.LastSeen, tb.Gone,
    round(julianday(coalesce(tb.Gone, 'now')) - julianday(tb.FirstSeen)) AS Days,
    strftime('%Y-%m-%d', tb.FirstSeen) AS Since,
    strftime('%Y-%m-%d', tb.Gone) AS GoneFormatted,
    tb.SizeS, tb.PriceS, tb.SizeM, tb.PriceM, tb.SizeL, tb.PriceL
FROM tap_beers tb
JOIN locations l ON tb.Location = l.Id
LEFT JOIN brews b ON tb.Brew = b.Id
LEFT JOIN locations pl ON b.ProducerLocation = pl.Id
WHERE tb.Tap IS NOT NULL AND tb.Brew IS NOT NULL;
```

## Mobile / Scale Handling

- Table wrapped in `div.overflow-auto` for both-direction scrolling
- Cells: `max-width: 80px` (desktop), `max-width: 50px` (mobile)
- Tap # column: fixed `width: 40px`
- Details panel: full-width on mobile (pushes table down when visible)
- Taps with no data in the date range are hidden (no empty rows)
- For 61-tap venues at 30-day daily view: 30 columns × ~20 active taps = manageable

## Out of Scope

- SVG/Gantt chart rendering (keeping it HTML-table based for consistency)
- Editing tap data from this page (tap data is managed via scraping)
- Cross-location beer tracking in this view (brew's own tap history is on the brew page)
