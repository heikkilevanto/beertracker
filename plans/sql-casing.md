# Plan: Standardize SQL keyword case (audit P1)

## Goal
Make all SQL keywords uppercase (`SELECT`, `FROM`, `WHERE`, ...) in every SQL string/fragment in `code/*.pm`, per the AGENTS.md SQL style rule ("Use uppercase for keywords: SELECT, INSERT, UPDATE"). Purely cosmetic — SQLite keywords are case-insensitive, so behavior is unchanged. **Scope: `code/*.pm` only.**

## Canonical keyword list
Uppercase these as whole words when they appear in SQL text:

`SELECT FROM WHERE AND OR NOT NULL IS IN LIKE BETWEEN EXISTS AS ON JOIN LEFT RIGHT INNER OUTER CROSS NATURAL GROUP BY HAVING ORDER LIMIT OFFSET DISTINCT UNION ALL INSERT INTO VALUES UPDATE SET DELETE CREATE ALTER DROP TABLE INDEX VIEW IF WITH CASE WHEN THEN ELSE END ASC DESC BEGIN TRANSACTION COMMIT ROLLBACK PRAGMA DEFAULT COLLATE`

**Aggregates and scalar functions are left exactly as they are** (`count`, `sum`, `min`, `max`, `avg`, `abs`, `strftime`, `julianday`, `cast`, `group_concat`, `coalesce`, `row_number`). We only convert keywords; existing uppercase `COUNT`/`SUM` occurrences are not touched back down.

## Rules (protect from accidental edits)
1. **Never touch** content inside single quotes — `''`, `'Adjustment'`, `'-06:00'`, `'%Y-%m-%d %H:%M:%S'`, `'Producer'`, `'Beer'`, `'now'`, `'localtime'`, `'+5 minutes'`.
2. **Never touch** double-quoted identifiers/aliases — `"Id_A_link=Brew"`, `"Last"`, `"Day"`, `"Type_A"`.
3. **Never touch** Perl interpolation — `$table`, `$field`, `?`, `$sql_param`, `$calmon_expr`, `$where`, `$collate`, `%Y` etc.
4. Table/column names and aliases keep their existing case (`GLASSES` vs `glasses`, `id` vs `Id`) — identifier case is a separate concern, out of scope.
5. Never touch Perl/HTML/JS/regex/comments/log strings: `select $old_fh`, `<select>`, `'select'` in regexes, `# ... update ...` comments, `util::error("Failed to update ...")`.

## Worklist with commit points
Each file: edit only keywords to uppercase, then `perl -c code/<file>.pm` before moving on.

### COMMIT POINT 1 — core helpers & dynamic fragments
Commit message: `Standardize SQL keyword case in db.pm and listrecords.pm (Fix #plan audit P1)`
- **db.pm** — 294, 313, 357–358, 405–407, 470: `select * from $table where ...` → `SELECT * FROM ... WHERE`; `delete from ... where` → `DELETE FROM ... WHERE`; `update ... set ... where` → `UPDATE ... SET ... WHERE`; `insert into ... values` → `INSERT INTO ... VALUES`. (L92, L110 already UPPER — verify only.)
- **listrecords.pm** — 166: `$order = "Order by $orig_fields[$i]"` → `"ORDER BY ..."`; 181: `$where = "where $where"` → `"WHERE $where"`; 183: `"select * from ($sql_param) $where $order"` → `SELECT * FROM ...`. (L91 `"$sql_param LIMIT 0"` already UPPER.)

### COMMIT POINT 2 — glass entry/display
Commit message: `Standardize SQL keyword case in postglass, glasses and beerboard (Fix #plan audit P1)`
- **postglass.pm** — 32–33: `delete from GLASSES where ... and ...` → `DELETE FROM ... WHERE ... AND`; 133–146: `update GLASSES set ... where ... and ...` → `UPDATE ... SET ... WHERE ... AND`; 165–169: `insert into GLASSES (...) values (...)` → `INSERT INTO ... VALUES`; 263–266: `select ... from GLASSES where ... and ... order by ... limit 1` → UPPER.
- **glasses.pm** — 53: `select distinct BrewType from Glasses WHERE ...` → `SELECT DISTINCT ... FROM ... WHERE`; 76–80: `WHERE BrewType in (...)` → `IN` (rest already UPPER); 257–260, 263–264: `select id/* ... where ... and ...` → `SELECT/FROM/WHERE/AND`.
- **beerboard.pm** — 245–248: `select * from glassrec where ... order by ... limit 1` → `SELECT * FROM ... WHERE ... ORDER BY ... LIMIT`. (L265–296 already UPPER.)

### COMMIT POINT 3 — main list, topstats, graph
Commit message: `Standardize SQL keyword case in mainlist, util and graph (Fix #plan audit P1)`
- **mainlist.pm** — 25–64: `glassquery` q{} incl. subqueries `(select count(*) from comments/photos ...)` → `(SELECT count(*) FROM ...)`; 131–142: `bloodalc` q(); 273–281: `commentlines` `select COMMENTS.* ...`. (L597–604 already UPPER — verify only.)
- **util.pm** — 280–293: `topstats` `select ... sum(CASE WHEN ... THEN ... ELSE ... END) as price, ... from GLASSES where ... and effdate = ( select max (...) from GLASSES where ... and (...) ) and (...)` → UPPER keywords.
- **graph.pm** — 166–182: `SELECT ... from GLASSES where ... and ... and ... order by ...` → `FROM/WHERE/AND/ORDER BY`.

