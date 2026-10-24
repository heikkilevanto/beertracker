# Plan: Refactor listrecords.pm

**Status (2026-10-24):** Step 0a done on master (`b438d27`). Step 0b done
(`78e2ac1`). Step 0c / implementation step 1 done on branch
`769-listrecords-refactor` (committed together with this plan update).
Step 2 (suffix table) done. Step 3 (helpers) done — note: the body
keeps `$photo_skipped` set for the whole row (verified in rendered
output), so `_maybe_photo_colspan` deliberately does not reset the flag;
the header photo logic is a rowspan countdown, not a boolean, and stays
inline. Step 4 done: `@FIELD_DEFS` + `field_def()` carry styles/labels/
flags (format code-refs deliberately deferred to step 6 to avoid ~300
lines of dormant duplication); dead handlers dropped (header: Sub,
Photos, isGeneric, ^None; body: Sub, Photos, IsGeneric,
Website|UntappdLink|SearchLink|DetailsLink, no-op LocName, no-op
Comment). Step 5 done: `_render_header()` extracted with the `@hdr_def`
memo and rule-based dispatch; `initial_filter` now keyed on the raw name
on both sides (Approach step 7); `listrecords_structure` HTTP test added.
Step 6 done: `_render_body_row()` extracted with the `$ctx` format
contract (skip/data_attrs/word_split); format code-refs live in the rules
(exact names only — family matches stay identity so CommentRating/LocName/
GlassLocName keep their old no-handler behavior; exact Rate and PersonName
rules sit before their families). Corrected the step-4 `word_split` flags
to match the old handlers exactly: IdClr/Alc/d/Sim/Geo keep word_split=1
(never set it; plain values get word-spans), only Name/Id/Type/CountryRegion/
PersonName/Prod/BrewName/Chk/Photo/Day/Locations set 0. Pr|Vol split into
exact rules (the anchored family was only those two names). Note: Day is
now a body-only rule, so it is no longer a field_def fall-through.
Next: step 7 (soak with the compare still in place). Working agreement:
each numbered step is its own commit, but only when I say so after
reviewing and testing.

## Problem
`listrecords.pm` is the largest module. The `listrecords` function is ~880 lines,
with most of that in two massive loops: header generation (lines 283–448) and
body/field value formatting (lines 478–862). Both use long if/elsif chains keyed
on field names, but the header styling and body formatting for each field are
~200 lines apart. The suffix parsing (lines 105–164) is also a long chain.
The cont/contline state tracking and photo colspan logic are duplicated between
the header and body loops.

## Goal
Make the module easier to follow and extend. Co-locate header styling, header
input behavior, and value formatting for each field type. Eliminate duplicated
patterns. Make adding a new field type a single-entry change.

Line count is expected to stay roughly the same (the moved code is roughly the
size of the dispatch/glue that replaces it). The win is locality, not size.

## Caller audit (done — basis for the design below)
17 call sites in 6 modules (brews, locations, comments, persons, photos, stats),
plus `comments::comments_list_sql()` shared by 6 of them. Findings that shape
this plan:

- **Header matching is an ordered if/elsif chain with a mix of anchored and
  substring regexes; body matching is exact `$fn eq` on the alias-resolved
  name.** The substring families that actually occur:
  - `^X` prefix (hidden columns): `xUsername`, `xProducer`, `xTags`,
    `xGlass`, `xComment`, `xLocation`, `X_Gap`
  - `Id|Alc` substring: `Alc`, `BrewId`, `CommentId`, `GlassId`, `LocId`,
    `LocationId`, `PersonId`, `PlocId`, `ProdLocId`
  - `Rate|Rating` substring: `Rate`, `Ratings`, `CommentRating`
  - `LocName|PersonName` substring: `LocName`, `PersonName`, `GlassLocName`
    (raw `LocationName` does *not* match)
  - `Comment|Description` /i substring: `Comment`, `CommentPersons`,
    `CommentText`, `CommentType`, `Description`
- **Order dependence:** `CommentRating` must hit the Rate rule, not Comment
  (line 334 before 343); `CommentId` must hit the Id-family rule, not Comment
  (line 314 before 343).
- **Header styles the RAW column name, body formats the `as=` alias.**
  `LocationName_..._as=LocName` gets default header style but the body
  `LocName` handler; `Ratings_as=Stats` gets *Rate* header style but the body
  *Stats* handler. Header and body lookups must therefore use different keys
  for aliased columns.
- **Never used by any caller** (dead code): header rules `Sub`, `Photos`,
  `isGeneric`, `^None`; body handlers `Sub`, `Photos`, `IsGeneric`,
  `Website|UntappdLink|SearchLink|DetailsLink`, plus the no-op handlers
  `LocName` (line 571) and `Comment` (line 712).

Because of the substring families and the ordering constraints, a plain
exact-name hash (`%FIELD_DEFS`) cannot reproduce current rendering. An unknown
field that happens to contain "Id" or "Rating" would silently lose its style.
This plan uses an ordered rule list instead (see below).

## Step 0 — Setup before the refactor

