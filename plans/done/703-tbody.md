# Plan: Per-record `<tbody>` in listrecords

Wrap each record (main `<tr>` + linebreak continuation `<tr>`s) in its own
`<tbody>` so that `rowspan` can span continuation rows within a record.

## Changes

### 1. `code/listrecords.pm` — per-record tbody in the while loop

Currently (line 308):
```perl
$s .= "</thead><tbody>\n";
```
Then inside the while loop (lines 505-506):
```perl
$s .= "<tr data-first=1 class='top-border'$hidden>\n";
$s .= "$tds</tr>\n";
```
And after (line 508):
```perl
$s .= "</tbody></table>\n";
```

Change to:
```perl
$s .= "</thead>\n";
```
Then in the while loop, before each record's first `<tr>`:
```perl
$s .= "</tbody>\n" if $not_first;
$s .= "<tbody$hidden>\n";
$s .= "<tr data-first=1 class='top-border'>\n";
```
And after each record's `</tr>`, immediately close the tbody:
```perl
$s .= "$tds</tr>\n";
$s .= "</tbody>\n";
```
Remove the old `</tbody>` after the loop (line 508 becomes just `</table>\n`).

Since `$hidden` is now on `<tbody>`, the linebreak TRs don't need the hidden
attribute — remove the `$linebreak =~ s/<tr>/<tr$hidden>/` logic (line 340).

Bump the cache key version to `"listrecords_v3"` (line 62).



### 2. `static/listrecords.js` — sort function rewrite

**`doSortTable`** needs to reorder `<tbody>` elements instead of regrouping
`<tr>`s inside a single tbody:

```
function doSortTable(el, col, ascending):
  const table = el.closest('table')
  const tbodies = Array.from(table.tBodies)

  // temporarily unhide hidden tbodies
  // extract sort key from each tbody (first [data-col] in first tr)
  // sort tbodies by key
  // detach all tbodies from table
  // reattach in sorted order
  // re-hide tbodies beyond maxRecords
```

This is simpler than the current approach — no row-grouping logic needed.

**`dochangefilter`** — the `nextElementSibling` traversal still works within
each tbody (lines 53-75, 78-81). A tbody holds one record, so when
`nextElementSibling` after the last continuation `<tr>` is `null`, the inner
loop exits. **No changes needed.**

**`showMoreRecords`** — change `table.querySelectorAll('tr[hidden]')` to
`table.querySelectorAll('tbody[hidden]')`.

**Filter unhide** — change `table.querySelectorAll('tr[hidden]')` (line 42)
to `table.querySelectorAll('tbody[hidden]')`.

**Sort unhide** — same change (line 209).

**Filter rehide** — change `currentRow.setAttribute('hidden', '')` (line 97)
to set it on the tbody. Since records are per-tbody, the iteration changes:
instead of walking `nextElementSibling` from a `data-first` row, iterate
`table.tBodies` directly.

**Sort rehide** — same change (lines 262-273): iterate `table.tBodies`
instead of `tbody.querySelectorAll('tr[data-first="1"]')`.

### 3. Remove `data-first` reliance where possible

With per-record tbodies, the JS can iterate `table.tBodies` instead of
`table.querySelectorAll('tbody tr[data-first]')`. Keep `data-first` on the
first `<tr>` of each tbody for backward compatibility, but the sort and
filter functions should prefer tbody-level iteration.

## Steps

1. Edit `code/listrecords.pm` — restructure the while loop for per-record tbodies
2. Edit `static/listrecords.js` — rewrite sort, update hidden selectors and filter iteration
3. Touch `code/VERSION.pm` to trigger reload
4. Manual test: load a few listrecords views, test sort, filter, showMore, verify no visual regressions
5. Test with a record that has linebreak continuations to confirm rowspan would work

## Non-goals

- Not changing ratestats.pm or other modules that use `<tbody>`
- Not changing the SQL or view definitions
- Not adding actual rowspan usage — just enabling the structure for it
