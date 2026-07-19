# 716 Move `_list` views to inline SQL in Perl

Eliminate migration churn for list view layout changes. Keep utility views
(`brew_ratings`, `glassrec`, `LatestPrices`, `brew_taps`, `loc_ratings`,
`location_ratings`, `current_taps`) as DB views — they are stable and reused
across modules via direct SQL.

## Strategy

New `listrecords` signature: `($c, $sql, $sort, $opt)`.

Backward compat heuristic: if `$sql` starts with `SELECT` (case-insensitive),
treat it as inline SQL. Otherwise treat it as a view name and build
`"SELECT * FROM $sql"`. This allows migrating callers one by one without
breaking the rest.

---

## Stage 1: `code/listrecords.pm`

Signature changes from `($c, $table, $sort, $opt)` to `($c, $sql, $sort, $opt)`.

- If `$sql =~ /^SELECT/i` → inline SQL mode. Field names from `$sth->{NAME}`
  (prepare once without ORDER BY). `$sort` detection loop still applies if
  `$sort` is non-empty and no `ORDER BY` in `$sql`.
- Else → view mode. Treat `$sql` as view name, build `"SELECT * FROM $sql"`.
  Field names from `PRAGMA table_info` (current behavior). `$sort` detection
  unchanged.
- Suffix parsing, rendering — identical to current logic in both modes.
- Cache key uses `$sql` text instead of `$table`.
- Log messages reference `$sql` instead of `$table`.

Also: suffix parser accepts both `:` and `=` as separators in
`_as:Name` / `_as=Name` and `_link:Entity` / `_link=Entity`. This allows later
stages to use `=` (avoiding DBI named-parameter conflicts with `:`) while the
views still use `:`.

**No callers change in this stage.** Existing calls still pass a view name in
the `$sql` slot, which the heuristic detects and wraps automatically.

### Test
```bash
perl -c code/listrecords.pm
# Visit ?o=Brew, ?o=Comment, ?o=Location, ?o=Person, ?o=Photos
# All pages should render identically to before
```

## Stage 2: Proof of concept — `brews.pm`

Migrate the two brew-specific views:

- `brews.pm:23` — replace `"BREWS_LIST"` with inline SQL from mig_041.
  Use `=` instead of `:` in column suffixes (e.g., `_link=Brew`).
  `$sort` can be dropped (ORDER BY embedded in SQL).
- `brews.pm:223` — replace `"BREWS_DEDUP_LIST"` with inline SQL from mig_038.
  Use `=` instead of `:` in column suffixes.
  Keep `$sort` dynamic (the caller already sets it from `$c->{sort}`).

### Test
```bash
perl -c code/brews.pm code/listrecords.pm
touch code/VERSION.pm
# Visit ?o=Brew — brew listing renders identically (sort, filter, paginate)
# Visit a brew with ?e=X — sibling comments section still works
# Visit a brew with dedup enabled — dedup list renders with similarity sorting
```

## Stage 3: `code/comments.pm` helper

Add `sub comments_list_sql` returning the `COMMENTS_LIST` SQL (from mig_046),
using `=` instead of `:` in column suffixes.

Update 8 call sites across 4 modules — replace `"COMMENTS_LIST"` with
`comments::comments_list_sql()`:
- `comments.pm` lines 154, 420, 440, 462
- `locations.pm` lines 321, 334
- `brews.pm` line 456
- `persons.pm` line 73

Also rewrite 3 direct count queries against `COMMENTS_LIST` (comments.pm lines
414, 436, 456) to use base tables directly — these reference suffixed column
names (`"Id_A_link:Comment"`) which is fragile.

### Test
```bash
perl -c code/comments.pm code/locations.pm code/brews.pm code/persons.pm
touch code/VERSION.pm
# Visit ?o=Comment — comment listing renders identically
# Visit ?o=Brew&e=X — brew comments section renders
# Visit ?o=Location&e=X — location comments & producer comments render
# Visit ?o=Person&e=X — person comments section renders
# Each sibling comment section (same brew / same location / same person)
#   at the bottom of an edit page should render correctly
```

## Stage 4: Remaining views

Replace view name with inline SQL from migrate.pm (use `=` instead of `:`):

| File | Line | View | SQL source |
|------|------|------|------------|
| `locations.pm` | 34 | `LOCATIONS_LIST` | mig_043 |
| `locations.pm` | 110 | `producer_brews_list` | mig_037 |
| `locations.pm` | 142 | `LOCATIONS_DEDUP_LIST` | mig_037 |
| `persons.pm` | 20 | `PERSONS_LIST` | mig_042 |
| `photos.pm` | 327 | `PHOTOS_LIST` | mig_045 |

Also rewrite `locations.pm:106` — `SELECT count(*) FROM producer_brews_list ...`
→ direct join of `brews` + `glasses` + `locations`.

### Test
```bash
perl -c code/locations.pm code/persons.pm code/photos.pm
touch code/VERSION.pm
# Visit ?o=Location — location listing renders (sort, filter)
# Visit a producer location — producer brews count shows, list renders
# Visit ?o=Location&e=X&edit=1 — dedup list renders with geo distance
# Visit ?o=Person — person listing renders
# Visit ?o=Photos — photo listing renders (sort, filter)
```

## Stage 5: `code/migrate.pm`

Add migration 47 dropping all 8 `_list` views, bump `$CODE_DB_VERSION` to 47:

```sql
DROP VIEW IF EXISTS locations_list;
DROP VIEW IF EXISTS producer_brews_list;
DROP VIEW IF EXISTS locations_dedup_list;
DROP VIEW IF EXISTS brews_list;
DROP VIEW IF EXISTS brews_dedup_list;
DROP VIEW IF EXISTS comments_list;
DROP VIEW IF EXISTS persons_list;
DROP VIEW IF EXISTS photos_list;
```

### Test
```bash
perl -c code/migrate.pm
touch code/VERSION.pm
# Visit the app to trigger migration check, confirm migration runs
sqlite3 beerdata/beertracker.db \
  "SELECT name FROM sqlite_master WHERE type='view' AND name LIKE '%_list%'"
# Should return no rows
# Visit ?o=Brew, ?o=Comment, ?o=Location, ?o=Person, ?o=Photos
# All pages should render identically (SQL is now in Perl)
```

## Stage 6: Remove backward compat heuristic and `:` handling

Once all callers pass proper SQL (start with `SELECT`), remove the view-name
fallback in `listrecords.pm`. The heuristic is no longer needed and the
`else` branch (view name → `"SELECT * FROM $sql"`) can be deleted, leaving
only the inline SQL code path.

Also remove `:` from the suffix parser regexes (`_as[=:]` → `_as=`,
`_link[=:]` → `_link=`). Only `=` remains as the separator.

### Test
```bash
perl -c code/listrecords.pm
touch code/VERSION.pm
# Visit ?o=Brew, ?o=Comment, ?o=Location, ?o=Person, ?o=Photos
# All pages should render identically
sqlite3 beerdata/beertracker.db \
  "SELECT sql FROM sqlite_master WHERE type='view' AND name LIKE '%_list%'"
# Still empty — no _list views left in DB
```
