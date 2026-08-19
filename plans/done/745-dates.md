# 745 - Lifecycle dates for locations and brews

Add date fields tracking when places opened/closed and brews released/discontinued,
plus an automatically collected `FirstSeen` date. Closed places and discontinued
brews are marked in lists and excluded from selection, scraping, and the beerboard.

Dates may be partial (just a year, e.g. `2019`) - we often know the opening/release
year but not the day. They are stored as entered.

## 1. Migration - `code/migrate.pm`

`mig_051_add_lifecycle_dates`, registered in `@MIGRATIONS`, `$CODE_DB_VERSION` -> 51.

- `locations`: add `Opened text`, `Closed text`, `FirstSeen text`
- `brews`: add `Released text`, `Discontinued text`, `FirstSeen text`
- Backfill `FirstSeen` for existing rows:
  - brews: `strftime('%Y-%m-%d', MIN(tap_beers.FirstSeen))` where a tap entry exists
  - locations: `strftime('%Y-%m-%d', MIN(glasses.Timestamp), '-06:00')` where a glass exists
- After deploy run `tools/dbdump.sh` to refresh `doc/db.schema`.

## 2. Date shorthand / normalization - `code/util.pm`, `code/db.pm`

New `util::normalize_date($c, $val)`:
- empty string -> clears the field (this is how you reopen / re-release)
- `Y` -> yesterday
- `-Nd` -> N days before today (e.g. `-3d`)
- otherwise pass through unchanged (full `YYYY-MM-DD` or partial like `2019`)

Wire it into `db::updaterecord` / `db::insertrecord` exactly like
`normalize_country` (db.pm:412 and :462):
`$val = util::normalize_date($c, $val) if $f =~ /^(Opened|Closed|Released|Discontinued|FirstSeen)$/;`

## 3. Automatic `FirstSeen` collection

- **Brew**: `taps::update_taps` - after each `tap_beers` insert, run
  `UPDATE brews SET FirstSeen = COALESCE(FirstSeen, strftime('%Y-%m-%d', ?)) WHERE Id = ?`
  (first seen on tap).
- **Location & brew-glass fallback**: `postglass` - after the glass insert, fill the
  location's `FirstSeen` (and the brew's `FirstSeen` if still empty) from the glass's
  `'-06:00'` effective date. Brews never seen on tap thus fall back to the first glass.

`FirstSeen` values are full dates (`YYYY-MM-DD`).

## 4. Edit forms - `code/locations.pm`, `code/brews.pm`

The forms follow the automatic table layout in `inputs.pm`. Add to the field order
arrays (all fields remain editable, including `FirstSeen` to override the auto value):

- `$loc_field_order`: `Opened`, `Closed`, `FirstSeen` with help text, e.g.
  `["Opened", 'year or full date, e.g. "2019" or "-3d" or "Y"']`,
  `["Closed", "empty = still open"]`, `["FirstSeen", "auto-set from first visit"]`
- `$brew_field_order`: `Released`, `Discontinued`, `FirstSeen` with help text, e.g.
  `["Released", 'year or full date, e.g. "2019" or "-3d" or "Y"']`,
  `["Discontinued", "empty = still available"]`, `["FirstSeen", "auto-set from first tap/glass"]`

Fields may be ordered nicely within the arrays (no layout code changes needed).

## 5. Lists: small 'X' marker only

Do not dedicate wide columns to status text. Add a tiny marker column:

- `listlocations`: `CASE WHEN Closed IS NOT NULL AND Closed != '' THEN 'X' ELSE '' END AS "Closed"`
- `listbrews`: `CASE WHEN Discontinued IS NOT NULL AND Discontinued != '' THEN 'X' ELSE '' END AS "Discont"`

The header input still allows filtering the marker (type `X`); no JS changes.

## 6. Selection dropdowns - exclude entirely

- `selectlocation`: add `AND (Closed IS NULL OR Closed = '')` to all three `$where`
  variants (locations.pm:544).
- `selectbrew`: add `AND (Discontinued IS NULL OR Discontinued = '')` in the opts
  query (brews.pm:654).

## 7. Scraping and beerboard exclude closed locations

- `scrapeboard::get_scraper_locations` (scrapeboard.pm:25-28): add
  `AND (l.Closed IS NULL OR l.Closed = '')`. This covers both the beerboard location
  selector and the scrape loop.
- `scrapeboard::updateboard`: after fetching `$loc_rec`, if `Closed` is set, log
  "updateboard: skipping closed location" and return without scraping.
- `beerboard`: when the requested location `$loc_rec_check` has a `Closed` date,
  show a small "This place is closed" note (still show the last cached board).

## 8. producerbrews - show all, mark discontinued

`locations::producerbrews` (locations.pm:159): show all brews as before, and add an
'X' marker column for discontinued ones:
`CASE WHEN brews.Discontinued IS NOT NULL AND brews.Discontinued != '' THEN 'X' ELSE '' END AS "Discont"`

## 9. Dedup merge rules - `code/locations.pm`, `code/brews.pm`

Merge lifecycle dates from each duplicate into the kept record before the dup row
is deleted.

- `deduplocations`: merge `Opened`, `Closed`, `FirstSeen`
- `dedupbrews`: merge `Released`, `Discontinued`, `FirstSeen`

Rule:
- If the kept record is missing a date and the duplicate has one, copy it over.
- If values differ, **earliest wins** for `Opened`, `Released`, `FirstSeen`;
  **latest wins** for `Closed`, `Discontinued`.
- Dates are compared as strings (`YYYY-MM-DD` sorts lexically; a partial year like
  `2019` sorts before any `2019-...` date, which is the desired "earliest" behaviour).

Implementation: in the per-duplicate loop, fetch the dup's field values, compute the
merged value against the kept record, `UPDATE` the kept record when changed, then
proceed with the existing re-pointing and delete. Log each merged field.

## 10. Out of scope

- No status word columns in lists beyond the small 'X' marker (issue #745 decisions).
- `tap_beers` / tap history (`LastSeen`, `Gone`) unchanged - those are per-tap, not
  lifecycle.

## 11. Verification

- `perl -c` on all touched modules (`migrate.pm`, `util.pm`, `db.pm`, `locations.pm`,
  `brews.pm`, `taps.pm`, `postglass.pm`, `scrapeboard.pm`, `beerboard.pm`).
- `touch code/VERSION.pm` (separately) to trigger reload.
- Manual test: create records with `2019` and `-3d` / `Y` values, dedup a pair with
  differing dates, confirm closed location disappears from dropdown/scraper/board,
  and the 'X' markers show in the brew lists.