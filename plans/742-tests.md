# Test plan: HTTP test system + non-200 error handling

## Summary
Build a standalone Perl test script, `tools/test-http.pl`, that exercises the live
dev site over HTTP (the curl loop idea) with real assertions: GET smoke + content
checks, edit-page variants driven by **record IDs harvested from the rendered
list pages**, CopyProdData pre/post for data isolation, and a debug.log scan for
DB errors.

Ordering is deliberate: **all GET-based testing comes first and never touches the
database**, then data sync, and only last come the POST round-trips (dev-guarded).
The test script itself does **not** open the dev DB — real record IDs come from
parsing the links the app itself renders, so the tests exercise the exact URLs a
user sees.

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
- The default run is GET-only. POST tests only run with an explicit selector
  (below) *and* pass the **dev post-guard**: they abort unless the URL contains
  `-dev` *and* the script runs from a `-dev` checkout. CopyProdData is
  inherently dev-only (`superuser.pm:34`).
- `--no-post` flag to force GET-only even when a POST selector was given.

### HTTP helper
`req($method, $url, \%form)` via LWP with a cookie jar, 30s timeout, redirects
**not** auto-followed so the `Location` header can be asserted; returns
`(status, headers, body)`. POST is supported in the helper from the start
(needed late, harmless early), but no POST *tests* exist until Task 6.

For GET requests, a `302` with an empty body and a `Location` header means the
fcgi script reloaded itself (task-1 change; happens once right after a `git
pull` when `VERSION.pm`/the script mtime changed). `req` absorbs that one-time
bounce by retrying the GET once, so the first test isn't spuriously flagged;
POST `Location` headers are still returned verbatim for round-trip assertions.

### Record-ID harvesting from HTML (no DB access)
The test script never opens the database. Instead, the list pages render the
edit/record links themselves, and those carry the ids:

- Brew list → `o=Brew&e=<id>`; Location list → `o=Location&e=<id>`;
  Person list → `o=Person&e=<id>`; Comments list → `o=Comment&e=<id>`;
  main list (Full/Graph) → `o=Full&e=<glassid>`.
- Helpers parse a fetched body and return the distinct ids in page order:
  - `harvest_ids($body, $op)` — all distinct ids for that op.
  - `first_id($body, $op)` — the first one, for edit-page variants.
- The regexes are small and kept next to the tests that use them, so they stay
  visible and easy to fix if a link format changes. Empty results (empty dev
  DB) make the test skip cleanly instead of failing.

### Assertion helpers
- `assert($cond, $msg)` with pass/fail counters; summary + exit code 0/1.
- `no_errors_in($body)`: body lacks crash markers — `DB ERROR`, `Stack Trace`,
  `Undefined subroutine`, `Can't locate`, `Use of uninitialized`
  (case-insens.). Note: the bare word `ERROR` is deliberately **not** a marker,
  because real user data (e.g. a comment "Coding Error") legitimately contains
  it; the real error signal is now the HTTP 500 from Task 1, asserted via status.

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

## Task 3 (done): GET smoke + content tests

- Ops: `Graph, Board, Full, Years, Months, short, DataStats, Ratings, About,
  Export, Comment, Location, Person, Brew, Photos, Debug`, plus `o=` (default)
  and bogus `o=Bogus` (must fall through to Graph). Skip `GitStatus/GitPull/
  CopyProdData` (side effects) and `migrate`.
- Assert: status 200 (now a real success signal), `<!DOCTYPE html>`, menu
  markup, `no_errors_in`.
- Per-page content marker: About→"Beertracker", Debug→"Grand total",
  Graph/Board/Full→`id='mainform'`, Full→"Older records", Years→"Year <b>",
  Months→"Show drinks", short→"Daily stats", DataStats→"Data file stats",
  Ratings→"Ratings statistics", Export→"Export data", Comment→"Comments by",
  Location/Person/Brew/Photos→their listrecords title.
- No record-id variants here — those belong to Task 4 where harvesting lives.

### Verify (done)
- `perl -c tools/test-http.pl` — OK.
- Default run: 18 tests / 111 assertions, all PASS against the live dev site.
- Selectors verified: `stats` (5 tests), `lists` (5), `brew` (1), unknown
  selector → lists available names and exits 1.
- Also removed the bare `ERROR` from `no_errors_in` markers (plan Task 2 spec
  says it is deliberately not a marker; real user data legitimately contains
  it) and added a menu-markup check (`id='menu-toggle'`) to `assert_page_ok`.
- Months marker note: the default `o=Months` page is drinks mode and renders
  the toggle "Show money spent", not "Show drinks". `test_months` therefore
  asserts "Show money spent" on the default page and fetches `o=Months&s=money`
  to assert the "Show drinks" link from the plan.

## Task 4: edit-page variants, filters, static assets (all DB-less)

Now the harvest helpers earn their keep, driven by ids remembered from the
list pages:

- For each list page from Task 3, harvest a real id and GET the matching edit
  page, asserting the edit-form markers:
  - `o=Brew&e=<id>` → "Editing Brew", `o=Location&e=<id>` → "Editing Location",
    `o=Person&e=<id>` → "Editing Person", `o=Comment&e=<id>` → "Edit comment",
    `o=Full&e=<glassid>` → the edit-glass page (input form + comments + photos).
  - New-record forms: `o=Brew&e=new`, `o=Location&e=new`, `o=Person&e=new`,
    and `o=Comment&e=new&glass=<id>` (new-comment prefill from a glass).
  - `o=Graph&e=<glassid>` — editing via the Graph page.
