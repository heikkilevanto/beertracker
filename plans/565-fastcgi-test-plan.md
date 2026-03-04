# Plan: test.fcgi — FastCGI demonstration page

## Goal

Create `code/test.fcgi`, a minimal standalone script that proves the FastCGI process stays in memory between requests. No integration with the main beertracker app.

## How FastCGI demonstrates persistence

A plain CGI script is a new process for every request — PID changes, all variables reset. A FastCGI process runs a `while` loop and handles many requests in a single persistent process. The proof is:

- **PID** (`$$`) — same value across all requests until Apache restarts the process.
- **Request counter** — a module-level `my $count` declared outside the loop; increments each request.
- **Start time** — stays constant; age of process grows with each request.

## Script structure (pseudocode only)

```
#!/usr/bin/perl
use CGI::Fast

declare $count, $pid, $start_time outside the loop

while CGI::Fast->new gives a new request:
    increment $count
    output HTML page showing:
        - PID
        - request count
        - start time and age of process
        - current time
        - instruction to reload and watch count/age grow while PID stays fixed
```

## Perl dependency

`CGI::Fast` is not in core Perl. On Debian/Ubuntu:

```
apt install libcgi-fast-perl   # pulls in libfcgi-perl
```

Check if already installed: `perl -e 'use CGI::Fast'`

## Apache dependency

Regular CGI uses `mod_cgi`. FastCGI needs a different module. Two main options:

### Option A: mod_fcgid (recommended)

Debian package `libapache2-mod-fcgid`. Manages the persistent process itself — Apache spawns and reaps `.fcgi` processes automatically.

Config needed (in the existing VirtualHost or .htaccess):
```
LoadModule fcgid_module ...   # or: a2enmod fcgid
AddHandler fcgid-script .fcgi
```
The directory containing `test.fcgi` must already have `Options +ExecCGI`.

### Option B: mod_fastcgi

Older and less maintained; skip unless mod_fcgid is unavailable.

### Option C: mod_proxy_fcgi + external process manager (e.g. spawn-fcgi)

More complex; overkill for a demo.

**Recommendation: Option A (mod_fcgid).**

## File location

`code/test.fcgi` alongside `code/index.cgi`. The existing Apache config already serves `code/` with `ExecCGI`, so adding the handler for `.fcgi` should be sufficient.

## Apache config changes needed

In `etc/apache-config.example.txt` (the live config), add inside or after the existing `<Directory>` block for `code/`:

```apache
LoadModule fcgid_module /usr/lib/apache2/modules/mod_fcgid.so
AddHandler fcgid-script .fcgi
```

Or alternatively enable globally via `a2enmod fcgid` and add only `AddHandler fcgid-script .fcgi` in the VirtualHost.

## Steps to implement

1. Install `libapache2-mod-fcgid` and `libcgi-fast-perl` if not present.
2. Add `AddHandler fcgid-script .fcgi` to Apache config; reload Apache.
3. Write `code/test.fcgi` with the loop structure above; `chmod +x`.
4. Load the URL in a browser, reload several times, confirm:
   - counter increments
   - PID stays the same
   - start time stays the same
5. Restart Apache (`apache2ctl restart`); reload again, confirm counter resets and PID changes.

## What success looks like

```
FastCGI demo
PID:      12345   ← constant across reloads
Requests: 7       ← increments each reload
Started:  2026-03-04 10:00:00 (43 seconds ago)
Now:      2026-03-04 10:00:43
```

After Apache restart: counter resets to 1, new PID shown.

## Out of scope

- Integration with beertracker `$c` context or database.
- Converting `index.cgi` to FastCGI (that is a separate, larger task).
