# Plan: Replace STDERR logging with a log file handle (issue 566)

## Goal
Stop writing debug log messages to STDERR (which is polluted by FastCGI noise)
and instead write them to a dedicated log file, accessed via `$c->{log}`.

## Log file location
`beerdata/debug.log`

Open in append mode (`>>`).

## Log rotation (on every startup)
Before opening the file, check its size.  If it exceeds 1 MB, rotate:
- `debug.log.2` → `debug.log.3`  (drop if `.3` already exists)
- `debug.log.1` → `debug.log.2`
- `debug.log`   → `debug.log.1`

Keep at most 3 old generations.  Then open a fresh `debug.log`.

## Changes to index.cgi

### 1. Open the log file early (before $c is built)

Near the top of the "Main program" section — right after `login::authenticate()`
succeeds and before the first `print STDERR` — add:

```perl
# Open log file (rotate if > 1MB, keep 3 generations)
my $logfile = $datadir . "debug.log";
if ( -f $logfile && -s $logfile > 1_000_000 ) {
  for my $n ( reverse 1..2 ) {
    rename "$logfile.$n", "$logfile." . ($n+1) if -f "$logfile.$n";
  }
  rename $logfile, "$logfile.1";
}
open( my $log, ">>", $logfile )
  or die "Cannot open log file $logfile: $!\n";
binmode $log, ":utf8";
```

At this point `$datadir` is already set, so this works.

### 2. Assign `$c->{log}` when $c is built

In the `my $c = { ... }` block, add:

```perl
'log' => $log,
```

### 3. Replace all `print STDERR` in index.cgi

Replace every `print STDERR` with `print $c->{log}` where `$c` is in scope.

The two early prints that fire *before* `$c` is built (the timestamp header and
the `copyproddata` line) should use the plain `$log` variable instead:

```perl
print $log  "\n\n" . $now->ymd . ...
print $log "Copying prod data to dev \n";
```

## Changes to all other modules

Every module that currently calls `print STDERR` already receives `$c` as its
first argument, so replace:

```perl
print STDERR "some message\n";
```

with:

```perl
print $c->{log} "some message\n";
```

Modules to update (all are in `code/`):
- `db.pm`       — several prints; all are inside functions that receive `$c`
- `util.pm`     — `util::error()` prints to STDERR; it receives `$c`
- `glasses.pm`
- `taps.pm`
- `yearstat.pm`
- `brews.pm`
- `styles.pm` — the one commented-out line.

Also convert any commented-out `#print STDERR` lines in those files to use
`$c->{log}` so they remain useful when uncommented.

## Do NOT change
- `code/test.fcgi` — leave its `print STDERR` calls as-is for now.

## Verification
After the changes:
1. Run `perl -c code/index.cgi` and `perl -c` on each changed module.
2. Make a test request in the dev environment and confirm messages appear in
   `beerdata/debug.log` and *not* in the Apache error log.
3. Confirm that a >1 MB log triggers rotation on the next request.