**0a DONE (commit `b438d27` on master). Fix the corrupted default style**, line 308:
`"style='max-widthem measurements,:200px; min-width:0'"` →
`"style='max-width:200px; min-width:0'"`. The corruption was introduced by
commit `539f86d`. This is a real behavior change (restores max-width on
default columns) — isolate it in its own commit so the refactor itself stays
behavior-neutral. **Create the frozen reference (0c) only after this fix**,
so the style fix is outside the comparison.

**0b DONE (commit `78e2ac1`). Remove the `rand()` aggregate-footer id**, line 885
(`my $fid = "lr-agg-" . int(rand(999999));`). The id exists only so the inline
script emitted right after the footer div can `getElementById` it — nothing
else uses it: all of `static/listrecords.js` finds the footer via
`wrapper.querySelector('[data-lr-agg]')`, and no CSS selector references it.
Drop the `id` attribute and bind the element directly, keeping the
DOMContentLoaded timing and listener registration order exactly as they are:

```perl
$s .= "<div data-lr-agg style='display:flex;...'>\n";
# ... aggregate spans ...
$s .= "</div>\n";
$s .= "<script>(function(){ var d = document.currentScript.previousElementSibling;\n"
    . "document.addEventListener('DOMContentLoaded', function(){ lr_update_footer(d); });\n"
    . "})();<\/script>\n";
```

Rejected alternatives: an id derived from the field/column name is not unique
across two aggregate tables on one page (both would be `lr-agg-<colindex>`;
nothing prevents a second aggregate list appearing — the comments sibling
lists already share `Rate_avg_cnt_A`); a fixed prefix + running counter is
unique per process, but the frozen reference and the new code would keep
*separate* counters while ordinary requests only advance the new one, so ids
would drift apart and every compare would report a false DIFF (or we would
keep normalizing, defeating the change). With no id, the rendered output is
fully deterministic — this was the module's only nondeterminism (grep: no
other `rand()`/`time()` in the output path) — and the compare becomes a plain
string `eq`. Behavior-visible change (HTML + inline script) → own commit,
before the reference is frozen.

**0c DONE (this commit = implementation step 1). Create the frozen reference
and the compare mode:**

- Copy `code/listrecords.pm` to `code/listrecordsorig.pm`, rename the package
  to `listrecordsorig`. This file is frozen from this point on — never edited
  again during the process. A separate file (rather than a renamed sub in the
  same module) keeps the new module free of 880 legacy lines and avoids
  duplicate sub names (`_word_spans`, `_colspan_last_td`, ...) between the
  two versions.
- Inside `listrecords()`, an opt-in branch on `util::param($c, "lrcompare")`
  that renders with `listrecordsorig::listrecords()` and with the (being
  refactored) body, compares, and appends an `lr-compare: OK` /
  `lr-compare: DIFF` marker, serving the new result (details: Test plan
  section C).
- A `$c->{cache_disable}` flag honored by `cache::get`/`cache::set`
  (2 lines in `code/cache.pm`), set for the duration of the compare —
  without it both renders hit the same cache key and the comparison silently
  compares a result with itself.

**Deferred, NOT part of this refactor:** the duplicate `data-col` attribute
that `d`/`Pr`/`Vol` add to their outer spans (data_attrs already starts with
`data-col='$i'`, lines 779/787/795 add it again; first-attr-wins in HTML so it
is harmless). Cleaning it up changes markup and would show up in every
comparison — do it later as its own commit if wanted.

## Approach: ordered field-definition rules

### 1. `@FIELD_DEFS` — ordered rule list (module scope)

Each rule is a hashref with `name` (exact string match) or `re` (regex),
first match wins. Rules carry header style, header input behavior, and value
formatting together:

