# Code Quality Audit Plan

## Scope
All modules in `code/` — ~30 Perl files checked for adherence to BeerTracker coding guidelines (AGENTS.md), potential bugs, dead code, and refactoring opportunities.

## Findings (Prioritized)

### P0: FastCGI error handling — comment added (not a bug)
**File:** `index.fcgi:332-336`

POST handlers are wrapped in `eval { ... }`. On error, `util::error()` is called outside the try/catch. `util::error()` does `die`, which in a FastCGI loop is **uncaught** and kills the worker process.

**Decision:** This is **intentional** — killing the FCGI worker ensures all in-process caches (Cache.pm) are invalidated so the next request starts clean. No code change to the `die` behavior.

**Fix applied:** Added explanatory comment. Also wrapped `rollback` in `eval {}` as a best-effort guard (rollback on a dead DBH could itself throw, though never observed in practice).



### P1: `?:` ternary operators — all replaced (done)
~75 Perl ternary operators across 20+ files. JavaScript ternaries (inside string literals) are **out of scope**. All Perl ternaries have been replaced using the patterns below; only SQL `?`, regex `?:`, and JS ternaries remain.

**Replacement patterns** (per user preference):
- Category A (return): `if (cond) { return v1; } return v2;`
- Category B (my assignment): `my $x = v2; $x = v1 if (cond);` — where v2 is the more common/default case
- Category C (non-my assignment): `$x = v2; $x = v1 if (cond);`
- Category D (inline/nested): extract to a `my` variable first, then apply A/B/C

**Category A: Return-based (`return $cond ? v1 : v2;`)** — replace with `if (cond) { return v1 } return v2;`
- `beerboard.pm:175` — `return $minutes <= 0 ? "less than 1m" : "${minutes}m";`
- `login.pm:148` — `return $file->lookup_user($username) ? 1 : undef;`
- `login.pm:205` — `return $user->check_password($password) ? 1 : undef;`
- `migrate.pm:145` — `return defined($v) ? int($v) : 0;`

**Category B: Simple `my $x = cond ? v1 : v2;`** — ~60 instances:
- `beerboard.pm:75,127,185,392,489,490,491`
- `brews.pm:193,614,615,617,618,698`
- `comments.pm:305,328,329,358,481,540,596,625`
- `db.pm:234`
- `export.pm:220,228,256`
- `geo.pm:77`
- `glasses.pm:57`
- `inputs.pm:38,39,40,42,85,86,87,277,284,287,298,304,308,315,319,323,327,372,373,397,436`
- `listrecords.pm:246,428,472,565,830,856,875`
- `locations.pm:583,584,585,586`
- `mainlist.pm:408,613`
- `monthstat.pm:95,201,214,257,289,290,291,397`
- `persons.pm:162`
- `photos.pm:70,180,264,276,559`
- `postglass.pm:349`
- `ratestats.pm:62,175,285,286,287,442`
- `scrapeboard.pm:58`
- `superuser.pm:118,145,208,233`
- `taps.pm:63`
- `util.pm:331`
- `yearstat.pm:153,189,236,393`

**Category C: Non-`my` assignments to existing vars:**
- `listrecords.pm:45`
- `monthstat.pm:268,269,271,280,281,282,283`

**Category D: Inline/nested — extract first, then apply pattern:**
- `beerboard.pm:158` — nested ternary (extract inner)
- `beerboard.pm:518,529` — nested inside `uri_escape_utf8()` call
- `comments.pm:528` — inside `print` concatenation
- `db.pm:42` — multi-line ternary for DSN
- `db.pm:153` — ternary inside `map { ... }` closure
- `listrecords.pm:75` — nested ternary
- `listrecords.pm:761-762` — ternary chain → if/elsif
- `listrecords.pm:156,176,178,186` — inside function calls/expressions
- `mainlist.pm:354-355` — multi-line ternary chain → if/elsif/else
- `monthstat.pm:212` — nested ternary
- `monthstat.pm:292,399` — inside string concat
- `monthstat.pm:401` — multi-line ternary
- `ratestats.pm:447` — inside string concat
- `util.pm:64` — ternary inside `map { ... }` closure
- `yearstat.pm:37-39` — multi-line ternary for SQL expression

### P1: SQL keyword capitalization inconsistency
**Files:** `db.pm`, `glasses.pm`, `brews.pm`, `locations.pm`, `comments.pm`, many others

Guidelines say use uppercase `SELECT`, `INSERT`, `UPDATE`. Found mixed case:
- `db.pm:84-88`: `select ... from ... where` (lowercase) with `WHERE` later in same query.
- Many inline queries in other modules use lowercase.

**Fix approach:** Standardize on uppercase SQL keywords across all modules. Can be done with a project-wide search/sed pass or editor macro.

