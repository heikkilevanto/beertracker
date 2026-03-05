# Plan: Switch index.cgi to FastCGI (issue 565)

Wrap the request body in a `CGI::Fast` loop, split per-process vs per-request
init, persist the ro dbh, and fix all `exit` calls. The `$c` hash itself is
rebuilt per-request as today — only module-level state and the dbh persist.

Key insight: `CGI::Fast` falls back silently to plain CGI behaviour when not
running under FastCGI (it checks for the FCGI socket). This means Phase A and B
can be done, tested, and merged while still running plain CGI. The actual
switch to FastCGI is just an Apache config change in Phase C.

Status: A1 (modules) and A2 are done. A1 (index.cgi exits) and A3 are still TODO.
Apache modules loaded. `code/test.fcgi` exists for testing and is live at
https://lsd.dk/beertracker-dev/code/test.fcgi

## Lessons learned from test.fcgi

Key findings that explain the implementation choices below:

- **Auto-reload**: A persistent process does not reload on file change. Solution
  (B3): a `?reload=1` URL parameter triggers an `exit(0)` after sending a redirect,
  so mod_fcgid gets a valid HTTP response (bare `exit` causes 500) and the next
  request hits a freshly-loaded process. Reloading all `require`d modules via
  mtime-checking was rejected as too complex given the number of modules.
- **UTF-8**: `FCGI::Stream` does not support PerlIO layers — `binmode STDOUT, ':utf8'`
  is silently ignored. Solution (B2): redirect bare `print` via `select` to an
  in-memory scalar opened with `>:utf8`. Print the already-encoded byte string
  to FCGI::Stream at the end of the loop. The HTTP headers from `htmlhead()`
  must be printed to FCGI::Stream **before** the `select` swap, because
  mod_fcgid parses them separately from the body.
- **POST params**: use `CGI::Fast qw(-utf8)` to decode incoming params to
  Unicode strings; without it params are raw bytes that double-encode in the
  `:utf8` buffer. `index.cgi` already uses `use CGI qw(-utf8)` so this is safe.
- **STDERR**: under mod_fcgid, every STDERR line is wrapped with Apache/fcgid
  noise and UTF-8 wide chars are mangled. A dedicated log file (`beerdata/beertracker.log`,
  handle in `$c->{log}`) is already in place (A3 done);
  keep STDERR for genuine crash output only.

## Apache Config Strategy

Both prod and dev run on the same machine; Apache points directly at the
git-tracked `etc/apache-config.example.txt` from the production site. Single-user, 
so downtime is acceptable.

Strategy: `index.cgi` stays live and untouched throughout the migration as a
fallback. Phase B creates a new `index.fcgi` alongside it. Testing is done via
the explicit `index.fcgi` URL. Cutover is a one-line `DirectoryIndex` change.

`AddHandler fcgid-script .fcgi` is already in the Apache config (added for
`test.fcgi`), so `index.fcgi` will be served under FastCGI as soon as the file
exists.

Rollback at any point:
    git checkout etc/apache-config.example.txt   # if needed
    sudo systemctl restart apache2

## Phase A: Preparatory cleanup (safe under plain CGI, index.cgi unchanged)

All of Phase A can be done, tested, and committed while `index.cgi` still runs
as a plain CGI script. No user-visible behaviour changes. These are prerequisites
for both `index.cgi` and `index.fcgi`.

### A1. Remove / replace `exit()` calls

The module-level fixes apply everywhere. The index.cgi-specific exits only need
to be fixed in `index.fcgi` (apply when creating it in Phase B, not to `index.cgi`).

| Location | Fix | Status |
|---|---|---|
| monthstat.pm — `exit()` at end of function | Remove | **DONE** |
| superuser.pm `copyproddata()` — `exit()` after redirect | Changed to `return` | **DONE** |
| util.pm `util::error()` — `exit()` | Changed to `die $msg` | **DONE** |
| index.fcgi — `exit 0 unless $username` (after auth) | Change to `next unless $username` | TODO |
| index.fcgi — `exit` after `copyproddata()` call | Change to `next` | TODO |
| index.fcgi — `exit` after POST redirect | Change to `next` | TODO |
| index.fcgi — `exit` after `do_export()` — see note | Change to `next` (see note) | TODO |
| index.fcgi — `exit()` at end of script (after GET eval) | Remove | TODO |

**Note on `do_export()`**: `do_export()` outputs its own `text/plain`
content-type header and body before `htmlhead()` is ever called. In the
FastCGI loop this exit becomes `next`, but because `do_export()` sends its
own HTTP header, the `select`/buffer setup (B2) must be placed *after* this
branch. See B2 for the exact structure.

**Test after A1:** Normal page load, bad-password 401, error condition, monthstat page, export — all should work under plain CGI.

### A2. Fix `htmlhead()` to use `$c` — **DONE**

