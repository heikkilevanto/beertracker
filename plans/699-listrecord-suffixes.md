# Plan: Suffix-driven formatting in listrecords

Make listrecords.pm formatting driven by field-name suffixes instead of
hardcoded field-name checks. The goal is to specify formatting in the SQL
view field aliases, so views become self-documenting and the rendering
code stays generic.

## Phase 1 — Core suffix parser & simple formatters

This phase replaces ~half of the hardcoded `elsif` chain in listrecords.pm
with a generic suffix system.

### 1.1 Rewrite suffix parsing (lines 76–89)

Current parser handles one suffix at a time with separate regexes in order.
Replace with a loop that extracts **all** known suffixes from each field
name, regardless of order or number.

Algorithm:

```
base_field = current name
suffixes = {}

# Known suffix patterns, tried in order (NO overlap between patterns)
patterns:
  - _R(\d+)        → rowspan = N
  - _C(\d+)        → colspan = N
  - _(\d+px)       → width_override = Npx
  - _A             → auto_width = true
  - _cont(br|sep:)? → cont = "br"/"sep:STR"/true
  - _bold          → bold = true
  - _italics       → italics = true
  - _small         → small = true
  - _mono          → mono = true
  - _center        → center = true
  - _num           → num = true
  - _bracket       → bracket = true
  - _paren         → paren = true
  - _hide          → hidden = true
  - _null          → null = true
  - _upper         → case = upper
  - _lower         → case = lower
  - _ucfirst       → case = ucfirst
  - _sort:(num|txt|date) → sort_type = num|txt|date
  - _edit:([^_]+)  → edit_op = CAPTURE  (e.g. "Glass" or "Person")
  - _link:([^_]+)  → link_op = CAPTURE
  - _prefix:(.)    → prefix = CAPTURE
  - _suffix:(.)    → suffix = CAPTURE
  - _unit:(.+)     → unit = CAPTURE  (e.g. "%", ".-", "cl")
  - _default:(.+)  → default_text = CAPTURE
  - _bool:(.+)     → bool_text = CAPTURE
  - _extlink:(.+)  → extlink_label = CAPTURE

Loop: while field =~ s/_(KNOWN_SUFFIX)$//, store it.  Strip rightmost
first so suffixes are order-independent.
```

Store parsed suffixes in a hashref per column:

```perl
my @suffix_info;  # array of hashrefs, one per column
```

### 1.2 Apply simple wrappers in the rendering loop (lines 280–388)

For each cell value, after the filter marker parsing (line 246–265), apply
suffix-driven formatting before the field-name checks:

```
sub apply_suffix_formatting {
    my ($v, $suf, $c, $rec, $i, $data_ref, $onclick_ref) = @_;

    # 1. Default/null handling
    if ($suf->{null} && !$v) {
        return "<span class='null-value'>NULL</span>";
    }
    if ($suf->{default_text} && !$v) {
        $v = $suf->{default_text};
    }

    # 2. Case transforms
    $v = uc($v)        if $suf->{case} eq 'upper';
    $v = lc($v)        if $suf->{case} eq 'lower';
    $v = ucfirst($v)   if $suf->{case} eq 'ucfirst';

    # 3. Bool display
    if ($suf->{bool_text} && $v) {
        $v = $suf->{bool_text};
    }

    # 4. Link / edit
    if ($suf->{edit_op}) {
        my $label = substr($suf->{edit_op}, 0, 1);  # "Persons" → "P"
        $v = "<a href='$c->{url}?o=$suf->{edit_op}&e=$v'><span>$label[$v]</span></a>";
        $$onclick_ref = "";
        return $v;
    }
    if ($suf->{link_op}) {
        $v = "<a href='$c->{url}?o=$suf->{link_op}&e=$rec[0]'><span>$v</span></a>";
        $$onclick_ref = "";
        return $v;
    }
    if ($suf->{extlink_label}) {
        return util::extlink($v, $suf->{extlink_label});
    }

    # 5. Prefix / suffix
    $v = $suf->{prefix} . $v  if $suf->{prefix};
    $v = $v . $suf->{suffix}  if $suf->{suffix};

    # 6. Unit
    if ($suf->{unit}) {
        $v = util::unit($v, $suf->{unit}) if $v;
        return $v;
    }

    # 7. Wrappers (apply from inside out)
    $v = "[$v]"  if $suf->{bracket};
    $v = "($v)"  if $suf->{paren};
    $v = "<b>$v</b>"      if $suf->{bold};
    $v = "<i>$v</i>"      if $suf->{italics};
    $v = "<small>$v</small>" if $suf->{small};
    $v = "<span style='font-family:monospace'>$v</span>" if $suf->{mono};

    return $v;
}
```

