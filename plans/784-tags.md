# Issue #784 — Tags on brews, with seasonal autofill

## Problem
The ølbaren scraper (`scripts/oelbaren.pl`) cannot tell which beers are Xmas
specials — the page carries no marker, only the beer names themselves
("45 Days of X-Mas", "Jule-IPA", "Christmas Ale"). So the scraper is the wrong
place for it.

`brews` has no `Tags` column at all, even though `persons` and `locations` do,
and `doc/manual.md` already claims *"It is possible to attach tags to brews,
locations, and persons"* — currently untrue for brews.

## Goal
1. A real free-form `Tags` column on `brews`, reusing the existing chip UI,
   `db::all_tags`, `util::clean_tags` and `#`-dropdown filtering.
2. When a new brew's name matches a seasonal pattern, the UI pre-fills the tag
   — **only if the user has not already touched the tags field**.
3. Make the tags findable: a visible column in the brews list, and `#tag`
   support in the main-list `q` filter.

## Decisions (confirmed)
- Free-form `Tags` column, not a dedicated Season column.
- Tags visible as a column in the brews list (`Tags_A_cont`).
- Main list `q` searches tags **only for tokens starting with `#`**
  (`?q=IPA #xmas` works, `?q=xmas` does not search tags).
- Autofill writes lowercase tags; **no** normalisation change to
  `util::clean_tags` or `db::all_tags`.
- The scraper stays untouched.

---

## The leading-space "not user-edited" marker

Reuse the existing convention (see `code/glasses.pm:131-140` for date/time,
`code/postglass.pm:155` for tap, `code/postglass.pm:419` for price):

> A **leading space** on a form value means *the user has not edited it*.
> JS checks `value.startsWith(" ")` before overwriting, and writes back
> `" " + value` to keep the marker. Any user interaction drops the space, so
> autofill permanently stands down for that field.

Applied to the Tags hidden input:

- **Server** (`inputs::tagsinput`, `code/inputs.pm:446`): render
  `value=' '` when the value is empty, `value='xmas'` when it has content.
  - New brew, no tags → marker present → autofill may fire.
  - Existing / duplicated brew with tags → no marker → autofill never fires.
  - `util::clean_tags` already splits on `\s+` (`util.pm:134-139`), so the
    marker is stripped before storage even if it ever reaches the DB.
- **JS**: autofill only runs while `hidden.value.startsWith(" ")`.
- **JS**: user chip add/remove rewrites the hidden input from the chip labels
  *without* the leading space → autofill is off for good. This replaces any
  need for a "dismissed" flag: removing the auto-added chip stops re-adding.

Note the existing submit handler (`inputs.js:105-114`) already rewrites the
hidden input from the chips on submit, so the marker never reaches the server
as data — it is purely client-side state.

---

## Changes

### 1. Migration — `code/migrate.pm`
Add `sub mig_055_add_brews_tags`:
```sql
ALTER TABLE brews ADD COLUMN Tags TEXT DEFAULT ''
```
- Register `[55, 'Add Tags column to brews', \&mig_055_add_brews_tags]` in
  `@MIGRATIONS` (`migrate.pm:33-36`).
- Bump `$CODE_DB_VERSION` (`migrate.pm:28`) 54 → 55.
- Load a page → migration form → POST to apply, then run `tools/dbdump.sh`.
  Never edit `doc/db.schema` by hand.

### 2. Field order — `code/brews.pm:13-35`
Append to `$brew_field_order`:
```perl
[ "Tags", "Space separated tags, e.g. xmas" ],
```
This alone makes the field appear in the full-page form *and* in the inline
quick-add sub-form (both go through `$brew_field_order`).

### 3. Edit form gets the chip widget — `code/brews.pm:353`
`editbrew` currently passes `undef` as the `$available_tags_ref`:
```perl
print inputs::inputform($c, "BREWS", $p, undef, undef, undef, undef, undef, $brew_field_order);
```
→ pass `db::all_tags($c, "BREWS")` in that slot so `inputs.pm:290-293` renders
`tagsinput` instead of a plain text input.

The inline quick-add path already does the right thing: `inputs::dropdown`
(`inputs.pm:67-71`) detects a `Tags` column via `db::tablefields` and passes
`db::all_tags` itself. No change needed there.

### 4. Leading-space marker — `code/inputs.pm:446`
```perl
my $hidden_val = ($current ne "") ? $current : " ";
$s .= "  <input type='hidden' name='$fieldname' id='$fieldname' value='" . util::htmlesc($hidden_val) . "'/>\n";
```
(`$current` is already split/filtered into chips at `inputs.pm:399`, so an
empty value renders zero chips either way.)

### 5. Chip widget API — `static/inputs.js`
Add two small globals next to `initTagsInput` (`inputs.js:33-148`):

- `window.tagsIsAuto(fieldname)` → `hidden.value.startsWith(" ")`.
- `window.tagsSet(fieldname, value, auto)` → clear current chips, add one chip
  per whitespace-separated word, mark the matching available chips `used`, and
  set `hidden.value = auto ? " " + value : value`.

Needed because `initTagsInput` only syncs chips → hidden input on form submit
(`inputs.js:105-114`); writing the hidden input alone would be clobbered.

