# Plan: Standalone cron scraper script (Issue 640)


## Goal

Replace the current `cronjob.sh` (which POSTs to the web endpoint once per
location) with a single standalone Perl script `scripts/scrapeall.pl` that
scrapes all known locations directly, with configurable delays between requests.

The script runs outside the FastCGI process: no HTTP, no Apache, no login.

---

## Why not a web request?

- A single `o=updateallboards` HTTP request ties up a FastCGI worker for the
  full duration (potentially minutes with delays between untappd scrapers).
- A standalone script can sleep arbitrarily between scrapers without blocking
  any web workers.
- Cron jobs do not need HTTP semantics.

---

## Approach

The script reuses all existing beertracker modules directly.  The heavy lifting
is already in `scrapeboard::updateboard($c)`.  The script just builds a minimal
`$c` context (same pattern as `index.fcgi`) and calls that function for each
location in `%scrapeboard::scrapers`.

---

## Script: `scripts/scrapeall.pl`

### Setup
- `chdir` to the beertracker root (same as `index.fcgi` already does).
- `require` only the modules that are actually needed:
  `db.pm`, `util.pm`, `styles.pm`, `taps.pm`, `scrapeboard.pm`.
  (Not `migrate.pm` — migrations should be run interactively. Not CGI, login,
  graph, etc.)
- Open a log filehandle to `beerdata/scrapeall.log` and place it in
  `$c->{log}` **before** calling `db::open_db`, which requires `$c->{log}`
  to already exist for error reporting.
- Open a read-write database connection with `db::open_db($c, "rw")`.
- Build a minimal `$c` hash: `dbh`, `username`, `scriptdir`, `datadir`,
  `devversion`, `log`, `cache => {}`.  No CGI object needed — `$c->{cgi}`
  is intentionally omitted because the location is always passed as a direct
  argument and `util::param` is never called.

### Main loop
- Iterate over `sort keys %scrapeboard::scrapers`.
- Call `scrapeboard::updateboard($c, $locname)` (see below) wrapped in
  `eval {}` so one failing location does not abort the rest.
- After each untappd-backed scraper (`untappd.pl`), `sleep($delay)` (default
  5 seconds, overridable by `--delay N` command-line arg).
- Print a summary line per location to STDOUT (start time, location, beer count
  or error).  Cron redirects STDOUT+STDERR to a file in `beerdata/`; this way
  cron does not send daily mail.

### Passing the location name

Refactor `scrapeboard::updateboard($c)` to accept an optional second argument:

```perl
sub updateboard {
  my $c = shift;
  my $locparam = shift || util::param($c, "loc");
  ...
}
```

When called from the web (POST handler), no argument is passed and the existing
`util::param` lookup works as before.  When called from `scrapeall.pl`, the
location name is passed directly.  No fake params, no changes to `util.pm`.

### Redirect handling

`scrapeboard::updateboard($c)` sets `$c->{redirect_url}` at the end.  The
script simply ignores this.

### Database transaction

Each location's update is wrapped in explicit `BEGIN`/`COMMIT`/`ROLLBACK`
calls in `scrapeall.pl`.  This mirrors what `index.fcgi` does around its
`updateboard` call — `db::open_db` uses `AutoCommit => 1` and transaction
management is the caller's responsibility.  A failure mid-scrape will trigger
`ROLLBACK` so partial writes for that location are discarded before continuing
to the next.

### Error handling

- `eval {}` per location; print the error to STDOUT and continue.
- Scraper timeouts are already handled inside `scrapeboard::updateboard`
  (`timeout 5s`).

### Command-line options (minimal)

- `--delay N`  seconds to sleep between untappd scrapers (default 5)
- `--loc NAME` scrape only this location (for manual testing)

---

## Changes to existing code

### `scrapeboard.pm` — `updateboard()`

Accept an optional location argument as the second parameter, falling back to
`util::param($c, "loc")` when not provided.  One-line change at the top of the
function.

---

## Files changed/created

| File | Change |
|---|---|
| `scripts/scrapeall.pl` | New script |
| `code/scrapeboard.pm` | Accept optional location arg in `updateboard()` |
| `scripts/cronjob.sh` | No longer needed; crontab calls `scrapeall.pl` directly |

---

## Testing

1. Run `perl -c scripts/scrapeall.pl` for syntax.
2. Run with `--loc Ølbaren` manually and check DB tap counts.
3. Run for all locations and verify `beerdata/scrapeall.log` looks correct.
4. Replace cron entry and monitor for one day.
