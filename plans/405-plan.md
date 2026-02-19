# Issue #405 — Comments data‑model: implementation plan

## Summary
A minimal, backwards‑compatible enhancement to the existing `comments` model that:
- supports multiple people per comment,  
- allows comments to target a Location (or a Visit) without creating "empty" glasses,  
- makes intent explicit using `CommentType` values (including `visit` and `meal`).

This plan keeps changes small, incremental and reversible.

---

## Goals
- Eliminate the need for most "empty glass" workarounds.  
- Distinguish clearly between glass‑comments, visit/night comments, meal/restaurant comments, and person comments.  
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

- Photo support is handled separately; see `tmp/557-photo-plan.md`.

---

## Migration / backfill steps (ordered, reversible)
1. Add new columns/tables (run in a transaction where possible).

Important: this migration is more than a simple schema tweak — it requires data backfill and cross‑table updates. **Do not rely solely on `tools/dbchange.sh`** for the whole job; create a migration script (suggested: `tools/migrate_comments_model.sh`) that performs the ALTERs, backfills, and safe checks. Test the script on a dev copy and a production backup before running it live.

2. Populate `comment_persons` from legacy `comments.Person`:
```sql
INSERT INTO comment_persons (Comment, Person)
  SELECT Id, Person FROM comments WHERE Person IS NOT NULL;
```
3. For comments that refer to an "empty" glass used as a visit/meal, populate `comments.Location`:
```sql
UPDATE comments
  SET Location = (SELECT Location FROM glasses g WHERE g.Id = comments.Glass)
  WHERE Location IS NULL AND Glass IS NOT NULL;
```
4. Backfill `CommentType` using inference rules (then allow manual correction):
```sql
-- A comment is a "glass" comment only if it refers to a glass that actually has a Brew
UPDATE comments SET CommentType='glass'
  WHERE Glass IS NOT NULL AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NOT NULL);

-- Visit by empty-glass marked as Night
UPDATE comments SET CommentType='visit'
  WHERE CommentType IS NULL AND Glass IS NOT NULL
    AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL AND g.BrewType = 'Night');

-- Visit (location + people)
UPDATE comments SET CommentType='visit'
  WHERE CommentType IS NULL AND Location IS NOT NULL AND EXISTS(SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id);

-- Meal/restaurant: detect from the empty glass metadata (Brew IS NULL and BrewType indicates restaurant)
UPDATE comments SET CommentType='meal'
  WHERE CommentType IS NULL AND Glass IS NOT NULL
    AND EXISTS(SELECT 1 FROM glasses g WHERE g.Id = comments.Glass AND g.Brew IS NULL AND (g.BrewType = 'Restaurant' OR g.BrewType = 'Meal'));

-- Pure location note (no people)
UPDATE comments SET CommentType='location' WHERE CommentType IS NULL AND Location IS NOT NULL;

-- Person-only comments (no glass)
UPDATE comments SET CommentType='person' WHERE CommentType IS NULL AND EXISTS(SELECT 1 FROM comment_persons cp WHERE cp.Comment = comments.Id);

-- Leave CommentType NULL where we cannot infer intent (do not force a 'generic' value)
```
(Adjust the `meal` rule if you have other conventions for restaurant empty‑glasses.)

5. Leave legacy `comments.Person` and `comments.Photo` columns untouched until the app code has been updated and tested; then optionally DROP/CLEAR them.

6. Run `tools/dbdump.sh` and update `code/db.schema` to reflect schema changes.

---

## Code changes (small, files to update)
- `code/comments.pm` —
  - write/read `comment_persons`; accept multi‑person input and migrate legacy `comments.Person`.  
  - honor `comments.Username` when creating/listing comments (NULL = public; non‑NULL = visible only to that username).  
  - set/interpret `CommentType` and `Ts` on create/list operations.
