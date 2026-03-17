# Issue #405 — Comments data‑model: implementation plan

## Summary
A minimal, backwards‑compatible enhancement to the existing `comments` model that:
- supports multiple people per comment,  
- allows comments to target a Location (or a Visit) without creating "empty" glasses,  
- makes intent explicit using `CommentType` values (including `night` and `meal`).

This plan keeps changes small, incremental and reversible.

---

## Goals
- Eliminate the need for most "empty glass" workarounds.  
- Distinguish clearly between brew‑comments, night/visit comments, meal/restaurant comments, and person comments.  
- Allow multiple people per comment.  
- Keep current UI and data working during migration.

---

## High‑level approach
1. Add three small schema pieces: `comments.CommentType`, `comments.Ts`, `comments.Location` (nullable).  
2. Add `comment_persons` (many→many) so one comment can reference many people.  
3. Backfill/migrate existing data.  
4. Small code/UI updates (comments.pm, locations.pm, persons.pm, index.cgi, templates).  
5. Keep backward compatibility fields until verified.

---

## Schema changes (apply via migration)

- Add columns to `comments`:
```sql
ALTER TABLE comments ADD COLUMN CommentType TEXT;
ALTER TABLE comments ADD COLUMN Ts DATETIME DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE comments ADD COLUMN Location INTEGER;
ALTER TABLE comments ADD COLUMN Username TEXT; -- NULL = public comment; non-NULL = visible only to that user
CREATE INDEX IF NOT EXISTS idx_comments_type ON comments(CommentType);
CREATE INDEX IF NOT EXISTS idx_comments_location ON comments(Location);
CREATE INDEX IF NOT EXISTS idx_comments_username ON comments(Username);
```

**`CommentType` values:**
| Value | Meaning |
|-------|---------|
| `brew`     | Comment on a specific glass that has a brew (most common case) |
| `night`    | A night out / visit — empty glass of BrewType `Night`, or a location visit with people |
| `meal`     | A meal / restaurant visit |
| `location` | A note about a location (no people, no glass) |
| `person`   | A note about a person (no glass) |
| `glass`    | Fallback — comment has a glass but intent could not be inferred |

- Add `comment_persons` join table:
```sql
CREATE TABLE comment_persons (
  Comment INTEGER NOT NULL,
  Person  INTEGER NOT NULL,
  PRIMARY KEY (Comment, Person),
  FOREIGN KEY (Comment) REFERENCES comments(Id) ON DELETE CASCADE,
  FOREIGN KEY (Person)  REFERENCES persons(Id)
);
CREATE INDEX idx_comment_persons_person ON comment_persons(Person);
```

- Photo support is handled separately; see `plans/557-photo-plan.md`. **Photo work is complete** (mig_002 backfilled `comments.Photo` into the `photos` table; `comments.pm` now uses `thumbnails_html`).

---

## Migration / backfill steps (ordered, reversible)
1. Add new columns/tables and perform all backfill steps via `migrate.pm` (same pattern as the photo migration mig_002–mig_004). Each logical step should be a separate numbered migration. Run in a transaction where possible.

2. Populate `comment_persons` from legacy `comments.Person`:
```sql
INSERT INTO comment_persons (Comment, Person)
  SELECT Id, Person FROM comments WHERE Person IS NOT NULL;
```

3. For comments that refer to an **empty** glass used as a visit/meal, populate `comments.Location`. Restrict to empty glasses only (`g.Brew IS NULL`) — comments on real beer glasses should not inherit the location automatically:
```sql
UPDATE comments
  SET Location = (SELECT Location FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL)
  WHERE Location IS NULL AND Glass IS NOT NULL
    AND EXISTS (SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL);
```

4. Backfill `CommentType` using inference rules (then allow manual correction):
```sql
-- Most common case: comment on a glass that has a brew
UPDATE comments SET CommentType='brew'
  WHERE Glass IS NOT NULL AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NOT NULL);

-- Meal/restaurant: detect from the empty glass metadata (Brew IS NULL and BrewType indicates restaurant)
UPDATE comments SET CommentType='meal'
  WHERE CommentType IS NULL AND Glass IS NOT NULL
    AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL AND (g.BrewType = 'Restaurant' OR g.BrewType = 'Meal'));

-- Night out: empty glass with BrewType 'Night', OR location + people with no glass
UPDATE comments SET CommentType='night'
  WHERE CommentType IS NULL AND (
    (Glass IS NOT NULL AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL AND g.BrewType = 'Night'))
    OR
    (Location IS NOT NULL AND EXISTS(SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id))
  );

-- Pure location note (no people)
UPDATE comments SET CommentType='location' WHERE CommentType IS NULL AND Location IS NOT NULL;

-- Person-only comments (no glass)
UPDATE comments SET CommentType='person' WHERE CommentType IS NULL AND EXISTS(SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id);

-- Fallback: anything remaining with a glass gets 'glass'
UPDATE comments SET CommentType='glass' WHERE CommentType IS NULL;
```

5. Leave legacy `comments.Person` column untouched until the app code has been updated and tested; then DROP it. `comments.Photo` has already been migrated to the `photos` table and its display code updated — it can be dropped as part of this migration. Also update the `compers` view in `db.schema` to remove the `photo` column once `comments.Photo` is dropped.

6. Run `tools/dbdump.sh` and update `code/db.schema` to reflect schema changes.

---