### P2: Dead code (never called)
- **`comments::ratingline`** — `comments.pm:20-26`
- **`util::locdesc`** — `util.pm:562-574`
- **`postglass::curprice`** — `postglass.pm:405-416`, plus dead `%currency` hash at `postglass.pm:396-402`
- **Unused imports in `index.fcgi`**: `File::Copy`, `JSON`, `URI::Escape`

**Fix approach:** Remove dead functions, remove unused module imports. Low-risk cleanup.

### P2: `graph::addsums` confusing/buggy scalar comparison
**File:** `graph.pm:67`

Current: `if ( scalar(@{ $g->{last30} } > 30 ) )` — the `>` compares the array deref to 30 in boolean context, returning 0/1, then `scalar()` wraps that. **Result is technically correct** but extremely fragile and clearly not the author's intent.

**Fix:** Change to `if ( scalar(@{ $g->{last30} }) > 30 )`.

### P2: Not using existing helpers (`db.pm`, `util.pm`)
**Files:** comments, photos, scrapeboard, postglass, util

- **7 direct `$c->{dbh}->last_insert_id(...)`** calls bypass `db::insertrecord()`:
  - `comments.pm:660,690`
  - `photos.pm:237`
  - `scrapeboard.pm:176,197`
  - `postglass.pm:184`
- **`$c->{cgi}->param()`** direct access in `postglass.pm:62` instead of `util::param`.
- **`util::unit()`** not used in `yearstat.pm` and `monthstat.pm` where similar formatting exists.
- Raw `$c->{dbh}->do("INSERT ...")` instead of `db::insertrecord` in several places.

**Fix approach:** Replace direct DBI calls with `db::insertrecord` and `db::findrecord` helpers where applicable, replace `param` calls with `util::param`, use `util::unit` for unit formatting.

### P3: Code duplication
- **Glass effdate query** (min timestamp) duplicated in `mainlist.pm:596-598` and `comments.pm:701-703`.
- **"Time ago" display** (strftime-based relative time) duplicated across `beerboard.pm`, `yearstat.pm`, `monthstat.pm`, `tap_beers.pm`, `glasses.pm` — `util::reldate` exists but is not used everywhere.
- **Size/price extraction parsing** duplicated between `taps.pm` and `scrapeboard.pm` — could be a shared helper in `util.pm`.
- **`max(timestamp)` + datetime display pattern** in `brews.pm`, `locations.pm`, `persons.pm`, `mainlist.pm`.

**Fix approach:** Extract shared queries and formatting into helper functions in `db.pm` and `util.pm`.

### P3: Missing `use open ':encoding(UTF-8)'` (done)
**Files:** `db.pm`, `graph.pm`, `stats.pm`, `debug.pm` (note: `error.pm` does not exist)

**Fix applied:** Added `use open ':encoding(UTF-8)'` to all 4 modules that do file I/O. (28 other modules also lack it, but they don't open files directly.)

### P3: `uri_escape` vs `uri_escape_utf8` inconsistency (done)
**File:** `yearstat.pm:63` uses `uri_escape` (plain), while lines 327 and 333 use `uri_escape_utf8`. Guidelines say use `uri_escape_utf8`.

**Fix approach:** Change `uri_escape` to `uri_escape_utf8` in `yearstat.pm:63`.

### P3: Misleading closing comment
**File:** `db.pm:317` — `findrecord` function closes with `} # getrecord` (copy-paste error).

### P3: Missing closing function comments (done)
Added `} # function_name` closing comments to `db.pm` (9 functions) and `graph.pm` (3 functions). Also fixed misleading `} # getrecord` → `} # findrecord` on `db.pm:317`.

---

## Execution Order (recommended)

| Order | Task | Effort | Risk |
|------|------|--------|------|
| 1 | Fix `graph::addsums` scalar comparison (P2 — **done**) | 5 min | Low |
| 2 | Remove dead code — `ratingline` and `locdesc` (P2 — **done**); keep `curprice` & index.fcgi imports | 15 min | Low |
| 3 | Fix `uri_escape` → `uri_escape_utf8` in `yearstat.pm` (P3 — **done**) | 5 min | Low |
| 4 | Add `use open ':encoding(UTF-8)'` + fix closing comments (P3 — **done**) | 10 min | Low |
| 5 | Replace `?:` ternary operators — Category A first (P1 — **done**) | 60-90 min | Medium |
| 7 | Standardize SQL keyword case (P1) | 60-120 min | Low |
| 8 | Replace direct DBI calls with helpers (P2) | 60-90 min | Medium |
| 9 | Extract duplicated queries/formatting (P3) | 90-120 min | Medium |
| 10 | Add comments to FastCGI error handling (P0 — done) | 5 min | Low |

## Notes
- No automated tests exist. Must verify manually under Apache after each change.
- After editing code and `perl -c` check, touch `code/VERSION.pm` to trigger FCGI reload.
- The P0 error-handling fix should be done **last** (or very carefully) since it touches the central dispatch path.
