# Test plan: HTTP test system + non-200 error handling

## Summary
Build a standalone Perl test script, `tools/test-http.pl`, that exercises the live
dev site over HTTP (the curl loop idea) with real assertions: GET smoke + content
checks, edit-page variants driven by **record IDs harvested from the rendered
list pages**, a post-run CopyProdData sync for data isolation, and a
debug.log scan for DB errors.

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

## Task 2 (done): Test script skeleton `tools/test-http.pl`

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
- `all` — everything, including POST round-trips and the post-run CopyProdData
  sync (needs the dev-only guard).
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

## Task 4 (done): edit-page variants, filters, static assets (all DB-less)

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

## Task 5 (done): Data sync + debug.log scan (GET-only)

- **No CopyProdData before the run.** Each run starts against the dev DB as it
  is; a pre-sync would always clobber the dev data and was only ever needed to
  wipe POST residue — which doesn't exist yet at the start.
- **One CopyProdData after the run, and only if the run made POST requests.**
  GET-only runs (quick/`all` with no `posts` selector) never touch the database,
  so they leave the dev DB exactly as they found it. Only when the run actually
  performed POST round-trips is the final `GET o=CopyProdData` issued, restoring
  a fresh prod copy and wiping the test residue (Brew/Location/Person records
  have no web delete; that is their cleanup).
- Record `debug.log` size before, scan the appended portion for new
  `DB ERROR`/`ERROR`/`Use of uninitialized` lines after — fail if any.
- If dev code is ahead of prod (new migrations), the first GET after
  CopyProdData redirects to `o=migrate`; detect and report "run migrations
  first" instead of failing confusingly.
- Wrap the run so a mid-run failure (e.g. a POST killing the worker) still
  triggers the final sync (when POSTs happened) and log scan. In the default run
  this task does the post-run sync *once around the whole run*, not per test.
- No DB access here either: the test script only reads the log file and the
  HTTP responses.

## Task 6 (done): POST round-trips (much later, dev-guarded)

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

## Task 6a (done): Glass round-trip in tools/test-http.pl

The glass round-trip from Task 6 is missing. It creates a glass through the web
(POST `submit=Record`), verifies it on the main list, updates it
(`submit=Save`), and deletes it (`submit=Del`) — all through HTTP, no DB
access. Two markers identify the record as a test and keep it harmless:
the note is `TST<epoch>` (greppable in pages, like the other roundtrips) and
the volume is an **unlikely 11 cl** so it never collides with real drinking
data in stats or price guessing.

### Registration (add to @TESTS, not in 'quick')
```perl
{ name => "glass_roundtrip", sets => [qw(posts roundtrip postglass glasses)], test => \&test_glass_roundtrip },
```
It inherits the existing dev-guard (the `posts` tag + the `-dev`/`--no-post`
logic) and the post-run CopyProdData sync. No new guarding code needed.

### New helper: `brew_with_defprice($body)`
Use a brew that already has a `DefPrice`, so the `DefPrice=50/DefVol=11`
auto-update in `postglass.pm:189` becomes a no-op (that is the only real
side effect the glass POST can have on the `brews` table). Also harvest the
brew's real `BrewType` to send as `selbrewtype`.

Rather than looping over `o=Brew&e=<id>` edit pages, parse the main input
form's brew dropdown on the Full page — each item carries `defprice='…'` and
`brewtype='…'` attributes (`brews.pm:708`), so one fetch yields the brew id
and its type. Returns `($brewid, $brewtype)` for the first item with a
non-empty `defprice`, else `()` (then the test skips):
```perl
sub brew_with_defprice {
  my $body = shift;
  while ( $body =~ m{<div class='dropdown-item' id='(\d+)'[^>]*?defprice='([^']+)'[^>]*?brewtype='([^']*)'}g ) {
    return ($1, $3);
  }
  return ();
}
```
(The `id='actions'` item does not match `\d+`. The regex lives right next to
the test, per the "regexes stay visible" convention.)

### Test flow (`test_glass_roundtrip`, placed after `test_location_roundtrip`)
Add `use POSIX qw(strftime);` to the script imports for the date/time.

