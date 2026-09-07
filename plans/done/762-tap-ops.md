# Plan 762: Tap Action Buttons on Beer Board

## Summary
Add tap management actions (close, close & reopen, mark unusual) to the beer
board expanded view and the tap history single-tap view. A shared helper renders
the form. An "reopen" action allows recovering a wrongly closed keg.

## Changes

### 1. Database Migration (mig_053)

**File: `code/migrate.pm`**

- Add migration 53: `ALTER TABLE tap_beers ADD COLUMN Unusual integer DEFAULT 0`
- Bump `$CODE_DB_VERSION` to 53
- Register in `@MIGRATIONS`

### 2. Pass tap_beers ID Through Beerboard Queries

**File: `code/beerboard.pm`**

Both beerboard SQL queries (historical `as_of` path and current `current_taps` path)
currently don't select `tap_beers.Id`. Add it:

- **Historical query** (line ~322): Add `tb.Id AS tap_beers_id` to SELECT
- **Current query** (line ~372): Add `ct.Id AS tap_beers_id` to SELECT (ct is current_taps view which exposes Id)
- **Data structure** (line ~448): Add `tap_beers_id => $row->{tap_beers_id}` to the beerlist hash
- **prepare_beer_entry_data** (line ~536): Pass through `tap_beers_id => $e->{tap_beers_id}`

### 3. Filter Unusual Kegs from Age Calculations

**File: `code/beerboard.pm`**

In both SQL subqueries for `avg_days_on_tap` and `tap_history_count` (lines ~338-348 and ~388-398), add:
```sql
AND h.Unusual = 0
```

**File: `code/brews.pm`**

In `listbrewtaps` (line ~758), add `&& !$tap->{Unusual}` to the skip condition:
```perl
next if $tap->{Days} >= 45 || $tap->{Unusual};
```
And adjust the " ???" marker logic (lines ~774, ~798) to also show for unusual kegs.

### 4. Shared Form Helper

**File: `code/taps.pm`**

Add new function `render_tap_action_form($c, $tap_beers_id, $locname, $is_gone)`:

- `$tap_beers_id`: the tap_beers row Id (active or closed)
- `$locname`: location name for redirect back
- `$is_gone`: if true, the keg is closed — show "reopen" instead of "close & reopen"

Renders a compact inline `<form>` (method POST, accept-charset UTF-8):
- Hidden fields: `o=Taps`, `tap_beers_id=<id>`, `loc=<locname>`
- `<select name='tap_action'>` with options:
  - `""` (empty value) — "(no action)" — the default
  - `"close"` — "Close tap"
  - `"close_reopen"` — "Close & reopen same" (omit if `$is_gone`)
  - `"reopen"` — "Reopen this keg" (only if `$is_gone` and no newer keg on this tap)
- `<input type='checkbox' name='mark_unusual' value='1'>` — "Unusual"
- `<input type='submit' value='OK'>`

The form is wrapped in a `<span>` with a `[manage]` text link that toggles it visible/hidden.

For the beer board: the form appears after the "On for N days" line, only for
active taps (where `tap_beers_id` is available). The `$is_gone` flag is false.

For the tap history single-tap view: the form appears on each row. For the active
keg (Gone IS NULL), `$is_gone` is false. For closed kegs, check if a newer keg
exists on the same tap — if not, offer "reopen"; otherwise show close/unusual only.

### 5. Add "[manage]" Button in Beer Board Expanded View

**File: `code/beerboard.pm`** (in `render_beer_row`, after line ~692)

After the "On for N days" span and the hidden "since..." span, call:
```perl
taps::render_tap_action_form($c, $processed_data->{tap_beers_id}, $locparam, 0)
  if $processed_data->{tap_beers_id};
```

### 6. Add "[manage]" Form in Tap History Single-Tap View

**File: `code/taphistory.pm`** (in `render_single_tap`, ~line 450-458)

After rendering each row in the tap detail table, if the row is active (Gone IS NULL),
call the shared form helper. For closed rows, also check whether a newer keg exists
on the same tap (the query is ordered by FirstSeen DESC, so the first row is the most
recent — if it's the first row in the result set and Gone IS NOT NULL, it's the
most recent keg and can be reopened).

Add a column to the table header: "Ops" or leave it empty (just the form).

