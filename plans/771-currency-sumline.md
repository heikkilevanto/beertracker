# Issue #771: Currency total on main-list summary lines

## Summary
Add a fourth figure to the location/day summary lines: the total of glasses
whose notes mention a foreign currency (e.g. `[5.5 e]`). When a location or
day has glasses in more than one currency, show only the most relevant
currency total.

Before that total can be trusted, currency **aliases must be merged into one
table** — today `e`/`eur`, `p`/`gbp`, `s`/`sek` are duplicated in
`postglass.pm`, and `u` is documented but not accepted.

## Why this fits existing behaviour
Foreign prices are entered as a suffix on the price field (`5.5e`), converted
to DKK into `glasses.Price`, and the original amount is stored on the note as
`[amount currency]` (`postglass.pm` `fixprice`/`curprice`, `doc/manual.md`).
So a “currency total” must be summed from the **note**, not from `Price`.

Note pattern used today (copy buttons, `mainlist.pm`):
`/\[([0-9.]+) +(\w+)\]/`

Current `%currency` in `postglass.pm` (aliases are ad-hoc keys with duplicated
rates):

| alias | rate (DKK) | note / manual |
|---|---|---|
| `e`, `eur` | 7.5 | both accepted; notes store the alias as typed |
| `usd` | 6.3 | code has no `u`; **manual documents `u`** |
| `p`, `gbp` | 8.5 | both accepted |
| `s`, `sek` | 0.65 | both accepted |

Dev data currently only shows `[8 e]` / `[9 e]`-style notes, but aliases will
diverge as soon as anyone types `5.5eur` or follows the manual’s `u`.

## Part A — Merge currency aliases (do first)

### Single source of truth
One registry, used by both price conversion (writer) and sumline parsing
(reader):

```perl
# code/currencies.pm  (tiny module — postglass and mainlist both need it)
package currencies;
use strict;
use warnings;

my @CURRENCIES = (
  { code => "EUR", rate => 7.5,  aliases => [qw(e eur)] },
  { code => "USD", rate => 6.3,  aliases => [qw(u usd)] },  # add 'u' to match manual
  { code => "GBP", rate => 8.5,  aliases => [qw(p gbp)] },
  { code => "SEK", rate => 0.65, aliases => [qw(s sek)] },
);

# Flatten alias -> { code, rate } once
my %by_alias;
foreach my $cur (@CURRENCIES) {
  foreach my $alias (@{ $cur->{aliases} }) {
    $by_alias{lc $alias} = $cur;
  }
}

# Lookup any alias (or full code). Returns { code, rate } or undef.
sub lookup {
  my $token = shift;
  return undef unless defined $token && $token ne "";
  return $by_alias{lc $token};
}

# Canonical code for a note/currency token, or undef.
sub code {
  my $token = shift;
  my $cur = lookup($token);
  return undef unless $cur;
  return $cur->{code};
}

# Known codes for docs/tests: "EUR", "USD", ...
sub codes {
  return map { $_->{code} } @CURRENCIES;
}

1;
```

Why a tiny module rather than `util.pm`: both `postglass.pm` (conversion) and
`mainlist.pm` (sumline) need the map; neither should own it. Keep it small
and procedural — no rates loaded from DB, no extra config.

### What merges where
1. **`postglass::curprice`** — delete `%currency` and the alias loop body’s
   duplication. Match via `currencies::lookup($alias)`, convert with
   `$cur->{rate}`.
2. **Stored note text** — always write the **canonical code**, not the alias
   as typed:
   - Input `5.5e` or `5.5eur` → note `[5.5 EUR]`, `Price = 41`
   - Input `10u` or `10usd` → note `[10 USD]`
   - Copy-button path in `mainlist.pm` already re-reads the note and passes
     `$1$2` through `curprice`; canonical codes still match (`5.5EUR`).
3. **`mainlist::note_currency`** (new, Part B) — normalise via
   `currencies::code($token)` so **old** notes (`[8 e]`, `[10 usd]`) group
   with new ones (`[8 EUR]`). Do not rewrite historical notes.
4. **Manual** — list both shorthand and full code for each currency; state
   that notes are stored with the full code (e.g. `[5.5 EUR]`).
5. **HTTP tests** (`tools/test-http` currency roundtrip) — expectations
   change from `[5.5 e]` / `[10 usd]` to `[5.5 EUR]` / `[10 USD]`.
6. **Unit tests** (`tools/test-unit` `curprice`) — add `u`/`usd` cases; note
   text assertions become canonical codes if they assert `$orig`.

### Behaviour notes
- Shorthands stay accepted on **input**; storage and grouping use one code.
- Rates live only in `currencies.pm` (single place to update when DKK
  moves).
- No migration; old alias notes remain readable via `lookup`.
- `u` becomes valid (matches manual). Document that in the commit message.

## Part B — Currency total on sumline

### Decisions (recommended)
- **Sum** original amounts from note brackets, grouped by canonical code.
  Do **not** sum DKK `Price` (would double-count).
