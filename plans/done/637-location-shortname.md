# Plan: Short names for locations (issue #637)

## Decisions

- Add `ShortName TEXT` column to the `locations` table only (not `brews` for now).
- The field is intended primarily for producer locations (LocType = 'Producer') as shown on the beer board.
- `ShortName` is null when not set; the display code continues to use its existing computed shortening until a later phase removes it.
- Shortening logic stays in `beerboard.pm` for now as `beerboard::compute_short_location_name($name)`; it will be moved to `util.pm` in a later phase.
- When scraping: if an existing producer has no `ShortName`, compute one and update. When inserting a new producer, compute and store if it differs from the full name.
- In `beerboard.pm` display: if the computed short name differs from the full name and the DB record has no `ShortName`, log a warning to `$c->{log}` so it can be fixed manually.
- Out of scope for this phase: using `ShortName` in display code (beerboard.pm), editing UI.

## Database changes

- **New column on locations**: `locations.ShortName TEXT` — the preferred short display name; null if same as `Name` or not yet determined.
- **New column on brews**: `brews.ShortName TEXT` — reserved for future use; no code changes for brews in this phase.
- Add migration **21** in `code/migrate.pm`:
  ```sql
  ALTER TABLE locations ADD COLUMN ShortName TEXT
  ALTER TABLE brews ADD COLUMN ShortName TEXT
  ```
- Bump `$CODE_DB_VERSION` to 21 in `migrate.pm`.
- Run `tools/dbdump.sh` after applying the migration to update `doc/db.schema`.

## Phases

### Phase 1 — DB migration (`code/migrate.pm`)
- Add sub `mig_021_add_shortname_to_locations`.
- Execute `ALTER TABLE locations ADD COLUMN ShortName TEXT` and `ALTER TABLE brews ADD COLUMN ShortName TEXT`.
- Register `[21, '637 add ShortName to locations and brews', \&mig_021_add_shortname_to_locations]` in `@MIGRATIONS`.
- Bump `$CODE_DB_VERSION` to 21.

### Phase 2 — Plain-text shortening helper (`code/beerboard.pm`)
- Add sub `beerboard::compute_short_location_name($name)` that returns a shortened plain-text name, or `undef` if no shortening applies.
- Logic (adapted from the existing inline display code in `beerboard::process_entry()`):
  - Strip stop words: `the`, `brouwerij`, `brasserie`, `van`, `den`, `Bräu`, `Brauerei` (case-insensitive).
  - Apply specific full-name rules (e.g., `Schneider`), same as beerboard.pm.
  - Strip ` & ` and ` &amp; ` edge cases.
  - Trim leading/trailing spaces.
  - Take only the first word (split on `[ -]`).
  - Return `undef` if the result equals the original `$name` (no shortening needed).
- Will be moved to `util.pm` in a later phase.

### Phase 3 — Warning in beerboard display (`code/beerboard.pm`)
In `beerboard::process_entry()`, after computing `$shortmak`:

- If `$shortmak` differs from the full `$mak` and `$e->{shortname}` is not set, log a warning:
  ```perl
  print { $c->{log} } "beerboard: no ShortName for '$mak' (id $e->{maker_id}) (would shorten to '$shortmak')\n";
  ```
- This requires fetching `locations.ShortName` as `shortname` in the board SQL query in `beerboard::load_board_entries()` (around line 267).

### Phase 4 — Populate ShortName when scraping (`code/scrapeboard.pm`)
In `scrapeboard::updateboard()`, in the "ensure producer exists" block:

- **Existing producer found** (`$prod_rec`): if `$prod_rec->{ShortName}` is null, call `beerboard::compute_short_location_name($maker)`; if it returns a value, run:
  ```sql
  UPDATE LOCATIONS SET ShortName = ? WHERE Id = ?
  ```
  and log the update.

- **New producer inserted**: after the INSERT, call `beerboard::compute_short_location_name($maker)`; if it returns a value, run a separate:
  ```sql
  UPDATE LOCATIONS SET ShortName = ? WHERE Id = ?
  ```
  and log it.

## Open questions

- Should `compute_short_location_name` also handle the beer-name-specific rules currently in beerboard.pm (Warsteiner, Hopfenweisse, Ungespundet)? Probably not — those are beer names, not location/producer names.
- Should `ShortName` also be settable via the location edit UI? Out of scope for this phase, but a natural follow-on.
