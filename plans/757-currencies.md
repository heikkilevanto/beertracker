# Plan: Currency Support (#757)

## Summary

Re-enable currency support so users can enter prices in EUR, USD, GBP, or SEK
while traveling. The user suffixes the price with a currency letter (e.g. `5.5e`
for euros). The code converts to DKK using hardcoded exchange rates and stores
a `[5.50 e]` note in the Note field. No database schema changes needed.

## Design Decisions

- **Currencies**: EUR (`e`), USD (`u`), GBP (`p`), SEK (`s`). Short shorthands
  match the dead code convention and are easy to type.
- **Exchange rates**: Hardcoded in `%currency` hash. Simple, no external dependency.
- **Storage**: Converted DKK price goes in `Price` column. Original price and
  currency stored in `Note` field as `[5.50 e]`. Square brackets make it
  machine-detectable for copy buttons.
- **Copy buttons**: When copying a glass with a `[price cur]` note, pass the
  original format (e.g. `5.5e`) so the user sees the foreign price.
- **No schema migration**: Everything fits in existing columns.

## Dead Code to Replace

- `postglass.pm:449-469` — `%currency` hash and `curprice()` function. Both are
  explicitly marked "not used". Replace with updated versions.

## Edit-Glass Issue: Avoiding Duplicate Currency Notes

When editing a glass that already has a `[5.50 e]` note and entering a new
currency price, the code must strip the old `[...]` marker before appending the
new one. Otherwise repeated edits accumulate markers like `[5.50 e] [10 usd]`.

The `fixprice()` code must first remove any existing `\[.*?\]` pattern from the
note before appending the new currency marker. Same for the empty and adjustment
glass paths.

## Changes

### 1. `code/postglass.pm` — Currency hash and helper

Replace lines 449-469 with:

```perl
# Currency conversion rates to DKK
my %currency;
$currency{"eur"} = 7.5;
$currency{"e"} = 7.5;     # shorthand for EUR
$currency{"usd"} = 6.3;
$currency{"gbp"} = 8.5;
$currency{"p"} = 8.5;     # shorthand for GBP
$currency{"sek"} = 0.65;
$currency{"s"} = 0.65;    # shorthand for SEK

############## Helper for currency conversion
# Returns (dkk_price, "orig_price currency") on match, empty list otherwise
sub curprice {
  my ($c, $v) = @_;
  for my $cur (keys %currency) {
    if ( $v =~ /^(-?[0-9.]+) *$cur$/i ) {
      my $orig = $1;
      my $dkk = int(0.5 + $orig * $currency{$cur});
      print { $c->{log} } "curprice: '$orig $cur' -> $dkk DKK\n";
      return ($dkk, "$orig $cur");
    }
  }
  return ();
} # curprice
```

### 2. `code/postglass.pm` — `fixprice()` currency detection

Insert before the `X` check (around line 442), inside `fixprice()`:

```perl
  # Currency conversion: e.g., "5.5e" -> 41 DKK, note "[5.50 e]"
  if ($rawpr && $rawpr !~ /^x/i) {
    my ($converted, $origtext) = curprice($c, $rawpr);
    if (defined $converted) {
      $glass->{Price} = $converted;
      my $note = $glass->{Note} || "";
      $note =~ s/\s*\[.*?\]\s*/ /g;  # strip any existing currency note
      $note =~ s/^\s+|\s+$//g;        # trim
      $note .= " " if $note;
      $note .= "[$origtext]";
      $glass->{Note} = $note;
      return;
    }
  }
```

### 3. `code/postglass.pm` — Empty glass currency support

After the existing price read for empty glasses (after line 79), add:

```perl
    # Currency conversion for empty glasses
    if (util::param($c, "pr") !~ /^\s*x/i) {
      my ($converted, $origtext) = curprice($c, util::param($c, "pr"));
      if (defined $converted) {
        $glass->{Price} = $converted;
        my $note = $glass->{Note} || "";
        $note =~ s/\s*\[.*?\]\s*/ /g;  # strip any existing currency note
        $note =~ s/^\s+|\s+$//g;        # trim
        $note .= " " if $note;
        $note .= "[$origtext]";
        $glass->{Note} = $note;
      }
    }
```

### 4. `code/postglass.pm` — Adjustment glass currency support

Replace the `util::paramnumber` call at line 94 with:

