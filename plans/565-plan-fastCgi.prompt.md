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
`binmode STDOUT, ':utf8'` is silently ignored, even when set inside the loop.

Any wide-character string (Unicode code point > 127) printed directly will
produce the warning:
> Use of wide characters in FCGI::Stream::PRINT is deprecated

**Fix**: use `Encode::encode_utf8()` to convert to bytes before printing:

    use Encode ();
    print Encode::encode_utf8($html);

Implication for beertracker: `index.cgi` and all modules contain hundreds of
bare `print` statements and `print qq{...}` blocks that produce HTML. With
`use utf8` in effect, all literals with non-ASCII characters (em dashes,
Scandinavian chars in hardcoded strings, etc.) are wide strings. Every `print`
path that reaches STDOUT needs to go through `Encode::encode_utf8`.

Options to consider:
1. Wrap every HTML-producing print in `encode_utf8(...)` — verbose and error-prone.
2. Build the full HTML response into a scalar, then `print encode_utf8($output)` once per request.
3. Tie or replace STDOUT with an encoding wrapper at the top of each loop iteration.

Option 2 (accumulate then print) is the cleanest for beertracker's existing
`print` style — replace `print` with `$out .= ` in HTML-producing code, then
emit at the end.  That is a substantial refactor.

Option 3 could be done with `tie` or by redirecting to an `IO::String`/`PerlIO`
wrapper. Needs investigation.

This is the biggest migration challenge. Needs a clear strategy before Phase B.

### Dedicated log file for beertracker

Under plain CGI, STDERR goes to the Apache error log and is readable.
Under mod_fcgid, every STDERR line is prefixed with Apache timestamp, fcgid
module info, PID, thread, and client IP — making it hard to read app-level log
lines.

Example of what a single `print STDERR "..."` produces in the error log:
    [Wed Mar 04 12:52:54.978840 2026] [fcgid:warn] [pid 1601283:tid 1601315] [client 192.168.0.2:52970] mod_fcgid: stderr: test.fcgi: pid=1601933 request=3, referer: ...

For a high-request app this becomes noisy fast. Consider:
- Opening a dedicated log file (e.g. `beerdata/beertracker.log`) at startup
  (outside the loop) and writing app log lines there.
- Keep STDERR for genuine errors only.
- The log file path can be derived from `$c->{basedir}` so it works in both
  prod and dev.

## Apache Config Strategy

Both prod and dev run on the same machine; Apache points directly at the
git-tracked `etc/apache-config.example.txt`. Single-user, so downtime is
acceptable.

Plan: complete and test Phases A+B under plain CGI first (no Apache change
needed). When ready for Phase C, edit the single config file, install fcgid,
and restart Apache.

Rollback if needed:
    git checkout etc/apache-config.example.txt
    sudo systemctl restart apache2

## Phase A: Module fixes (safe under plain CGI, testable immediately)

### A1. Remove leftover `exit()` in modules
These are all safe to change now — plain CGI is unaffected.

| Location | Current | Fix |
|---|---|---|
| monthstat.pm line 362 | `exit()` leftover at end of function | Remove; falls through to caller |
| superuser.pm line 56 — `copyproddata()` | `exit()` after redirect | Change to `return` |
| util.pm line 181 — `util::error()` | `exit()` after printing error | Change to `die $msg` (POST eval already catches it; add a bare `eval` wrapper in GET path too) |
| index.cgi line 123 — auth failure | `exit 0 unless $username` after 401 sent | Change to `next unless $username` inside the request loop |

**Test after A1:** Normal page load, bad-password 401, error condition, monthstat page — all should work under plain CGI.

### A2. Fix `htmlhead()` to use `$c`
`htmlhead()` currently closes over the package-level `$q` directly (~line 339).
Change its signature to accept `$c` and use `$c->{cgi}` inside.
Update the one call site (`htmlhead($c)`).

**Test after A2:** Any page render — headers, cookies, CSS links should be unchanged.

## Phase B: Add CGI::Fast loop (safe under plain CGI)

### B0. Install dependencies
    apt install libfcgi-perl libcgi-fast-perl

(mod_fcgid is not needed yet — that's Phase C.)

### B1. Replace `use CGI` with `use CGI::Fast`
`CGI::Fast` is a drop-in subclass of `CGI`. Under plain CGI it behaves
identically. Replace:

    use CGI qw( -utf8 );
    my $q = CGI->new;
    $q->charset("UTF-8");

with:

    use CGI::Fast qw( -utf8 );

### B2. Wrap request body in the FastCGI loop
Move everything from the `$c_auth` construction down to (and including)
`htmlfooter()` inside:

    while (my $q = CGI::Fast->new) {
        # NOTE: binmode STDOUT, ":utf8" does NOT work here — FCGI::Stream ignores PerlIO layers.
        # All HTML output must be encoded with Encode::encode_utf8() before printing.
        # See "Lessons learned" section above for the full discussion.
        # ... all per-request code ...
    }

Replace all `exit` calls inside the loop with `next`:
- After `copyproddata` redirect
- After POST redirect
- After `do_export`

Remove the `exit()` at the very end of the GET dispatch (falls through to `}`).

Under plain CGI, `CGI::Fast->new` returns an object once then undef, so the
loop runs exactly once — identical to current behaviour.

**Test after B1+B2:** Full regression under plain CGI: page loads, POST, export, auth failure.

## Phase C: Switch Apache to FastCGI

### C1. Prerequisites on server
    apt install libapache2-mod-fcgid
    a2enmod fcgid

### C2. Edit Apache config
In `etc/apache-config.example.txt` change `SetHandler cgi-script` →
`SetHandler fcgid-script`. Restart Apache.

Rollback: `git checkout etc/apache-config.example.txt && sudo systemctl restart apache2`

**Test after C:** Same as Phase B regression, plus confirm process persistence
(e.g., check that module-level state survives across requests with STDERR logging).

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
