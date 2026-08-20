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
- `$c->{qry}` is still wired up: set at `index.fcgi:253`, kept in cache key
  `mainlist.pm:612` and copy-button hidden input `mainlist.pm:344`.
- `filt()` helper was deleted in `e25e506`; current convention is tokenized
  matching (`static/filter-utils.js`, plans/715-filtering.md).

## Decisions (confirmed)
- **Matching:** tokenized AND + substring (Unicode-safe, case-insensitive),
  quotes for phrases. Matches any of brewname, producer, locname, subtype,
  brewtype, shortname, note, tap. Comments excluded (covered by planned
  `o=Search`, issue #740).
- **Filtered view:** date+location headers, no sum lines/adjustment forms/day
  totals.
- **Limiting:** record cap `maxl` (default 45) + "More results" link; scans
  from today backwards; ignores `ndays`.
- **Scope:** just `q` for now; `qf` and `y` are future enhancements.

## Implementation

### 1. Tokenizer helper in util.pm
Port `_tokenizeFilterInput` from `static/filter-utils.js`:
`sub filter_tokens($)` returns an arrayref of tokens, respecting `"..."`
phrases (quotes stripped) and splitting unquoted input on whitespace.

### 2. `sub matching_rec($c, $rec)` in mainlist.pm
- `return 1` if no `$c->{qry}` or `q eq "."` (`.` only opens the filter UI).
- Tokens obtained via `util::filter_tokens($c->{qry})`; every token must match
  (`/\Q$token\E/i`, AND-logic) at least one of the match fields:
  `brewname`, `producer`, `locname`, `subtype`, `brewtype`, `shortname`,
  `note`, `tap`. Undefined/empty fields are skipped.
- `\Q\E` prevents regex injection; data comes from the DB (server-side),
  `$c->{qry}` is already sanitized at `index.fcgi:253`.

### 3. New `sub filtered_list($c)` in mainlist.pm
- Branch in `mainlist()` (mainlist.pm:584): if `$c->{qry}` → filtered_list();
  else keep the existing day-loop/`oneday()` completely unchanged (no
  regression risk, no added markup by default).
- Reads `maxl` via `util::paramnumber($c, "maxl", 45)`.
- Runs `glassquery($c, today)` to get the buffered lazy stream (`db::peekrow`/
  `nextrow`/`pushback_row`). Scan from today backwards:
  - collect one day's rows (same grouping as `oneday` pass 1) so per-record BA
    is computed physically via `bloodalc_compute` on the full day;
  - keep only records where `matching_rec` returns true, preserving order;
  - render matching records reusing existing per-record renderers
    (`locationhead` for a light date+location header on each group, then
    `nameline`, `numbersline`, `photoline`, `commentlines`, `buttonline`);
  - do NOT call `sumline`, `adjustment_form`, or the day total;
  - stop once `maxl` matches are rendered (`last`, with
    `db::pushback_row` only if we consumed a row of the next day we don't need;
    otherwise just leave the stream and `$sth->finish`).
- Emit "More results" link when the stream had more matches:
  `<a href='$c->{url}?o=$c->{op}&q=…&maxl=$maxl*2'><span>More results</span></a>`
  (double the cap; `uri_escape_utf8` the q).
- "No matches for '<q>'" line when nothing matched.
- `$sth->finish` at the end.

### 4. Filter UI (no clutter when not filtering)
- No `q` → page renders exactly as today.
- `q` present (incl. `q=.`): compact one-line bar modeled on the beerboard
  banner (`beerboard.pm:55-59`):
  `Filter: <b>…</b> (<a … Clear>/</a>)` plus a small GET form
  `<input name='q'>` and `Go` button, hidden `o`.
- Small **Filter** link near the "Main List" heading that sets `q=.` to open
  the bar without filtering.
- Hide the date/ndays form while filtering (filtered view is a flat result
  list, not day-grouped); keep the summary count/unfiltered view unchanged.

### 5. Cache key & POST persistence
- Filtered path uses a distinct cache key including `$c->{op}`, `$c->{qry}`,
  `date`, and `maxl`, e.g.
  `"mainfilter:$c->{username}:$c->{op}:$c->{qry}:$date:$maxl"`.
  (Extend or replace the existing key at mainlist.pm:612 for the filtered
  branch.) `cache::clear` after any POST already invalidates these.
- Preserve `q` across POST copy-buttons: `index.fcgi:346` redirect
  (`$c->{redirect_url} || "$c->{url}?o=$c->{op}"`) drops q; append
  `&q=` from the copy-button hidden input (mainlist.pm:344) so a filter
  survives a copy. Update beerboard/mainlist redirect-building accordingly.

## Files to change
- `code/util.pm` — add `filter_tokens`.
- `code/mainlist.pm` — `matching_rec`, `filtered_list`, `mainlist()` branch,
  filter UI, cache key.
- `code/index.fcgi` — redirect keeps `q` after POST.

No schema change, no new JS/CSS. `doc/design.md:193` already documents the
feature; wording should remain accurate.

## Verification
1. `perl -c code/util.pm code/mainlist.pm code/index.fcgi` — regression check.
2. Touch `code/VERSION.pm` (separate step so it can be gated).
3. Manual dev tests:
   - multi-word AND: `q=Mikkeller IPA` → only records having both words;
   - phrase: `q="Beer Geek"` matches as one substring;
   - no match → "No matches for '<q>'";
   - `maxl` cap and "More results" link work and preserve `q`;
   - `q=.` opens the bar without filtering anything;
   - copies (`Copy 25`) keep the filter after the POST redirect;
   - cache behaves: filtered views cached, cleared after POST / VERSION touch;
   - unfiltered default list looks exactly as before (no new clutter).

## Future enhancements
- `qf` to restrict matching to a single field; `y` year filter.
- Optional SQL-side bounding of the row stream if large history makes the
  scan slow (note: SQLite LIKE is ASCII-only case-insensitive, so keep Perl
  matching for UTF-8 correctness).