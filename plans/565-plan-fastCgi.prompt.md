# Plan: Switch index.cgi to FastCGI (issue 565)

Wrap the request body in a `CGI::Fast` loop, split per-process vs per-request
init, persist the ro dbh, and fix all `exit` calls. The `$c` hash itself is
rebuilt per-request as today — only module-level state and the dbh persist.

Key insight: `CGI::Fast` falls back silently to plain CGI behaviour when not
running under FastCGI (it checks for the FCGI socket). This means Phase A and B
can be done, tested, and merged while still running plain CGI. The actual
switch to FastCGI is just an Apache config change in Phase C.


Stage A changes done and seem to work. The rest is stashed away.
Apache modules loaded. There is a code/test.fcgi file that can be used to test 
FastCGI and to demonstrate the persistent process behavior. It should be accessible at
https://lsd.dk/beertracker-dev/code/test.fcgi

## Lessons learned from test.fcgi

### Auto-reload on code change (required for development workflow)

A persistent process **does not reload when the script file changes**. Without a
mechanism to force reload, every code edit requires `sudo apache2ctl restart`.

Solution: record mtime of `$0` at startup; check it on every request; if
changed, send a redirect response and `exit(0)`:

    my $mtime = (stat($0))[9];  # outside loop

    # inside loop, first thing:
    if ((stat($0))[9] != $mtime) {
        print $q->header(-status => '302 Found', -location => $q->url());
        exit(0);
    }

**Critical**: must send a valid HTTP response before `exit`. Calling `exit`
without output gives mod_fcgid "End of script output before headers" → 500.
The browser follows the redirect, which hits the freshly-spawned process.

Workflow after adding this: save file → reload browser once (exits old process)
→ reload again (new code running). No Apache restart needed.

### UTF-8: `binmode STDOUT` does not work under FastCGI

`FCGI::Stream` (the object that replaces STDOUT) does not support PerlIO layers.
`binmode STDOUT, ':utf8'` is silently ignored, and any wide-character string
printed directly produces:
> Use of wide characters in FCGI::Stream::PRINT is deprecated

FCGI::Stream also does not support `open`-based dup operations (`open my $save, '>&', \*STDOUT`
fails with "Operation 'OPEN' not supported on FCGI::Stream handle").

**Solution: `select` + scalar buffer with `:utf8` layer.**

Use `select` to redirect bare `print` to an in-memory scalar opened with the
`:utf8` encoding layer. All existing `print` statements write Unicode strings
into the buffer; the layer encodes them to UTF-8 bytes as they land. At the end
of the request, restore the default filehandle with `select` and print the
already-encoded byte string directly to FCGI::Stream:

    # top of loop, after $q->header() is sent:
    my $body = '';
    open my $buf, '>:utf8', \$body or die $!;
    my $old_fh = select $buf;

    # ... all module print statements go into $body as UTF-8 bytes ...

    # end of loop:
    select $old_fh;
    print $body;   # $body is already bytes — no Encode needed

Key points:
- `open '>:utf8', \$scalar` works fine on a plain Perl scalar filehandle.
- `select` changes the default filehandle without touching the FCGI::Stream handle.
- `$q->header()` must be printed **before** the `select` swap — it goes directly to FCGI::Stream.
- No `use Encode` needed anywhere.
- **No changes to any module required.** Only the loop body in `index.cgi` needs the three lines above.

Verified working in `test.fcgi`.

### UTF-8: POST params are raw bytes without the `-utf8` flag

Without `use CGI::Fast qw(-utf8)`, `$q->param('text')` returns raw UTF-8 bytes
(e.g. `Æ` arrives as `\xc3\x86`). When that byte string flows into the `:utf8`
buffer it gets double-encoded and characters are mangled.

**Fix**: always use the `-utf8` flag: `use CGI::Fast qw(-utf8)`. This decodes
all incoming params to Perl Unicode strings automatically. `index.cgi` already
does this (`use CGI qw(-utf8)`), so beertracker is safe on this front.


### STDERR: UTF-8 characters are scrambled

`print STDERR` with wide characters also hits FCGI::Stream's encoding limitation.
Example: `Posted 'OE: Ø ø'` appears as `Posted 'OE: \xd8 \xf8'` in the error log.

Not worth fixing at the STDERR level — the dedicated log file (see below) will
handle app-level logging with proper encoding. Keep STDERR for genuine crash
output only.

### Dedicated log file for beertracker

Under plain CGI, STDERR goes to the Apache error log and is readable.
Under mod_fcgid, every STDERR line is prefixed with Apache timestamp, fcgid
module info, PID, thread, and client IP — making it hard to read app-level log
lines.

Example of what a single `print STDERR "pid=33"` produces in the error log:
    [Wed Mar 04 12:52:54.978840 2026] [fcgid:warn] [pid 1601283:tid 1601315] [client 192.168.0.2:52970] mod_fcgid: stderr: test.fcgi: pid=33, referer: ...

