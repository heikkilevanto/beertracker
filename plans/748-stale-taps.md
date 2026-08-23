# Plan: Close stale taps when scraping is missed

**Status: Deferred — will implement later when we have more keg age data to set the threshold better.**

## Problem
When a scraper breaks (e.g., Cloudflare 403) or a venue isn't scraped for a while,
tap_beers rows with `Gone IS NULL` accumulate indefinitely. The beer board shows
"On for X days" with unreasonably long X, and avg_days_on_tap stats get skewed.

## Root Cause
`scrapeboard::updateboard()` returns early when the scraper fails or returns empty,
without calling `taps::update_taps()`. So no cleanup of stale taps happens.

## Solution
Close any active tap row whose `LastSeen` is older than a threshold (TBD).
Mark these closures with a `Stale` flag so they are excluded from keg age stats.

## Changes

### 1. Migration #53 (migrate.pm)
```sql
ALTER TABLE tap_beers ADD COLUMN Stale INTEGER DEFAULT 0
```
Bump `$CODE_DB_VERSION` to 53.

### 2. taps.pm — add close_stale_taps()
- Constant `$STALE_TAP_DAYS` (value TBD — currently thinking ~21 days)
- `sub close_stale_taps($c, $location_id)`:
  - `UPDATE tap_beers SET Gone = <now>, Stale = 1 WHERE Location = ? AND Gone IS NULL AND Brew IS NOT NULL AND LastSeen < <now - $STALE_TAP_DAYS>`
  - Excludes the scrape marker row (Brew IS NULL)
  - Returns count; logs it

### 3. scrapeboard.pm — call at failure returns in updateboard()
- Move `$loc_id = $loc_rec->{Id}` earlier (before scraper checks)
- Call `taps::close_stale_taps($c, $loc_id)` at each early-return point:
  - No scraper configured
  - Scraper exit code != 0
  - Empty JSON output

### 4. beerboard.pm — exclude stale from keg stats
Add `AND (h.Stale IS NULL OR h.Stale = 0)` to both subqueries:
- avg_days_on_tap (line ~277)
- tap_history_count (line ~283)

### 5. No display changes
Stale-closed taps disappear from the board (current_taps view filters Gone IS NULL).
No UI note needed — correct behavior is implicit.

## Design Decisions
- **Threshold**: value TBD. Need more data on typical keg lifetimes across venues
  to set a threshold that is long enough to survive intermittent scrape failures
  but short enough to prevent stale data accumulation.
- **Called only at failure returns**: on successful scrape, update_taps already
  closes taps not in the list and updates LastSeen for all active taps.
- **Stale column**: explicit marker avoids coupling staleness detection to the
  threshold value and makes the exclusion query clean.