```perl
# Order matters. Narrow exact rules before family regexes.
# Header lookup keys on the RAW column name; body lookup keys on the
# as= alias when present (see _render_header/_render_body_row).
my @FIELD_DEFS = (
  { re   => qr/^X/i,            style => "display:none", hidden => 1 },
  { name => "Id",               style => "max-width:40px; text-align:center",
    placeholder => "Id", word_split => 0, format => sub { ... } },
  { name => "IdClr",            style => "max-width:40px; text-align:center",
    placeholder => "Id", word_split => 0, format => sub { ... } },
  { name => "Alc",              style => "max-width:55px; text-align:center",
    unit => "%", word_split => 0, format => sub { ... } },
  { re   => qr/Id|Alc/,         style => "max-width:55px; text-align:center" },
  { name => "Stats",            style => "max-width:100px; text-align:center",
    format => sub { ... } },
  { name => "Last",             style => "max-width:100px", format => sub { ... } },
  { name => "LastProd",         style => "max-width:100px", format => sub { ... } },
  { name => "Ts",               style => "max-width:100px", format => sub { ... } },
  { name => "Type",             style => "max-width:200px; text-align:center",
    mobile_style => "max-width:100px; text-align:center",
    word_split => 0, format => sub { ... } },
  { re   => qr/^(Com|Count)$/,  style => "text-align:right; max-width:50px" },
  { name => "d",                style => "text-align:right; max-width:50px",
    word_split => 0, format => sub { ... } },  # exact rule: has its own handler
  { re   => qr/^(Pr|Vol)$/,     style => "text-align:right; max-width:35px" },
  { name => "Photo",            style => "width:96px; text-align:center; padding:1px",
    word_split => 0, format => sub { ... } },
  { re   => qr/Rate|Rating/,    # MUST stay before the Comment rule
    style => "text-align:center; font-weight:bold; max-width:50px",
    format => sub { ... } },
  { name => "Chk",              style => "text-align:center;max-width:50px",
    no_events => 1, word_split => 0, format => sub { ... } },
  { re   => qr/LocName|PersonName/,
    style => "font-weight: bold; max-width:200px",
    format => sub {
      my ($ctx) = @_;
      if ( $ctx->{fn} eq "PersonName" ) { ...handler... }
      return $ctx->{v};    # LocName (via as= alias) stays pass-through
    } },
  { re   => qr/Comment|Description/i,
    style => "max-width:200px; min-width:0; font-style: italic" },
  { name => "Sim",              style => "max-width:55px; min-width:0; text-align:right",
    word_split => 0, format => sub { ... } },
  { name => "Geo",              # label/style depend on $c->{mobile}
    style => "max-width:100px; min-width:0; text-align:right",
    mobile_style => "max-width:55px; min-width:0; text-align:right",
    label => sub { $_[0] ? "km" : "Dist (km)" },
    word_split => 0, format => sub { ... } },
  { name => "CountryRegion",    word_split => 0, format => sub { ... } },
  # ... remaining exact-name rules with format code-refs:
  # Name, Prod, BrewName, Day, Locations
);
# Fall-through (no match): default style, word_split => 1, identity format.
```

Notes:

- **Styles above are copied from the current code, not invented.** In
  particular: `Alc` is 55px centered (via the old `/Id|Alc/` rule — not the
  bold 50px style, which belongs to Rate); `Type` is 200px on desktop and
  100px on mobile (the earlier draft of this plan had these inverted).
- The `^X` rule and the family regexes reproduce current prefix/substring
  semantics exactly. Adding a new field that happens to contain "Id" or
  "Rating" keeps working, same as today.