Call this AFTER filter marker parsing but BEFORE the field-name checks.
The field-name checks remain for now as overrides; in future phases they
get removed one by one as view definitions are updated.

### 1.3 Add sort-type and alignment data attributes

In the `<td>` generation (line 392), if `$suffix_info[$i]{sort_type}`
or `$suffix_info[$i]{center}/$suffix_info[$i]{num}`:

```
data-sort-num  = "1"  if sort_type eq 'num'
data-sort-date = "1"  if sort_type eq 'date'
style text-align:center  if center
style text-align:right   if num
```

### 1.4 Implement `_cont` handling

Add a `$continue` flag before the cell loop. In each iteration:

```
if ($continue) {
    # Don't emit <td>
} else {
    emit "<td ...>"
}
# render value
if ($suffix_info[$i]{cont}) {
    $continue = 1;
    if ($suffix_info[$i]{cont} eq 'br') {
        append "<br/>" after value
    } elsif (my $sep = $suffix_info[$i]{cont_sep}) {
        append $sep after value
    }
    # DON'T emit </td>
} else {
    emit "</td>"
    $continue = 0;
}
```

### 1.5 Update suffix parsing order

The existing order (lines 76–89) processes suffixes in a fixed sequence.
The new parser must extract ALL suffixes from a single field name.
The order they are applied in rendering (wrappers) is independent of the
order in the field name.

### 1.6 Pseudo-fields `_break` and `_hide`

Add `_break` suffix as an alternative to the `TR` prefix:
- `_break`  → line break unconditionally (like `TR`)
- `_breakMOB` → line break only on mobile (like `TRMOB`)

Add `_hide` suffix as an alternative to the `x` prefix.

For now, keep the existing prefix handling too — don't break existing views.

## Phase 2 — BeerTracker-specific function wrappers

Replace the rest of the hardcoded field-name checks:

| Field | Current | Suffix |
|-------|---------|--------|
| `Name` | bold link `?o=$op&e=$id` | Would need: `_link:OP_bold` but OP is dynamic. Could use `_edit:OP` where OP is the current operation. Or keep `Name` special. |
| `Type` | `styles::brewstyledisplay()` | `_brewstyle` |
| `Stats` | `comments::avgratings()` | `_avgratings` |
| `Chk` | checkbox input | `_checkbox` |
| `Last` | date link with time/weekday | `_datelink` (calls util::splitdate) |
| `Photo` | `photos::imagetag()` | `_photo` (needs Id from row) |
| `Photos` | multiple image tags | `_photolist` |
| `Sim` | `util::namesimilarity()` | `_namesim` (needs Name + extraparams) |
| `Geo` | `geo::geodist()` | `_geodist` (needs extraparams) |

These are implemented as additional `if ($suf->{brewstyle}) { ... }` blocks
in the formatting function. Each wraps a specific module function.

Implementation notes:
- `_datelink` needs the cutoff date for when to show full vs short format
- `_photo` / `_photolist` needs the `Id` column index from the same row
- `_namesim` needs `$extraparams->{refname}` and the `Name` column value
- `_geodist` needs `$extraparams->{lat/lon}` and parses the value

## Phase 3 — Update existing views