For a high-request app this becomes noisy fast. Consider:
- Opening a dedicated log file (e.g. `beerdata/beertracker.log`) at startup
  (outside the loop) and writing app log lines there.
- Keep STDERR for genuine errors only.
- The log file path can be derived from `$c->{basedir}` so it works in both
  prod and dev.

**This must be done before the FastCGI switch** — see Phase A3.

## Apache Config Strategy

Both prod and dev run on the same machine; Apache points directly at the
git-tracked `etc/apache-config.example.txt`. Single-user, so downtime is
acceptable.

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

| Location | Fix | Status |
|---|---|---|
| monthstat.pm — `exit()` at end of function | Remove | **DONE** |
| superuser.pm `copyproddata()` — `exit()` after redirect | Changed to `return` | **DONE** |
| util.pm `util::error()` — `exit()` | Changed to `die $msg` | **DONE** |
| index.cgi line 123 — `exit 0 unless $username` | Change to `next unless $username` | TODO |
| index.cgi line 191 — `exit` after redirect | Change to `next` | TODO |
| index.cgi line 244 — `exit` after redirect | Change to `next` | TODO |
| index.cgi line 256 — `exit` after redirect | Change to `next` | TODO |
| index.cgi line 321 — `exit()` end of GET dispatch | Remove (falls through to `}`) | TODO |

**Test after A1:** Normal page load, bad-password 401, error condition, monthstat page, export — all should work under plain CGI.

### A2. Fix `htmlhead()` to use `$c` — **DONE**

`htmlhead()` already takes `$c` and uses `$c->{cgi}`. Nothing to do.

### A3. Dedicated log file

Add this now — it works under plain CGI and is needed for debugging the FastCGI
switch. In `index.cgi`, open the log file near the top (outside any future loop),
store the handle in `$c`:

    my $logpath = $basedir . "/beerdata/beertracker.log";
    open my $log_fh, '>>', $logpath or warn "Cannot open log $logpath: $!";
    $c->{log_fh} = $log_fh;

Add `util::applog($c, $msg)` — a simple helper that writes a timestamped line:

    sub applog {
        my ($c, $msg) = @_;
        my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
        print { $c->{log_fh} } "$ts  $msg\n" if $c->{log_fh};
    } # applog

Use `util::applog` for app-level debug output. Keep STDERR for genuine
startup/crash errors only (it is noisy and mangles UTF-8 under mod_fcgid).

**Test after A3:** Log file appears, entries written on page loads under plain CGI.

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

In `index.fcgi`, move everything from the `$c_auth` construction down to (and
including) `htmlfooter()` inside:

    while (my $q = CGI::Fast->new) {
        # 1. Send HTTP headers directly (goes to FCGI::Stream as ASCII bytes — safe):
        print $q->header(...);

        # 2. Buffer all body output via select + :utf8 scalar:
        my $body = '';
        open my $buf, '>:utf8', \$body or die $!;
        my $old_fh = select $buf;

        # ... all per-request code, all module print statements unchanged ...

        # 3. Restore and emit:
        select $old_fh;
        print $body;   # already UTF-8 bytes, no Encode needed
    }

All `exit` calls were already replaced with `next`/`return` in A1.

Under plain CGI, `CGI::Fast->new` returns an object once then undef — the loop
runs exactly once, identical to current behaviour. Safe to test under plain CGI.

### B3. Force-reload via URL parameter

In `index.fcgi`, add at the top of the loop after auth:

    if ($c->{devversion} && util::param($c, 'reload')) {
        print $q->header(-status => '302 Found', -location => $c->{url});
        exit(0);
    }

Add a **Reload** link in the dev-mode page header pointing to `$c->{url}?reload=1`.
Under plain CGI this is a no-op (just loads the front page). Under FastCGI it
kills the process; the follow-up GET hits a fresh one loaded from disk.

**Test after B1–B3:** Hit `index.fcgi` directly in the browser. Full regression:
page loads, POST, export, auth failure, UTF-8 characters. Check log file written.
Check reload link kills and respawns the process (PID changes). `index.cgi`
continues to work normally throughout.

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

**Test after C:** Same regression as Phase B, now via the default URL (no
explicit filename). Confirm process persistence via the reload link and log file.

## Phase D: Persistent ro database handle (follow-up)

Once FastCGI is stable, declare `my $dbh_ro` outside the loop.
In the GET path, replace `db::open_db($c, "ro")` with a reconnect-if-needed
pattern using `$dbh_ro->ping`.
POST continues to open a fresh rw handle per request.

## Follow-ups

- **In-process caching**: with a persistent process, module-level caches become
  viable. `selectbrew` and other heavy queries are candidates. To be planned
  separately.
- **fcgid tuning**: if process count or memory use becomes an issue, look at
  `FcgidMaxRequestsPerProcess`, `FcgidMaxProcesses`, etc. Not needed upfront.
