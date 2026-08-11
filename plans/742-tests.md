# Test plan: HTTP test system + non-200 error handling

## Summary
Build a standalone Perl test script, `tools/test-http.pl`, that exercises the live
dev site over HTTP (the curl loop idea) with real assertions: GET smoke + content
checks, POST round-trips with self-cleanup, CopyProdData pre/post for data
isolation, and a debug.log scan for DB errors.

The **first task** is to make GET error handling return a non-200 HTTP status,
so that HTTP status becomes a reliable success signal for the tests.

## Task 1 (first): GET errors return HTTP 500 instead of 200

### Why
Today GET handler errors are caught in `index.fcgi:436` and the page still
finishes with HTTP 200, with the error text embedded in the body. This forces
any test system to scan the body for `ERROR` / `DB ERROR` markers. Making errors
return 500 is HTTP-correct and lets `curl -w "%{http_code}"` detect failures.

POST errors already yield non-200 (the worker dies by design at
`index.fcgi:341` to invalidate caches) — leave that path untouched.

### Change (index.fcgi only)
The whole GET body is already buffered in `$body` (`index.fcgi:367-442`); only
`htmlhead()` sends the 200 header, and it runs before the eval. Defer it:

- Remove the `htmlhead($c);` call at `index.fcgi:365`.
- In the `if ($@)` branch: log, disconnect `$dbh_ro`, and replace `$body` with a
  small 500 error page (keep the error text in a `<pre>`, as now).
- After the eval, only if there was no error: `htmlhead($c);` then `print $body;`
  then `htmlfooter();`. On error: emit the 500 page (with `no-cache` headers)
  and skip the wrapper/`htmlfooter` (the partial body already contains an
  unclosed `<div class='content-wrapper'>`).
- Keep `log_request_duration` and `$log->flush` in both paths.

### Verified safe
- No module prints its own `redirect()`/`header()` during GET body generation
  (all redirects use `$c->{redirect_url}`, consumed only in the POST path;
  the only direct `->redirect` is `superuser::copyproddata`, which runs before
  htmlhead).
- Nothing writes to STDOUT bypassing the buffer (only `index.fcgi:43` sets
  `binmode STDOUT` at startup).

### Side effects
- Browser receives nothing until the page finishes rendering (delayed part is
  only the ~few-KB head; body was already buffered). Negligible.
- Errors show a 500 page instead of an inline dump; text still in the 500 body
  and in `debug.log`.
- Auth cookie sent only on success.
- POST behavior and cache-invalidation design unchanged.

### Verify
- `perl -c code/index.fcgi`.
- Manually trigger a GET error (e.g. a bad `e=` id) → HTTP 500, no partial page.
- Normal pages still HTTP 200 with full content.
- `touch code/VERSION.pm` (separate step) to reload the FCGI script.

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

## Open item: `&testing=1` URL parameter (under consideration)

The test script could append `&testing=1` to every request, letting the app
detect a test run and adapt. Two ideas, not yet decided:

1. **Separate test database** — `testing=1` opens `beerdata/beertracker-test.db`
   (auto-copied from the real dev DB when missing/older) instead of the live
   DB, giving clean isolation without the CopyProdData-before/after dance.
2. **Footer diagnostics** — `testing=1` appends a small `#testinfo` div (elapsed
   ms, SQL count, cache hits/misses, version) that the test script can assert on.

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

### Files touched (if implemented)
- `index.fcgi`: detect param, build context (`$c->{testing}`, test datadir,
  fresh cache, skip `$dbh_ro` reuse); append testinfo in `htmlfooter`.
- `db.pm`: `open_db` targets the test file when testing; auto-copy real DB;
  per-request `$c->{query_count}` counter.
- `cache.pm`: per-request hits/misses when testing.
- Test DB copy inherits the "pending migrations → redirect to `o=migrate`"
  behaviour; the script already plans to detect and report that.

## Notes / risks
- No `code/` changes except Task 1 (index.fcgi); the rest is additive tooling.
- If the `&testing=1` separate-DB idea is adopted, dev DB after a run is
  untouched; otherwise (CopyProdData approach) it equals a prod copy (by design).
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
