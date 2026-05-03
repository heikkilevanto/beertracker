# Plan: styles.pm refactor — issue 671

## Goal

Simplify and fix the styles.pm interface. The main problems today:

- `brewcolor` strips multi-word input down to a single word via an overly aggressive regex,
  defeating the purpose of callers that pass richer strings.
- The `$line` identifier argument present in `beercolorstyle` was never wired through to
  the actual log warning in `brewcolor`, so failed color lookups are unidentifiable.
- `beercolorstyle` has a hashref-dispatch path that is confirmed unused (no real location
  record callers exist).

---

## Changes

### 1. Fix `brewcolor` — restore full-string matching

Remove the regex that strips input to a single word:

```perl
# Old — strips "Beer,NEIPA" to "Beer", "New England IPA" to "New"
if ( $brew =~ /^\[?(\w+)(,(.+))?\]?$/i ) {
    $type = "$1";
    $type .= ",$3" if ( $3 );
}
```

Replace with bracket-stripping only, then match against the full string:

```perl
(my $type = $brew) =~ s/^\[|\]$//g;  # Strip brackets only
```

### 2. Add optional `$line` argument to `brewcolor`

Add a third optional argument used only in the "OOPS!" log message:

```perl
sub brewcolor {
    my $c    = shift;
    my $brew = shift;
    my $line = shift || "";   # optional caller context for log messages
    ...
    print { $c->{log} } "OOPS! Can not get color for '$brew' at $line\n";
```

All existing callers that omit `$line` continue to work unchanged.

### 3. Add `brewinfo($c, $rec)` in styles.pm

New function that accepts a hashref (brew record or GLASSES row) and returns a hash of
precomputed display values. Handles the field-name difference between record types:

- Brew / GLASSES row: uses `BrewType` + `SubType`
- Location record: uses `LocType` + `LocSubType`

`BrewStyle` is intentionally excluded to keep behavior consistent with GLASSES rows,
which do not carry that field.

Returns a hash with:

| Key         | Value                                              |
|-------------|----------------------------------------------------|
| `color`     | Raw 6-char hex string from `brewcolor`             |
| `textstyle` | `style='background-color:#xx;color:#yy;'` attribute |
| `shortname` | Result of `shortbeerstyle` on the subtype          |
| `display`   | Full `<span style='...'>[$style_str]</span>` HTML  |

### 4. Remove / simplify `beercolorstyle`

The hashref-dispatch path in `beercolorstyle` is unused. The one external caller
(`beerboard.pm` line 99) passes a short style string and a `$line` identifier.

Migrate that caller to call `brewcolor($c, $sty, $line)` directly (it only needs the
style attribute, not the full span). Then remove `beercolorstyle` entirely.

### 5. Fix the silently-ignored 4th argument in `beerboard.pm` line 99

The current call:
```perl
my $beerstyle = styles::beercolorstyle($c, $processed_data->{sty}, "Board:$e->{'id'}",
    "[$e->{'type'}] $e->{'maker'} : $e->{'beer'}");
```
The 4th argument is silently ignored. After removing `beercolorstyle`, replace with:
```perl
my $beerstyle = styles::brewtextstyle($c, $processed_data->{sty}, "Board:$e->{'id'}");
```
(passing the line identifier as the 3rd arg to `brewtextstyle`, which forwards it to
`brewcolor`).

### 6. Update `graph.pm` caller (optional improvement)

Currently `graph.pm` manually constructs the type string:
```perl
my $style = $r->{BrewType};
$style .= ",$r->{SubType}" if ($r->{SubType});
my $color = styles::brewcolor($c, $style);
```
This can be replaced with:
```perl
my $color = styles::brewinfo($c, $r)->{color};
```
This is a minor cleanup; the manual string construction also remains correct after the
`brewcolor` fix.

### 7. `brewtextstyle` — no change

Internal-only helper. Not externally callable. Leave as-is.

---

## Callers summary after refactor

| Caller                   | Before                         | After                                      |
|--------------------------|--------------------------------|--------------------------------------------|
| `graph.pm`               | `brewcolor($c, $style_string)` | `brewinfo($c, $r)->{color}` (optional)     |
| `beerboard.pm` line 99   | `beercolorstyle($c, $sty, $line, ...)` | `brewtextstyle($c, $sty, $line)`   |
| `beerboard.pm` line 365  | `shortbeerstyle($sty)`         | unchanged                                  |
| `beerboard.pm` line 498  | `brewstyledisplay($c, "Beer", $sty)` | unchanged                            |
| `beerboard.pm` line 525  | `brewstyledisplay($c, "Beer", $origsty)` | unchanged                        |
| `scrapeboard.pm`         | `shortbeerstyle($sty)`         | unchanged                                  |
| `brews.pm`               | `brewstyledisplay($c, $bt, $su)` | unchanged                                |
| `mainlist.pm`            | `brewstyledisplay($c, $bt, $su)` | unchanged                                |
| `listrecords.pm`         | `brewstyledisplay($c, $bt, $su)` | unchanged                                |

---

## Files to change

- `code/styles.pm` — all logic changes
- `code/beerboard.pm` — fix line 99 caller
- `code/graph.pm` — optional cleanup of manual string construction

---

## Out of scope

- `brewtextstyle` rename/restructure
- Using `BrewStyle` in color matching
- Any changes to the pattern table in `brewcolor`
