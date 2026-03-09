# Plan: Issue #405 - Comments data-model (phased)

**TL;DR:** Photos are already done (migrations 002-005). For issue #405, start at `mig_006` with one schema sweep: add explicit comment target/type fields plus a many-to-many person link table, then update read paths, then posting/UI, then legacy cleanup.

---

## Current baseline (as of this update)

- `code/migrate.pm` currently ends at DB version 5 (`mig_005_idx_photos_glass`).
- Photo migration is complete and should stay out of scope for this plan.
- Existing `comments` table still has legacy columns `Person` and `Photo`.

So this plan must **not** reuse `mig_005`.

---

## Phase 1 - Schema + migrate.pm (mig_006) ✓ DONE

Phase 1 is a single migration pass in one new migration function, recommended name:
- `mig_006_comments_model_phase1`

Update registry/version:
- `our $CODE_DB_VERSION = 6;`
- Add `[6, 'comments model phase 1 (types/location/visibility/multi-person)', \&mig_006_comments_model_phase1],`

### 1) Exact schema DDL

Add new columns to `comments`:

```sql
ALTER TABLE comments ADD COLUMN CommentType TEXT;
ALTER TABLE comments ADD COLUMN Ts DATETIME;
ALTER TABLE comments ADD COLUMN Location INTEGER;
ALTER TABLE comments ADD COLUMN Username TEXT;
```

Create multi-person join table:

```sql
CREATE TABLE IF NOT EXISTS comment_persons (
  Comment INTEGER NOT NULL,
  Person INTEGER NOT NULL,
  PRIMARY KEY (Comment, Person),
  FOREIGN KEY (Comment) REFERENCES comments(Id) ON DELETE CASCADE,
  FOREIGN KEY (Person) REFERENCES persons(Id)
);
```

Create indexes (exact names):

```sql
CREATE INDEX IF NOT EXISTS idx_comments_type ON comments(CommentType);
CREATE INDEX IF NOT EXISTS idx_comments_location ON comments(Location);
CREATE INDEX IF NOT EXISTS idx_comments_username ON comments(Username);
CREATE INDEX IF NOT EXISTS idx_comments_ts ON comments(Ts);

CREATE INDEX IF NOT EXISTS idx_comment_persons_person ON comment_persons(Person);
CREATE INDEX IF NOT EXISTS idx_comment_persons_comment ON comment_persons(Comment);
```

### 2) Backfill data (exact order)

Backfill `comment_persons` from legacy single-person data:

```sql
INSERT OR IGNORE INTO comment_persons (Comment, Person)
SELECT Id, Person
FROM comments
WHERE Person IS NOT NULL;
```

Backfill `comments.Location` only from empty glasses:

```sql
UPDATE comments
SET Location = (
  SELECT g.Location
  FROM glasses g
  WHERE g.Id = comments.Glass
    AND g.Brew IS NULL
)
WHERE Location IS NULL
  AND Glass IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM glasses g
    WHERE g.Id = comments.Glass
      AND g.Brew IS NULL
  );
```

Backfill visibility owner (`comments.Username`) from linked glass owner:

```sql
UPDATE comments
SET Username = (
  SELECT g.Username
  FROM glasses g
  WHERE g.Id = comments.Glass
)
WHERE Username IS NULL
  AND Glass IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM glasses g WHERE g.Id = comments.Glass
  );
```

Backfill timestamp (`comments.Ts`) from glass timestamp when available, else now:

```sql
UPDATE comments
SET Ts = COALESCE(
  (SELECT g.Timestamp FROM glasses g WHERE g.Id = comments.Glass),
  CURRENT_TIMESTAMP
)
WHERE Ts IS NULL;
```

Infer `CommentType` in this exact chain:

```sql
UPDATE comments
SET CommentType = 'brew'
WHERE CommentType IS NULL
  AND Glass IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NOT NULL
  );

UPDATE comments
SET CommentType = 'meal'
WHERE CommentType IS NULL
  AND Glass IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM glasses g
    WHERE g.Id = comments.Glass
      AND g.Brew IS NULL
      AND g.BrewType IN ('Restaurant', 'Meal')
  );

UPDATE comments
SET CommentType = 'night'
WHERE CommentType IS NULL
  AND (
    (
      Glass IS NOT NULL
      AND EXISTS (
        SELECT 1
        FROM glasses g
        WHERE g.Id = comments.Glass
          AND g.Brew IS NULL
          AND g.BrewType = 'Night'
      )
    )
    OR (
      Location IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
      )
    )
  );

UPDATE comments
SET CommentType = 'location'
WHERE CommentType IS NULL
  AND Location IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
  );

UPDATE comments
SET CommentType = 'person'
WHERE CommentType IS NULL
  AND EXISTS (
    SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id
  )
  AND Glass IS NULL;

UPDATE comments
SET CommentType = 'glass'
WHERE CommentType IS NULL;
```

