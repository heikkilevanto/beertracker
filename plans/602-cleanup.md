## Plan: Repo-wide Perl module cleanup (scan results)



NOTE: This audit strictly follows the repository's procedural Perl style (see copilot-instructions.md). At the end there's a very short "optional modernization" note with ideas you can ignore; do not apply modernization without approval.

Overview
--------
- Scope: thorough, read-only audit of all files in `code/` for style consistency, dead code, duplication, SQL/HTML safety, and refactor opportunities.
- High-level findings: (1) a few high-impact logic/DB issues that can break runtime; (2) many medium-risk XSS/escaping problems where DB values are printed directly into HTML; (3) some SQL-building patterns that interpolate values into SQL and should be parameterized.

Top-priority tasks (remaining)
------------------
1. Replace or limit SQL string interpolation in `code/listrecords.pm` and selected callers (priority: 1, effort: medium). This is the primary SQL-safety surface.
2. Site-wide output escaping: wrap DB/user strings with `util::htmlesc()` where embedded in HTML or attributes (priority: 2, effort: medium). This reduces XSS and broken pages.
3. Harden external-process invocations (`convert`, scrapers, shell `cp`/`rm`) and check return codes (priority: 3, effort: medium).

Per-file findings and recommendations
------------------------------------

The following lists concrete issues per file. Each entry: issue, severity, location, suggested fix (adhering to the project's style).

- `code/db.pm`
  - Status: unqualified `error(...)` calls were replaced with `util::error(...)` in this audit pass.
    - Severity: LOW (fixed)
    - Notes: The previous concern about the `open_db` write-permission check is intentional for this project and has been removed from the action list per project policy.
- `code/graph.pm`
  - Status: `addsums` parentheses bug corrected in this audit pass (now uses `scalar(@{ $g->{last7} }) > 7`).
    - Severity: LOW (fixed)
    - Suggested follow-up: add a small regression check for sums/averages to avoid future regressions.


- `code/listrecords.pm`
  - Issue: `listrecords` concatenates a `$where` string directly into SQL; many callers construct interpolated WHERE fragments.
    - Severity: HIGH
    - Suggested fix: Change `listrecords` to accept a parameterized WHERE clause plus bind values (e.g., `($where_clause, @bind)`) or enforce callers to validate numeric inputs. Start by auditing call-sites that interpolate untrusted values.
  - Issue: Rendering loop prints DB values directly into HTML table cells.
    - Severity: MEDIUM
    - Suggested fix: Use `util::htmlesc()` when printing values into HTML.

- Widespread (many modules: `glasses.pm`, `brews.pm`, `persons.pm`, `comments.pm`, `locations.pm`, `beerboard.pm`, `mainlist.pm`, `inputs.pm`, `photos.pm`, `export.pm`, `aboutpage.pm`, `stats.pm`, `monthstat.pm`, `yearstat.pm`, `ratestats.pm`)
  - Issue: Many places print DB-origin strings directly into HTML or JS without escaping, causing XSS or broken markup if values contain quotes/HTML.
    - Severity: MEDIUM (per-file instances vary)
    - Suggested fix: Audit templates and printing sites; apply `util::htmlesc()` for HTML text and `uri_escape_utf8()` for query params. For JS data, prefer `encode_json()` to produce safe JS literals.

- `code/postglass.pm`
  - Issue: Date validation regex is wrong/ambiguous: `if ( $d =~ /^\\d\\d-\\d\\d-\\d\\d|$/ )` (alternation binds incorrectly).
    - Severity: MEDIUM
    - Suggested fix: Use a clear pattern such as `^\\d{4}-\\d{2}-\\d{2}$` or `^(?:\\d{4}-\\d{2}-\\d{2})?$` depending on whether empty allowed.
  - Issue: Printing user/DB values into HTML without escaping.
    - Suggested fix: `util::htmlesc()` for HTML output.

- `code/listrecords.pm`, `code/brews.pm`, `code/inputs.pm`, `code/glasses.pm`, `code/locations.pm`, `code/comments.pm`, `code/persons.pm`, `code/beerboard.pm`, `code/mainlist.pm`
  - Issue: Attribute and JS interpolation sometimes uses raw DB values; may break HTML/JS.
    - Severity: MEDIUM
    - Suggested fix: Use `util::htmlesc()` for attribute values and `encode_json()` or `util::htmlesc()` for inline JS content.

- `code/photos.pm`
  - Status: `convert` calls moved from backticks to list-form `system()` with return-code checks; upload temp-file readability and destination directory creation are now verified.
    - Severity: LOW (fixed)
    - Suggested follow-up: consider additional tests for various image formats and error paths.

- `code/scrapeboard.pm`
  - Issue: Runs external scraper scripts via backticks; captures output but may ignore failures.
    - Severity: MEDIUM
    - Suggested fix: Ensure only fixed, internal scripts are called, capture stderr, check exit codes, and log or surface failures rather than silently proceeding.

- `code/superuser.pm`
  - Issue: Uses shell `rm`/`cp` with interpolated paths in `copyproddata` and related functions.
    - Severity: MEDIUM
    - Suggested fix: Prefer Perl file-copy APIs (File::Copy) or carefully shell-escape inputs and check return codes.

- `code/login.pm`
  - Issue: `read_secret` currently `die`s on missing secret file; produce hard exit instead of controlled `util::error()`.
    - Severity: MEDIUM
    - Suggested fix: Convert `die` to `util::error()` so failures produce consistent HTTP-friendly errors.

- Misc minor items (low severity)
  - `code/cache.pm`: assume `$c->{log}` exists — consider defensive checks or documenting the requirement.
  - `code/yearstat.pm`: use `uri_escape_utf8()` consistently for query params in links.
  - `code/ratestats.pm`: build JS data using `encode_json()` to avoid breaking quotes.
  - `code/debug.pm`: ensure debug output is protected and does not leak sensitive content in production.

Effort estimates
----------------
- Quick (<1h): fix `db::open_db` permission check, fix unqualified `error()` calls, fix `graph.pm` parentheses bug.
- Medium (1–4h): refactor `listrecords` to accept parameterized WHERE / audit callers, site-wide escaping changes (spread across many files), harden external process calls, photos `convert` error handling.

Suggested immediate next steps
----------------------------
1. Apply the two high-impact quick fixes in `code/db.pm` and `code/graph.pm` and run `perl -c` across the repo.
2. Create a follow-up PR that: (a) converts `listrecords` to accept a parametrized WHERE clause with bind args, (b) updates a few high-traffic callers (e.g., glasses, brews, mainlist) to use placeholders.
3. Run a focused escaping pass: add `util::htmlesc()` in the 10 most-visible printing sites (mainlist, beerboard, glasses, brews, listrecords, comments, persons, locations, postglass, inputs).
4. Harden external calls and image handling by adding return-code checks and error paths.

Optional modernization notes (very short)
--------------------------------------
- If you later consider modernization: introduce a minimal templating helper to centralize escaping, and a thin DB wrapper that enforces parameterized queries everywhere. Also add unit/regression tests for `graph` and DB helper flows.

Next steps for me if you want me to continue
-------------------------------------------
- I can (A) implement the quick fixes now, (B) prepare a PR that changes `listrecords` to accept parameterized WHERE + update a few callers, or (C) run a site-wide escaping sweep. Tell me which of A/B/C to do next.

Detailed per-file findings (raw, actionable)
-------------------------------------------

The full per-file findings were generated by a thorough read of `code/`. If you want the verbatim per-file JSON-style findings inserted here, tell me and I will append them; otherwise this plan captures the concrete, prioritized actions.

-- End of plan
