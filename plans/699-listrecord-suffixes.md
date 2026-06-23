# Plan: Multiple suffix support & `_cont` in listrecords

Make listrecords.pm field-name suffix parsing handle **multiple suffixes**
on one field, add **`_cont`** to merge multiple DB columns into one `<td>`,
and add **`_as:name`** to let any column borrow formatting from an existing
hardcoded field check.

Also moves `data-col`, `data-filter`, and `onclick` from the `<td>` element
to a wrapper `<span>` inside each cell, so `_cont`-grouped fields can each
have their own filter column and click handler.

## Completed

### 1. Multiple suffix parser (replaces lines 76-89)

A `do/while` loop extracts **all** known suffixes from each field name by
repeatedly stripping the rightmost recognized suffix. Parsed info is stored
in `@suffix_info` (array of hashrefs, one per column).

Known suffix patterns (tried in order per pass for correct rightmost-first
greediness):

  - `_R(\d+)`      → rowspan = N
  - `_C(\d+)`      → colspan = N
  - `_as:([^_]+)`  → effective field name override
  - `_(\d+px)`     → width override
  - `_A`           → auto_width
  - `_cont(:...)?` → continue cell (see below)

### 2. `_cont` — continuation suffix

Lets multiple SQL columns render inside a **single `<td>`**. The first field
in a group carries `_cont`; subsequent fields in the same row contribute
their content (with a separator) to the same cell.

Syntax:
- `_cont` — concatenated without separator
- `_cont:br` — `<br/>` between values
- `_cont:sep:TEXT` — custom TEXT separator between values

**Rendering logic:**

Before the inner data loop, initialize `$cont_active = 0` and `$cont_sep = ""`.
For each column:
- If `$cont_active` is true: append `$cont_sep . cell_value` (no `<td>` wrapper)
- Otherwise: emit `<td ...>` then cell_value
- If the field has `_cont`: set `$cont_active = 1` and calculate separator,
  but DON'T emit `</td>`
- Otherwise: emit `</td>` and reset `$cont_active`

Linebreaks (TR fields) inside a `_cont` group close the hanging `<td>` first.
After the row loop, if still continuing, force-close the `<td>`.

**Header loop:** Parallel `$hdr_cont_active` tracking stacks filter inputs
inside the same header `<td>`, using the same separator logic.

### 3. `_as:name` — effective field name override

```perl
$fn = $suffix_info[$i]{as_name} if $suffix_info[$i]{as_name};
```

Column header reads the base field name (after suffix stripping). The
formatting `elsif` chain uses the `_as:` value. The pattern uses `[^_]+`
(no underscores) to avoid ambiguity with following suffixes.

### 4. Span wrapper for all cells

Every data cell value is wrapped in a `<span>` carrying that column's
`data-col`, `data-filter` (if applicable), and `onclick`:

```html
<td style="...">
  <span data-col="0" data-filter="Heineken" onclick="fieldclick(event,this,0)">Heineken</span>
</td>
```

This lets `_cont`-grouped fields each have their own `data-col` on their
own span. The `<td>` only carries visual styles and extra attributes
(rowspan/colspan).

### 5. JavaScript change

In `fieldclick()`, column lookup prefers `target.dataset.col` (from the
clicked filter span) before falling back to `el.getAttribute("data-col")`:

```javascript
const col = target && target.dataset.col ? target.dataset.col : el.getAttribute("data-col");
```

This allows `_cont`-grouped spans to route filter clicks to the correct
header input regardless of which sub-field is clicked.

### 6. Cache key

Bumped to `"listrecords_v2"` to invalidate all cached HTML after the span
wrapper structural change.

### 7. `_filter` suffix

Wraps the column value in `«»` markers (U+00AB/U+00BB) so the entire cell
content becomes filterable. Applied after `$v //= ""`, before the existing
«» parser, so it integrates with the existing filter segment logic.

  - `_filter` → wraps non-empty values in `«value»`
  - NULL handling: guarded by `$v ne ""`, so empty cells stay empty

Replaces explicit `char(0xAB) || col || char(0xBB)` SQL in view definitions.

### 8. `_link:EntityType` suffix

Formats the cell value as a linked entity reference. Stored suffix info
includes the entity type name (e.g. `Person`, `Brew`, `Location`).

  - `_link:Person` → renders `42` as `<a href='?o=Person&e=42'><span>P[42]</span></a>: `
  - The prefix letter is `substr($entity, 0, 1)` (first char of entity type)
  - Appends `: ` after the link to serve as separator before the description
  - NULL handling: guarded by `if ($v)` in the formatting chain
  - Checked before `Id`/`Sub` in the `elsif` chain to avoid double-bracketing

## Migration 28 — `photos_list` view rewrite (issue #699)

Rewrote the `PHOTOS_LIST` view to use the new suffixes instead of inline
formatting:

| Old column | New column(s) |
|---|---|
| `PersonPref_A_cont` → inline `P[id]: ` | `PersonId_A_cont_link:Person` (raw id) |
| `PersonName_A` → `char(0xAB) \|\| Name \|\| char(0xBB)` | `PersonName_A_filter` (no prefix) |
| `Brew_A` → inline `B[id]: Producer: Name` | `BrewId_A_cont_link:Brew` + `BrewText_A_filter` |
| `Location_A` → inline `L[id]: Place` | `LocationId_A_cont_link:Location` + `LocationName_A_filter` |
| `Glass_A` → inline `G[id]: Producer: Beer` | `GlassId_A_cont_link:Glass` + `GlassText_A_filter` |
| `Comment_A` → inline `C[id]: (Rating) text` | `CommentId_A_cont_link:Comment` + `CommentText_A` |

Key decisions:
- `_cont` on ID columns merges the linked ID with the description into one
  visual cell — the `: ` separator comes from the `_link` handler
- `_filter` replaces explicit `char(0xAB)` wrappers on simple text columns
- `CommentText_A` retains explicit `char(0xAB)` in its subquery for
  individual person-name filtering — `_filter` would wrap too broadly
- `NULLIF(TRIM(...), '')` prevents edge case where TRIM('') produces an
  empty string (not NULL), which would show a stray `: ` prefix
- CASE WHEN wrappers dropped entirely — NULL propagation from joins and
  the suffix handlers' empty-value guards handle nulls correctly

## Non-goals (considered but not implemented)

**Semantic suffixes** (`_location`, `_person`, `_percent`, etc.) were
considered but decided against. The `_as:` override provides a simpler
bridge for reusing existing formatting.

## Design decisions

**Suffix parsing order:** Patterns are checked in a specific order within
the do/while loop — more specific patterns (`_R`, `_C`, `_as:`, `_px`, `_A`)
come before `_cont` to prevent the greedy `.+` in `_cont(?::(.+))?` from
eating subsequent suffixes.

**First-field style governs:** For `_cont` groups, the first column's
`$styles[$i]` sets the `<td>` width/alignment. Subsequent fields' styles
are ignored (they share the same cell).

**`data-col` on spans:** Each field wrapper span carries its own `data-col`,
so JS can route filter clicks to the right header input. Non-`_cont` cells
also use spans for consistency — the `<td>` no longer carries data-*
attributes or onclick.
