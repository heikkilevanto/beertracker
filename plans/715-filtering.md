# Issue 715: Token-based filtering for dropdowns

## Background

The brew dropdown (and other entity dropdowns) uses a simple single-string
`item.textContent.includes(searchTerm)` filter. This makes searching for
multi-word beer names + breweries difficult — `Mikkeller Brunch` fails because
the text contains `Mikkeller: Beer Geek Brunch Weasel 10.5% ...` and the words
aren't contiguous.

listrecords.js solves this with `_tokenizeFilterInput()` which splits input
into tokens (respecting quoted strings) and AND-matches each one against the
target text.

## What already exists (no change needed)

These dropdown filter features are already implemented in `inputs.js`:

| Prefix | Meaning | Example |
|--------|---------|---------|
| `#tag` | Filter by tags attribute | `#ipa` → items tagged "ipa" |
| `#tag ` | Exact tag match (trailing space) | `#ipa ` |
| `@text` | Filter by seenat/location attribute | `@Mikkeller` |
| `brewtype` cascade | Hide items with wrong brewtype | automatic via `selbrewtype` |
| `loctype` cascade | Hide items with wrong loctype | automatic via `selloctype` |
| `regioncountry` | Hide regions outside selected country | automatic via `data-country-input` |

The `.` (dot) prefix is removed — bare `@` does the same thing.

## What's being added

### 1. Tokenization of general text search

Replace `item.textContent.includes(searchTerm)` with token-based AND matching,
using the same approach as listrecords:

| Token prefix | Meaning | Example |
|--------------|---------|---------|
| *(none)* | contains | `Mikkeller` → text includes "Mikkeller" |
| `-term` | NOT contains | `-Weasel` → text does NOT include "Weasel" |
| `=term` | exact match | `=Mikkeller: Beer Geek` → text equals exactly |
| `"phrase"` | phrase (quoted) | `"Beer Geek"` → matches as single substring |

All tokens must match (AND logic). Empty input shows all items.

### 2. Shared filter-utils.js module

Extract `_tokenizeFilterInput()` into `static/filter-utils.js` so both
listrecords.js and inputs.js use the same function without duplication.

## Implementation stages

### Stage 1: Refactoring (filter-utils.js + listrecords)

| Step | File | Action |
|------|------|--------|
| 1a | `static/filter-utils.js` | **Create** — shared `_tokenizeFilterInput()` function |
| 1b | `code/index.fcgi` | Add `print jslink("filter-utils");` in `htmlhead()` before `inputs.js` |
| 1c | `static/listrecords.js` | Remove local `_tokenizeFilterInput`, uses shared version |
| 1d | — | `perl -c` check, touch VERSION.pm, verify listrecords still works |

### Stage 2: Dropdown tokenization

| Step | File | Action |
|------|------|--------|
| 2a | `static/inputs.js` | In `filterItems()`, replace else-branch `.includes()` with tokenized matching |
| 2b | `static/inputs.js` | Remove the `isDotFilter` block (`.` prefix) — no longer needed |
| 2c | — | `perl -c` check, touch VERSION.pm, manual browser test |

## What stays the same

- `#` tag filter, `@` location filter — handled before the text block
- `brewtype`/`loctype`/`regioncountry` cascade — separate logic, unchanged
- All Perl modules — no server-side changes
- Dropdown item HTML structure — unchanged

## Future enhancements

- OR operator (`|` pipe) between tokens for alternative matching

## Verification

1. `perl -c` all Perl files (regression check)
2. Touch `code/VERSION.pm`
3. Manual browser test:
   - `Mikkeller Brunch` → matches non-contiguously
   - `"Beer Geek"` → matches as phrase
   - `Mikkeller -Weasel` → exclusion works
   - `=Mikkeller: Beer Geek Brunch Weasel` → exact match
   - `#tag` / `@location` filters still work
   - Cascade filters (brewtype, loctype, country) still work
   - Empty filter shows all items