### 3) View rebuilds in Phase 1 migration

Rebuild these views inside `mig_006_comments_model_phase1`:
- `compers`: remove `comments.Photo`, remove duplicate `com_cnt`, get people via `comment_persons`.
- `persons_list`: use `comment_persons` instead of `comments.Person`.
- `loc_ratings` and `location_ratings`: include comments directly linked by `comments.Location = locations.Id` in addition to glass-linked rows.
- `comments_list`: include `CommentType`, remove `Photo` output column.

Keep legacy columns for compatibility in this phase:
- `comments.Person` stays for now.
- `comments.Photo` stays for now (already unused by photo UI).

### 4) Phase 1 verification

- `perl -c code/*.pm`
- Open the site and verify migration page shows only `mig_006` pending.
- Spot-check row counts:
  - `SELECT count(*) FROM comment_persons;`
  - `SELECT CommentType, count(*) FROM comments GROUP BY CommentType;`
  - `SELECT count(*) FROM comments WHERE Ts IS NULL;` should be 0
- Run `tools/dbdump.sh` and commit updated `code/db.schema`.

---

## Phase 2 - Mainlist display ✓ DONE

Update `code/mainlist.pm` and `code/comments.pm` read paths only:
- `listcomments($c, $glassid)`: join through `comment_persons` and show `GROUP_CONCAT(persons.Name, ', ')`.
- Show a compact type badge when `CommentType != 'brew'`.
- Keep posting behavior unchanged in this phase.

**Testable:** current comments still render; multi-person names appear for migrated data.

---

## Phase 3 - Other display pages ✓ DONE

Read-path updates only:
- `code/locations.pm` `listlocationcomments()`: show direct location comments (`comments.Location = ?`) and glass-routed comments (`glasses.Location = ?`), with visibility filter `comments.Username IS NULL OR comments.Username = ?`.
- `code/persons.pm` `showpersondetails()`: replace legacy `comments.Person` lookup with `comment_persons` join.
- `code/comments.pm` `listallcomments()`: include `CommentType` in listing.

Display ordering rule for all lists:
- Use `COALESCE(glasses.Timestamp, comments.Ts)` for sorting and shown date/time.

---

## Phase 4 - Multi-person chip UI (inputs.js / inputs.css)

UI-only foundation before backend write-path changes:
- Extend `initDropdown` for `data-multi="1"`.
- Selected person adds chip + hidden `<input name="person_id" value="N">`.
- Removing chip removes its hidden input.
- Do not close dropdown after each select.

Wire this mode into existing comment person selector in `comments.pm`.

**Testable:** UI supports add/remove multiple persons; backend still behaves as before.

---

## Phase 5 - Posting comments

Update `postcomment()` in `code/comments.pm`:
- Write `CommentType`, `Ts`, `Location`, `Username`.
- Read and persist all `person_id[]` to `comment_persons`.
- Keep `person=new` flow working.
- Remove old `comments.Photo` update logic.
- Stop writing legacy `comments.Person` in normal path.

Form updates:
- Explicit `CommentType` selector: `brew`, `night`, `meal`, `location`, `person`, `glass`.
- Multi-person selector uses Phase 4 chips.
- Privacy toggle maps to `Username` set/unset.

**Testable:** create/edit round-trip works for multi-person + type + privacy.

---

## Phase 6 - Cleanup migration (mig_007)

Add a second schema migration for cleanup only:
- New migration function: `mig_007_comments_cleanup_drop_legacy`
- Bump `CODE_DB_VERSION` to 7 when this lands.
- Recreate `comments` table without `Person` and `Photo` (SQLite table-copy pattern).
- Rebuild views again so none reference dropped columns.

Also update remaining code references:
- `code/listrecords.pm`, `code/brews.pm`, `export.pm`, and any lingering `comments.Person` or `comments.Photo` SQL.

Run `tools/dbdump.sh` after migration and commit `code/db.schema`.

---

## Final verification checklist

- Migration path works from DB version 5 -> 6 -> 7.
- No SQL errors on page loads using comments/locations/persons/mainlist.
- Privacy filter works (public or own private).
- No references remain to dropped legacy columns after Phase 6.