1. `my $locid = get_first_id("Location");` — skip if the list has no ids.
2. Warm-up GET (`get_first_id("Full")`) to absorb the one-time fcgi reload
   bounce before the first POST.
3. GET `?o=Full`, parse `brew_with_defprice` → `($brewid, $brewtype)`;
   skip if no brew has a DefPrice in the dev data.
4. **Insert** — POST `o=Full, Location, Brew, selbrewtype, date=today,
   time=now, vol=>"11", alc=>"4.6", pr=>"50", note=>"TST".time(),
   submit=>Record`. Assert 302 + Location (`assert_post_redirect`).
5. Follow the redirect; `assert_page_ok` (`id='mainform'`); assert the note
   appears; harvest the glass id via `id_before_text($body, "Full", $note)`;
   assert the `o=Full&e=$id` link exists.
6. **Verify vol landed** — GET `?o=Full&e=$id` (edit form); assert the vol
   input shows `value='11c'` and the note is in the form.
7. **Update** — POST `o=Full, e=$id, Location, Brew, selbrewtype, date,
   time, vol=>"11", alc, pr, note=>$note2, submit=>Save`. Use
   `$note2 = "TST" . (time()+1) . "upd"` — it **must not contain `$note` as
   a substring**, or the "old note gone" assertion fails. Assert 302, follow
   redirect, assert old note gone / new note present.
8. **Delete** — POST `o=Full, e=$id, submit=>Del`. Assert 302, follow
   redirect, assert note2 absent.

Note: the update **must** resend `Location`/`Brew`/`vol`. On Save,
`postglass` overwrites `$glass->{Brew}`/`{Location}` with the posted params,
and `vol` defaults to `"L"` → 40 cl when missing (`postglass.pm:66,289`).

### Side effects on other tables (analysis)
- **glasses** — the row itself; insert → update → delete. Intended.
- **brews** — **no write**: only brews with an existing `DefPrice` are used,
  so the `DefPrice/DefVol` auto-update (`postglass.pm:189`) is skipped.
  `setdef`/`updateGeo` are not sent, so `update_brew_defaults` and
  `locations.Lat/Lon` never run.
- **locations / persons / tap_beers** — untouched.
- **comments / comment_persons / photos** — untouched: the glass gets no
  comments or photos, so the delete triggers neither the
  `comments.Glass ON DELETE SET NULL` FK (FKs are enforced, `db.pm:49`) nor
  orphaned `photos.Glass` rows.
- **Transient view/stat effects while the row exists** (gone after the
  delete, or after the post-run CopyProdData sync): `brew_ratings`
  glass_count +1 for the brew; `LatestPrices` gains a spurious 50.-/11cl
  "latest" row; Year/Month/short/blood-alcohol aggregates gain ~+50.- and
  ~+0.33 std drinks for today; `fixprice` guessing can never inherit from it
  because vol=11 matches no real (brew, location, volume) — the reason for
  the unlikely volume.
- **Non-DB**: `graph::clearcachefiles` on each glass POST unlinks the user's
  cached graph PNGs and touches `beerdata/<user>.last` (same as any real
  glass POST, transient); `debug.log` gets normal param-dump/POST lines (the
  log scan fails only on ERROR lines); a POST error would kill the fcgi
  worker by design, so the test avoids erroring.

### Cleanup / re-runnability
The test deletes its own glass, so re-runs do not accumulate rows; each run
uses a fresh epoch in the note. A mid-run abort leaves a greppable
`TST<epoch>` glass, but the post-run CopyProdData sync (fires whenever POSTs
happened and the run passed) restores a fresh prod copy; if the run failed
the sync is skipped so the DB can be inspected.

### Files touched
`tools/test-http.pl` only (imports + helper + test sub + one `@TESTS` row).
No `code/VERSION.pm` touch — the test script is standalone, not loaded by
index.fcgi.

### Verification (done)
- `perl -c tools/test-http.pl`.
- `perl tools/test-http.pl -v glass_roundtrip` (dev checkout, so the POST
  guard passes).