### 7. Add POST Handler for Tap Actions

**File: `code/taps.pm`**

Add new function `posttapaction($c)`:
- Read `tap_action` and `tap_beers_id` from params
- Read `mark_unusual` checkbox value
- Look up the tap_beers row (Location, Tap, Brew) by Id
- Actions:
  - **close**: `UPDATE tap_beers SET Gone = now WHERE Id = ?`
  - **close_reopen**: `UPDATE tap_beers SET Gone = now WHERE Id = ?` then
    `INSERT INTO tap_beers (Location, Tap, Brew, FirstSeen, LastSeen, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL)
     SELECT Location, Tap, Brew, now, now, SizeS, PriceS, SizeM, PriceM, SizeL, PriceL
     FROM tap_beers WHERE Id = ?`
  - **reopen**: `UPDATE tap_beers SET Gone = NULL WHERE Id = ?`
  - **(no action)**: skip if tap_action is empty
- If `mark_unusual` is set: `UPDATE tap_beers SET Unusual = 1 WHERE Id = ?`
- If `mark_unusual` is not set: `UPDATE tap_beers SET Unusual = 0 WHERE Id = ?`
- Redirect to `o=Board&loc=<location>` (using loc param) after completion

### 8. Wire Up POST Dispatch

**File: `code/index.fcgi`**

Add a new elsif branch in the POST section (before the default glass post, ~line 331):
```perl
} elsif ( $c->{op} =~ /Taps/i ) {
  taps::posttapaction($c);
```

### 9. Tests

**File: `tools/test-http`**

Add a new test `test_tap_action_roundtrip` in the POST round-trips section:
- POST with `o=Taps, tap_action=close, tap_beers_id=<active_id>, loc=<name>`
- Verify redirect and that the tap row now has Gone set (by checking the tap history page)
- POST with `o=Taps, tap_action=reopen, tap_beers_id=<same_id>, loc=<name>`
- Verify redirect and that Gone is cleared (tap appears active again)
- POST with `o=Taps, tap_action=close_reopen, tap_beers_id=<active_id>, loc=<name>`
- Verify old row closed, new identical row opened

Register the test: `{ name => "tap_action_roundtrip", sets => [qw(posts roundtrip taps)], test => \&test_tap_action_roundtrip }`

### 10. Documentation

**File: `doc/design.md`** (tap_beers section, ~line 92)

Add note about the Unusual column:
```
- `Unusual`: When set, excludes this keg from average-age calculations.
  Used for kegs that are not representative (e.g. a forgotten keg left on tap).
```

**File: `doc/manual.md`** (Tap Timeline section, ~line 395)

Add after the single-tap view description:
```
For active kegs, a small [manage] link reveals a form to close the tap,
close and reopen with the same beer, or mark the keg as unusual (which
excludes it from age calculations).
```

## Files Modified

| File | Change |
|------|--------|
| `code/migrate.pm` | Migration 53: add Unusual column |
| `code/beerboard.pm` | Pass tap_beers_id, add manage form call, filter unusual in SQL |
| `code/taps.pm` | New `render_tap_action_form()` helper and `posttapaction()` handler |
| `code/taphistory.pm` | Call shared form helper in single-tap view |
| `code/index.fcgi` | POST dispatch for o=Taps |
| `code/brews.pm` | Filter unusual in keg age calculations |
| `doc/db.schema` | Updated by `tools/dbdump.sh` after migration |
| `doc/design.md` | Document Unusual column |
| `doc/manual.md` | Document tap action form |
| `tools/test-http` | New tap_action_roundtrip test |

## Testing

- `tools/test-unit` — verify unit tests pass
- `tools/test-http` — verify smoke tests pass, new tap_action_roundtrip test passes
- Manual: open beer board, expand a tap, verify [manage] button appears
- Manual: test pulldown "Close tap" → OK → verify tap row gets Gone set
- Manual: test pulldown "Close & reopen same" → OK → verify old row closed, new row opened
- Manual: test "Mark unusual" checkbox → OK → verify Unusual=1, age calc ignores it
- Manual: in tap history, open single-tap view, verify [manage] form on active row
- Manual: test "Reopen" on a closed keg (if it's the most recent) → verify Gone cleared
- Verify the form only appears for active taps on beer board (not historical views)