- **Dominant currency** when several appear:
  1. most glasses mentioning that code
  2. tie-break: higher sum of amounts
  3. final tie-break: code name alphabetically
- **Display** one figure: `12.30 EUR`. Blank cell when none.
- **Where**: location sum lines + day sum line (day line still only when
  `location_count > 1`). Not on filtered view.
- **Column**: after blood-alc, before the label; right-aligned; empty cell
  kept so columns stay aligned.

### Implementation
1. **Helpers in `mainlist.pm`** (pure, unit-tested):
   ```perl
   # Parse one note. Returns ($amount, $code) or ().
   sub note_currency {
     my $note = shift;
     return () unless defined $note && $note =~ /\[([0-9.]+) +(\w+)\]/;
     my ($amount, $token) = ($1, $2);
     my $code = currencies::code($token);
     return () unless defined $code;
     return ($amount, $code);
   }

   # Dominant currency for a list of glass hashrefs.
   # Returns { code => 'EUR', total => "12.30" } or undef.
   sub currency_total {
     my $glasses = shift;
     my (%count, %sum);
     foreach my $rec (@$glasses) {
       my ($amount, $code) = note_currency($rec->{note});
       next unless defined $code;
       $count{$code}++;
       $sum{$code} += $amount;
     }
     return undef unless keys %count;
     my ($best) = sort {
       $count{$b} <=> $count{$a}
         || $sum{$b} <=> $sum{$a}
         || $a cmp $b
     } keys %count;
     return { code => $best, total => sprintf("%.2f", $sum{$best}) };
   }
   ```
2. **`oneday`**: keep glasses per location session; call `currency_total` on
   the session and on all `@glasses` for the day; pass `"12.30 EUR"` into
   `sumline`.
3. **`sumline`**: optional 6th arg `$cursum`; render as an extra `<td>` (or
   empty).
4. **Unit tests**: alias merge (`e`/`eur`/`u`/`usd`/…), ranking, empty notes.
5. **Docs**: short note under Foreign currencies in `doc/manual.md`.

## Suggested commit split
1. `currencies.pm` + `curprice` merge + test updates + manual (alias merge)
2. Sumline currency total + helpers + unit tests + manual blurb

## Part A status — done
- `code/currencies.pm` — codes, rates, aliases, `lookup`/`code`/`aliases`/`codes`
- `postglass::curprice` uses the registry; notes store canonical codes
  (`5.5e` and `5.5eur` → `[5.5 EUR]`; `u` accepted for USD)
- Unit tests: `postglass_curprice` 22/22 PASS
- HTTP test: `glass_currency_roundtrip` 33/33 PASS on dev server
- Manual: both shorthands and full codes; rates in `currencies.pm`

## Part B status — done
- `mainlist::note_currency`, `currency_total`, `currency_sumline_text`
- `sumline` optional currency column (blank cell when none)
- `oneday`: per-location session + multi-location day totals
- Unit tests: `mainlist_currency` (note parse, ranking, grouping, empty)
- Manual: sumline foreign-currency total blurb
- `index.fcgi` requires `currencies.pm`

## Layout fix (post-B)
- Dropped fixed-width table in `sumline`; now a `.sumline` div like `numbersline`
- `white-space: nowrap` in `static/layout.css` — currency stays one token; long lines extend past the screen
- Currency omitted entirely when empty (no reserved 60px cell)

## Test status
- Unit: `postglass_curprice` + `mainlist_currency` in quick set
- HTTP: currency roundtrip (canonical notes); Full page loads after Part B
- Dev check still useful: mixed `[5.5 e]` / `[12 p]` shows dominant total

## Out of scope
- Converting foreign totals into DKK on the sumline.
- Showing all currencies (only the dominant one).
- Changing which glasses count as spending (adjustments, bottle purchases).
- Forcing the day line when only one location that day.
- Rewriting historical note text in the DB.

## Verification
- `perl -c code/currencies.pm code/postglass.pm code/mainlist.pm`
- `tools/test-unit` (curprice + new note_currency/currency_total cases)
- `tools/test-http` currency roundtrip (updated expectations)
- `touch code/VERSION.pm`
- Dev check: location with mixed `[5.5 e]` and `[12 p]` shows one dominant
  total; pure-DKK location shows blank; typing `5.5e` and `5.5eur` both land
  as `[5.5 EUR]`
- `./tools/testall`

## Files touched
- **Part A**: `code/currencies.pm` (new), `code/postglass.pm`,
  `tools/test-unit`, `tools/test-http`, `doc/manual.md`
- **Part B**: `code/mainlist.pm`, unit tests, `doc/manual.md`

## Open questions
1. **Note storage format** — recommended: always store canonical code
   (`[5.5 EUR]`). Alternative: keep whatever alias the user typed and only
   normalise on read (less test churn, messier notes). Confirm before
   Part A.
2. **Display string** — `12.30 EUR` recommended vs `12.30e`.