- `perl tools/test-http.pl posts` — all roundtrips (person, brew, location,
  glass, comment) pass; the post-run CopyProdData sync ran.

## Task 6b (done): Comment round-trip in tools/test-http.pl

The comment round-trip from Task 6. It attaches a comment to an **existing**
glass (no glass is created — comments always sit on a glass), verifies it,
updates it, and deletes it — all through HTTP, no DB access. The comment text
is `TST<epoch>` (greppable in pages), and the rating is a midrange 7.

### Registration (add to @TESTS, not in 'quick', after glass_roundtrip)
```perl
{ name => "comment_roundtrip", sets => [qw(posts roundtrip comment comments)], test => \&test_comment_roundtrip },
```
It inherits the existing dev-guard (the `posts` tag + the `-dev`/`--no-post`
logic) and the post-run CopyProdData sync. No new guarding code needed.

### Why the flow works (comments.pm)
- **Dispatch**: `index.fcgi:322` routes on the `commentedit=1` param →
  `comments::postcomment` (regardless of `o`).
- **Insert**: no `comment_id` → INSERT (`comments.pm:685`); `Ts` is inherited
  from the glass; redirect to `?o=Full&date=$effdate&ndays=1`
  (`comments.pm:704`) — i.e. back to the glass's page, which renders the
  comment via `commentlines` (`mainlist.pm:286`, gated on `comcount`).
- **Harvest**: `commentline` renders the `o=Comment&e=<id>` link immediately
  before the note text (`comments.pm:40`), so
  `id_before_text($body, "Comment", $note)` returns the new comment's id. The
  `(New comment)` link is `e=new` — not digits — so it cannot match.
- **Update**: `comment_id` set + submit != Del → UPDATE branch
  (`comments.pm:665-683`), gated on `Glass IS NOT DISTINCT FROM ?` — must
  resend `glass`.
- **Delete**: `submit=Del` + `comment_id` → DELETE (`comments.pm:666`). Must
  resend `glass`, else the redirect falls back to `?o=comment` instead of the
  glass page.
- `o=Comment` and `e=<new|id>` go in the POST body (form realism; postcomment
  only reads `comment_id`/`glass`/`submit`/`rating`/`comment`/`commenttype`).

### Test flow (`test_comment_roundtrip`, placed after `test_glass_roundtrip`)
1. `my $glassid = get_first_id("Full");` — skip if the main list has no glass
   ids. (The warm-up GET also absorbs the one-time fcgi reload bounce before
   the first POST.)
2. `$note = "TST" . time();` — rating `7`, `commenttype=brew`.
3. **Insert** — POST `commentedit=1, o=Comment, e=new, glass=$glassid,
   rating=7, comment=$note, commenttype=brew, submit=Add`. Assert 302 +
   Location (`assert_post_redirect`).
4. Follow redirect; `assert_page_ok` (`id='mainform'`); assert the note
   appears; harvest `$id = id_before_text($body, "Comment", $note)`; assert
   the `o=Comment&e=$id` link exists.
5. **Verify persisted** — GET `?o=Comment&e=$id`; assert "Edit comment"
   heading, note in the textarea (`name='comment'`), and the rating/type
   dropdowns show `value='7'` / `value='brew'`.
6. **Update** — POST `commentedit=1, o=Comment, e=$id, glass=$glassid,
   comment_id=$id, rating=8, comment=$note2, commenttype=brew, submit=Upd`.
   Use `$note2 = "TST" . (time()+1) . "upd"` — it **must not contain `$note`
   as a substring**, or the "old note gone" assertion fails. Assert 302,
   follow redirect, assert old note gone / new note present.
7. **Delete** — POST `commentedit=1, o=Comment, e=$id, glass=$glassid,
   comment_id=$id, submit=Del`. Assert 302, follow redirect, assert `$note2`
   absent.

Note: the plan's Task 6 bullet for comment only lists insert → verify →
delete, but the task intro says every round-trip does create/verify/**update**/
delete, and the comment form's `submit=Upd`/`comment_id` UPDATE branch
(`comments.pm:665`) is otherwise untested — hence the update step.

