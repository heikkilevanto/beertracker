# Plan: Multiple suffix support & `_as:name` in listrecords

Make listrecords.pm field-name suffix parsing handle **multiple suffixes**
on one field, and add **`_as:NAME`** to let any column borrow formatting
from an existing hardcoded field check.

## Completed: Multiple suffix parser

### Suffix parser (replaces lines 76-89)

The old parser handled one suffix per field with separate regexes in fixed
order. Now a `do/while` loop extracts **all** known suffixes from each field
name by repeatedly stripping the rightmost recognized suffix.

Algorithm:
- For each field name, loop stripping known suffix patterns from the right
- Store parsed info in `@suffix_info` (array of hashrefs, one per column)
- The loop continues until no more patterns match
- Remaining string is the base field name (used for display headers)

Known suffix patterns (tried in order per pass, no overlap):
  - `_R(\d+)`      → rowspan = N, stored in `$extra_attr[$i]`
  - `_C(\d+)`      → colspan = N, stored in `$extra_attr[$i]`
  - `_as:([^_]+)`  → as_name = CAPTURE (see below)
  - `_(\d+px)`     → width_override = Npx, stored in `$px_override{$i}`
  - `_A`           → auto_width, stored in `$auto_override{$i}`

### `_as:name` — effective field name override

Before the formatting `elsif` chain, override `$fn` with the `_as:` value:

```perl
$fn = $suffix_info[$i]{as_name} if $suffix_info[$i]{as_name};
```

Effect:
- Column header reads the base field name (after suffix stripping)
- The `elsif` chain uses the `_as:` value for matching
- Example: `Venue_as:LocName` → header "Venue", formats as `@Venue`

The `_as:` pattern uses `[^_]+` (no underscores in the captured name) to
avoid ambiguity when other suffixes follow (e.g. `Venue_as:LocName_A`
strips `_A` first, then `_as:LocName`).

### Design decisions

**Multiple suffixes on one field:**
Field name `Photo_R8_as:Photos` strips right-to-left:
1. `_as:Photos` → as_name="Photos", base="Photo_R8"
2. `_R8` → rowspan=8, base="Photo"
Final: field="Photo", rowspan=8, as_name="Photos"

**Header vs formatting:**
The base field name (after suffix stripping) drives headers and filter
placeholders. Only the formatting `elsif` chain uses `_as:`.

**Backward compatibility:**
All existing views work unchanged — none use `_as:` yet, and fields with
a single suffix parse exactly as before.

## Non-goals (considered but not implemented)

**Semantic suffixes** (`_location`, `_person`, `_percent`, etc.) were
considered as a more abstract alternative but decided against. The `_as:`
override provides a simpler bridge: reuse existing formatting by aliasing
the field name. Semantic dispatch would require a new formatter registry
and migration of all views — not worth the complexity now.

## Future extensions (not in this plan)

- Presentational wrappers (`_bold`, `_italics`, `_center`, `_num`, etc.)
- `_cont` / `_break` / `_hide` pseudo-field suffixes
- Function wrappers (`_brewstyle`, `_avgratings`, `_datelink`, etc.)
- Updating existing views to use suffixes instead of hardcoded checks