- Ordering constraints, to be written as comments above the affected rules:
  - `^X` rule first (it wins over everything for hidden columns).
  - Exact `Id`/`IdClr`/`Alc` rules before the `Id|Alc` family rule.
  - `Rate|Rating` before `Comment|Description` (CommentRating).
  - `Id|Alc` family before `Comment|Description` (CommentId).
  - `LocName|PersonName` before `Comment|Description` (no live collision, but
    keep the current chain's order to stay mechanical).
- Header-input quirks become flags on the rules: `placeholder` override (only
  IdClr needs one — its placeholder is "Id"; other fields already default to
  their own name), `no_events` (Chk: no oninput/ondblclick on the header
  input), `label` (Geo's km/"Dist (km)" rename; the old `Sim` and `^None`
  renames were no-ops or dead).
- `$f =~ s/^-//` (strip a leading dash from the header label, line 368) stays
  in the header code — it applies to all fields, not per-rule.
- Lookup sub, module scope, pure (testable without $c or a dbh):

  ```perl
  sub field_def {
    my ($name, $mobile) = @_;
    foreach my $def (@FIELD_DEFS) {
      if ( defined $def->{name} ) {
        return $def if $name eq $def->{name};
      } elsif ( $name =~ $def->{re} ) {
        return $def;
      }
    }
    return $FIELD_DEFAULT;   # shared fall-through def
  } # field_def
  ```

- **Two memoized lookups per call** (computed once before the loops, not per
  cell): `@hdr_def[$i] = field_def($fields[$i], $mobile)` keyed on the raw
  post-suffix-strip name, and `@body_def[$i] = field_def($as_name || $fields[$i],
  $mobile)` keyed on the alias-resolved name. This encodes the header-raw /
  body-alias quirk in one visible place instead of scattering it.

### 2. Suffix parsing as a table-driven loop (corrected)

Replace the do/while chain (lines 105–164) with a `@SUFFIX_DEFS` table and a
pure extraction:

```perl
my @SUFFIX_DEFS = (
  [qr/_R(\d+)$/,           'rowspan'],
  [qr/_C(\d+)$/,           'colspan'],
  [qr/_as=([^_]+)$/,       'as_name'],
  [qr/_(\d+px)$/,          'width_px'],
  [qr/_A$/,                'auto_width'],
  [qr/_filter$/,           'filter'],
  [qr/_nofilter$/,         'nofilter'],
  [qr/_noheader$/,         'noheader'],
  [qr/_link=([A-Z][a-zA-Z]+)$/, 'link'],
  [qr/_contline$/,         'contline'],
  [qr/_cont$/,             'cont'],
  [qr/_sum$/,              'aggregate', 'sum'],
  [qr/_avg$/,              'aggregate', 'avg'],
  [qr/_cnt$/,              'aggregate', 'cnt'],
);
```

**Side effects must be preserved** (the earlier draft of this plan dropped
them — they are not optional):

- `_R`/`_C` set `$extra_attr[$i] = "rowspan='N'"` / `"colspan='N'"` in
  addition to `$suf->{rowspan}/{colspan}`. The `<td>`s in both header and
  body use `$extra_attr[$i]`; without this, every rowspan/colspan attribute
  disappears.
- `_(\d+px)` also fills `%px_override`, `_A` also fills `%auto_override`.

Extract as a pure function for testability:

```perl
sub parse_field_suffixes {
  my ($raw_fields) = @_;
  # returns {
  #   base       => \@base_names,   # fields with suffixes stripped
  #   suffix     => \@suffix_info,  # per-column hashref (rowspan, cont, ...)
  #   extra_attr => \@extra_attr,   # rowspan/colspan attrs for <td>
  #   px         => \%px_override,
  #   auto       => \%auto_override,
  #   warnings   => \@warnings,     # unrecognized-suffix messages
  # }
} # parse_field_suffixes
```

No `$c` inside — the caller writes `@{$res->{warnings}}` to `$c->{log}`
(current behavior: warn, do not strip, leave the field name as-is).

Behavior to preserve and pin down with tests:

- Multiple suffixes stack and are stripped one per pass, repeatedly
  (`Name_A_C2_cont`, `Photo_R3_noheader_nofilter`, ...).
- `aggregate` stacking: `Rate_avg_cnt_A` strips A, then cnt, then avg —
  final value is `avg` (the last one stripped wins; document this).
- `_as=` values cannot contain underscores (`[^_]+`), `_link=` entities must
  start uppercase — both preserved as-is.
- No `_cont` vs `_contline` conflict exists (`_cont$` cannot match a
  `..._contline` string); keep `_contline` before `_cont` anyway to stay
  a mechanical translation of the current chain.

### 3. Extract `_render_header()` and `_render_body_row()`

Move the `<thead>` loop (283–448) and the per-row field loop (478–862) into
two subs. **Do not use long positional parameter lists** (the earlier draft
had 9 and 10 positional args). Pass a state hashref:

```perl
sub _render_header {
  my ($c, $st) = @_;   # $st: fields, suffix, extra_attr, hdr_def, px, auto,
                       #      initial_filter, maxrecords, styles_out, ...
  # returns the <thead> HTML; fills @{$st->{styles}} for the body
}
sub _render_body_row {
  my ($c, $st, $rec) = @_;   # $st adds: body_def, url, extraparams, cutoff,
                             #           cont/photo state per row
  # returns one <tr> HTML
}
```

**The body format handlers are not a pure ($fn, $v) -> $v mapping.** Any
design must give format code-refs access to, and the ability to mutate:

- `$data_attrs` (append sort keys, lat/lon, filter/onclick attrs),
- the `word_split` policy flag,
- a "skip this cell" signal (empty Photo closes the td, does the colspan
  fixup, and `next`s),
- sibling columns (`Sim` reads the `Name` column, `Photo` falls back to the
  `Id`/`IdClr` column),
- `$cutoff` (date logic for Ts/Last/LastProd).

Concrete contract (keep it explicit, no magic):

```perl
format => sub {
  my ($ctx) = @_;          # hashref: v, fn (alias-resolved name), i, rec,
                           #          fields, c, url, extraparams, cutoff,
                           #          id, data_attrs (ref), word_split (ref)
  ...                      # mutate ${$ctx->{data_attrs}}, ${$ctx->{word_split}}
  return $ctx->{v};        # new value, or return early with skip => 1:
}                          #   $ctx->{skip} = 1; return $ctx->{v};
```

`fn` in the context lets one family rule serve several body handlers (the
`LocName|PersonName` rule branches on it, just like the old chain did).

The `_link=` suffix case is keyed on the suffix, not the name, and the current
body chain checks it *before* the `Id` handler (line 517). Keep it that way:
the dispatch checks `$suffix_info[$i]{link}` before consulting `@FIELD_DEFS`,
and a field like `Id_A_link=Brew` gets the link markup, not the Id handler.

Dispatch wraps each call: build `$ctx`, call rule's `format` (identity if
none), apply skip (close td + colspan fixup + next), then the existing
suffix-driven post-processing (`_filter`, `_nofilter`, default word_split,
cell wrapper span, cont/contline td closing).

The cont/contline/photo state handling stays inside the header/body subs
(or in the small helpers of step 4) — it is inherently per-loop state, not
per-field config.

### 4. Extract helpers for duplicated logic

**cont/contline state** — appears ~8 times across header and body:

```perl
sub _close_cont { my ($s_ref, $active_ref) = @_;
  if ($$active_ref) { $$s_ref .= "</td>\n"; $$active_ref = 0; }
} # _close_cont
```

**photo colspan** — appears ~4 times (body only; the header uses a rowspan
countdown, not a boolean, and stays inline):

```perl
# Does NOT reset the flag: the body keeps it set for the whole row, so
# every segment-ending td after a skipped photo gets the fixup.
sub _maybe_photo_colspan { my ($s_ref, $skipped_ref) = @_;
  if ($$skipped_ref) { _colspan_last_td($s_ref); }
} # _maybe_photo_colspan
```

