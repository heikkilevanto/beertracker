# Photo plan (split from issue #405)

> This file contains the photo‑specific plan extracted from the comments refactor. `tmp/405-plan.md` assumes photo support is already implemented and points to this document.

## Summary
Implement first‑class photo support allowing multiple images on glasses, comments, locations, persons and brews.  
Each photo records an uploader (`persons.Id`, NULL = unknown) and obeys existing visibility/export rules.

Database alterations are handled by `migrate.pm` with an automatic migration on first page load; no external scripts are required.

---

## Goals
- Allow multiple photos per comment/glass/location/person/brew.  
- Track uploader as `persons.Id` and index it for queries.  
- Provide upload, display, and delete functionality. (Export deferred to #560.)
- Keep photo rollout independent from the main comments migration so we can deploy or rollback separately.

---

## Schema (single source)
```sql
CREATE TABLE photos (
  Id INTEGER PRIMARY KEY,
  Filename TEXT NOT NULL,
  Caption TEXT,
  Glass INTEGER,
  Location INTEGER,
  Person INTEGER,
  Comment INTEGER,
  Brew INTEGER,
  Uploader INTEGER, -- person id (references persons.Id); NULL = unknown
  Public INTEGER NOT NULL DEFAULT 0, -- 0 = private, 1 = public
  Ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_photos_comment ON photos(Comment);
CREATE INDEX idx_photos_location ON photos(Location);
CREATE INDEX idx_photos_person ON photos(Person);
CREATE INDEX idx_photos_brew ON photos(Brew);
CREATE INDEX idx_photos_uploader ON photos(Uploader);
CREATE INDEX idx_photos_public ON photos(Public);
```

Notes:
- `Filename` stores just the base name (no directory). Photos are stored under `beerdata/<username>.photo/`. The phone camera typically produces timestamp-based names like `2025-01-18+15:54:12.jpg`; the original is saved as `2025-01-18+15:54:12+orig.jpg`, and resized versions get a size suffix, e.g. `2025-01-18+15:54:12+640w.jpg`. The `imagefilename()` helper in `photos.pm` encodes this convention.
- At upload time the image is auto-oriented (EXIF rotation applied) so it always displays upright.
- Resized variants are created on first display and cached alongside the original; they can be deleted and regenerated freely.
- Multiple nullable FK columns let a photo attach to any relevant entity. A photo may legitimately reference more than one entity (e.g. both a `Glass` and a `Location` for the same evening), so no strict single-FK constraint is enforced — this is intentional.
- `Glass` and `Comment` are both kept as attachment points. Once the comments refactoring (see `tmp/405-plan.md`) is complete, revisit whether the `Glass` column is still needed or whether all glass-level photos should go via a comment.
- `Brew` photos (labels, tap handles, etc.) are first-class: photos can attach directly to a brew via `Brew INTEGER`. Brew photos default to `Public = 1`.

---

## Migration / backfill (via migrate.pm)

All DB changes are managed through `migrate.pm`. Add a new migration entry (e.g. `mig_002_photos_table`) and bump `$CODE_DB_VERSION`. The code will execute on first page load; no manual CLI steps or extra sanity checks are needed.

Migration steps (in the new sub):

```perl
sub mig_002_photos_table {
  my $c = shift;
  db::execute($c, q{
    CREATE TABLE IF NOT EXISTS photos (
      Id INTEGER PRIMARY KEY,
      Filename TEXT NOT NULL,
      Caption TEXT,
      Glass INTEGER,
      Location INTEGER,
      Person INTEGER,
      Comment INTEGER,
      Brew INTEGER,
      Uploader INTEGER,
      Public INTEGER NOT NULL DEFAULT 0,
      Ts DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  });
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_comment   ON photos(Comment)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_location  ON photos(Location)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_person    ON photos(Person)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_brew      ON photos(Brew)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_uploader  ON photos(Uploader)");
  db::execute($c, "CREATE INDEX IF NOT EXISTS idx_photos_public    ON photos(Public)");

  # Backfill: migrate legacy comments.Photo filenames into the photos table.
  # Uploader comes from comments.UserId (may be NULL for old records).
  db::execute($c, q{
    INSERT INTO photos (Filename, Comment, Uploader, Public, Ts)
      SELECT Photo, Id, UserId, 0, CURRENT_TIMESTAMP
        FROM comments
       WHERE Photo IS NOT NULL AND Photo != ''
  });
  db::execute($c, "UPDATE comments SET Photo = NULL WHERE Photo IS NOT NULL");

  # Mark photos attached to locations as public.
  db::execute($c, q{
    UPDATE photos SET Public = 1
     WHERE Comment IN (SELECT Id FROM comments WHERE Location IS NOT NULL)
  });

  # Application behavior going forward:
  # - new photos attached to a Location or a Brew default to Public = 1; others to Public = 0.
} # mig_002_photos_table
```

Register in `@MIGRATIONS`:
```perl
[2, 'create photos table and backfill from comments.Photo', \&mig_002_photos_table],
```
Bump `$CODE_DB_VERSION` to `2`.

---

## Code changes (where to edit)
- `code/migrate.pm` — add `mig_002_photos_table` sub and register it; bump `$CODE_DB_VERSION` to 2.
- `code/photos.pm` — primary module; extend existing utilities with:
  - Photo-record helpers: `get_photos($c, entity_type, entity_id)`, `insert_photo($c, ...)`, `delete_photo($c, id)`. Use `db.pm` helpers for SQL.
  - `photo_form($c, %opts)` — a reusable upload/metadata form widget (see UI section below). This is the single place where a photo can be taken or uploaded and metadata edited. Called from all entity pages.
  - POST handler `post_photo($c)` — handles both new uploads and metadata edits. Dispatched from `index.cgi` (`o=Photos` or piggybacked on the entity's own POST).
- `code/comments.pm` — list and display photos for a comment using `photos::get_photos`; remove legacy `comments.Photo` display code. (The `comments.Photo` column itself is left nullable; cleaned up in the big comments refactor — do not drop it here.)
- `code/locations.pm`, `code/persons.pm` — embed `photos::photo_form` and display photo thumbnails where relevant.
- `code/brews.pm` — embed `photos::photo_form` for brew photos (labels, tap handles, etc.). New brew photos default to `Public = 1`.
- `static/*` — any JS needed for the collapsible photo form widget (toggle show/hide on clicking "(photo)").
- `tools/migrate_comments_model.sh` — remove the `comments.Photo` migration block from this script; it is now handled by `migrate.pm`.
- Consider adding a `photos` list page (e.g. `o=Photos`) later for bulk management and review.

Security/visibility:
- Photo display must respect `comments.Username` and the `Public` flag.
- Only the uploader (or admin) may delete or replace a photo.

---

## UI interactions

### Reusable `photos::photo_form` widget
A single Perl function in `photos.pm` renders a collapsible form used everywhere a user can attach a photo (comments, glasses, locations, persons, brews):

- Renders as a plain `(photo)` link by default. Clicking it reveals the full form (JavaScript toggle, no page reload).
- Form fields: file input (camera capture or file pick), optional caption, `Public` checkbox (pre-ticked for locations and brews), hidden entity FK fields (`glass`, `comment`, `location`, `person`, `brew`).
- On submit (POST), `photos::post_photo($c)` saves the file, creates the `photos` row, and redirects back.
- Callers pass the entity type and id; the widget handles everything else.

### Photo display
- Thumbnail inline with the parent entity (comment, location, brew, etc.). Clicking opens the full-size image.
- Inline delete button for the uploader or admin.
- Inline edit link (caption, `Public` flag) opens a small edit form (same widget in edit mode.

### Thumbnails & editing
- Clicking any thumbnail should navigate to a dedicated photo‑edit page where metadata can be changed or the photo deleted. This page is the canonical place for editing a single photo record.
- Entity edit/display pages (persons, locations, brews, glasses) show all relevant thumbnails for that record. Those pages also include a `photos::photo_form` widget for capturing/uploading a new photo.
- In record lists (e.g. person or location index) show only the most recent thumbnail in a small, unobtrusive size.
- The main glass list (`o=MainList`) also displays thumbnails: include any photo attached directly to the glass or to its comments. The comment form on the main list continues to embed the `(photo)` widget for quick uploads.

### Public default rules
| Attached to | Default `Public` |
|-------------|-----------------|
| Glass       | 0 (private)     |
| Comment     | 0 (private)     |
| Location    | 1 (public)      |
| Person      | 0 (private)     |
| Brew        | 1 (public)      |

---

## Tests / verification
- Upload a photo for a comment → photo appears on the comment and in the photos table with `Uploader` = current person's Id (or NULL for anonymous).
- Upload a photo for a brew → `Public` defaults to 1; photo appears on the brew page.
- Upload a photo for a glass or comment → `Public` defaults to 0.
- Upload a photo for a location → `Public` defaults to 1.
- Photo visibility follows privacy rules (`Public` flag and `comments.Username` where applicable).
- Support editing a photo record (caption, `Public` flag) and verify edits persist.
- Public photos are included in user exports (deferred to #560).
- Deletion: only uploader or admin can delete a photo.
- Migration: after running `mig_002`, verify that `photos` row count equals the old `comments.Photo` non-null count, filenames display correctly, and `Uploader` is set where `comments.UserId` was non-null.
- `(photo)` link is hidden by default; clicking shows the form without a page reload.

---

## Rollout plan
1. Add `mig_002_photos_table` to `migrate.pm`, bump `$CODE_DB_VERSION` to 2.
2. Implement `photos.pm` helpers and the `photo_form` widget + POST handler.
3. Wire the widget into comments, locations, persons, and brews pages.
4. Deploy to dev (migration runs automatically on first page load); manually verify all test cases.
5. Git pull to production — migration runs automatically on first page load.

---

## Estimated effort
- Schema + `migrate.pm` entry + basic `photo_form` widget: **~1–2 hours**.
- Full UI polish (gallery, captions, reorder): **additional 2–4 hours**.

---

## Cross‑refs
- Main comments refactor: `plans/405-comments.md` (assumes photo support implemented separately).
- Photo export: issue #560.
