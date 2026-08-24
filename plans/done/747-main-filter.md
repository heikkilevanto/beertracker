# Issue #747: Reintroduce &q= filtering on the main list

## Summary
The main list (`mainlist.pm`) lost its grep-style `q` filtering during the #423
rewrite (May 2025). `o=Full`/`o=Board` pages currently ignore `$c->{qry}`
except for the cache key and copy-button passthrough. This plan reinstates
filtering with a modern, tokenized match, a non-cluttering UI, suppressed
summaries while filtering, and a result cap with a "More results" link.

## Background / Findings
- Old filter lived in the deleted `index.cgi::fulllist` (removed `11b3d82`).
  Semantics: `q` (whole string) matched `\b$qry\b` word-boundary against a
  concatenated `rawline`; `qf` chose a target field; `y` year-limited; `maxl`
  capped records; summaries were suppressed while filtering; `q=.` opened the
  search form without filtering.
- `$c->{qry}` is still wired up: set at `index.fcgi:259`, kept in cache key
  `mainlist.pm:619` and copy-button hidden input `mainlist.pm:347`.
- `filt()` helper was deleted in `e25e506`; current convention is tokenized
  matching (`static/filter-utils.js`, `plans/715-filtering.md`).

## Decisions (confirmed)

### Matching
- **Matching:** tokenized AND + substring (Unicode-safe, case-insensitive),
  quotes for phrases. Matches any of: brewname, producer, locname, subtype,
  brewtype, shortname, note, tap. Comments excluded (covered by planned
  `o=Search`, issue #740).

### Filtered view
- **Filtering UI:** Normally no filter inputs are shown. The form appears only
  when `q` or `date`/`ndays` params are present.
- **Trigger:** Clicking any beer style label in the main list (e.g. `[NEIPA]`)
  navigates to `?o=...&q=NEIPA`, which opens the form (filter pre-filled with
  the style text) and immediately shows matching results. A date parameter
  (e.g. from clicking a date in the `locationhead`) also opens the form.
- **Date defaults to today** when clicking a style label.
- **No `q=.` convention.** Dropped — not needed since style labels and date
  params are the triggers.
- **No POST redirect preservation.** The filter is not preserved across POST
  redirects (e.g. recording a new glass). The user re-opens the form by clicking
  a style label or date link.
- **Unified form:** When shown, the form contains:
  1. Filter input (`q`), pre-filled with current value.
  2. Date input (`date`), "first date to show."
  3. Either "number of lines" (`maxl`, for filtered) or "number of days"
     (`ndays`, for unfiltered) — server-side conditional based on whether `q`
     is non-empty.
  4. Submit button + a "clr" link that clears all params.
- **Filtered view:** date+location headers, no sum lines/adjustment forms/day
  totals.

### Limiting
- **Record cap:** `maxl` (default 45) + "More results" link; scans from the
  given date backwards; ignores `ndays`.
- **"More results"** in filtered mode (doubles `maxl`). **"Older records"** in
  unfiltered mode (existing behavior, shifts date).

### Scope
- Just `q` for now; `qf` and `y` are future enhancements.

## Implementation

### 1. Tokenizer helper in util.pm
Port `_tokenizeFilterInput` from `static/filter-utils.js`:
`sub filter_tokens($val)` returns a list of tokens, respecting `"..."` quotes
(quotes stripped) and splitting unquoted input on whitespace.

### 2. `sub matching_rec($c, $rec)` in mainlist.pm
- `return 1` if no `$c->{qry}` (empty/undefined).
- Tokens obtained via `util::filter_tokens($c->{qry})`; every token must match
  (`/\Q$token\E/i`, AND-logic) at least one of the match fields:
  `brewname`, `producer`, `locname`, `subtype`, `brewtype`, `shortname`,
  `note`, `tap`. Undefined/empty fields are skipped.
- `\Q\E` prevents regex injection; data comes from the DB (server-side),
  `$c->{qry}` is already sanitized at `index.fcgi:259`.

### 3. New `sub filtered_list($c)` in mainlist.pm
- Reads `maxl` via `util::paramnumber($c, "maxl", 45)`.
- Uses `$c->{sth}` (already set by `mainlist()` via `glassquery($c, $date)`).
- Scan from `$date` backwards using `db::peekrow`/`db::nextrow`/`db::pushback_row`:
  - collect one day's rows (same grouping as `oneday` pass 1) so per-record BA
    is computed physically via `bloodalc_compute` on the full day;
  - keep only records where `matching_rec` returns true, preserving order;
  - render matching records reusing existing per-record renderers
    (`locationhead` for a light date+location header on each group, then
    `nameline`, `numbersline`, `photoline`, `commentlines`, `buttonline`);
  - do NOT call `sumline`, `adjustment_form`, or the day total;
  - stop once `maxl` matches are rendered (`last`, with `db::pushback_row`
    only if we consumed a row of the next day we don't need; otherwise just
    leave the stream and `$sth->finish`);
- Emit "More results" link when the stream still had more records after the cap:
  `<a href='$c->{url}?o=$c->{op}&q=...&maxl=$maxl*2&date=$date'><span>More results</span></a>`
  (double the cap; `uri_escape_utf8` the q and date).
- "No matches for '<q>'" line when nothing matched.
- `$sth->finish` at the end.

### 4. `nameline()` — Beer style label becomes a link
- Wrap `styles::brewstyledisplay(...)` output in an `<a>` link:
  `<a href='$c->{url}?o=$c->{op}&q=STYLENSTR'><span ...>[STYLE]</span></a>`
  where `STYLENSTR` is the style string (e.g. "NEIPA", "Wine,Red") and is
  `uri_escape_utf8`-d. This opens the form with the filter pre-filled and
  shows filtered results immediately.
- Only in `nameline` (main list); not in beerboard or other call sites.

### 5. `mainlist()` — Branch and form rendering
- **show_form** now includes `q` param check:
  `$show_form = 1 if (defined $c->{cgi}->param("q") || defined $c->{cgi}->param("date") || defined $c->{cgi}->param("ndays") || $derived_date);`
- **Unified form** (when `show_form`):
  - Always render filter input (`q`) and date input (`date`).
  - If `$c->{qry}` is non-empty → render "number of lines" input (`maxl`,
    default 45), label "lines".
  - Else → render "number of days" input (`ndays`, default as before),
    label "days".
  - Submit button + "clr" link to `?o=$c->{op}` (clears all params).
- **Branch after form:**
  - If `$c->{qry}` is non-empty → call `filtered_list($c)` instead of the
    day-loop. No "Older records" link; instead "More results" (if stream has
    more).
  - Else → existing day-loop with `oneday()` (unchanged). Keep "Older records"
    link as before.
- **Cache key:** Extend existing key at `mainlist.pm:619` to include `maxl`:
  `"mainlist:$c->{username}:$c->{op}:$c->{qry}:$date:$original_ndays:$show_form:$maxl"`
  ( `$maxl` defaults to 0 when not filtering.)

### 6. No changes needed
- `code/index.fcgi` — POST redirect: No change. `$c->{redirect_url}` (set by
  `postglass.pm:183` or `comments.pm:704`) or default `?o=$c->{op}` is fine;
  filter is not preserved after POST (by design).
- `code/postglass.pm` — No change.
- `code/comments.pm` — No change.
- `code/buttonline()` — Already passes `q` in hidden input (mainlist.pm:347).
  This is still useful for the form, but POST redirect will drop it (by design).
- No schema change, no new JS/CSS. `doc/design.md:193` wording remains
  accurate.

## Files to change
- `code/util.pm` — add `filter_tokens`.
- `code/mainlist.pm` — `matching_rec`, `filtered_list`, `mainlist()` branch/form
  changes, `nameline()` style-link, cache key.
- No other files need changes.

## Verification
1. `perl -c code/util.pm code/mainlist.pm code/index.fcgi` — regression check.
2. Touch `code/VERSION.pm` (separate step so it can be gated).
3. Manual dev tests:
   - Beer style label `[NEIPA]` is a clickable link; clicking opens form with
     filter=NEIPA and shows matching results (date defaults to today, lines=45).
   - Filtered list: no sum lines, no adjustment forms, no day totals.
   - "More results" link doubles maxl and preserves q+date.
   - Date param (e.g. from locationhead) opens form with date pre-filled,
     shows "days" field (not "lines").
   - "Older records" still works in unfiltered (date) mode.
   - "clr" link clears all params → clean list, no form.
   - Multi-word AND: `q=Mikkeller IPA` → only records having both words.
   - Phrase: `q="Beer Geek"` matches as one substring.
   - No match → "No matches for '<q>'".
   - Unfiltered default list looks exactly as before (no new clutter).
   - Copy buttons (`Copy 25`) work normally (POST drops filter, redirect to
     same page without q — by design).
   - Cache behaves: filtered views cached with distinct key including maxl,
     cleared after POST / VERSION touch.

## Future enhancements
- `qf` to restrict matching to a single field; `y` year filter.
- Optional SQL-side bounding of the row stream if large history makes the
  scan slow (note: SQLite LIKE is ASCII-only case-insensitive, so keep Perl
  matching for UTF-8 correctness).
