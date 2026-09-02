# Plan: Pure function unit tests + test wrapper

## Summary

Create `tools/test-unit.pl` for pure function unit tests across util, dateutil, geo,
comments, glasses, and styles modules. Add `tools/test-all.sh` wrapper that runs
both test-unit.pl and test-http.pl. The unit test script reuses the same
assert/selector pattern as test-http.pl (same exit code convention, same `-v`
flag, same `quick` default set) but without HTTP infrastructure — just
`require` the modules and call functions directly.

## Task 1: Create `tools/test-unit.pl`

Standalone Perl script, run from the repo root: `perl tools/test-unit.pl`.
No LWP, no HTTP, no database, no CGI. Just loads modules via `require` and
calls functions with test inputs.

### Structure

Same skeleton as test-http.pl:
- Config section (minimal — just the module paths)
- Assertion helpers: `assert()`, `skipmsg()` (identical to test-http.pl)
- Test table: `my @TESTS = (...);` with name, sets, test sub
- Test selection: `select_tests()` (identical logic to test-http.pl)
- Main loop: iterate selected tests, per-test pass/fail counters, summary, exit code

No HTTP helper needed. No `req()`, no LWP, no cookie jar, no CopyProdData.

### Modules to test and key functions

#### util.pm (no dependencies)

`trim($val)` — strips leading/trailing whitespace, collapses all internal
whitespace (spaces, tabs, etc.) to single spaces. Returns `""` for undef.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `trim("")` | `""` | empty |
| `trim("  foo  bar  ")` | `"foo bar"` | internal whitespace collapsed |
| `trim(undef)` | `""` | undef default |

`number($v)` — cleans numeric string. Commas→dots, strips non-numeric chars.
Returns `"x"` verbatim if input matches `/^ *x/i` (clear marker). Returns `""`
if result is empty (then treated as 0 elsewhere). Always returns a string.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `number("4,5")` | `"4.5"` | comma to dot |
| `number("abc")` | `"0"` | non-numeric → 0 |
| `number("x")` | `"x"` | clear marker, returned verbatim |
| `number("  x")` | `"  x"` | clear marker with leading space |
| `number("45.-")` | `"45"` | trailing .- stripped |
| `number("-3")` | `"-3"` | negative |
| `number("")` | `"0"` | empty → 0 |
| `number(undef)` | `"0"` | undef → 0 |

`unit($v, $u)` — returns `$v<span style='font-size: xx-small'>$u</span> `.
Returns `""` if `$v` is falsy. Default unit is `"XXX"` if `$u` not passed.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `unit(50, ".-")` | `50<span...>.-</span> ` | normal |
| `unit(0, "d")` | `""` | falsy value |
| `unit(undef, "d")` | `""` | undef value |

`sizeprices(\@arr)` — takes arrayref of `{vol, price}` hashes. Returns
`(\@sizes, \%out)` where `\%out` has `SizeS/PriceS/SizeM/PriceM/SizeL/PriceL`.
Two sizes skips M (S+L directly).

| Function call | Expected | Notes |
|---------------|----------|-------|
| `sizeprices([{vol=>33,price=>50},{vol=>50,price=>75}])` | sizes=[33,50], SizeS=33, SizeL=50 | 2 sizes: S+L |
| `sizeprices([{vol=>20},{vol=>33},{vol=>50}])` | sizes=[20,33,50], SizeS=20, SizeM=33, SizeL=50 | 3 sizes |
| `sizeprices([{vol=>33}])` | sizes=[33], SizeS=33 | 1 size: S only |
| `sizeprices([])` | sizes=[], empty out | empty |

`clean_tags($raw)` — strips leading `#` from each word. Returns string.

| Function call | Expected |
|---------------|----------|
| `clean_tags("#foo #bar")` | `"foo bar"` |
| `clean_tags("")` | `""` |
| `clean_tags(undef)` | `""` |

`filter_tokens($val)` — splits on whitespace, supports double-quoted tokens.
Returns a list.

| Function call | Expected |
|---------------|----------|
| `filter_tokens('IPA "New England"')` | `("IPA", "New England")` |
| `filter_tokens("hello")` | `("hello")` |
| `filter_tokens("")` | `()` |

`htmlesc($s)` — escapes `& < > "`. Returns string.

| Function call | Expected |
|---------------|----------|
| `htmlesc('<script>&"x"')` | `"&lt;script&gt;&amp;&quot;x&quot;"` |
| `htmlesc(undef)` | `""` |

#### dateutil.pm (no dependencies)

`eff_day_of($ts)` — takes an ISO timestamp string like `"2026-01-01 01:00:00"`,
NOT an epoch. Applies -6h offset. Returns `"YYYY-MM-DD"` or `""` for undef.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `eff_day_of("2026-01-01 01:00:00")` | `"2025-12-31"` | before 6am = prev day |
| `eff_day_of("2026-01-01 07:00:00")` | `"2026-01-01"` | after 6am = same day |
| `eff_day_of("2026-01-01 05:59:59")` | `"2025-12-31"` | just before 6am cutoff |
| `eff_day_of(undef)` | `""` | undef |

