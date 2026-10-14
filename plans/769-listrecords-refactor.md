# Plan: Refactor listrecords.pm

## Problem
`listrecords.pm` is the largest module. The `listrecords` function is ~860 lines,
with most of that in two massive loops: header generation (lines 277–437) and
body/field value formatting (lines 463–861). Both use long if/elsif chains keyed
on field names, but the header styling and body formatting for each field are
~200 lines apart. The suffix parsing (lines 98–157) is also a long chain.
The cont/contline state tracking and photo colspan logic are duplicated between
the header and body loops.

## Goal
Make the module shorter, easier to follow, and easier to extend. Co-locate
header and field processing for each type. Eliminate duplicated patterns.
Make adding a new field type a single-entry change.

## Approach: Table-driven field definitions

### 1. Define a `%FIELD_DEFS` hash (module scope or sub-local)

Each field type gets one entry that co-locates header style, header input
behavior, and value formatting:

```perl
my %FIELD_DEFS = (
  Name => {
    style     => "max-width:200px; min-width:0",
    mobile    => "max-width:90px; min-width:0",
    placeholder => "Name",
    word_split => 0,
    format    => sub { "<b>" . _word_spans($_[0], $_[1]) . "</b>" },
  },
  Id => {
    style     => "max-width:40px; text-align:center",
    placeholder => "Id",
    word_split => 0,
    format    => sub { ... },  # existing link logic
  },
  Type => {
    style     => "max-width:100px; text-align:center",
    mobile_style => "max-width:200px; text-align:center",
    word_split => 0,
    format    => sub { ... },  # brewtextstyle logic
  },
  # ... etc for each field type
);

# Fields not in %FIELD_DEFS get defaults:
#   style: max-width:200px (or 90px mobile)
#   word_split: 1
#   format: identity (pass through)
```

This replaces the header-style if/elsif (lines 299–347) and the body-format
if/elsif (lines 498–804). Fields not in the hash get sensible defaults.

Complex fields that need access to `$c`, `$url`, `$extraparams`, `$fields`,
`$rec`, etc. get code-ref handlers. The dispatch function passes all needed
context.

### 2. Extract `_render_header()` function

Move the `<thead>` loop (lines 277–437) into:
```perl
sub _render_header {
  my ($c, $fields, $suffix_info_ref, $extra_attr_ref, $styles_ref,
      $px_override_ref, $auto_override_ref, $initial_filter, $maxrecords) = @_;
  # ... returns HTML string
}
```