### Side effects on other tables (analysis)
- **comments** — the row itself; insert → update → delete. Intended.
- **comment_persons** — untouched: no `person_id` chips are sent (the update
  branch re-runs DELETE+INSERT with an empty list, a no-op).
- **glasses / brews / locations / persons / photos** — no writes. The
  comment's `Brew`/`Location` columns stay NULL (not posted); `Ts` is read
  from the glass only.
- **Transient view effects while the comment exists** (gone after the delete,
  or after the post-run CopyProdData sync): the glass's brew gains a rating-7
  entry in `brew_ratings` (avg/count shown on brew list, beerboard, main list)
  and the Ratings histogram shifts by one 7.
- **Non-DB**: `cache::clear` on each POST (same as any write); debug.log gets
  normal POST lines; no glass graph-PNG cleanup (that only happens in
  postglass).

### Cleanup / re-runnability
The test deletes its own comment, so re-runs do not accumulate rows; each run
uses a fresh epoch in the note. A mid-run abort leaves a greppable
`TST<epoch>` comment, but the post-run CopyProdData sync (fires whenever POSTs
happened and the run passed) restores a fresh prod copy; if the run failed the
sync is skipped so the DB can be inspected. Attaching to an existing glass
means no glass cleanup is needed.

### Files touched
`tools/test-http.pl` only (one `@TESTS` row + one test sub).
No `code/VERSION.pm` touch — the test script is standalone, not loaded by
index.fcgi.

### Verification (done)
- `perl -c tools/test-http.pl` — OK.
- `perl tools/test-http.pl comment_roundtrip` (dev checkout, POST guard
  passes) — 39 PASS, no fails.
- `perl tools/test-http.pl posts` — all five round-trips (person, brew,
  location, glass, comment) = 171 PASS; post-run CopyProdData sync ran and
  left no `TST<epoch>` residue on the Comment/Full pages.
- Note: the dropdown hidden inputs render their attributes on separate lines
  with double quotes (`inputs.pm` template), so the rating/commenttype
  assertions match `id="rating"\s+name="rating"\s+value="7"` etc.

## Deferred: DBI access from the test script (avoid unless needed)

The current design deliberately avoids a DBI connection to
`beerdata/beertracker.db`. Ids come from the rendered pages and residue is wiped
by the post-run CopyProdData sync (POST runs only), so reads aren't needed. If
we later want:

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
- Data isolation is handled by the post-run CopyProdData sync (only issued when
  the run made POST requests), which leaves the dev DB untouched for GET-only
  runs.
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
  CopyProdData approach, the dev DB after a GET-only run is left as it was, and
  after a POST run it equals a fresh prod copy (by design).
- A GET-only run never syncs data at all: no pre-sync (would clobber dev data
  needlessly) and no post-sync (nothing was changed). Only POST runs get the
  final CopyProdData.
- If dev code is ahead of prod (new migrations), the first GET after
  CopyProdData redirects to `o=migrate`; detect and report "run migrations
  first" instead of failing confusingly.
- Never intentionally trigger POST errors in tests (kills the worker by design).

## Execution order
1. Task 1 (HTTP 500 on GET errors) — **done**; enables status-based checks.
2. Task 2 skeleton: config, HTTP helper, HTML-id harvest helpers, assertion
   helpers, GET smoke loop, selector plumbing.  **done**
3. Task 3: GET smoke for all ops (no DB, no id variants).  **done**
4. Task 4: harvested-id edit-page variants, `q=` filters, static assets
   (still GET-only, still DB-free).  **done**
5. Task 5: debug.log scan + conditional post-run CopyProdData sync, migration
   detection.  **done**
6. Task 6 (last): POST round-trips — dev-guarded, cleanup via web + post-run
   CopyProdData sync.  **done** (person, brew, location, glass, comment)
7. Polish: `--no-post`, `--verbose`, `perl -c`, verify prod-URL refusal.
   **done** (prod-URL refusal verified manually)