`reldate($date)` — takes `"YYYY-MM-DD"` string. Returns `"today"`,
`"yesterday"`, or the date string. Uses `eff_day_of(now())` internally.

| Function call | Expected |
|---------------|----------|
| `reldate($today_str)` | `"today"` |
| `reldate($yesterday_str)` | `"yesterday"` |
| `reldate("2020-01-01")` | `"2020-01-01"` |

Note: `$today_str` and `$yesterday_str` should be computed at test time
using `dateutil::datestr("%F", 0)` and `dateutil::datestr("%F", -1)`.

`normalize_date($c, $val)` — does NOT use `$c` at all (API consistency only).
Returns `""` for empty, yesterday for `"Y"`, N-days-ago for `"-Nd"`, else passthrough.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `normalize_date({}, "")` | `""` | empty → clear |
| `normalize_date(undef, "Y")` | yesterday | Y → yesterday |
| `normalize_date(undef, "-3d")` | 3 days ago | -Nd → offset |
| `normalize_date(undef, "2024-12-25")` | `"2024-12-25"` | ISO passthrough |

`ts_epoch($ts)` — ISO timestamp string → epoch seconds (local time). Returns
`undef` for undef or non-matching format.

| Function call | Expected |
|---------------|----------|
| `ts_epoch("2026-06-15 12:00:00")` | numeric epoch |
| `ts_epoch(undef)` | undef |
| `ts_epoch("bad")` | undef |

`date_plus_days($datestr, $k)` — adds $k days to a YYYY-MM-DD string.

| Function call | Expected |
|---------------|----------|
| `date_plus_days("2026-01-01", 1)` | `"2026-01-02"` |
| `date_plus_days("2026-01-10", -5)` | `"2026-01-05"` |

`day_diff($a, $b)` — returns `int(b - a)` in whole days.

| Function call | Expected |
|---------------|----------|
| `day_diff("2026-01-01", "2026-01-10")` | `9` |
| `day_diff("2026-01-10", "2026-01-01")` | `-9` |
| `day_diff("2026-01-01", "2026-01-01")` | `0` |

#### geo.pm (no dependencies, needs Math::Trig)

`haversineKm($lat1, $lon1, $lat2, $lon2)` — distance in km (numeric).

| Function call | Expected | Notes |
|---------------|----------|-------|
| `haversineKm(55.6761, 12.5683, 55.6761, 12.5683)` | `0` | same point |
| `haversineKm(55.6761, 12.5683, 48.8566, 2.3522)` | `~950` | Copenhagen→Paris, assert > 900 && < 1000 |

`geodist(@_)` — passes to haversineKm, returns formatted string with variable
precision (3 decimals if <1km, 2 if <10km, 1 if <100km, 0 if >=100km).

| Function call | Expected | Notes |
|---------------|----------|-------|
| `geodist(55.6761, 12.5683, 55.6761, 12.5683)` | `"0.000"` | 3 decimals for <1km |
| `geodist(55.6761, 12.5683, 48.8566, 2.3522)` | matches `^\d+$` | 0 decimals for >=100km |

#### comments.pm (no dependencies)

`get_rating_class($rating)` — rounds via `int($rating + 0.5)`, returns CSS class.

| Function call | Expected |
|---------------|----------|
| `get_rating_class(1)` | `"rating-rubbish"` |
| `get_rating_class(3)` | `"rating-rubbish"` |
| `get_rating_class(4)` | `"rating-bronze"` |
| `get_rating_class(5)` | `"rating-bronze"` |
| `get_rating_class(6)` | `"rating-silver"` |
| `get_rating_class(7)` | `"rating-silver"` |
| `get_rating_class(8)` | `"rating-gold"` |
| `get_rating_class(2.7)` | `"rating-bronze"` | rounding: 2.7 → 3 → rubbish |

Wait — 2.7 rounds to 3 (`int(2.7 + 0.5) = int(3.2) = 3`), which is rubbish,
not bronze. Let me re-check the thresholds:

- 0-3 → rubbish (get_rating_class maps 0,1,2,3 to rubbish)
- 4-5 → bronze
- 6-7 → silver
- 8+ → gold

So `get_rating_class(2.7)` → `int(2.7+0.5)=3` → `"rating-rubbish"`.
And `get_rating_class(3.5)` → `int(3.5+0.5)=4` → `"rating-bronze"`.

#### glasses.pm (no dependencies)

`isemptyglass($type)` — returns count of matches (0 or 1). Use in boolean
context. Types: Night, Meal, Restaurant, Adjustment.

| Function call | Expected | Notes |
|---------------|----------|-------|
| `isemptyglass("Night")` | 1 (true) | |
| `isemptyglass("Restaurant")` | 1 (true) | |
| `isemptyglass("Adjustment")` | 1 (true) | |
| `isemptyglass("Beer")` | 0 (false) | |
| `isemptyglass("")` | 0 (false) | |

