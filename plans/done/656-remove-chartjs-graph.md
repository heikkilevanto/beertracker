# Plan: Get rid of graph.umd.js (issue #656)

## Decisions

- Replace the Chart.js bar chart in `code/ratestats.pm` with a gnuplot-generated PNG, matching the style used by `code/monthstat.pm`.
- Use a dedicated plot data file (`username-ratings.plot`) and PNG file (`username-ratings.png`) under `beerdata/` to avoid colliding with the main `username.plot` file used by `graph.pm`.
- The gnuplot chart is a horizontal bar chart: ratings 1–9 on Y axis, count on X axis. Implemented using gnuplot's `boxxy` style.
- Keep the existing `histogram_data()` SQL function and `data_table()` HTML table — only the chart rendering changes.
- Remove `static/chart.umd.min.js` and `static/chart.umd.min.js.map` once the gnuplot implementation is confirmed working.
- Remove the inline `<style>` block (`.chart-container`, `.chart-item`) in `ratings_histogram()` — no longer needed.
- Update `doc/design.md` to remove the reference to `chart.umd.min.js`.
- No DB changes.

## Phases

### Phase 1 — Add gnuplot chart function to `code/ratestats.pm`

Replace `chart_chartjs()` with a new `chart_gnuplot()` function:

1. Derive the PNG file path from `$c->{plotfile}` (e.g., substitute `.plot` with `-ratings.png`), and a separate data file (e.g., `-ratings.plot`).
2. Write the rating counts (ratings 1–9) to the data file, one count per line with the rating label.
3. Build a gnuplot command string:
   - `set term png small size 400,400`
   - `set out "...username-ratings.png"`
   - Match dark background style: `set object 1 rect ... fc "$c->{bgcolor}"`, `set border linecolor "white"`, `set xtics textcolor "white"`, `set ytics textcolor "white"`
   - Use `boxxy` style for horizontal bars: `using ($2/2):1:($2/2):(0.35) with boxxy`
   - Y axis labels: rating numbers 1–9 only (full label text is visible in the table below)
4. Write the gnuplot command to a cmd file (e.g., `-ratings.cmd`) and run `system("gnuplot ...")`.
5. Emit `<img src="...username-ratings.png" style='max-width:95vw' />`.

### Phase 2 — Update `ratings_histogram()` in `code/ratestats.pm`

- Replace the call to `chart_chartjs($c, $rows)` with `chart_gnuplot($c, $rows)`.
- Remove the inline `<style>` block for `.chart-container` / `.chart-item` (no longer needed).
- Remove the `<div class="chart-container">` / `<div class="chart-item">` wrapping divs.
- Remove the comment on line 4: `# Experimenting with Chart.js for the graph.`

### Phase 3 — Delete `chart_chartjs()` from `code/ratestats.pm`

Once Phase 1+2 are tested and working, remove the entire `chart_chartjs()` sub (lines ~173–246).

### Phase 4 — Remove static JS files

Delete `static/chart.umd.min.js` and `static/chart.umd.min.js.map`.

### Phase 5 — Update `doc/design.md`

Remove or update the line (line 155):
> The js code makes use of quagga.min.js, and chart.umd.min.js

Change to:
> The js code makes use of quagga.min.js

## Resolved decisions

- Horizontal bar chart (ratings on Y, counts on X) using gnuplot `boxxy`.
- Y-axis shows rating numbers 1–9 only; full label text visible in the table below.
- Files: reuses `$c->{plotfile}` (`username.plot`) for data and `$c->{cmdfile}` (`username.cmd`) for the gnuplot command; PNG is `username-ratings.png`.
- Always regenerate PNG on each request (no caching).