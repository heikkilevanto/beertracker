# 748 - Per-user subdirectories in beerdata

Group each user's graph files, plot/cmd files, and photo directory into a
`beerdata/<username>/` subdirectory. Only global things (the DB, debug logs,
dumps, scrape logs) stay directly in `beerdata/`.

## Target layout

Keep the current filenames, just nest them:

```
beerdata/
  (global only)  beertracker.db*  db.dump  data.dump  debug.log*  scrapeall.log*  production->symlink
  heikki/        heikki.plot  heikki.cmd  heikki-pr.plot  heikki-pr.cmd  heikki.last
                 heikki-2026-07-21-2026-08-21.png  heikki-stat.png  heikki-ratings.png
                 heikki.yearbars-N.png
                 heikki.photo/          # photos + export tarballs
  dennis/        dennis.photo/
```

No Apache config change needed: the photo dir keeps the `.photo` suffix, so the
existing `beerdata/.*\.photo` grant and the `.png` FilesMatch already cover the
nested paths.

## Code changes

### code/index.fcgi (~line 213-236)
After the username validation, build the per-user dir and use it:

```perl
my $usrdir = $datadir . $username . "/";
unless ( -d $usrdir ) {
  mkdir $usrdir or util::error("Could not create $usrdir: $!");
}
...
$plotfile = $usrdir . $username . ".plot";
$cmdfile  = $usrdir . $username . ".cmd";
$photodir = $usrdir . $username . ".photo";
```

Add `'usrdir' => $usrdir,` to the `$c` hash.

### code/graph.pm
- `clearcachefiles` (~26-45): iterate `glob($usrdir."*")`, skip directories
  (the photo dir) and skip `.data` files, unlink everything else (png/plot/cmd/
  last), recreate `username.last`. Drop the old root-level iteration and the
  `-M > 7` age rule - nothing per-user lives at root anymore.
- `graph()` (402-404): build `$g->{plotfile}`, `$g->{cmdfile}`, `$g->{pngfile}`
  from `$c->{usrdir}`, not `$c->{datadir}`.

### code/yearstat.pm:191
`my $pngfile = $c->{usrdir} . $c->{username} . ".yearbars-$n$suffix.png";`

### code/export.pm
Add a helper and use it at the four `$c->{datadir} . $user . ".photo"` sites
(lines 151, 194, 463, 479):

```perl
sub user_photodir {
  my ($c, $user) = @_;
  return $c->{datadir} . $user . "/" . $user . ".photo";
}
```

### code/superuser.pm copyproddata
No change. Photos are not synced from prod while prod still uses the old
layout; copyproddata is simply not used until prod is migrated.

### No change needed
- `monthstat.pm`, `ratestats.pm` - derive their PNGs from `$c->{plotfile}`.
- `photos.pm` - already uses `$c->{photodir}`; its `mkdir` parent (`<user>/` )
  now exists thanks to index.fcgi.
- Apache config - see above.

## New tool: tools/move-userdata.sh

Idempotent bash script, run from the repo root. This is the manual step for the
production migration (run after `git pull`).

For each user found via `beerdata/*.photo` dirs or `beerdata/*.plot` files:

1. `mkdir -p beerdata/<username>/`
2. If `beerdata/<username>.photo` exists: `mv` it to
   `beerdata/<username>/<username>.photo`
3. For every remaining `beerdata/<username>*` file (plot, cmd, last, `-pr.*`,
   `-*.png`, `.yearbars-*`, old `-price` names): move it into the subdir.
4. Delete legacy `beerdata/<username>.data` archives.
5. Leave the `production` symlink and all global files alone.
6. Report each action; safe to re-run (skip when target already exists).

## Documentation
- Update `doc/design.md:97` photo path to
  `beerdata/<username>/<username>.photo`.
- Commit message must note the manual production step: run
  `tools/move-userdata.sh` from the repo root after the git pull.

## Execution & verification (dev)
1. Apply code changes; `perl -c` each modified module.
2. Run `tools/move-userdata.sh` in dev to restructure `beerdata/`.
3. Touch `code/VERSION.pm` to reload.
4. Under Apache verify: Graph (including price mode), Months, Years, Ratings
   generate the new PNGs; Photos still display; Export tarball link works; a
   POST clears the user dir's cached files.

## Production rollout
- `git pull` the new code in prod.
- Run `tools/move-userdata.sh` from the repo root (moves prod files, deletes
  the `.data` archives).
- Until that is done, do not use copyproddata.