### COMMIT POINT 4 — list modules
Commit message: `Standardize SQL keyword case in comments, persons, locations and brews (Fix #plan audit P1)`
- **comments.pm** — 171–178: `commentlines` `select COMMENTS.* ... from ... left join ... on ... where ... group by ... order by ...` → UPPER. (Rest already UPPER.)
- **persons.pm** — 143–155: `selectperson` `select PERSONS.Id ... from PERSONS left join ... group by ... order by` → UPPER. (L30–50 already UPPER.)
- **locations.pm** — 71–88: ratings subquery in `listlocations` (incl. `union all`, `$username` interpolation stays); 112–121: `locationvisits` q{}; 165–184: `producerbrews` q{} `with users as (...) select ...`; 536–545: `$where` fragments → `WHERE`, `IS NULL OR`; 552–568: `selectlocation`. (L426–431, L634–641 already UPPER.)
- **brews.pm** — 45–76, 276–298: `listbrews` q{} (two variants) `with users as (...) select ... from ... cross join ... left join ... on ... and ... group by ... ORDER BY`; 318, 335: dropdown queries; 665–668: dedup queries `left join GLASSES on ...`, subquery `(select brew, rating_count, ...`.

### COMMIT POINT 5 — stats modules
Commit message: `Standardize SQL keyword case in yearstat, monthstat, stats and ratestats (Fix #plan audit P1)`
- **yearstat.pm** — 254–260, 269–272, 274–278, 286–290: `select distinct/min/max ... from glasses where ... and ... as integer` → UPPER; 301–322: big query incl. `CASE WHEN ... THEN ... ELSE ... END`, `count(distinct(...))`, appended `order by ... COLLATE NOCASE` at 317/320. (L42–54 already UPPER.)
- **monthstat.pm** — 31, 34, 38, 41: `$where_clause` fragments `"where ..."` → `WHERE`, `" and ..."` → `AND`, `" and (Brew is not null or BrewType = 'Adjustment')"` → `AND ... IS NOT NULL OR`; 43–56: qq{} summary query; 71–74: `select min(...) from glasses where ... and ...`.
- **stats.pm** — 38–39, 51–52, 64–65, 80–83, 96–99: `select ... from ... group by ... order by ... where ... COLLATE NOCASE` → UPPER. (L137–147 already UPPER.)
- **ratestats.pm** — 48–52, 55–58, 72–77: dropdown queries → UPPER. (L114–146, L294–320 already UPPER — verify only.)

### Verify-only (already fully UPPER, no edits expected)
`index.fcgi` (309/329/336), `taps.pm`, `scrapeboard.pm`, `export.pm`, `migrate.pm`, `photos.pm` (incl. `$where` q{} at 320–327), `aboutpage.pm`.

## Final verification
1. `perl -c` on every module in `code/`.
2. Review `git diff --word-diff` — every hunk must be pure keyword casing; nothing inside quotes, identifiers, or non-SQL strings.
3. Straggler sweep: `grep -nEi 'select |insert into |update |delete from | where |left join |group by |order by | values ' code/*.pm` and confirm each hit is already-UPPER, a comment, or a non-SQL false positive.
4. `touch code/VERSION.pm` (separate step, needs user approval) to force the FCGI reload and wipe the in-process Cache.pm.

## Manual tests (dev instance, Apache `/var/www/html/beertracker-dev`, login first)
Regression smoke tests after the VERSION.pm touch. Dev logs each SQL statement to error.log — eyeball that queries execute without "near syntax error".

| Route | Exercises | Check |
|---|---|---|
| `o=Graph` / `o=Board` / `o=Full` | graph.pm, glasses.pm, beerboard.pm, mainlist.pm, util.pm | Page renders, graph plots, top-stats row correct, main list with comments, empty-glass types (`'Adjustment'` literal) still filtered, location/brewtype dropdowns populated |
| `o=Years` (+ `?q=YYYY`, sort) | yearstat.pm | Summary, projection, stacked bar; `-06:00` grouping intact |
| `o=Months` (+ date-range filter) | monthstat.pm | Chart, adjustment CASE math, `$where_clause` fragments filter correctly |
| `o=short`, `o=DataStats` | stats.pm | Day stats; counts tables with `COLLATE NOCASE` ordering |
| `o=Ratings` (+ filters) | ratestats.pm | Histogram; dynamic `. WHERE ... AND ... GROUP BY` appends work |
| `o=Brew`, `o=Location`, `o=Person`, `o=Photo`, `o=Comment` | brews/locations/persons/photos/comments (listrecords CTEs) | Lists render, sort/filter, dropdowns, ratings/visits/comment counts |
| `o=About`, `o=migrate`, `o=Export` | aboutpage, migrate, export | Pages render |
| **POST / write paths** | postglass.pm, db.pm, comments.pm, brews/locations/persons forms | Add glass → appears; edit & save (UPDATE); delete (DELETE); `L` timestamp glass (`+5 minutes` query); add comment; create/edit brew/location/person (recursion in `insertrecord`); no errors in error.log |

## Out of scope
- `doc/db.schema` — generated artifact (dbdump.sh lowercases keywords); never edited directly.
- `tools/dbchange.sh`, `scripts/` — per scope choice.
- Comments containing SQL examples (`db.pm:193`, `migrate.pm:171`, postglass log line 39).
- Identifier/table-name casing (`GLASSES` vs `glasses`) — separate task.
