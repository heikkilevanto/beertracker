# Test plan: HTTP test system + non-200 error handling

## Summary
Build a standalone Perl test script, `tools/test-http.pl`, that exercises the live
dev site over HTTP (the curl loop idea) with real assertions: GET smoke + content
checks, POST round-trips with self-cleanup, CopyProdData pre/post for data
isolation, and a debug.log scan for DB errors.

The **first task** is to make GET error handling return a non-200 HTTP status,
so that HTTP status becomes a reliable success signal for the tests.

## Task 1 (done): GET errors return HTTP 500 instead of 200

### Why
GET handler errors used to be caught in `index.fcgi:436` and the page still
finished with HTTP 200, with the error text embedded in the body. This forced
any test system to scan the body for `ERROR` / `DB ERROR` markers. Making errors
return 500 is HTTP-correct and lets `curl -w "%{http_code}"` detect failures.

POST errors already yield non-200 (the worker dies by design at
`index.fcgi:341` to invalidate caches) — that path is untouched.

### Change (index.fcgi only)
The whole GET response (header + body) is now buffered; `htmlhead()` moved into
the eval, and on error the buffer is discarded and a real HTTP 500 page is sent:

- `htmlhead($c);` was removed from before the eval and is now the first line
  inside the eval, so its header+head go into the `$body` buffer.
- `my $get_error = $@;` captures the error; on error the branch logs it,
  disconnects `$dbh_ro`, and emits a minimal 500 page (no-cache headers, error
  text in a `<pre>`). The partial buffer (incl. unclosed content-wrapper) is
  discarded.
- On success: `print $body;` then `htmlfooter($c);` as before.
- `log_request_duration` now appends ` ERROR` to the label when the GET failed.
- `$log->flush` runs in both paths.

### Verified safe
- No module prints its own `redirect()`/`header()` during GET body generation
  (all redirects use `$c->{redirect_url}`, consumed only in the POST path;
  the only direct `->redirect` is `superuser::copyproddata`, which runs before
  the eval).
- Nothing writes to STDOUT bypassing the buffer (only `index.fcgi:43` sets
  `binmode STDOUT` at startup).
- `migrate::startup_check` just sets `$c->{op} = 'migrate'` (no output), so it
  is unaffected.

### Side effects
- Browser receives nothing until the page finishes rendering (delayed part is
  only the ~few-KB head; body was already buffered). Negligible.
- Errors show a 500 page instead of an inline dump; text still in the 500 body
  and in `debug.log`.
- Auth cookie sent only on success.
- POST behavior and cache-invalidation design unchanged.

### Verify (done)
- `perl -c code/index.fcgi` — OK.
- `o=Comment&e=999999999` (bogus id) → **500** with "Comment 999999999 not
  found" in a `<pre>`; no partial page.
- Sweep of all ops (`Graph, Board, Full, Years, Months, short, DataStats,
  Ratings, About, Export, Comments, Location, Person, Brew, Photos, Debug`,
  default and bogus op) → all 200, no error markers in body.
- `debug.log` shows `GET error: ...` plus `GET o=Comment&e=999999999 ERROR`.
- Footer diagnostic comment still present on success pages.

## Task 2: Test script skeleton `tools/test-http.pl`

Standalone Perl script, run from the repo root (`perl tools/test-http.pl`),
modelled on `tools/test-login.pl`. Uses LWP::UserAgent + HTTP::Cookies
(already project dependencies). No `prove`/`Test::More` needed.

### Config & safety
- `$BASE_URL` default `http://127.0.0.1/beertracker-dev/code/index.fcgi`,
  overridable via `--url=`.
- Flags: `--no-post` (GET-only mode), `--verbose`.
- **Post-guard**: POST tests abort unless the URL contains `-dev` *and* the
  script runs from a `-dev` checkout. CopyProdData is inherently dev-only
  (`superuser.pm:34`).

### HTTP helper
`req($method, $url, \%form)` via LWP with a cookie jar, 30s timeout, redirects
**not** auto-followed so the `Location` header can be asserted; returns
`(status, headers, body)`.

### Assertion helpers
- `assert($cond, $msg)` with pass/fail counters; summary + exit code 0/1.
- `no_errors_in($body)`: body lacks `ERROR`, `DB ERROR`, `Stack Trace`,
  `Undefined subroutine`, `Can't locate`, `Use of uninitialized` (case-insens.).