```perl
    # Currency conversion for adjustment glasses
    my ($converted, $origtext) = curprice($c, util::param($c, "pr"));
    if (defined $converted) {
      $glass->{Price} = $converted;
      my $note = $glass->{Note} || "";
      $note =~ s/\s*\[.*?\]\s*/ /g;  # strip any existing currency note
      $note =~ s/^\s+|\s+$//g;        # trim
      $note .= " " if $note;
      $note .= "[$origtext]";
      $glass->{Note} = $note;
    } else {
      $glass->{Price} = util::paramnumber($c, "pr");
    }
```

### 5. `code/mainlist.pm` — Copy button passes currency format

Replace the `$copy_price` logic (lines 346-351) with:

```perl
    my $copy_price = '';
    # Check for currency note pattern like [5.50 e] - pass original format
    if ($rec->{note} && $rec->{note} =~ /\[([0-9.]+) +(\w+)\]/) {
      $copy_price = "$1$2";  # e.g., "5.50e"
    } elsif ( defined $rec->{price} && $rec->{price} < 0 ) {
      $copy_price = 0;  # Negative price means bottle purchase, copy as zero price
    } elsif ( $rec->{vol} && $volx == $rec->{vol} && defined $rec->{price} ) {
      $copy_price = $rec->{price};  # Same volume, copy the price
    }
```

## Files Modified

| File | What changes |
|------|-------------|
| `code/postglass.pm` | Currency hash, curprice(), fixprice(), empty glass, adjustment glass |
| `code/mainlist.pm` | Copy button price logic |
| `tools/test-unit` | Add `postglass_curprice` test, require postglass |
| `tools/test-http` | Add `glass_currency_roundtrip` test |
| `doc/manual.md` | Document currency suffix feature in Price section |
| `plans/improvements.md` | Mark Currency Support as done |

## Files NOT modified

- `code/util.pm` — No changes needed; raw param is read before `util::number()`
- `doc/db.schema` — No migration needed
- `static/` files — No UI changes; user types the suffix directly

## Automated Tests

### `tools/test-unit` — `postglass_curprice` test

Add a new test to verify the `curprice()` helper function in isolation. This
requires no HTTP, no database — just load `postglass.pm` and call the function
with a mock `$c` hash (only needs `$c->{log}`).

```perl
sub test_postglass_curprice {
  require postglass;
  my $c = { log => \*STDERR };

  # EUR shorthand
  my ($dkk, $orig) = postglass::curprice($c, "5.5e");
  assert(defined $dkk && $dkk == 41, "curprice 5.5e -> 41 DKK");
  assert($orig eq "5.5 e", "curprice 5.5e orig text");

  # Full currency name
  ($dkk, $orig) = postglass::curprice($c, "10eur");
  assert(defined $dkk && $dkk == 75, "curprice 10eur -> 75 DKK");

  # USD
  ($dkk, $orig) = postglass::curprice($c, "20usd");
  assert(defined $dkk && $dkk == 126, "curprice 20usd -> 126 DKK");

  # GBP
  ($dkk, $orig) = postglass::curprice($c, "8.5p");
  assert(defined $dkk && $dkk == 72, "curprice 8.5p -> 72 DKK");

  # SEK
  ($dkk, $orig) = postglass::curprice($c, "100s");
  assert(defined $dkk && $dkk == 65, "curprice 100s -> 65 DKK");

  # No currency suffix — should return empty list
  my @result = postglass::curprice($c, "45");
  assert(scalar(@result) == 0, "curprice '45' returns empty (no match)");

  # Negative price with currency
  ($dkk, $orig) = postglass::curprice($c, "-5e");
  assert(defined $dkk && $dkk == -38, "curprice -5e -> -38 DKK");
}
```

Register in `@TESTS`:
```perl
{ name => "postglass_curprice", sets => [qw(quick postglass)], test => \&test_postglass_curprice },
```

Add `require postglass;` to the module loading section at the top of test-unit.

### `tools/test-http` — `glass_currency_roundtrip` test

Add a POST round-trip test that creates a glass with a currency-suffixed price,
verifies the DKK conversion and the `[price cur]` note, edits the glass with a
different currency to verify the old note is replaced, and cleans up.

This test follows the same pattern as `test_glass_roundtrip` (lines 937-1006):
dev-guarded, not in 'quick', uses TST tokens and assert helpers.

