## Plan: Repo-wide Perl module cleanup (scan results)

Summary
-------
- Focus: standardize DB access to `db::*` helpers and param access to `util::param`.
- Primary risk: many modules use direct `$c->{dbh}->prepare`/`execute`/`selectrow_*` and `$c->{cgi}->param` leading to inconsistent sanitization and logging.
- Next steps recommended: grep for direct DB and CGI usages, then convert low-risk places to `db::query`/`db::execute` and `util::param`.

Per-module findings
-------------------

- `code/db.pm`
  - Summary: central DB helper; canonical API exists.
  - Issues: none critical.
  - Suggestion: document and advertise preferred wrappers (e.g., `db::queryrecord`).

- `code/util.pm`
  - Summary: param normalization and helpers.
  - Issues: callers still use raw CGI params in many places.
  - Suggestion: document `util::param` as required API for param reads.

- `code/comments.pm`
  - Summary: comment display & posting.
  - Critical: direct `$c->{dbh}->prepare`/`selectrow_*` usage.
  - Important: direct `$c->{cgi}->param`/`multi_param` usage.

  ## Plan: Repo-wide Perl module cleanup (scan results)

  Summary
  -------
  - Focus: standardize DB access to `db::*` helpers and param access to `util::param`.
  - Progress: Many low-risk conversions have been completed (see "Completed" below). This plan now lists remaining hotspots and next steps.

  Completed
  ---------
  - Converted many `prepare`/`execute`/`selectrow_*` usages to `db::query`, `db::queryrecord`, `db::queryarray`, or `db::execute` in multiple modules (examples: `glasses.pm`, `stats.pm`, `photos.pm`, `persons.pm`, `locations.pm`, `monthstat.pm`, `yearstat.pm`, `ratestats.pm`, `graph.pm`, `postglass.pm`, `taps.pm`).
  - Replaced many raw param reads with `util::param` where appropriate.

  Remaining hotspots (manual review recommended)
  --------------------------------------------
  - `code/scrapeboard.pm`
    - Issues: `last_insert_id` usage after inserts; scraper input sanitization still needs explicit validation. Consider using `db::insertrecord` when inserting from structured form data or add explicit validation steps before `db::execute`.

  - `code/photos.pm`
    - Issues: `last_insert_id` usage and a few remaining `$c->{cgi}->param('return_url')` locations that intentionally bypass `util::param` due to allowed characters. Review whether `util::param` can be extended or those usages should be wrapped with a documented exception.

  - `code/brews.pm` and `code/locations.pm`
    - Issues: loops that enumerate CGI parameter names (e.g., `foreach my $paramname ($c->{cgi}->param)`) — these are intentional for checkbox lists/dedup flows; consider keeping but document and, where possible, replace with explicit `util::param` reads for known field names.

  - `code/yearstat.pm`
    - Issues: uses `selectcol_arrayref` directly on `$c->{dbh}`. Option: add small `db::selectcol_arrayref($c,$sql,@params)` helper in `db.pm` or convert call-sites to use `db::query` + `fetchall_arrayref`.

  Notes
  -----
  - `last_insert_id` calls were left where conversion would require more structural changes (e.g., replacing raw INSERT + last_insert_id with `db::insertrecord`). We can add `db::insertrecord` call-sites later where the insert originates directly from form fields.
  - `multi_param` usages (enumerating multi-valued inputs) were left as-is; these are acceptable in places where truly multiple values are expected. If you want, I can add a `util::multparam` wrapper for consistency.

  Next actions (suggested)
  -----------------------
  1. Add small helper `db::selectcol_arrayref($c,$sql,@params)` if you prefer replacing `selectcol_arrayref` call-sites for consistency. (Low risk)
  2. Convert `last_insert_id` patterns where the insert is from CGI fields to `db::insertrecord` (requires checking field mapping). (Medium risk)
  3. Audit and sanitize scraper outputs in `code/scrapeboard.pm` before DB writes. (Medium risk)
  4. Document `multi_param` usage or add a `util::multparam` wrapper. (Low risk)

  If you want, I can: (A) implement `db::selectcol_arrayref`, (B) convert selected `last_insert_id` flows to `db::insertrecord`, and (C) add a `util::multparam` wrapper — tell me which subset to do next.

  -- End of updated plan