### DB helper
Read-only DBI connection to `beerdata/beertracker.db` to (a) pick real
Brew/Location/Glass ids for POSTs and (b) verify/clean up test rows.

### Test selection via command-line argument
`tools/test-http.pl` takes one optional argument that selects what to run:

- **(no argument)** — the default: the quick tests (all GET smoke/content
  checks; nothing that writes data).
- `all` — everything, including POST round-trips and the CopyProdData
  pre/post sync (needs the dev-only guard).
- `modulename` — all tests that invoke that module (e.g. `graph`, `brews`,
  `comments`). A page test counts if any of its exercised modules/ops matches.
- `testname` — run exactly that one test.

The selector argument can also name a **more abstract test set**, not tied to a
single module — e.g. `posts` (all POST round-trips), `lists` (all list/edit
pages: Brew, Location, Person, Photos, Comment), `stats` (Years/Months/short/
DataStats/Ratings). Each test can carry one or more such group tags. A selector
matches against group tags, module names, and full test names alike.

Structure: each test is its own `sub test_Xxx($c)` (with the test name derived
from the sub name), and a driving table registers them. All selection flags live
in a single `sets` list — module/op names, abstract group tags, and the
special `quick` tag (tests included in the default run) — so there is no
separate flags column:

```perl
# name => sub, sets => [selectors this test matches; "quick" = default run]
my @TESTS = (
  { name => "graph",           sets => [qw(quick lists graph glasses mainlist)], test => \&test_graph },
  { name => "roundtrip_glass", sets => [qw(posts postglass glasses)],            test => \&test_roundtrip_glass },
  ...
);
```

Selection logic: if no arg → tests whose `sets` contains `quick`; `all` →
everything; otherwise match the arg case-insensitively against each test's
`name` (exact) and against each entry in `sets` (substring). Unknown arg →
list the available names/selectors and exit non-zero.

Rationale: the driving table keeps selection simple and declarative, and makes
it easy to add a test (new sub + one table row). Slower/destructive tests simply
omit the `quick` tag in `sets` so the default run stays fast and safe.
"Module" selectors mostly hit page-level tests that render more than one module
(e.g. Graph also uses glasses + mainlist) — acceptable: the filter is "tests
that touch this module", not "only this module".

## Task 3: GET smoke + content tests

- Ops: `Graph, Board, Full, Years, Months, short, DataStats, Ratings, About,
  Export, Comment, Location, Person, Brew, Photos, Debug`, plus `o=` (default)
  and bogus `o=Bogus` (must fall through to Graph). Skip `GitStatus/GitPull/
  CopyProdData` (side effects).
- Assert: status 200 (now a real success signal), `<!DOCTYPE html>`, menu
  markup, `no_errors_in`.
- Per-page content marker: About→"Beertracker", Debug→module table,
  Graph/Board→`id='mainform'`, Full→glass rows, stats pages→tables, etc.
- Variants with real ids (`o=Comment&e=…`, `o=Graph&e=…`, `o=Brew&e=…`),
  a `q=` filter (`o=Full&q=IPA`), and static assets (`static/base.css`, JS)
  → 200.

## Task 4: Data sync + POST round-trips

- Pre- and post-run: GET `o=CopyProdData` (restores a fresh prod copy, wiping
  test residue; matches normal dev workflow). Record `debug.log` size before,
  scan the appended portion for new `DB ERROR`/`ERROR` lines after.
- Unique test marker `TST<epoch>` in name/note; cleanup via web delete where
  supported, else direct DBI, in an `END`/trap block so each test is
  individually re-runnable.
- Glass: `submit=Record` with real Location/Brew/`selbrewtype`, date/time,
  `vol=33`, `alc`, `pr=50`, `note=TST…` → expect 302; verify row; then
  update (`Save`) and delete (`Del`).
- Brew (`e=new`, `Name`, `BrewType`, Create), Location (`e=new`, `Name`,
  `LocType`), Comment (`commentedit=1`, `glass`, `rating`, `comment`),
  Person (`e=new`, `Name`).
- Delete test records in FK order (comments before their glass).

## Dev footer diagnostics: HTML comments for the tests to grep

Already implemented. The idea is that each rendered dev page carries useful
debug info (timings, counter values) as **HTML comments**, invisible in the
browser but trivially greppable by the test script. `htmlfooter($c)`
(index.fcgi) appends such a comment just before `</body>`, only when
`$devversion`:

```
<!-- beertracker-test elapsed=10ms queries=3 cache_hits=1 cache_misses=1 cache_sets=1 cache_entries=1 -->
```

- `elapsed` = server-side render time (from `$c->{request_start}`, set via
  `Time::HiRes` in the FastCGI loop).
- `queries` = per-request SQL count, incremented in `db::logquery` (counted even
  when SQL logging is disabled; misses direct `prepare` calls in getrecord/
  findrecord — close enough as a diagnostic).
- `cache_hits/misses/sets` = per-request counters in `cache::get`/`set`.
- `cache_entries` = current size of the in-process cache hash.
- Gated on `$devversion`, so production pages are untouched.
- The test script greps the body for `beertracker-test` to assert on timings and
  counts. Useful for spotting performance regressions (e.g. a page that stops
  hitting the cache). Any further per-page diagnostics should be added here as
  key=value pairs, so the tests always have a single, greppable line to parse.

Verified: About → 3 queries; first Graph load → 25 queries/869ms, second →
1 query/9ms with 4 cache hits (confirms the cache diagnostic reflects reality).

## Considered, deferred: `&testing=1` URL parameter (not needed yet)

We considered having the test script append `&testing=1` to every request so
the app could detect a test run (open a different database, isolate the cache,
extra diagnostics). Decided it is **not needed yet**:

- The footer HTML comments (above) already provide the per-request diagnostics
  with no parameter at all.
- Data isolation is handled by CopyProdData-before/after, which matches the
  normal dev workflow.
- A `testing=1` switch would require dev-only gating plus care with the
  persistent dbh, cache, and graph files (see below).

The separate-test-database idea may be worth revisiting in a **future version**
if running against the live dev DB becomes a problem:

1. **Separate test database** — `testing=1` opens `beerdata/beertracker-test.db`
   (auto-copied from the real dev DB when missing/older) instead of the live
   DB, giving clean isolation without the CopyProdData-before/after dance.

### Constraints if we do it
- Honor `testing=1` **only when `$devversion` is set**; ignore it on the
  production site (same gating as CopyProdData / Debug).
- **Cache**: give a testing request a fresh `$c->{cache} = {}` hash so test
  renders never read or pollute the real process cache — no per-module key
  changes (cache.pm uses `$c->{cache}` directly).
- **Graph files**: graph.pm derives both the PNG filename and the `<img src>`
  from `$c->{datadir}` (graph.pm:362-374, incl. the cached-file check). A
  testing request with a separate datadir (`beerdata/test/`) gets its own
  graphs and never clobbers real dev PNGs.
- **DB connection**: testing requests must open a fresh connection to the test
  DB and skip the persistent `$dbh_ro` reuse (index.fcgi:355).

### Files touched (if revisited)
- `index.fcgi`: detect param, build context (`$c->{testing}`, test datadir,
  fresh cache, skip `$dbh_ro` reuse); append testinfo in `htmlfooter`.
- `db.pm`: `open_db` targets the test file when testing; auto-copy real DB;
  per-request `$c->{query_count}` counter.
- `cache.pm`: per-request hits/misses when testing.
- Test DB copy inherits the "pending migrations → redirect to `o=migrate`"
  behaviour; the script already plans to detect and report that.

## Notes / risks
- `code/` changes: Task 1 (index.fcgi error status) plus the footer diagnostic
  in index.fcgi/db.pm/cache.pm; the rest is additive tooling.
- The `&testing=1` separate-DB idea is deferred (above); with the current
  CopyProdData approach, the dev DB after a run equals a prod copy (by design).
- If dev code is ahead of prod (new migrations), the first GET after
  CopyProdData redirects to `o=migrate`; detect and report "run migrations
  first" instead of failing confusingly.
- Never intentionally trigger POST errors in tests (kills the worker by design).

## Execution order
1. Task 1 (HTTP 500 on GET errors) — small, enables status-based checks.
2. Task 2 skeleton: config, HTTP/assertion/DB helpers, GET smoke loop.
3. Task 3: content markers, id-param variants, static assets.
4. Task 4: CopyProdData pre/post, POST round-trips, cleanup, log scan.
5. Polish: `--verbose`, `perl -c`, verify prod-URL refusal.