In the existing user-action handlers (`inputs.js:44-68`, chip remove and
available-chip add), after mutating the chips also rewrite
`hidden.value = labels.join(" ")` **without** a leading space — this is what
arms the "user has edited it" state.

### 6. Autofill — `static/brews.js`
New IIFE covering **both** forms, keyed by prefix:

| form | name field | tags field |
|---|---|---|
| full page `?o=Brew&e=new` | `Name` | `Tags` |
| inline quick-add in glass form | `newbrewName` | `newbrewTags` |

(The existing ShortName IIFE at `brews.js:4-11` bails out when `input[name=Name]`
is absent, so it never runs for the quick-add form. Do not copy that structure —
iterate the prefixes instead.)

On `input` of the name field:
1. If `!tagsIsAuto(tagsField)` → return (user has edited tags).
2. Compute the suggestion from `Name + " " + BrewStyle + " " + Details`.
3. If a suggestion exists and differs from the current auto value →
   `tagsSet(tagsField, suggestion, true)`.

Pattern map as a single constant at the top of `brews.js` (UI-only source of
truth, lowercase output):

| tag | pattern (case-insensitive) |
|---|---|
| `xmas` | `\bjul\b`, `\bjule[\p{L}]*\b`, `\bx[\s-]?mas\b`, `\bchristmas\b`, `\badvent\b`, `\bnisse[\p{L}]*\b` |
| `easter` | `\bpåske[\p{L}]*\b`, `\beaster\b` |
| `summer` | `\bsommer[\p{L}]*\b`, `\bsummer\b` |
| `oktoberfest` | `\boktoberfest\b`, `\bm[aä]rzen\b` |

Why these boundaries: `\bjul\b` must **not** match "Juli" (July) — the `\b`
after `jul` fails on `i`; `\bjule[\p{L}]*\b` catches "Jule-IPA" and
"Julebryg" (`jule` followed by `-` or more letters).

### 7. Dropdown must merge, not replace — `code/brews.pm`
- `brews.pm:521-542` selectbrew SQL: add `BREWS.Tags` to the SELECT, and add
  the extra value to the `fetchrow_array` destructuring at `brews.pm:546`.
- `brews.pm:568-573`: today `$tags_str = lc($SubType)` — that is the *only*
  source of the dropdown `tags` attribute. Append the real tags:
  ```perl
  my @parts = grep { $_ } ( lc($su // ""), lc($rec_tags // "") );
  my $tags_str = join(" ", @parts);
  ```
  Replacing instead of merging would silently break `#ipa` filtering.

The opts HTML is cached under `selectbrew_opts:$user:$brewtype`
(`brews.pm:517`); `cache::clear` runs after every POST, so no stale-cache work.

### 8. Brews list column — `code/brews.pm:52-70`
Add to the `listbrews` SELECT:
```sql
brews.Tags AS "Tags_A_cont",
```
Visible, auto-width, client-side filterable like any other listrecords column.

### 9. Main-list `#tag` search — `code/mainlist.pm`
- `glassquery` (`mainlist.pm:44` area): add `brews.Tags AS tags`.
- `matching_rec` (`mainlist.pm:656-664`): branch per token —
  ```perl
  if ( $token =~ /^#(.*)$/ ) {
      my $want = lc($1);
      # a bare '#' matches any record that has at least one tag
      $matched = has_tag_prefix($rec->{tags}, $want);
  } else {
      ... existing field loop ...
  }
  ```
  `has_tag_prefix`: split `tags` on whitespace, case-insensitive word-prefix
  match — mirrors the dropdown's prefix behaviour (`inputs.js:595`).
  Tokens stay AND'd, so `?q=IPA #xmas` works.

  `util::filter_tokens` (`util.pm:240-251`) keeps `#xmas` as one token and
  `util::param` (`util.pm:112-126`) permits `#` and space in the sanitiser
  class, so no tokenizer change is needed.

### 10. Docs / help text
- `doc/manual.md` §Tags — already claims brews are taggable; add a sentence
  about the `#tag` main-list filter and the seasonal autofill.
- Main-list filter form hint (`mainlist.pm:773-784`) — mention `#tag`.
- `static/glasses.js:234-241` Brew help already says `'#tag = filter by tags'`
  — becomes true, no change.

---

## Tests
- `tools/test-unit` — existing `clean_tags` test (`tools/test-unit:305-308`)
  must still pass; add a case for a leading-space value.
- `tools/test-http` — round-trip POST creating a brew with tags; confirm the
  stored value has no leading space and no `#`.
- Manual:
  - Full-page `?o=Brew&e=new`: type "Ebeltoft Jule-IPA" → `xmas` chip appears;
    edit the chips → further name edits no longer touch tags.
  - Inline quick-add in the glass form (`newbrewName`/`newbrewTags`).
  - Existing brew with tags → no autofill on edit.
  - Duplicate a tagged brew → tags preserved, no autofill.
  - `?q=#xmas`, `?q=IPA #xmas`, `?q=xmas` (must NOT filter on tags).
  - `#ipa` in the Brew dropdown still filters by subtype.

## Out of scope
- `scripts/oelbaren.pl` — unchanged.
- `scrapeboard.pm` (beer-board scraper) creates brews server-side with no
  autofill; leave as is.
- Lowercasing existing `persons`/`locations` tags.