### 5. Unit-format fields: keep as small explicit code-refs

The earlier draft claimed Alc/d/Pr/Vol share one pattern and can collapse
into a generic `unit`/`suffix` config. They do **not** — current markup
differs and the compare gate would catch any over-generalization:

- `Alc`: adds only `data-sort-key` to `$data_attrs`; puts
  `data-col/data-filter/onclick` on an *inner* span around `util::unit($v,"%")`.
- `Pr`, `Vol`: add `data-sort-key` **plus a duplicate `data-col`** and
  `data-filter/onclick` to the *outer* data_attrs; value is bare
  `util::unit($v, ".-")` / `util::unit($v, "c")`.
- `d`: same outer pattern, but `sprintf('%.1f') . "<span…>d</span> "` (suffix,
  not util::unit).

Decision: give each its own small `format` code-ref (~4 lines each) that
reproduces the current markup exactly, including the duplicate `data-col`
(step 0 defers removing it). The shared bits (empty → "", data-sort-key) can
be a tiny local helper if it stays obvious. Do not build a unit-format
framework for four fields.

### 6. Remove dead handlers (explicit decision, from the audit)

Drop from the header rules: `Sub`, `Photos`, `isGeneric`, `^None`.
Drop from the body chain: `Sub`, `Photos`, `IsGeneric`,
`Website|UntappdLink|SearchLink|DetailsLink`, `LocName` (no-op),
`Comment` (no-op `$v = "$v"`).

Rationale: unreachable from all 17 current call sites; re-adding is exactly
the one-entry change this refactor is meant to enable. Note the removal in
the commit message.

### 7. Fix the initial_filter naming inconsistency (tiny, do while here)

The header builds the initial value from `initial_filter->{$f}` using the
*renamed* field (line 405), while the footer script looks up
`initial_filter->{$fields[$i]}` using the raw name (line 929). Only
`CommentType` uses initial_filter today (renamed by nothing) so nothing is
visibly broken, but the rename path is a trap. Use the raw name on both
sides.

## Files changed

- `code/listrecords.pm` — all production changes are here
- `code/listrecordsorig.pm` — frozen pre-refactor reference, **deleted in the
  final step**
- `code/cache.pm` — 2-line `cache_disable` flag, **deleted in the final step**
- `tools/test-unit` — new `listrecords` test set (see Test plan)
- `tools/test-http` — `listrecords_structure` + `listrecords_compare` tests
  (see Test plan)
- Touch `code/VERSION.pm` after each edit, in a separate call

## Test plan

### A. Unit tests — new `listrecords` set in `tools/test-unit`

`listrecords.pm` loads without a dbh (only POSIX etc. at compile time), so
`require listrecords;` fits the existing harness. The three new subs
(`parse_field_suffixes`, `field_def`, plus the helpers) are pure by
construction (steps 1, 2, 4) — that is why the plan extracts them the way it
does. Register in the test table as `sets => [qw(quick listrecords)]` (pure
and fast, so they belong in the default `quick` run):

```perl
{ name => "lr_suffixes",   sets => [qw(quick listrecords)], test => \&test_lr_suffixes },
{ name => "lr_fielddef",   sets => [qw(quick listrecords)], test => \&test_lr_fielddef },
{ name => "lr_helpers",    sets => [qw(quick listrecords)], test => \&test_lr_helpers },
```

**`test_lr_suffixes`** (against `parse_field_suffixes`):

- Simple: `["Id_A_link=Brew"]` → base `Id`, `{ auto_width, link=Brew }`,
  no extra_attr.
- Stacked with attr side effects: `["Photo_R3_noheader_nofilter"]` →
  base `Photo`, rowspan 3, `extra_attr[0] eq "rowspan='3'"`, noheader+nofilter.
- Colspan: `["Name_A_C2_cont"]` → base `Name`, colspan 2,
  `extra_attr[0] eq "colspan='2'"`, cont + auto_width.
- Width override: `["LastSeen_90px"]` → base `LastSeen`, `px->{0} eq "90px"`.
- Aggregate stacking: `["Rate_avg_cnt_A"]` → base `Rate`, auto_width,
  `aggregate eq "avg"` (documenting the last-stripped-wins behavior).
- as= alias: `["LocationName_A_filter_as=LocName"]` → base `LocationName`,
  as_name `LocName`.
- contline vs cont: `["Last_A_contline"]` → contline (not cont);
  `["Last_cont"]` → cont.
- Unrecognized suffix: `["Foo_bar"]` → base stays `Foo_bar`, one warning
  naming `Foo_bar` and the original field.
- Mixed batch: multiple fields in one call keep per-column alignment of all
  returned arrays.
- No suffix at all: `["Name", "Alc"]` → bases unchanged, empty warnings.

**`test_lr_fielddef`** (against `field_def($name, $mobile)`):

- Exact rules: `Id`/`IdClr` → 40px center + placeholder "Id";
  `Stats` → 100px center; `Photo` → 96px.