`htmlhead()` already takes `$c` and uses `$c->{cgi}`. Nothing to do.

### A3. Dedicated log file — **DONE**

`beerdata/beertracker.log` opened at startup, handle in `$c->{log}`. Nothing to do.

## Phase B: Create index.fcgi (runs in parallel with index.cgi)

Dependencies already installed: `libfcgi-perl`, `libcgi-fast-perl`, `mod_fcgid`.
`AddHandler fcgid-script .fcgi` is already in the Apache config.

`index.fcgi` is a **copy of `index.cgi`** with the FastCGI-specific changes
applied. `index.cgi` is not modified. Both files can be served simultaneously;
`index.cgi` remains the default (`DirectoryIndex`) until Phase C.

### B1. Create index.fcgi — replace `use CGI` with `use CGI::Fast`

    cp code/index.cgi code/index.fcgi
    chmod +x code/index.fcgi

In `index.fcgi`, replace:

    use CGI qw( -utf8 );
    my $q = CGI->new;
    $q->charset("UTF-8");

with:

    use CGI::Fast qw( -utf8 );

### B2. Wrap request body in the FastCGI loop

In `index.fcgi`, move everything from the `$c_auth` construction down to
(and including) `htmlfooter()` inside:

    while (my $q = CGI::Fast->new) {

        # Handle DoExport before buffer setup — it sends its own content-type:
        if ($c->{op} =~ /DoExport/i) {
            export::do_export($c);  # outputs text/plain header + body to FCGI::Stream
            next;
        }

        # Send HTML HTTP headers to FCGI::Stream before the select swap:
        htmlhead($c);   # prints Content-Type + HTML <head> directly to FCGI::Stream

        # Buffer remaining body output through a :utf8 layer:
        my $body = '';
        open my $buf, '>:utf8', \$body or die $!;
        my $old_fh = select $buf;

        # ... all per-request content dispatch, module print statements unchanged ...

        # Restore and emit:
        select $old_fh;
        print $body;   # already UTF-8 bytes, no Encode needed

        htmlfooter();
    }

Note: `htmlhead()` currently prints both the HTTP `Content-Type` header and the
HTML `<head>` block. Both go to FCGI::Stream before the `select` swap, which is
correct. Under plain CGI, `CGI::Fast->new` returns an object once then undef —
the loop runs exactly once, identical to current behaviour.

All `exit` calls were already replaced with `next`/`return` in A1.

### B3. Force-reload via URL parameter

In `index.fcgi`, record the mtimes of `$0` and `code/VERSION.pm` at startup,
outside the loop:

    my $mtime0    = (stat($0))[9];
    my $mtime_ver = (stat("code/VERSION.pm"))[9];

At the top of each loop iteration, before auth, check for both a manual reload
request and a code-change:

    if ( $q->param('reload') ||
         (stat($0))[9]              != $mtime0 ||
         (stat("code/VERSION.pm"))[9] != $mtime_ver ) {
        my $op = $q->param('o') || 'Graph';
        print $q->header(-status => '302 Found', -location => $q->url() . "?o=$op");
        exit(0);
    }

Make the version number in the page header a link to `$c->{href}&reload=1`. **DONE**
A `git pull` to production updates `VERSION.pm` on disk; the next request sees
the mtime change, force-exits, and the following request loads fresh code.
No manual reload needed after deploys.

**Test after B1–B3:** Hit `index.fcgi` directly. Full regression: page loads,
POST, export, auth failure, UTF-8 characters. Check log file written. Check
reload link kills and respawns the process (PID changes). `index.cgi` continues
to work normally throughout.

## Phase C: Cutover

When `index.fcgi` is stable and fully tested:

### C1. Switch DirectoryIndex

In `etc/apache-config.example.txt` change:

    DirectoryIndex code/index.cgi

to:

    DirectoryIndex code/index.fcgi

Restart Apache. `index.cgi` remains on disk as an instant rollback target.

### C2. Rollback if needed

    # Revert the one-line config change:
    git checkout etc/apache-config.example.txt
    sudo systemctl restart apache2

**Test after C:** Same regression as Phase B, now via the default URL. Confirm
process persistence via the reload link and log file.

## Follow-ups

- **Persistent ro dbh**: declare `my $dbh_ro` outside the loop. In the GET
  path, replace `db::open_db($c, "ro")` with a reconnect-if-needed pattern
  using `$dbh_ro->ping`. POST continues to open a fresh rw handle per request.
- **In-process caching**: with a persistent process, module-level caches become
  viable. `selectbrew` and other heavy queries are candidates.
- **fcgid tuning**: if process count or memory becomes an issue, look at
  `FcgidMaxRequestsPerProcess`, `FcgidMaxProcesses`, etc.
- **Cleanup**: once `index.fcgi` is stable in production, remove `index.cgi`.