#### styles.pm (no dependencies for shortbeerstyle)

`shortbeerstyle($sty)` — abbreviates beer style. Returns `""` for undef/empty.

| Function call | Expected |
|---------------|----------|
| `shortbeerstyle("American IPA")` | `"AIPA"` |
| `shortbeerstyle("New England IPA")` | `"NEIPA"` |
| `shortbeerstyle("Pils")` | `"Lager"` |
| `shortbeerstyle("Stout")` | `"Stout"` |
| `shortbeerstyle("")` | `""` |
| `shortbeerstyle(undef)` | `""` |

`brewcolor($c, $brew)` — needs `$c->{bgcolor}` and `$c->{log}`. Returns hex
color without `#`. Falls back to `"9400d3"` (violet) for unrecognized types.
Skip this function in unit tests — it's better tested through the HTTP tests
where the full context exists.

### Test registration

Each function group gets its own test sub. Sets use module names as selectors:

```perl
my @TESTS = (
  { name => "util_trim",         sets => [qw(quick util)],       test => \&test_util_trim },
  { name => "util_number",       sets => [qw(quick util)],       test => \&test_util_number },
  { name => "util_unit",         sets => [qw(quick util)],       test => \&test_util_unit },
  { name => "util_sizeprices",   sets => [qw(quick util)],       test => \&test_util_sizeprices },
  { name => "util_tags",         sets => [qw(quick util)],       test => \&test_util_tags },
  { name => "util_htmlesc",      sets => [qw(quick util)],       test => \&test_util_htmlesc },
  { name => "dateutil_effday",   sets => [qw(quick dateutil)],   test => \&test_dateutil_effday },
  { name => "dateutil_reldate",  sets => [qw(quick dateutil)],   test => \&test_dateutil_reldate },
  { name => "dateutil_normalize",sets => [qw(quick dateutil)],   test => \&test_dateutil_normalize },
  { name => "dateutil_misc",     sets => [qw(quick dateutil)],   test => \&test_dateutil_misc },
  { name => "geo_haversine",     sets => [qw(quick geo)],        test => \&test_geo_haversine },
  { name => "comments_rating",   sets => [qw(quick comments)],   test => \&test_comments_rating },
  { name => "glasses_isempty",   sets => [qw(quick glasses)],    test => \&test_glasses_isempty },
  { name => "styles_short",      sets => [qw(quick styles)],     test => \&test_styles_short },
);
```

All tagged `quick` — unit tests are instant, no reason to exclude any.

### Selector behavior

Same as test-http.pl:
- No args → `quick` tests (all of them, since all are quick)
- `all` → all tests (same as quick for unit tests)
- Module name (e.g. `util`, `dateutil`) → tests matching that module
- Individual test name (e.g. `util_trim`) → exactly that test
- Unknown selector → print available selectors, exit 1

### Files touched
- `tools/test-unit.pl` (new, ~350 lines)

## Task 2: Create `tools/test-all.sh`

Thin wrapper that runs both test scripts with forwarded arguments.

```bash
#!/bin/bash
# Run all test suites. Exit non-zero if any suite fails.
# Examples:
#   ./tools/test-all.sh          # quick tests from both suites
#   ./tools/test-all.sh all      # all tests from both suites

fail=0
perl tools/test-unit.pl "$@" || fail=1
perl tools/test-http.pl "$@" || fail=1
exit $fail
```

Unknown selectors (e.g. `filters` passed to test-unit.pl) cause test-unit.pl
to print a warning and exit 1. This means `./tools/test-all.sh filters` would
fail on the unit side. Two options:

**Option A (simpler)**: test-unit.pl exits 1 for unknown selectors (current
behavior, same as test-http.pl). The wrapper is only meant for `""` or `all`.
For module-specific runs, use the individual scripts directly.

**Option B**: test-unit.pl silently skips unknown selectors (exit 0). Then
`./tools/test-all.sh filters` works — unit side skips, HTTP side runs filters.

**Recommendation**: Option B. It's more forgiving and matches the user's
expectation that `test-all.sh` "just works."

### Behavior
- `./tools/test-all.sh` — both scripts run quick tests (default)
- `./tools/test-all.sh all` — both scripts run all tests
- `./tools/test-all.sh filters` — test-unit.pl skips (no match), test-http.pl
  runs filter tests

### Files touched
- `tools/test-all.sh` (new, ~5 lines, chmod +x)

## Verification

1. `perl -c tools/test-unit.pl` — syntax check
2. `perl tools/test-unit.pl` — all unit tests pass (instant, no server needed)
3. `perl tools/test-unit.pl -v` — verbose output shows each assertion
4. `perl tools/test-unit.pl util` — only util tests
5. `./tools/test-all.sh` — both suites pass (needs running dev server for HTTP part)
6. `./tools/test-all.sh all` — full run of both suites