- Family rules: `BrewId`/`CommentId`/`LocId` → 55px center (Id family);
  `CommentRating` → bold 50px (Rate rule wins over Comment rule —
  the ordering constraint, asserted explicitly);
  `GlassLocName` → bold 200px; `CommentText`/`Description` → italic.
- Non-matches that must fall through: `LocationName` (does NOT match the
  LocName family), `Closed`, `Day`, `Caption`.
- Prefix rule: `xUsername`, `X_Gap` → `display:none`.
- Mobile variants: `field_def("Type", 1)` uses `mobile_style` (100px);
  `field_def("Type", 0)` uses desktop style (200px); `Geo` label is "km"
  when mobile, "Dist (km)" when not.
- Dropped handlers now fall through: `IsGeneric`, `Sub`, `Photos`,
  `Website` → the default def (locks in the step-6 decision).

**`test_lr_helpers`**:

- `linebreak(undef, "TR1")` returns `"</tr>\n<tr>\n"`; `linebreak(undef, "Name")`
  returns `""` ($c is unused — pass undef or a dummy).
- `_word_spans`: `"foo bar"` → two `fw` spans with escaped content;
  `"a&b<b>"` escaped; `""` → `""`; single word no space.
- `_colspan_last_td`: appends `colspan='2'` to the last td; skips a trailing
  td that has `display:none`; returns 0 when the last td already has a
  colspan; returns 0 when there is no td.
- `_close_cont`: closes and resets when active; no-op when inactive.

### B. HTTP tests — additions to `tools/test-http`

The existing assertions only check 200/DOCTYPE/menu/text-marker/no-error, so
they would not notice a missing thead or a dropped colspan. Add a shape
helper + shape test, and the byte-identical compare test (heavy list pages
stay out of `quick`, matching the existing convention for list pages):

```perl
sub assert_listrecords_shape {
  my ($body, $what) = @_;
  assert(scalar($body =~ /<table class='listrecords'/), "$what has the listrecords table");
  assert(scalar($body =~ /<thead>/) && scalar($body =~ m{</thead>}), "$what has a complete thead");
  assert(scalar($body =~ /lr-filter-row/), "$what has the filter row");
  assert(scalar($body =~ /<tbody/), "$what has at least one tbody");
  assert(scalar($body =~ m{</table>}), "$what table is closed");
} # assert_listrecords_shape

sub test_listrecords_structure {
  foreach my $op (qw(Brew Location Comment Photos Person short)) {
    my ($status, $headers, $body) = req("GET", "$BASE_URL?o=$op");
    assert_page_ok($status, $body, "List $op", "listrecords");  # <table class=...>
    assert_listrecords_shape($body, "List $op");
  }
}
```

Register as `{ name => "listrecords_structure", sets => [qw(listrecords http)],
test => \&test_listrecords_structure }` (deliberately not `quick`, like the
other list-page tests). `o=short` is the Daily Stats page (dailystats) — the
only caller exercising `Day`, `d`, `Pr`, `Locations`, and the gap column.

This catches structural breakage (missing thead, unclosed table, lost tbody
splitting) but not style regressions — that is what the compare test is for.

**The main test — old vs new rendered in one request:**

```perl
sub test_listrecords_compare {
  return unless $on_dev;   # reference + compare branch exist only during #769
  foreach my $op (qw(Brew Location Comment Photos Person short)) {
    my ($status, $headers, $body) = req("GET", "$BASE_URL?o=$op&lrcompare=1");
    assert_page_ok($status, $body, "Compare $op", "listrecords");  # <table class=...>
    assert(scalar($body =~ /lr-compare: OK/),    "$op: old and new output identical");
    assert(scalar($body !~ /lr-compare: DIFF/),  "$op: no DIFF marker");
  }
  # Mobile variant: same assertion, iPhone UA (index.fcgi sniffs the UA for
  # mobile styles). req() does not take headers, so set one on $ua and restore:
  #   my $old_ua = $ua->default_header("User-Agent" => $IPHONE_UA);
  #   ...one GET with lrcompare=1, assert OK...
  #   $ua->default_header("User-Agent" => $old_ua);
} # test_listrecords_compare
```

Register as `{ name => "listrecords_compare", sets => [qw(listrecords http)],
test => \&test_listrecords_compare }`, also not `quick`. This is the
byte-identical gate: no files, no normalization rules, no data-stability
constraints (see section C).

### C. Byte-identical verification — frozen reference + in-request compare

`tools/testall` cannot catch a wrong column width or a lost rowspan, and a
snapshot-diff harness (render → save → edit → render again → diff) compares
two renders from two different moments: the data can drift in between (page
order shifts, re-copied prod data, cross-day relative dates).

Instead, the old implementation stays in the code as a frozen reference and
both versions render **within the same request, from the same rows**:

- **Reference:** `code/listrecordsorig.pm` (created in step 0c), package
  `listrecordsorig` — a verbatim copy of the pre-refactor module, frozen.
- **Trigger:** GET a list page with `lrcompare=1` (opt-in via
  `util::param($c, "lrcompare")`; inert without the param, so normal browsing
  and production are unaffected).

