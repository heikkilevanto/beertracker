# Plan: Graph over annual statistics (issue #176)

## Decisions

- Graph shows money spent per year, stacked by location (matching the Dennis screenshot in the issue).
- X-axis: years (oldest → newest). Y-axis: total kroner spent.
- Top N locations by total spend across all years; N defaults to 8, respects the existing `maxl` URL parameter.
- Remaining locations are aggregated into an "Other" bucket.
- Only years with at least some spending are shown.
- Graph is generated with gnuplot, following the same pattern as `ratestats.pm` / `graph.pm`.
- **Colors**: a hardcoded array of hex colors in `yearstat.pm` (e.g. 10–12 entries). Each top location gets a color by index. "Other" gets the last color. No legend in the graph (no room on mobile). Instead, a small colored square (inline `<span>` with matching background) is shown next to each location name in the data table below the graph.
- **Caching**: PNG filename encodes username and N: `$username.yearbars-$n.png`. On page load, if the file already exists, reuse it. The file is deleted as part of `graph::clearcachefiles()` (which runs after any POST that changes glass data), so the cache stays valid until data changes. CMD and data files use the same stem.
- The graph is shown at the top of the `o=Years` page (before the table), only when viewing all years (i.e. `$c->{qry}` is empty).
- No database changes are needed.
- Drinks-per-year version is out of scope for this issue; money only for now.

## Phases

### Phase 1 — SQL query for per-year/per-location spending

In `code/yearstat.pm`, add a helper `yearbarsql($c)` that returns a data structure:

```
$data{$year}{$locname} = $total_price
@years  (sorted asc)
@top_locs (top N by total, sorted desc by grand total)
```

SQL skeleton:
```sql
SELECT
  strftime('%Y', glasses.Timestamp, '-06:00') AS yr,
  locations.Name AS loc,
  SUM(glasses.Price) AS total
FROM glasses
LEFT JOIN locations ON glasses.Location = locations.Id
WHERE glasses.Username = ?
  AND glasses.Brew IS NOT NULL
  AND glasses.Price > 0
GROUP BY yr, loc
ORDER BY yr, total DESC
```

Post-process in Perl: compute per-location grand totals, pick top N, lump the rest into "Other".

### Phase 2 — Write data file and gnuplot command

Add helper `yearbar_plot($c, $data, $years, $top_locs, $colors)` in `code/yearstat.pm`.

Data file format — one row per year, columns are: `year col1 col2 ... colN other`.
First line is a comment/header (used only for human readability; gnuplot uses column index):
```
# Year  LocA  LocB  ...  Other
2018 1200 800 0 400 200
2019 1500 900 300 0 100
```

Hardcoded color array at the top of `yearstat.pm` (12 entries, last used for "Other"):
```perl
my @BARCOLS = qw(
  e6194b 3cb44b ffe119 4363d8 f58231 911eb4
  42d4f4 f032e6 bfef45 fabed4 469990 aaffc3
);
```

Gnuplot stacked histogram — **no legend** (`unset key`), colors set explicitly per series:
```gnuplot
set term png small size 700,350
set out "PNGFILE"
set style data histograms
set style histogram rowstacked
set style fill solid noborder
set boxwidth 0.8
set yrange [0:]
set xtics rotate by -30 textcolor "white"
set ytics textcolor "white"
set border linecolor "white"
set object 1 rect noclip from screen 0,0 to screen 1,1 behind fc "BGCOLOR" fillstyle solid border
unset key
plot "DATAFILE" using 2 lc rgb "#COL0" notitle, \
     "" using 3 lc rgb "#COL1" notitle, \
     ...
```

The `plot` line is built dynamically in Perl by iterating over `@top_locs` + "Other".

File paths:
- Data file: `$c->{plotfile}` (e.g. `beerdata/heikki.plot`) — reuse existing context file
- CMD file:  `$c->{cmdfile}` (e.g. `beerdata/heikki.cmd`) — reuse existing context file
- PNG file:  `$c->{datadir} . $c->{username} . ".yearbars-$n.png"` — unique name for caching

On page load: if PNG exists, skip regeneration entirely (reuse cached file).
`graph::clearcachefiles()` matches `/$username.*png/` so it will delete these automatically.

### Phase 3 — Wire into `yearsummary()`, add colored dots to table

In `code/yearstat.pm::yearsummary()`, at the top of the function (before the table), add:

```perl
if (!$c->{qry}) {  # only show graph when viewing all years
    yearbar($c);
}
```

Where `yearbar($c)` calls `yearbarsql()`, `yearbar_plot()`, and prints the `<img>` tag.

In `yearbar($c)`, return a hash of `locname → color` so the table loop can use it.

In `yearsummary()`, when printing location name rows, prepend a colored dot:
```html
<span style='display:inline-block;width:10px;height:10px;background:#COL;margin-right:4px'></span>
```
Only applied to locations that appear in the top-N list; "Other" gets its color too.
The dot span is inside the existing `<td>` for the location name.

### Phase 4 — Manual test

- Load `o=Years` page and verify graph appears with stacked bars and colored dots in table.
- Load `o=Years&q=2024` (single year view) and verify graph is absent.
- Load `o=Years&maxl=5` and verify only 5 locations appear (rest in "Other").
- Post a new glass and reload — verify PNG is regenerated (cache was cleared).
- Check with no price data — graph should be skipped gracefully (no bars to plot).

## Open questions

*(All answered — no blockers.)*
