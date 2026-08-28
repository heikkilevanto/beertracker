# Plan 753 — Consolidate date/time helpers into `code/dateutil.pm`

## Goal
Perl-side date/time helpers are currently split between `util.pm` (getting large) and
`taphistory.pm`, with duplicated logic and the −6h "effective day" convention
re-implemented in two places. Consolidate them into a focused new module
`code/dateutil.pm`, merge the duplicated parse, and make the −6h rule a single
source of truth.

## Current state
Perl-side date/time helpers today:

`util.pm` ("Helpers for date and timestamps"):
- `datestr`, `now`, `reldate` (today/yesterday using the −6h convention),
  `splitdate`, `normalize_date`, `parse_beerboard_date`

`taphistory.pm`:
- `eff_day_of` (ISO ts → effective day with −6h shift), `ts_epoch` (ISO ts → epoch),
  `date_plus_days`, `day_diff`

## Overlap / duplication found
1. `eff_day_of` and `ts_epoch` in `taphistory.pm` share the *exact same* regex +
   `timelocal` parse — `eff_day_of` is just `ts_epoch` minus 6h. Merge them.
2. `taphistory::ts_epoch` duplicates the inline `Time::Local::timelocal` parse at
   `beerboard.pm:52-53`.
3. The −6h "effective day" convention is re-implemented independently in
   `eff_day_of` (taphistory) and `reldate` (util). SQL uses `strftime(...,'-06:00')`
   separately (out of scope here).

## Callers to update (verified by grep)
- `datestr` / `splitdate` / `now` used widely: `mainlist.pm`, `comments.pm`,
  `postglass.pm`, `taps.pm`, `export.pm`, `yearstat.pm`, `graph.pm`, `monthstat.pm`,
  `listrecords.pm`, `util.pm` (internal).
- `reldate`: `beerboard.pm:144,154`, `brews.pm:237,238`.
- `parse_beerboard_date`: `beerboard.pm:43`.
- `normalize_date`: `db.pm:497,548`.
- `eff_day_of` / `ts_epoch` / `date_plus_days` / `day_diff`: only `taphistory.pm`.

## Steps

### 1. Create `code/dateutil.pm`
New package `dateutil` with `use Time::Local qw(timelocal); use POSIX qw(strftime);`.
Proposed subs:
- `ts_epoch($ts)` — ISO `YYYY-MM-DD HH:MM:SS` → local epoch (or `undef`). (from taphistory)
- `eff_day_of($ts)` — canonical effective day = `strftime("%Y-%m-%d",
  localtime(ts_epoch($ts) - 6*3600))`, `""` on undef. (merged: was duplicating ts_epoch's parse)
- `date_plus_days($date, $k)` — (from taphistory)
- `day_diff($a, $b)` — (from taphistory)
- `datestr`, `now`, `splitdate`, `normalize_date`, `parse_beerboard_date` —
  (moved verbatim from util.pm)
- `reldate($date)` — simplified to derive today/yesterday via `eff_day_of(now)` +
  `date_plus_days`, so the −6h convention lives only in `eff_day_of`.

Merge detail: `eff_day_of` becomes a thin wrapper over `ts_epoch` (removes the
duplicated regex). `reldate`'s own `time()-6*3600` logic is deleted.

### 2. Register the module
Add `require "./code/dateutil.pm";` in `index.fcgi` (after the `util.pm` require,
~line 68). No per-module `use` needed (same pattern as `styles::` / `db::`).

### 3. Update `util.pm`
Remove the moved subs (`datestr`, `now`, `reldate`, `splitdate`, `normalize_date`,
`parse_beerboard_date`) and their "Helpers for date and timestamps" TOC entry.
Keep `use POSIX qw(strftime localtime);` (still used by other util funcs like
`topline` and SQL-building strings).

### 4. Update all callers (39 sites, ~13 files)
Replace `util::` → `dateutil::` for the moved subs:
- `beerboard.pm`: `reldate`, `parse_beerboard_date`; **also** replace the inline
  `Time::Local::timelocal` parse at line 52-53 with `dateutil::ts_epoch($as_of)`.
- `brews.pm`, `db.pm`, `mainlist.pm`, `comments.pm`, `postglass.pm`, `taps.pm`,
  `export.pm`, `yearstat.pm`, `graph.pm`, `monthstat.pm`, `listrecords.pm`:
  `datestr` / `now` / `splitdate` / `normalize_date` / `reldate`.
- `taphistory.pm`: change internal `eff_day_of` / `ts_epoch` / `date_plus_days` /
  `day_diff` calls to `dateutil::`, and delete the local subs. Keep its
  `use Time::Local; use POSIX qw(strftime);` (still used by the `from`-month
  calculation in `taphistory()`).

### 5. Verify
- `perl -c` on every touched `.pm` and `index.fcgi`.
- `touch code/VERSION.pm` to trigger FCGI reload.
- Manual checks: beerboard date input, taphistory timeline, a `reldate` page
  (brews), and `normalize_date` on a brew edit.

## Out of scope
The SQL-side `strftime(...,'-06:00')` convention across modules is separate;
unifying that would be a larger db-layer change and is not part of this move.
