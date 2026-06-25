# Plan: Word-level multi-token filtering for listrecords

Replace the current cell-level `_filter` / `data-filter` / `«»`-marker system
with **word-level filtering**: each word in a cell is individually clickable,
the filter input accepts space-separated tokens (AND logic), and `«…»` markers
denote multi-word terms (spaces stored as `_`).

## Summary

- **Default**: every column is filterable (no suffix needed)
- **`_nofilter`** → column name in header, no filter input, no click-to-filter
- **`_noheader`** → no visible header cell, but hidden `<input>` keeps
  programmatic filtering alive (data-word clicks still work)
- **`_nofilter` + `_noheader`** together = data-only column, no header, no filter
- **`_link:Entity`** → implicitly acts as `_nofilter` + `_noheader`
  (clicking the link navigates, not filters)
- **Filter input**: space-separated tokens, each checked independently (AND)
- **`_` in a token** → matches `[ _]` in text content (so `John_Doe` matches
  both `John Doe` and `John_Doe` in the data)
- **Case-insensitive** matching; no diacritic normalization
- **`«term with spaces»`** in SQL → single token, spaces become `_`
  (e.g., `«John Doe»` → token `John_Doe`). The cleaned word is used for
  filtering; display text preserves the readable form.

## Word cleaning

Use the character allowlist from `util::param()` (line 149 of util.pm):
```
a-zA-ZñÑåÅæÆøØÅöÖäÄéÉáÁāĀüÜß\/ 0-9.,&:()[]?%!#=_-
```
(plus whitespace). Characters outside this set are stripped from tokens.
Filter matching also uses this allowlist: any non-allowed character in the
filter input is stripped when building match tokens.

## Phase 1 — Core word-split filtering

### 1a. `listrecords.pm` — rendering changes

1. Keep `_filter` in the suffix-stripping loop as a **no-op** (strip the suffix
   for clean column names, but don't add `«»` wrapping). This avoids breaking
   the `photos_list` view — migration of the view can come later.
2. Remove the `_filter` → `«value»` wrapping code (lines 304–307)
3. Remove the `«»` display-vs-filter segment parser (lines 309–328)
4. New word-splitting renderer (applied to every cell that is not `_nofilter`
   and not `_link`):
   - Parse `«…»` markers → single token, `s/ /_/g` inside
   - Clean the token: strip characters outside the util::param allowlist
   - Split remaining (non-`«»`) text by `\s+` into individual word tokens
   - Clean each: strip non-allowed characters
   - Empty tokens skip rendering
   - Render each token as: `<span onclick='fieldclick_word(event,this,COL)'>DISPLAY</span>`
   - No `data-word` attribute needed — the handler reads `el.textContent` directly
5. Remove `data-filter` from cell spans (not needed anymore)
6. Remove `onclick='fieldclick(...)'` from the cell wrapper span
7. Keep `data-col` on the cell wrapper span for sort/filter key lookup
8. **Double-click** on any cell: a `dblclick` handler on the cell wrapper span
   takes the full `el.textContent`, replaces spaces with `_`, strips non-allowed
   characters, and sets that as the column filter value (then triggers filter).
   This provides a way to filter multi-token cell content as one term.

### 1b. `listrecords.js` — client-side changes

9. New `fieldclick_word(event, el, col)`:
   - Reads `el.textContent` (the word itself) as the token
   - Strips characters outside the allowlist
   - Appends it to the column filter input's value (space-separated), not replace
   - Calls `dochangefilter(el)`
   - Keep old `fieldclick()` as fallback for backward compat

10. Update `dochangefilter()`:
    - Split each filter input's value by `\s+` into tokens
    - Strip non-allowed characters from each token
    - For each token: if it contains `_`, match against `[ _]` in cell text
    - A row's cell must match **all** tokens for the row to stay visible (AND)
    - Case-insensitive matching (like current regex with `i` flag)
    - Empty tokens are skipped

11. Add `dblclick` handler on cell wrapper span (data-col span):
    - Gets full `el.textContent`
    - Replaces spaces with `_`
    - Strips non-allowed characters
    - Sets that as the filter input value, replacing whatever was there
    - Triggers `dochangefilter`

12. Keep existing `showMoreRecords`, `clearfilters`, `sortTable` — no changes.

### 1c. `migrate.pm` — skip for now

The `_filter` suffix is kept as a no-op strip in the suffix loop, so the
`photos_list` view with its `_filter` column aliases still works (clean column
names, no `«»` wrapping). View migration can be done in a separate step.

### 1d. Cache key

No bump needed. The whole cache is cleared when the FastCGi script reloads.

## Phase 2 — New suffixes

### 2a. Add `_nofilter` to suffix pipeline

- Check in the do/while loop (before `_A`, after `_link`)
- `$suf->{nofilter} = 1`
- Header: render column name, no `<input>`
- Data: render plain text, no word spans, no click/dblclick handlers

### 2b. Add `_noheader` to suffix pipeline

- Check in the do/while loop
- `$suf->{noheader} = 1`
- Header: skip `<td>` entirely, but emit a hidden `<input type=text
  style='display:none' data-col='i'>` (appended after the header row)
  so the column remains programmatically filterable
- Data: normal word-span rendering, clicks append to filter as usual

### 2c. `_link` implies `_nofilter` + `_noheader`

When `_link:Entity` is detected, automatically set `nofilter` and `noheader`
flags. The link column gets no filter input and no word spans — its click
handler navigates to the entity page instead.

### 2d. Both combined

`_nofilter` + `_noheader` = no header cell, no filter input, no word spans
(raw display-only data column)

### 2e. `_clearfilters` — future alias for `Clr`

Consider adding `_clearfilters` as a suffix equivalent to the current `Clr`
hardcoded column name check.

## Phase 3 — Future

- `-PREFIX` token negation (e.g. `IPA -lager` = matches rows with IPA but not lager)
- Review all list views for `X`-prefix hidden columns → migrate to `_noheader`
- Review `Clr` hardcoded name check → `_clearfilters` suffix
- Review `None` name check → could be `_noheader_nofilter`
- Review `description`/`Comment` style checks → could be `_italic` suffix

## Existing views — impact analysis

All 8 views currently used with listrecords (from `caller` analysis):

| View | Suffixes used | Will the change break it? |
|---|---|---|
| `LOCATIONS_LIST` | none | **No** — no `_filter`, no `«»` in SQL. All cells get word-span rendering. |
| `LOCATIONS_DEDUP_LIST` | none | **No** — `Chk`, `Sim`, `Geo` have hardcoded `if` checks that suppress onclick. Word-split added with no effect. |
| `BREWS_LIST` | none | **No** — `tr`, `Clr` have hardcoded checks that suppress onclick. |
| `BREWS_DEDUP_LIST` | none | **No** — same as above. |
| `producer_brews_list` | none | **No** — `xId`, `xProducer`, `xUsername` matched by `^X` → `display:none`. |
| `COMMENTS_LIST` | none | **No** — `tr`, `Clr`, `None` suppress click handlers. |
| `PERSONS_LIST` | none | **No** — `Clr`, `trmob`, `tr` suppress. |
| `PHOTOS_LIST` | `_R8`, `_A`, `_filter`, `_cont`, `_link:` | **No** (with `_filter` kept as no-op). `_link:` columns become `_nofilter` + `_noheader`. `_cont` columns combine normally. `_filter` suffix stripped, no wrapping added. |

### Views that could be improved with new suffixes

1. **`PRODUCER_BREWS_LIST`**: `xId`, `xProducer`, `xUsername` use the `^X` hide
   pattern. Could become `_noheader`. But since they also need `display:none`
   on data cells, they'd need `_nofilter` + `_noheader` + `_hidden` (a new
   suffix for `display:none`). Out of scope for now.