```perl
if ( util::param($c, "lrcompare") ) {
  my $old = listrecordsorig::listrecords($c, $sql_param, $opt);
  my $new = _render($c, $sql_param, $opt);   # the refactored body
  if ( $old eq $new ) {
    $new .= "<!-- lr-compare: OK -->\n";
  } else {
    # log first-diff offset (binary search, see below) to $c->{log},
    # write both strings to $c->{datadir}lrcompare-<user>-{old,new}.html
    # for a full external diff, append:
    $new .= "<!-- lr-compare: DIFF -->\n";
  }
  return $new;   # always serve the new implementation
}
```

Key details:

- **The first-diff offset is found by binary search, not a byte scan.**
  A byte-by-byte `substr` loop in pure Perl takes minutes on the ~1MB Brew
  page (two string allocations per byte) — Apache kills the worker first, and
  the DIFF log line (which comes after the scan) never appears, which looks
  like a silent hang. Binary search on the common prefix is O(log n) memcmp
  probes and finishes in well under a second. (Found the hard way: forcing
  the DIFF path during harness verification wedged two FCGI workers at 100%
  CPU for minutes each.)
- **DIFF dumps go to `$c->{datadir}`, not `/tmp`.** Apache runs with
  `PrivateTmp=yes`: files written to `/tmp` land in a systemd-private
  namespace owned by root that the user cannot read. The datadir
  (`./beerdata/`) is already per-user, writable, and readable.
- **Cache bypass is mandatory, or the comparison is meaningless.** Both
  implementations compute the *same* cache key, so the second render would
  get the first one's cached HTML and report a false OK. Set
  `$c->{cache_disable}` for the duration of the compare branch; honor it in
  `cache::get` (return undef) and `cache::set` (skip) — 2 lines total.
- **No normalization: the compare is a plain string `eq`.** The module's only
  nondeterminism — the `int(rand(999999))` aggregate footer id — was removed
  in step 0b (the footer div no longer carries an id; the inline script binds
  the element directly). The `-7 days` cutoff is epoch arithmetic, not
  wall-clock (grep-verified: no other `time()`/`rand()` in the module), so the
  output is fully deterministic within one request.
- **Two queries per compare request.** A POST from another tab landing
  between the old and new query could produce a spurious diff; irrelevant for
  a single-user app. If a mystery diff appears with no code cause, check for
  concurrent writes before debugging the render.
- **The test (`listrecords_compare`, section B) is data-independent:** it can
  run on any day, after any `copyproddata`, with no baseline files, no
  normalization rules to maintain, and no `diff -u` bookkeeping. One page load
  is the whole check.
- **Endgame:** the reference and the compare branch are a one-shot refactoring
  tool. Once the refactor is done and verified (steps 7–8), delete
  `listrecordsorig.pm`, the compare branch, and the `cache_disable` lines, and
  run `testall` again. Git history keeps the reference if a future refactor
  wants to resurrect the same pattern. Keeping it around would only mean
  guaranteed compare failures the next time output intentionally changes —
  and ~970 lines of frozen legacy sitting in the tree.

While the compare mode exists, it doubles as a regression check for mobile:
run it with a phone User-Agent too (same assertion, mobile styles covered).

## Implementation order

0. DONE: commit `b438d27` (master) — fix the corrupted default style
   (Step 0a). DONE: commit `78e2ac1` — remove the `rand()`
   aggregate-footer id (Step 0b).
1. DONE (this commit). **Compare setup** — split `listrecords()` into a thin dispatcher plus
   `_render()` holding the body unchanged; create `listrecordsorig.pm` from
   the fixed code (step 0c); add the `lrcompare` branch + `cache_disable`
   (step 0c); add the `listrecords_compare` HTTP test. Gate: test reports OK
   for all six pages (old-vs-old, trivially identical — it proves the harness
   itself works, including the cache bypass). Verified, plus a forced-DIFF
   run that detected a deliberate one-line change at the right offset in
   0.36s. The test also covers the detail-page sub-lists (brew
   comments/prices/glasses/dedup, location visits/producer brews/dedup,
   comment sibling lists) and a mobile-UA pass — an extension beyond the
   original plan, agreed with the maintainer.
2. DONE. **Suffix table** — replace lines 105–164 with `parse_field_suffixes` +
   `@SUFFIX_DEFS`. Unit tests: `lr_suffixes`. Gate: `perl -c`,
   `listrecords_compare` all OK, `tools/testall`.
3. DONE. **Helpers** — `_close_cont`, `_maybe_photo_colspan` (pure refactor;
   the photo helper does not reset the flag — see Status note). Unit tests:
   `lr_helpers`. Gate: compare OK.
4. DONE. **Define `@FIELD_DEFS` + `field_def`** — styles, labels, flags moved
   into rules; the simple format code-refs (Name, Id, IdClr, Alc, Pr, Vol, d,
   Chk, Sim, Geo, Type, Ts, Last, LastProd, Stats, CountryRegion, PersonName,
   Prod, BrewName, Photo, Day, Locations) move in step 6 with the body
   dispatch, to avoid ~300 lines of dormant duplication. Dead handlers
   dropped (Approach step 6). Unit tests: `lr_fielddef`. Gate: compare OK.