## Code changes (small, files to update)
- `code/comments.pm` —
  - write/read `comment_persons`; accept multi‑person input and migrate legacy `comments.Person`.      
  - honor `comments.Username` when creating/listing comments (NULL = public; non‑NULL = visible only to that username).  
  - set/interpret `CommentType` and `Ts` on create/list operations.
  - handle `postcomment()` form: multi‑person, `CommentType`, and `comments.Username` (privacy). This lives in `comments.pm`, not `index.cgi`.
  - *(Done)* legacy `comments.Photo` display replaced by `thumbnails_html('Comment', ...)`.
- `code/locations.pm` — show direct location comments (`CommentType IN ('night','meal','location')`) first, then brew/glass comments for the location (`g.Location = id`). Use `listrecords()`. Respect comment visibility (Username).
- `code/persons.pm` — show `person`‑type comments on the person page via `comment_persons`. Other comment types can be added later.
- `code/db.schema` — views (`compers`, `loc_ratings`, `persons_list`) need updating to reflect `CommentType`, `Location`, `Username`, and concatenated person names (now that a comment can have multiple). All view changes go via `migrate.pm`; `db.schema` is updated afterwards with `tools/dbdump.sh`.
- `static/inputs.js` / `inputs.css` — chip/tag input for multi‑person selection (see UI changes below).
- `code/mainlist.pm` — brew/glass comments continue to come from the input form at the top of the page as before. Consider inline comment forms for location headlines as follow‑up work.
- `code/listrecords.pm`, `brews.pm` — adjust summary lines/readers to use `CommentType` and to respect comment visibility (Username).  
- `export.pm` — ensure exported data respects `comments.Username` (only export public comments unless running as superuser).  


---

## UI changes (minimal)
- Comment form: add an **About** selector (auto‑infer default but allow override): `brew`, `night`, `meal`, `location`, `person`, `glass` (fallback).
- Allow multi‑person selection via a **chip/tag input**: a text field that filters the `persons` list as you type (same autocomplete pattern as the brew input). Selecting a person adds a removable tag above the field and appends a hidden `<input name="person_id" value="N">` to the form. An "Add new person" fallback link opens the person edit form. Implement in `inputs.js` (~40 lines), reusing existing autocomplete fetch/render logic. 
- Respect privacy: show comments only when `comments.Username` is NULL or equals the current user; add a small lock/public toggle in the comment form.
- Decouple comment entry from the glass input form — consider adding inline comment forms in the `mainlist` for location headlines as follow‑up work.
- Photo UI is complete (issue #557).
- Display rules: prefer `glass.Timestamp` when `Glass` set; otherwise show `comments.Ts`.  

---

## Query examples
- Location page (show glass + visit/location comments):
```sql
SELECT c.*, g.Timestamp AS glass_ts
FROM comments c
LEFT JOIN glasses g ON g.Id = c.Glass
WHERE c.Location = :loc_id OR (g.Location = :loc_id)
ORDER BY COALESCE(g.Timestamp, c.Ts) DESC;
```

- Person page (show comments involving person):
```sql
SELECT c.*
FROM comments c
LEFT JOIN comment_persons cp ON cp.Comment = c.Id
WHERE cp.Person = :person_id
ORDER BY COALESCE((SELECT Timestamp FROM glasses g WHERE g.Id = c.Glass), c.Ts) DESC;
```

- Show meal visits only:
```sql
SELECT * FROM comments WHERE CommentType = 'meal';
```

---

## Tests / verification (manual + quick checks)
- Create a person‑only comment (no Glass, Person(s) selected) → should list on Person page.
- Create a night comment with Location + people (no Glass) → shows on Location page as `night`.
- Create a meal comment (Location + CommentType='meal') → shows on Location page and in `meal` reports.
- Add multiple people to a single comment and verify `persons` page shows it for each person.
- Verify privacy: comments with `comments.Username` set must be visible only to that user; public comments (`Username IS NULL`) are visible to all.
- Test the migration script on a dev copy and on a production DB dump before touching live production.

Add simple unit/manual tests and run them before deployment.

---

## Rollout plan (safe, stepwise)
1. Add numbered migrations to `migrate.pm` (schema ALTERs and backfill steps, same pattern as mig_002–mig_004).
2. Update `code/db.schema` via `tools/dbdump.sh` after verifying migrations on a dev DB.
3. Implement code changes behind small UI updates.
4. Deploy to dev and manually verify test cases.
5. Deploy to production: git pull, migrations run automatically on first page load. Take a DB backup first.
6. After a few days of monitoring, remove legacy columns (optional cleanup) and update `db.schema`.

If rollback is needed: restore DB from the pre‑migration backup and revert code to the previous commit.  Always keep the migration script idempotent where possible and include safety checks (row counts, sanity asserts) before committing production changes.

---

## Commit checklist
- [ ] Add numbered migrations to `migrate.pm` (schema ALTERs, backfill steps, and view updates).  
- [ ] Implement code changes and minimal UI updates.  
- [ ] Add/adjust tests and manual test instructions (including privacy checks).  
- [ ] Update `plans/405-comments.md` (this file) and any other design notes.  
- [ ] Bump `code/VERSION.pm` if appropriate.  
- [ ] Prepare production migration instructions (backup, run script, verify).

---


## Notes / alternatives considered
- Full polymorphic `annotations` model (more flexible) — postponed (larger refactor).  
- Keeping `ratings` in `comments` for now (no immediate split).  
- Photo plan: see `plans/557-photo-plan.md` (complete).

---