```perl
sub test_glass_currency_roundtrip {
  # Currency round-trip: record a glass with a currency-suffixed price,
  # verify the DKK conversion and the [price cur] note, then edit it
  # with a different currency to verify the old note is replaced, not
  # accumulated. Cleanup via delete at the end.
  my $locid = get_first_id("Location");
  if ( !defined $locid ) { skipmsg("Location list has no ids for a glass"); return; }
  get_first_id("Full");

  my ($status, $headers, $body) = req("GET", "$BASE_URL?o=Full");
  my ($brewid, $brewtype) = brew_with_defprice($body);
  if ( !defined $brewid ) { skipmsg("no brew with a DefPrice in the dev data"); return; }

  my $note = "TST" . time() . "cur";
  my $date = strftime("%Y-%m-%d", localtime());
  my $time = strftime("%H:%M", localtime());

  # Insert: record a glass with pr='5.5e' (EUR). Should convert to 41 DKK
  # and add '[5.5 e]' to the note.
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", Location => $locid, Brew => $brewid, selbrewtype => $brewtype,
        date => $date, time => $time, vol => "33", alc => "4.6", pr => "5.5e",
        note => $note, submit => "Record" });
  my $loc = assert_post_redirect($status, $headers, "Glass currency insert");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after currency insert", "id='mainform'");
  # The note field should contain both the user note and the currency marker
  assert(scalar($body =~ /\Q$note\E.*\Q[5.5 e]\E/),
         "Full page shows note with currency marker '[5.5 e]'");
  my $id = id_before_text($body, "Full", $note);
  assert(defined $id, "harvested the new glass id from the main list");
  return unless defined $id;

  # Edit: change the currency to USD (pr='10usd'). The old '[5.5 e]' note
  # should be replaced by '[10 usd]', not accumulated.
  my $note2 = $note . "upd";
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", e => $id, Location => $locid, Brew => $brewid,
        selbrewtype => $brewtype, date => $date, time => $time, vol => "33",
        alc => "4.6", pr => "10usd", note => $note2, submit => "Save" });
  $loc = assert_post_redirect($status, $headers, "Glass currency update");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after currency update", "id='mainform'");
  assert(scalar($body =~ /\Q$note2\E.*\Q[10 usd]\E/),
         "Full page shows updated note with '[10 usd]'");
  assert(scalar($body !~ /\Q[5.5 e]\E/),
         "Full page no longer shows the old currency note '[5.5 e]'");

  # Delete
  ($status, $headers, $body) = req("POST", "$BASE_URL",
      { o => "Full", e => $id, submit => "Del" });
  $loc = assert_post_redirect($status, $headers, "Glass currency delete");
  return unless defined $loc;
  ($status, $headers, $body) = req("GET", $loc);
  assert_page_ok($status, $body, "Full after currency delete", "id='mainform'");
  assert(scalar($body !~ /\Q$note\E/), "Full page no longer shows the deleted record");
} # test_glass_currency_roundtrip
```

Register in `@TESTS`:
```perl
{ name => "glass_currency_roundtrip", sets => [qw(posts roundtrip postglass glasses)], test => \&test_glass_currency_roundtrip },
```

## Documentation

### `doc/manual.md` — Price section

Add a new subsection after the existing "Bottle and box prices" section (after
line 156), under the "### Price" heading:

```markdown
#### Foreign currencies

When traveling, you can enter prices in a foreign currency by adding a suffix
letter to the price. The system converts it to DKK (Danish Kroner) and stores
the original price in the note field.

Supported currencies:
- **EUR** — suffix `e` (e.g. `5.5e` for 5.50 euros)
- **USD** — suffix `u` (e.g. `8u` for 8 dollars)
- **GBP** — suffix `p` (e.g. `4.5p` for 4.50 pounds)
- **SEK** — suffix `s` (e.g. `65s` for 65 kronor)

Example: typing `5.5e` stores a price of 41 DKK and adds `[5.5 e]` to the note
field. When copying that glass, the original `5.5e` format is passed so you see
the foreign price.

Exchange rates are hardcoded in `postglass.pm` and may need periodic updating.
```

### `doc/design.md` — No changes needed

The existing documentation is accurate enough: the Price field is documented as
storing the DKK value, and the Note field is described as free text. The currency
marker `[5.5 e]` is just content in the Note field — no schema or design doc
change required.

### `plans/improvements.md` — Mark as done

Update the "Currency Support" entry (line 83) to mark it as implemented:

```markdown
### ~~Currency Support~~ (done)
~~Add a currency field to glasses and a default currency setting, with optional
conversion rates.~~ Implemented via price suffix (e.g. `5.5e`) with hardcoded
exchange rates. Original price stored in Note field as `[5.5 e]`. See issue #757.
```

### Commit message

Include in the commit message:
- Mention the currency suffix feature and the supported currencies/shorthands
- Reference issue #757
- Note the hardcoded exchange rates in `postglass.pm`