5. DONE. **Extract `_render_header()`** — state hashref, `@hdr_def` memo,
   dispatch via rules, initial_filter raw-name fix (Approach step 7). Gate:
   compare OK, `listrecords_structure` HTTP test (added here, kept in step 8).
6. DONE. **Extract `_render_body_row()`** — state hashref, `@body_def` memo, the
   `$ctx` format contract including skip/data_attrs/word_split, and the
   format code-refs into the rules (see step 4). Gate: compare OK,
   `tools/testall`.
7. **Soak with the compare still in place** — manual spot checks (list
   below), `tools/testall all`, optionally re-run compare after a
   `copyproddata` (the compare is data-independent — copy freely).
8. **Delete the scaffolding** — remove `listrecordsorig.pm`, the `lrcompare`
   branch in `listrecords()`, the `cache_disable` lines in `cache.pm`, and
   the `listrecords_compare` test (table entry + sub) in `tools/test-http`
   (final state should not carry dead tooling; agreed: drop `cache_disable`
   too, not keep it). Keep `listrecords_structure`. Gate: `tools/testall all` +
   one manual browse of the six pages. Commit.

Commit after each numbered step. Steps 1–7 are behavior-neutral for normal
(non-`lrcompare`) requests and independently revertable; step 0 is the only
intended rendering change; step 8 only removes scaffolding.

## Verification

- `perl -c code/listrecords.pm` after every edit.
- `./tools/testall` — unit (incl. new `lr_*` tests) + HTTP (incl.
  `listrecords_structure` and `listrecords_compare`).
- `listrecords_compare` all OK after every step (desktop and mobile UA) — this
  is the byte-identical gate. Touch `code/VERSION.pm` first (separate call)
  after edits so the FCGI process reloads and stale in-process HTML cannot
  mask a regression. (`cache_disable` covers the compare render itself; the
  VERSION.pm touch covers the normal requests the other tests make.)
- Manual spot checks (the compare covers byte-identical rendering; these cover
  interaction and mobile):
  - Browse Brews, Locations, Comments, Photos, Persons, Daily Stats.
  - Sorting (dbl-click a header input), multi-word and `-`/`=`/`>=` filters,
    Clr/Hdr buttons, page size + Prev/Next.
  - Photo columns with empty photos still get colspan (Photos page, and a
    brew/location without a photo).
  - contline fields still span correctly (Comments: Last + BrewName;
    Brews: Location + Last).
  - Mobile layout: fetch with a phone UA (or devtools) — Type column 100px,
    Geo label "km", default columns 90px.
  - Aggregate footer (Comments: Rate_avg_cnt) shows and updates after
    filtering.
  - Initial filters: Comments opened for a specific brew/location/person
    pre-filters CommentType.

## Design decisions

- **Ordered rule list, not an exact-name hash**: the live field set relies on
  substring/prefix matching in five families plus cross-rule ordering
  (CommentRating, CommentId). An exact-name hash would either change today's
  rendering or enumerate the families into brittle key lists. The ordered list
  is a mechanical translation of the current elsif chain, so "no behavior
  change" is checkable, and a future `BrewRating` column keeps its style
  without touching the table.
- **Header/body lookup keyed differently** (raw name vs as= alias), memoized
  into `@hdr_def`/`@body_def`: reproduces the current quirk in one explicit
  place instead of relying on loop order.
- **Explicit `$ctx` contract for format code-refs**: handlers mutate
  data_attrs/word_split and can signal skip; a pure string-returning sub
  cannot express the Photo/sort-key cases. No closures over loop lexicals —
  the hashref keeps the dependency list visible and testable.
- **State hashref, not 9–10 positional params**, for the extracted render subs.
- **Unit fields stay as four small code-refs**, not a generic unit/suffix
  mini-framework: their markup genuinely differs (inner vs outer attrs,
  duplicate data-col), and byte-identical output is the verification strategy.
- **Dead handlers dropped, with the audit as evidence** and the removal
  called out in the commit message. Re-adding is one table entry — the point
  of the refactor.
- **Only step 0 changes behavior** (default-style corruption fix and footer-id
  removal, each its own commit). The duplicate `data-col` cleanup is
  explicitly deferred.
- **Verification = frozen reference compared in-request, not snapshot files.**
  Rendering old and new back-to-back in one request compares the same rows at
  the same moment: no same-day constraint, no "don't re-copy prod data", no
  baseline bookkeeping, and the reference is always current.
  Two traps are handled explicitly: both renders share a cache key (so the
  compare must set `cache_disable`, or it compares a result with itself and
  reports a false OK), and the rendered output must be deterministic (the
  aggregate footer id was `rand()`-generated — step 0b removes the id
  entirely rather than keeping a normalization rule in the compare).
- **The reference is scaffolding, deleted in the last step.** Kept around, it
  would guarantee failures on the next intentional output change and leave
  ~970 lines of frozen legacy in the tree; git history preserves it for a
  future refactor that wants the same pattern.
- **No schema or SQL changes.** All changes are Perl, confined to
  listrecords.pm, the temporary reference/scaffolding, and test tooling.
