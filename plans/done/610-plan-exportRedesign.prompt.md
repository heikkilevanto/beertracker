# Plan: Redesign export.pm

## TL;DR

Rewrite export.pm to behave like a normal module (no DoExport special case), show data in `<pre>` blocks or bundle SQL + photos into a .tar.gz in the user's photo dir (served directly by Apache). Expand data coverage to include comments, photos, and comment_persons. Add tap_beers option.

---

## Decisions

- **No special handling in index.fcgi** — remove DoExport check; single `Export` op for all cases.
- **Download = tarball** — .tar.gz created in `$c->{photodir}`, Apache serves it directly (photo dir is `Require all granted`).
- **Display = on-screen `<pre>` per table** in normal HTML page.
- **Public records** — NOT included (user-only export).
- **tap_beers** — select a) all in date range, b) for referenced brews, c) none.
- Form method stays GET; tgz generation on GET is idempotent (can regenerate on same params).

---

## Steps

### Phase 1 — index.fcgi cleanup
1. Remove lines 326–329 (the DoExport special case before htmlhead).
2. The existing `} elsif ( $c->{op} =~ /Export/i )` dispatch already routes to `export::exportform($c)` — change that call to `export::exportpage($c)`.

### Phase 2 — export.pm rewrite

#### Form changes
3. Change form hidden `o` value from `DoExport` to `Export`.
4. Replace `action` select "download" → "tarball". Add "tarball w photos"
5. Add `taps` select: "No tap data" / "Taps for referenced brews" / "All taps in date range".
6. Keep `schema` select "data only" / "drop+create"
6b. For the superuser, add a selection for `username` (list of all users) — allows exporting other users' data (for admin purposes).

#### Data collection
7. New `collect_ids($c, $datefrom, $dateto, $mode, $taps_mode)` function:
   - glasses: `WHERE Username=? AND strftime('%Y-%m-%d', Timestamp, '-06:00') BETWEEN ? AND ?`
   - comments: `WHERE Username=? AND strftime('%Y-%m-%d', Ts, '-06:00') BETWEEN ? AND ?`
   - photos: `WHERE Uploader=? AND strftime('%Y-%m-%d', Ts, '-06:00') BETWEEN ? AND ?`
   - comment_persons: for selected comment IDs
   - brews: referenced by glasses.Brew + comments.Brew (partial) or all (full)
   - locations: referenced by glasses.Location + brews.ProducerLocation (partial) or all (full)
   - persons: referenced via comment_persons (partial) or all (full)
   - tap_beers: none / for brew IDs / by date range

#### SQL generation
8. New `generate_sql($c, $ids_ref, $schema)` function — returns string of SQL INSERT statements, grouped by table (for `<pre>` rendering).
   - Order of tables: locations, brews, persons, glasses, comments, photos, comment_persons, tap_beers
   - Returns arrayref `[ { table => $name, sql => $text } ]` — one entry per table

#### Display mode
9. New `show_export($c)` function:
   - Calls collect_ids + generate_sql
   - Prints HTML: header section showing export params, then for each table one `<pre>` block

#### Tarball mode
10. New `make_tarball($c)` function:
    - Deletes old tarballs in photo dir 
    - Generates SQL string (same as display)
    - Writes `data.sql` to photo dir
    - Creates `photos/` subdir; copies `+orig.jpg` files for each photo record
    - Runs `tar czf "$c->{photodir}/beertracker_export_${username}_${date}.tar.gz" -C $tmpdir .`
    - deletes data.sql from photo dir

#### Unified entry point
11. New `export_page($c)` function:
    - No action param → call exportform
    - action=display → call show_export
    - action=tarball → call make_tarball and then call exportform (to show the form again with the link)

### Phase 3 — Schema option decision
12. Keep the `schema` (drop+create) select for now — it's useful for DB restore. Include it in phase 2 `generate_sql` logic.

---

## Relevant files

- `code/export.pm` — full rewrite of existing module
- `code/index.fcgi` — lines 326–329 (remove DoExport), line 379 (change exportform → export_page)

## Verification

1. Visit `?o=Export` — form should appear (no output change)
2. Select display, submit → page shows one `<pre>` per exported table
3. Select tarball, submit → page shows "Download tarball" link; file exists in `beerdata/heikki.photo/`; link works (Apache serves it); tar contains `data.sql` + `photos/` subdir
4. Verify comments exported by date (not just glass-linked)
5. Verify photos table records + physical files in tarball
6. Verify comment_persons records included
7. Verify tap_beers options work (a/b/c)
8. Verify `perl -c code/export.pm` passes

## Further considerations

- Old tarball cleanup: could delete tarballs older than e.g. 7 days on next export. Not strictly necessary for now.
- The schema option (drop+create) — keep it for now, it's useful.