- `code/locations.pm` — show `CommentType IN ('visit','meal','location')` and include comments where `comments.Location = id` plus glass comments for the location; respect comment visibility (Username).
- `code/persons.pm` — read comment list via `comment_persons` (and legacy `comments.Person` while migrating); ensure person pages include comments where the person appears in `comment_persons`.
- `code/index.cgi` — expand `postcomment()` form handling for multi‑person, `CommentType`, and `comments.Username` (privacy).  
- `code/db.schema` — add new tables/columns and update views (`compers`, `loc_ratings`, `persons_list`) to reflect `CommentType`, `Location` and `Username` where needed.
- `static/inputs.js` / `inputs.css` — simple autocomplete/multi‑select for people (allow creating a new person inline as fallback).  
- `code/mainlist.pm` / `mainlist.pm` — plan for UI adjustment: consider inline/hidden comment forms for glasses and location headlines (not part of the first implementation but noted for follow‑up).
- `code/listrecords.pm`, `brews.pm` — adjust summary lines/readers to use `CommentType` and to respect comment visibility (Username).  
- `export.pm` — ensure exported data respects `comments.Username` (only export public comments unless running as superuser).  


---

## UI changes (minimal)
- Comment form: add an **About** selector (auto‑infer default but allow override): `glass`, `visit`, `meal`, `location`, `person`.
- Allow multi‑person selection: implement a simple autocomplete/multi‑select that filters existing `persons` and offers an "Add person" fallback. (Full UX with fuzzy search / large lists is future work.)
- Respect privacy: show comments only when `comments.Username` is NULL or equals the current user; add a small lock/public toggle in the comment form.
- Optionally: checkbox `Create visit glass` to keep current empty‑glass behaviour for users who prefer grouping events.
- Decouple comment entry from the glass input form — consider adding hidden inline comment forms in the `mainlist` for both glasses and location headlines (UX follow‑up work).
- Photo UI assumed completed / out of scope for this plan.
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
- Create a visit comment with Location + people (no Glass) → shows on Location page as `visit`.
- Create a meal comment (Visit + CommentType='meal') → shows on Location page and in `meal` reports.
- Add multiple people to a single comment and verify `persons` page shows it for each person.
- Verify privacy: comments with `comments.Username` set must be visible only to that user; public comments (`Username IS NULL`) are visible to all.
- Test the migration script on a dev copy and on a production DB dump before touching live production.

Add simple unit/manual tests and run them before deployment.

---

## Rollout plan (safe, stepwise)
1. Create a feature branch (or a temporary working branch) and add the migration script `tools/migrate_comments_model.sh`.
2. Add migration SQL and update `code/db.schema` (use `tools/dbdump.sh` after applying migrations on a test DB).
3. Implement code changes behind small UI updates (keep changes feature‑flagged where useful).
4. Deploy to dev, run the migration script against a dev copy of the production DB, and manually verify test cases.
5. Prepare a production migration plan: take a full DB backup, test restoring that backup to a staging instance and run the migration script there, then run the script on production during a maintenance window.
6. After a few days of monitoring, remove legacy columns (optional cleanup) and update `db.schema`.

If rollback is needed: restore DB from the pre‑migration backup and revert code to the previous commit.  Always keep the migration script idempotent where possible and include safety checks (row counts, sanity asserts) before committing production changes.

---

## Commit checklist
- [ ] Add migration SQL and a tested migration script (e.g. `tools/migrate_comments_model.sh`) that can be run against dev and production backups.  
- [ ] Update `code/db.schema` via `tools/dbdump.sh` after running migration on a test DB.  
- [ ] Implement code changes and minimal UI updates.  
- [ ] Add/adjust tests and manual test instructions (including privacy checks).  
- [ ] Update `tmp/405-plan.md` (this file) and any other design notes.  
- [ ] Bump `code/VERSION.pm` if appropriate.  
- [ ] Prepare production migration instructions (backup, run script, verify).

---

## Estimated effort
- Schema + migration + basic tests: **~1–2 hours**.  
- Code + UI updates across listed files + manual verification: **2–4 hours**.  
- Total (end‑to‑end): **half day — 1 day**, depending on polish and extra UI work.

---

## Notes / alternatives considered
- Full polymorphic `annotations` model (more flexible) — postponed (larger refactor).  
- Keeping `ratings` in `comments` for now (no immediate split).  
- Photo plan: see `tmp/557-photo-plan.md` (handled separately).

---

