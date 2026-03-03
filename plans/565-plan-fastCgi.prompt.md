# Plan: Switch index.cgi to FastCGI (issue 565)

Wrap the request body in a `CGI::Fast` loop, split per-process vs per-request
init, persist the ro dbh, and fix all `exit` calls. The `$c` hash itself is
rebuilt per-request as today — only module-level state and the dbh persist.

Key insight: `CGI::Fast` falls back silently to plain CGI behaviour when not
running under FastCGI (it checks for the FCGI socket). This means Phase A and B
can be done, tested, and merged while still running plain CGI. The actual
switch to FastCGI is just an Apache config change in Phase C.


DID NO WORK! FastrCgi did spawn a new process every time, just slowing things
down. Claude talsk about needing spawn-fcgi + mod_proxy_fcgi instead of mod_fcgid, but that seems like a much bigger change. Maybe later...
Stage A changes done and seem to work. The rest is stashed away.


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
        binmode STDOUT, ":utf8";  # reset per request
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