Once the suffix system handles everything the hardcoded checks do, update
the SQL views in `migrate.pm` to use suffixes and remove the corresponding
hardcoded checks. Non-exhaustive list:

- `brews_list`: `Name` → `Name_link:Glass_bold` (but op is dynamic... keep as special case)
- `brews_list`: `Alc` → `Alc_unit:%_num`
- `locations_list`: `Geo` → `Geo_geodist_num`
- `comments_list`: `LocName` → `LocName_prefix:@`
- `comments_list`: `PersonName` → `PersonName_suffix::`
- `comments_list`: `Rate` → `Rate_paren_center`
- `comments_list`: `Comment` → `Comment_italics`
- `persons_list`: `Photo` → `Photo_photo`
- All views: `Stats` → `Stats_avgratings_center`
- All views: `Chk` → `Chk_checkbox`

The `Name` special case (bold link to current op) may need to stay
hardcoded or get a suffix like `_currlink` that uses the current `$c->{op}`.

## Phase 4 — Cleanup

Once all views are migrated and tested, remove the old hardcoded field-name
checks from listrecords.pm lines 280–388. Keep only the suffix-driven
formatting and the special `Name` case (or make Name suffix-driven too).

## Design decisions

### Multiple suffixes on one field
Field name: `Photo_R8_edit:Photos`
Parsing order: strip rightmost suffix repeatedly
- `_edit:Photos` → suffix_info = { edit_op => "Photos" }, base = "Photo_R8"
- `_R8` → suffix_info = { ..., rowspan => 8 }, base = "Photo"
Final: field="Photo", rowspan=8, edit_op="Photos"

### Suffix application order
Apply from "inner" to "outer": case transform → prefix/suffix → unit →
bracket/paren → bold/italics/small/mono → edit/link/extlink.
This way `<b>[value]</b>` looks right instead of `[<b>value</b>]`.

### Prefix letter for _edit
`_edit:Persons` → extract first letter "P" → `P[1234]`.
`_edit:Location` → first letter "L" → `L[99]`.
If the first letter isn't meaningful, allow `_edit:Persons:P` where the
third part is the explicit prefix. Or just use the full Op as the link text?

