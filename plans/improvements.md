# BeerTracker Improvement Ideas

Ideas for new features, gathered from codebase TODOs, design docs, and general
analysis. Not all are equally useful; prioritize based on what would get the
most use in daily tracking.

---

## Already Planned

### Full-Text Search Page (issue #740)
Add `o=Search` to search comments and glass notes with AND-ed word matching.
No schema changes needed. See `plans/740-searchpage.md` for details.

### Close Stale Taps (issue #748)
Auto-close tap_beers rows when scrapers fail, preventing stale "On for 300
days" entries. Deferred until more keg age data is available. See
`plans/748-stale-taps.md`.

---

## Statistics Improvements

### Expand Data Stats
The current datastats in stats.pm has several TODOs:
- Comments stats by brew type, night, restaurant
- Rating stats (min/max/avg/count) by brewtype
- Photo stats by brewtype or person
- Identify brews that have one or no glasses (orphaned brews)

### Zero-Day Tracking in Year Stats
Count and display days with zero drinks in annual summaries. Useful for
tracking drinking frequency and dry days. (TODO in yearstat.pm:221)

### Monthly/Weekly Drinking Goals
Set goals like "max 14 drinks per week" and track adherence on the graph.
Visual indicators (green/yellow/red zones) for goal status.

### Seasonal / Trend Analysis
Show which beer styles are trending up/down over time. "NEIPAs are
increasing" or "you're drinking more wine this year." Could be a new stats
view or extension to monthstat.

### Price History Graph per Brew
Currently listbrewprices shows a table. A price-over-time graph for a brew
across locations would visualize price trends.

---

## User Experience

### Graph Click-to-Zoom / Interactive Graph
The graph is currently a static PNG. Making it interactive — click a day to
zoom, hover for details — would improve usability. Could use SVG or a JS
charting library like Chart.js or D3. (TODO in graph.pm:414)

### Budget / Spending Limits
Allow setting monthly/weekly spending budgets per location or overall. Show
progress toward limits on the stats page. Could add visual indicators when
approaching limits.

### Beer Wishlist
Add a wishlist or "want to try" list for beers seen on boards or heard about.
Currently there's no way to bookmark a beer you haven't drunk yet.

### Better Copy Buttons with Price Adjustment
When copying to a different volume, adjust the price proportionally (e.g.,
copying 25cl at 45kr to 40cl should suggest 72kr). (TODO in mainlist.pm:313)

### Reminder / Notification System
"You haven't logged a beer in 3 days" or "You visited this bar last month"
notifications. Could be email-based or browser notifications.

---

## Data Entry and Automation

### Blood Alcohol Configuration per User
The blood alcohol calculation has hardcoded body weights in mainlist.pm:86-87.
Moving this to a per-user setting in globals or a user profile would make it
configurable for any user.

### ~~Currency Support~~ (done)
~~Add a currency field to glasses and a default currency setting, with optional
conversion rates.~~ Implemented via price suffix (e.g. `5.5e`) with hardcoded
exchange rates. Original price stored in Note field as `[5.5 e]`. See issue #757.

### Auto-Calculate SubType from Brew Style
When a brew style is entered, auto-suggest or auto-fill the subtype field.
Reduces manual data entry. (TODO in brews.pm:677)

### Person Details Page Improvements
Show when/where a person was last seen, drinking companions, and frequency.
(TODO in persons.pm:58)

---

## Import / Export

### CSV Export
Currently only SQL dump and tarball. CSV would be useful for spreadsheets
and data analysis in Excel or Google Sheets.

### Export as JSON
For integration with other tools, APIs, or data analysis pipelines.

### Export Filtered Data
Allow export filtered by location, brew type, or specific date ranges
beyond the current from/to dates.

---

## Beer Board Enhancements

### Scraped Beer List Price Comparison
When viewing a beer board, show if a beer is cheaper/more expensive than last
time you saw it, or compare prices across bars.

### Board History Comparison
Show what changed since the last scrape — new beers, removed beers, price
changes. Highlight differences.

---

## Multi-User / Social

### Shared Comments and Ratings
Allow users to see each other's comments and ratings on the same beers.
Currently the system supports multiple users but data is mostly private.

### Drinking Companion Tracking
Enhance the person-tagging feature to automatically suggest people based on
location and time patterns.

---

## Code Quality (from TODOs)

### Refactor Large Modules
- comments.pm: "This too big for a module. Split it somehow." (line 4)
- monthstat.pm: "Split this into smaller functions" (line 11)
- listrecords.pm: "This is basically one too-long function." (line 16)
- postglass.pm: "This is quite a long function, split into smaller ones" (line 24)

### Exponential Average for Graph
Check if exponential averaging would be better than the current weighted
30-day average. (TODO in graph.pm:71)

### Refactor inputs.pm Arguments
"Too many arguments, refactor to pass a hash" (TODO in inputs.pm:137)