- `q=` filter variants: `o=Full&q=IPA` and `o=Board&q=…` → assert "Filter:<b>";
  `o=Years&q=<year>` picked from the Years page's "Year <b>" links.
- Static assets: `static/base.css`, `static/menu.js`, plus `static/beer-dev.png`
  → 200 (direct HTTP, not the fcgi URL).
- A list page that yields no ids (empty/fresh dev DB) makes its variant tests
  skip, printing "skipped", rather than failing.

## Task 5: Data sync + debug.log scan (GET-only)

- Pre- and post-run: GET `o=CopyProdData` (restores a fresh prod copy, wiping
  test residue; matches normal dev workflow). Record `debug.log` size before,
  scan the appended portion for new `DB ERROR`/`ERROR`/`Use of uninitialized`
  lines after — fail if any.
- If dev code is ahead of prod (new migrations), the first GET after
  CopyProdData redirects to `o=migrate`; detect and report "run migrations
  first" instead of failing confusingly.
- Wrap the run so a mid-run failure (e.g. a POST killing the worker) still
  triggers the post-CopyProdData sync and log scan. In the default run this
  task does the pre/post sync *once around the whole run*, not per test.
- No DB access here either: the test script only reads the log file and the
  HTTP responses. This sync also doubles as the garbage collector for any
  record the POST round-trips left behind (which is why POST tests can afford
  to be sloppy about cleanup).

## Task 6: POST round-trips (much later, dev-guarded)

Each test = a `sub` that creates a record, verifies it, updates it, and deletes
it — **through the web only**, still without opening the DB. Unique test marker
`TST<epoch>` in name/note so rows are findable (and greppable) in pages.

- Every POST asserts a 302 with a `Location` header (the app's standard
  POST response; `index.fcgi:347`).
- **Glass**: POST with `submit=Record`, real `Location`/`Brew`/`selbrewtype`
  (ids harvested in Task 4), `date`/`time`, `vol=33`, `alc`, `pr=50`,
  `note=TST…`. Follow the redirect, harvest the new glass id from the main list
  (find the `TST…` note, take the nearest `o=Full&e=<id>` link), then update
  (`submit=Save`) and delete (`submit=Del`), verifying the row appears/disappears
  in the page.
- **Brew**: POST `o=Brew&e=new`, `Name=TST…`, `BrewType=Beer`,
  `submit=Insert Brew`. Verify the name + harvested id on the Brew list page.
  Brews have no web delete; rely on the post-run CopyProdData sync to remove it.
- **Location**: POST `o=Location&e=new`, `Name=TST…`, `LocType=Bar`,
  `submit=Insert Location`; verify on the Location list page (same cleanup note).
- **Person**: POST `o=Person&e=new`, `Name=TST…`, `submit=Insert Person`;
  verify on the Person list page (same cleanup note).
- **Comment**: POST `commentedit=1`, `glass=<id>`, `rating=7`,
  `comment=TST…`, `commenttype=brew`, `submit=Add`; verify on the glass page;
  delete via `submit=Del&comment_id=<id>`.
- Cleanup order: comments before their glass; everything else is left to the
  post-run CopyProdData sync. Comment/glass tests that are individually
  re-runnable clean up after themselves.
- POST tests are **not** in the `quick` set; they require `all` or a `posts`/
  module selector, and the dev post-guard.

## Deferred: DBI access from the test script (avoid unless needed)

The current design deliberately avoids a DBI connection to
`beerdata/beertracker.db`. Ids come from the rendered pages and residue is wiped
by CopyProdData pre/post, so reads aren't needed. If we later want:

- verification of a delete for records with no web delete (Brew/Location/
  Person), or
- fully self-contained POST tests without the CopyProdData dance,

then a read-only DBI helper can be added behind a `--db` flag (connect
`dbi:SQLite:uri=file:...?mode=ro` to pick ids / verify rows / clean leftovers).
Keep it optional: the default and `quick` suites must stay DB-free.

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
  in index.fcgi/db.pm/cache.pm; the rest is additive tooling. Since then the
  focus is the test script itself.
- The test script **never opens the dev DB**; ids come from the HTML the app
  renders. This keeps the tests honest (they exercise real user-visible links)
  and removes any permission/locking/coupling concerns with the running dev DB.
- The `&testing=1` separate-DB idea is deferred (above); with the current
  CopyProdData approach, the dev DB after a run equals a prod copy (by design).
- If dev code is ahead of prod (new migrations), the first GET after
  CopyProdData redirects to `o=migrate`; detect and report "run migrations
  first" instead of failing confusingly.
- Never intentionally trigger POST errors in tests (kills the worker by design).

## Execution order
1. Task 1 (HTTP 500 on GET errors) — **done**; enables status-based checks.
2. Task 2 skeleton: config, HTTP helper, HTML-id harvest helpers, assertion
   helpers, GET smoke loop, selector plumbing.  **done**
3. Task 3: GET smoke for all ops (no DB, no id variants).
4. Task 4: harvested-id edit-page variants, `q=` filters, static assets
   (still GET-only, still DB-free).
5. Task 5: CopyProdData pre/post, debug.log scan, migration detection.
6. Task 6 (last): POST round-trips — dev-guarded, cleanup via web + post-run
   CopyProdData sync.
7. Polish: `--no-post`, `--verbose`, `perl -c`, verify prod-URL refusal.