2. **`BREWS_LIST` / `BREWS_DEDUP_LIST`**: `xUsername` via `^X` hide — see above.

3. **`COMMENTS_LIST`**: `None` column renders an empty header (no filter input).
   Could use `_noheader_nofilter` instead. The `Xusername` (uppercase X) uses
   `^X` pattern — same story.

4. **`PERSONS_LIST`**: `description` (lowercase d) gets italic styling via the
   `Comment|Description` hardcoded check. `Clr` via name match.

5. **General `Clr` columns**: 4 views use `Clr` column name for the clear-filters
   button. Could be `_clearfilters` suffix for explicitness. Not urgent.

6. **General `tr`/`trmob` columns**: All views use `TR`/`TRMOB` prefix for
   linebreaks. Could be `_break` / `_break:mob` suffix. Out of scope.

   
   Suggested order (easiest → biggest impact):

    LOCATIONS_LIST — simplest conversion. Already has a migration in migrate.pm. Just needs _link:Location on Id, _as:LocName on Name, _contline for Geo/Stats, split Type into LocType+LocSubType.

    PERSONS_LIST — also simple. Id→_link:Person, Name→_as:Name or plain, _contline for Com/Last/Location/Description.

    BREWS_LIST — most frequently used. Big payoff. Split Type into BrewType+SubType, use _link:Brew on Id, _as:LocName on Producer/Location, Stats split with _as:, _contline for layout, move Clr to row 1.

    COMMENTS_LIST — medium complexity. Multiple tr breaks, combined entity fields. Split into _link:Comment, _link:Glass, _link:Brew, _as:LocName on locs, _as:Rate on rating, _contline groups.

    LOCATIONS_DEDUP_LIST — niche dedup page. Simple but low-use. _link:Location on Id, Geo as-is.

    BREWS_DEDUP_LIST — same pattern as BREWS_LIST but simpler (no photo). _link:Brew on Id, Chk checkbox.

    producer_brews_list — very simple, used inside a location detail page. Just Alc, Sub, Stats, Last. Quick win.

   
### Summary

- **Nothing breaks** — the change is purely additive (word spans added,
  existing suffix handling preserved). The only removed code is the `«»` wrapper
  for `_filter` columns, which is No-Op since we keep the suffix in the loop.
- Most views don't use any filtering suffixes at all. They work by name-based
  hardcoded `if` chain (lines 185–232, 348–463 of listrecords.pm). The new
  word-split rendering only affects cells that don't have an explicit
  suppressing check.
- `_link:` columns (Phase 2) will automatically opt out of word-splitting,
  which is the correct behavior.