Inside this function, dispatch via `%FIELD_DEFS` for style and placeholder.
The cont/contline/photo logic stays here (or is extracted into helpers — see #5).

### 3. Extract `_render_body_row()` function

Move the per-row field formatting (lines 463–861) into:
```perl
sub _render_body_row {
  my ($c, $rec, $fields, $suffix_info_ref, $styles_ref, $extra_attr_ref,
      $url, $extraparams, $i, $id) = @_;
  # ... returns HTML string for one <tr>
}
```

Inside this function, dispatch via `%FIELD_DEFS` for formatting. The
cont/contline/photo logic stays here (or extracted — see #5).

### 4. Rewrite suffix parsing as a table-driven loop

Replace the do/while chain (lines 98–157) with a `@SUFFIX_DEFS` table:

```perl
my @SUFFIX_DEFS = (
  [qr/_R(\d+)$/,       'rowspan'],
  [qr/_C(\d+)$/,       'colspan'],
  [qr/_as=([^_]+)$/,   'as_name'],
  [qr/_(\d+px)$/,      'width_px'],
  [qr/_A$/,            'auto_width'],
  [qr/_filter$/,       'filter'],
  [qr/_nofilter$/,     'nofilter'],
  [qr/_noheader$/,     'noheader'],
  [qr/_link=([A-Z][a-zA-Z]+)$/, 'link'],
  [qr/_contline$/,     'contline'],
  [qr/_cont$/,         'cont'],
  [qr/_sum$/,          'aggregate', 'sum'],
  [qr/_avg$/,          'aggregate', 'avg'],
  [qr/_cnt$/,          'aggregate', 'cnt'],
);
```

Then parse each field name:
```perl
for my $field (@fields) {
  my $suf = {};
  my $changed;
  do {
    $changed = 0;
    for my $def (@SUFFIX_DEFS) {
      if ($field =~ $def->[0]) {
        my $key = $def->[1];
        my $val = defined $def->[2] ? $def->[2] : $1;
        if ($key eq 'width_px') { $px_override{$i} = $val; }
        elsif ($key eq 'auto_width') { $auto_override{$i} = 1; }
        elsif ($key eq 'aggregate') { $suf->{aggregate} = $val; }
        else { $suf->{$key} = $val; }
        $field =~ s/$def->[0]//;
        $changed = 1;
        last;  # restart after first match
      }
    }
  } while ($changed);
  # warn on leftover suffix
}
```

### 5. Extract helpers for duplicated logic

**cont/contline state** — appears ~8 times across header and body:
```perl
sub _close_cont { my ($s_ref, $active_ref) = @_;
  if ($$active_ref) { $$s_ref .= "</td>\n"; $$active_ref = 0; }
}
```

**photo colspan** — appears ~4 times:
```perl
sub _maybe_photo_colspan { my ($s_ref, $skipped_ref) = @_;
  if ($$skipped_ref) { _colspan_last_td($s_ref); $$skipped_ref = 0; }
}
```

### 6. Remove no-op field handlers

- `LocName` (line 557–558): does nothing, remove from body chain
- `Comment` (line 697–698): `$v = "$v"` is a no-op, remove

### 7. Collapse unit-format fields into %FIELD_DEFS

`Alc`, `d`, `Pr`, `Vol` all follow the same pattern:
1. Add data-sort-key, data-col, data-filter, onclick to `$data_attrs`
2. Call `util::unit($v, $unit)`
3. If empty, return ""

A generic entry:
```perl
Alc => {
  style => "text-align:center; font-weight:bold; max-width:50px",
  unit => "%",
  word_split => 0,
},
Pr => {
  style => "text-align:right; max-width:35px",
  unit => ".-",
  word_split => 0,
},
Vol => {
  style => "text-align:right; max-width:35px",
  unit => "c",
  word_split => 0,
},
d => {
  style => "text-align:right; max-width:50px",
  suffix => "d",   # uses sprintf('%.1f', $v) . "<span ...>d</span>"
  word_split => 0,
},
```

The dispatch function checks for `unit` or `suffix` and applies the pattern
generically, collapsing ~40 lines to config entries.

## Files changed

- `code/listrecords.pm` — all changes are in this file
- Touch `code/VERSION.pm` after editing (separate step)

## Implementation order

1. **Suffix table** — rewrite lines 98–157 with `@SUFFIX_DEFS`. Test: existing
   SQL column suffixes should still parse correctly.
2. **Extract helpers** — `_close_cont`, `_maybe_photo_colspan`. Pure refactor, no
   behavior change.
3. **Define `%FIELD_DEFS`** — start with the simple fields (Name, Id, Sub, IsGeneric,
   Alc, d, Pr, Vol, Comment, LocName). Move style + format into the table.
4. **Extract `_render_header()`** — move the `<thead>` loop. Use `%FIELD_DEFS` for
   styles and placeholders.
5. **Extract `_render_body_row()`** — move the per-row loop. Use `%FIELD_DEFS` for
   formatting. Handle complex fields (Type, Ts, Last/LastProd, CountryRegion,
   PersonName, Stats, Photo/Photos, Sim, Geo, Locations, Day, Chk, Rate, link
   fields) as code-refs in the table or as explicit handlers.
6. **Add remaining fields** to `%FIELD_DEFS` as code-refs for complex cases.
7. **Verify** with `tools/testall` (unit + HTTP tests).

## Design decisions

- **Table-driven vs. full OO dispatch**: Table-driven (hash of config + code-refs)
  is simpler and more consistent with the procedural Perl style of this codebase.
  No classes, no role system.
- **Code-refs for complex fields**: Fields like Type, Ts, PersonName, CountryRegion
  have non-trivial logic that doesn't fit a simple config hash. These get code-ref
  handlers in `%FIELD_DEFS` that receive all needed context.
- **Simple fields as config only**: Fields like Name, Id, Alc, Pr, Vol, Sub,
  IsGeneric are fully described by a style string, optional placeholder, and
  optional unit/suffix. No code-ref needed.
- **Default for unknown fields**: Fields not in `%FIELD_DEFS` get the default style
  (max-width:200px) and pass-through formatting with word_split=1. This matches
  current behavior for any field not explicitly handled.
- **No schema or SQL changes**: All changes are Perl-only, confined to listrecords.pm.
- **No behavior changes**: The generated HTML should be identical (or functionally
  equivalent) before and after refactoring.

## Verification

- `perl -c code/listrecords.pm`
- `./tools/testall` — unit tests + HTTP smoke tests
- Manual: browse Brews, Locations, Comments, Photos, Persons, Daily Stats pages.
  Check that column headers, styles, filters, sorting, pagination all work.
- Check mobile layout still applies mobile-specific styles.
- Check photo columns with empty photos still get colspan.
- Check contline fields (e.g., comments Last + BrewName) still span correctly.