### _cont state management
Track `$continue` as a per-row state variable. If the last cell in a row
has `_cont`, force-close the TD (don't leave dangling).

### Views still need to define their columns
The suffixes augment what listrecords does — they don't replace the SQL
views. The view still defines which columns appear and in what order.

## Alternative: Semantic suffixes (vs. presentational)

The plan above uses **presentational** suffixes (`_bold`, `_prefix:@`, `_unit:%`)
that describe how something looks. An alternative is **semantic** suffixes
that describe what the data IS, leaving formatting to the code.

### Why semantic is better

- **Consistency**: A `_location` suffix always formats as a location (e.g. `@Name`),
  regardless of which view uses it. With presentational suffixes, each view author
  must remember to write `_prefix:@` on every location column.
- **Centralized formatting**: Change how locations display everywhere by editing
  one formatter function, not N view definitions.
- **Self-documenting views**: `LocName_location` tells you "this is a location name"
  — the intent is clear. `LocName_prefix:@` tells you "this has an @ in front."
- **Less boilerplate in views**: One semantic suffix replaces several
  presentational ones (e.g. `_location` = `_prefix:@_bold` internally).

### Semantic suffix taxonomy

| Semantic suffix | What it represents | Internal formatting |
|----------------|-------------------|-------------------|
| `_location` | Location name | `@` prefix, bold |
| `_person` | Person name | `:` suffix |
| `_percent` | Alcohol percentage | `util::unit(v, "%")`, right-align |
| `_price` | Price | `util::unit(v, ".-")` |
| `_volume` | Volume | `util::unit(v, "cl")` |
| `_drinks` | Standard drinks | `util::unit(v, "d")` |
| `_brewstyle` | Brew type/subtype | `styles::brewstyledisplay()` |
| `_ratings` | Avg ratings (cnt/avg/com) | `comments::avgratings()` |
| `_rating` | Single rating | `(v)` parenthesized |
| `_date` | Date/time stamp | Date link with weekday |
| `_comment` | Comment text | Italic style |
| `_text` | Long-form text | Auto-width, no truncation |
| `_generic` | IsGeneric flag | Show "Gen" if true |
| `_checkbox` | Checkbox input | `<input type=checkbox>` |
| `_photo` | Single photo thumbnail | `photos::imagetag()` |
| `_photos` | Pipe-separated photo list | Multiple `photos::imagetag()` |
| `_weblink` | External URL | `util::extlink()` badge |
| `_similarity` | Name similarity | `util::namesimilarity()` |
| `_geodist` | Geo distance | `geo::geodist()` |
| `_id` | Record ID | `[v]` bracketed |
| `_idclr` | ID + clear-filters button | `[v]` + Clr span |
| `_recordname` | Primary record name | Bold link to current op (handles `Name` field) |

### Semantic + presentational can coexist

A field could have both:
- `BeerName_recordname_200px` → "this is the record name, width 200px"
- `Alc_percent_num` → "this is a percentage, right-aligned"
- `Note_comment_bold` → "this is a comment, but make it bold"

The rendering pipeline would be:

```
parse suffixes (both semantic and presentational)
  ↓
apply case transforms
  ↓
apply semantic formatter (lookup in %semantic_formatters)
  ↓
apply presentational wrappers (bold/italics/small/mono)
  ↓
apply structural (edit/link/extlink)
  ↓
apply sort/alignment data attributes
```

Semantic formatters are a dispatch table, replacing the hardcoded `elsif`:

```perl
my %semantic_formatters = (
    location   => sub { my ($v, $c, $rec, $i) = @_;
        return $v ? "\@$v" : ""; },
    person     => sub { my ($v, $c, $rec, $i) = @_;
        return $v ? "$v:" : ""; },
    percent    => sub { my ($v, $c, $rec, $i) = @_;
        return $v ? util::unit($v, "%") : ""; },
    brewstyle  => sub { my ($v, $c, $rec, $i) = @_;
        return styles::brewstyledisplay(...); },
    ratings    => sub { my ($v, $c, $rec, $i) = @_;
        my ($cnt, $avg, $com) = split(";", $v);
        return comments::avgratings($c, $cnt, $avg, $com); },
    recordname => sub { my ($v, $c, $rec, $i) = @_;
        return "<a href='$c->{url}?o=$c->{op}&e=$rec[0]'>" .
               "<span><b>$v</b></span></a>"; },
    ...
);
```

### Implementation notes

- Semantic suffixes take precedence over presentational ones for the same
  aspect (e.g. `_location` wins over `_prefix:@` if both are present).
- The `%semantic_formatters` dispatch replaces Phase 2's function wrappers.
- Old field-name checks remain as fallback until all views are migrated.
- Presentational suffixes remain for rare cases where the author wants to
  deviate from the semantic default (e.g. `Note_comment_bold`).

### Key difference from the presentational approach

| Aspect | Presentational | Semantic |
|--------|---------------|----------|
| View says | `LocName_prefix:@` | `LocName_location` |
| Code knows | prepend "@" | lookup `_location` formatter |
| Change formatting | update every view | update one formatter |
| Self-documenting | shows *how* it displays | shows *what* it is |
| Boilerplate in views | more (need all suffixes) | less (one per field) |

### Recommendation

Start with the **semantic approach** as the primary design, but keep
presentational suffixes as escape hatches. Data fields that are purely
generic (like a Notes field that should be italic) benefit from
presentational suffixes; everything else benefits from semantics.

## Alternative 2: `_as:TYPENAME` — override the effective field name

A minimal-effort compromise: keep the existing field-name-based formatting
checks unchanged, but add a suffix that tells the parser **"pretend this
field has a different name"** for the purpose of those checks.

### How it works

Parse `_as:FIELDNAME` like any other suffix, storing it in
`suffix_info[$i]{as_name}`. After stripping all suffixes, the remaining
base field name is used for display/headers. But for the formatting if/elsif
chain, use the `_as:` value instead:

```perl
my $effective_fn = $suffix_info[$i]{as_name} // $fn;

# Then the existing checks work unchanged:
if ( $effective_fn eq "Name" )       { ... }   # matches via _as:Name
elsif ( $effective_fn eq "LocName" ) { ... }   # matches via _as:LocName
elsif ( $effective_fn eq "Alc" )     { ... }   # matches via _as:Alc
```

### Example

In `photos_list`, there's a CASE expression for the Glass column:

```sql
-- Current: Glass_A (field name IS the filter header, ugly for CASE)
case when p.Glass is not null then ... end AS Glass_A

-- With _as:: use a readable column header, keep Name-style formatting
case when p.Glass is not null then ... end AS MyHeader_as:Glass_A
                      ↑ column header reads "MyHeader"
```

Or to get `LocName` formatting on a custom field:

```sql
SELECT l.Name AS Venue_as:LocName  ...  → header "Venue", formats as @Venue
```

### Pros

- **Minimum code change**: one suffix pattern, one variable swap before the
  existing `elsif` chain. No new formatters, no dispatch table.
- **Backward compatible**: all existing views work unchanged — `_as:` is
  purely additive.
- **Column headers are decoupled from formatting**: you can name the column
  whatever makes sense for the UI while reusing existing formatting logic.
- **Works with anything**: `_as:Name_bold_200px` → header "Name", base
  formatting for Name, plus bold and width overrides.

### Cons

- **Still fundamentally tied to hardcoded field name checks** — no
  abstraction. Adding a new data type means adding a new `elsif` branch.
- **No consistency gain**: if three views all display location names but
  use different base names, they still need `_as:LocName` on each one.
  There's no "define once, use everywhere" benefit.
- **Doesn't reduce the code in listrecords.pm** — the `elsif` chain stays
  as-is. It only makes existing checks available under new names.
- **The formatting logic stays opaque** — a future developer still needs to
  read the listrecords code to understand what `_as:Stats` does.

## Summary of approaches

| Aspect | Presentational (`_bold`, `_prefix:@`) | Semantic (`_location`, `_percent`) | Override (`_as:LocName`) |
|--------|--------------------------------------|-----------------------------------|-------------------------|
| Code change in listrecords | Large (new parser + formatters) | Large (new parser + dispatch table) | Tiny (one suffix + variable swap) |
| Formatting centralized? | No (every view spells it out) | Yes (one formatter per type) | No (still the old elsif chain) |
| Column header vs formatting | Tied to base name | Tied to base name | Decoupled |
| Existing views need changes? | Yes (to add suffixes) | Yes (to rename to semantic) | No (optional, purely additive) |
| New data type needs | New suffix + code | New formatter entry | New elsif branch |
| Risk | Medium | Medium | Very low |

The three approaches are **not mutually exclusive** — `_as:` could be
implemented first (it's tiny), then semantic formatters could be layered
on top later, with `_as:` providing the bridge for views that haven't been
migrated yet.

## Future extensions (not in this plan)

- **mainlist.pm suffix system**: Line-based rendering with grouping,
  subtotals, forms. Would need a new rendering mode in listrecords or a
  separate suffix-aware renderer. Far future.
- **`_break` / `_hide` replacement of TR/x prefixes**: Stretch goal
  once all views are updated.
- **`_namesim` / `_geodist` context-dependent**: Needs careful design
  for cross-field references.
- **`_cont` with dynamic separators**: `_contsep:TEXT` where TEXT can
  include HTML like `_contsep:<br/>`.
- **`_img:WxH`** for inline images with sizing.
- **`_progress`** / **`_rating`** visual elements.
- **`_color`** color swatch from hex value.
- **`_link:OP` for non-ID fields**: Link arbitrary field values.
