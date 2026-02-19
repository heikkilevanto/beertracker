# Photo plan (split from issue #405)

> This file contains the photo‑specific plan extracted from the comments refactor. `tmp/405-plan.md` assumes photo support is already implemented and points to this document.

## Summary
Add robust photo support so photos can be attached to `glasses`, `comments`, `locations`, or `persons`.  
Key constraints: `photos.Uploader` is a `persons.Id`, `NULL` means unknown; photos respect comment visibility and export rules.

---

## Goals
- Allow multiple photos per comment/glass/location/person.  
- Track uploader as `persons.Id` and index it for queries.  
- Provide upload, display, delete, and export functionality.  
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
  Uploader INTEGER, -- person id (references persons.Id); NULL = unknown
  Public INTEGER NOT NULL DEFAULT 0, -- 0 = private, 1 = public; Location photos default to public by convention
  Ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_photos_comment ON photos(Comment);
CREATE INDEX idx_photos_location ON photos(Location);
CREATE INDEX idx_photos_person ON photos(Person);
CREATE INDEX idx_photos_uploader ON photos(Uploader);
CREATE INDEX idx_photos_public ON photos(Public);
```

Notes:
- `Filename` stores just the base name (no directory). Photos are stored under `beerdata/<username>.photo/`. The phone camera typically produces timestamp-based names like `2025-01-18+15:54:12.jpg`; the original is saved as `2025-01-18+15:54:12+orig.jpg`, and resized versions get a size suffix, e.g. `2025-01-18+15:54:12+640w.jpg`. The `imagefilename()` helper in `photos.pm` encodes this convention.
- At upload time the image is auto-oriented (EXIF rotation applied) so it always displays upright.
- Resized variants are created on first display and cached alongside the original; they can be deleted and regenerated freely.
- Multiple nullable FK columns let a photo attach to any relevant entity. A photo may legitimately reference more than one entity (e.g. both a `Glass` and a `Location` for the same evening), so no strict single-FK constraint is enforced — this is intentional.
- `Glass` and `Comment` are both kept as attachment points. Once the comments refactoring (see `tmp/405-plan.md`) is complete, revisit whether the `Glass` column is still needed or whether all glass-level photos should go via a comment.
- `Brew` photos (labels, etc.) are not directly addressed here; attach via a glass or comment for now. Revisit when the comments structure is refactored.

---

## Migration / backfill (safe, idempotent)
- Migrate any existing `comments.Photo` values into `photos` (one photo row per non‑empty filename).  
- If you have uploader info in legacy data, map it to `persons.Id`; otherwise leave `Uploader` NULL.

Example migration snippet (run as part of the central migration script or separately):
```sql
INSERT INTO photos (Filename, Comment, Ts, Public)
  SELECT Photo, Id, CURRENT_TIMESTAMP, 0 FROM comments WHERE Photo IS NOT NULL AND Photo != '';
UPDATE comments SET Photo = NULL WHERE Photo IS NOT NULL;

-- Backfill: mark photos attached to locations as public
UPDATE photos SET Public = 1 WHERE Comment IN (SELECT Id FROM comments WHERE Location IS NOT NULL);

-- Application behavior: new photos attached to a Location should default to Public = 1; others default to 0.
```

Run these steps on a dev copy of the production DB first and include row‑count sanity checks.

---

## Code changes (where to edit)
- `code/photos.pm` — primary module; already has rudimentary utilities (`imagefilename`, `imagetag`, resize-on-demand, `$photodir`). Extend it with photo-record helpers: `get_photos($c, entity_type, entity_id)`, `insert_photo($c, ...)`, `delete_photo($c, id)`, etc. Use `db.pm` helpers for the actual SQL.
- `code/comments.pm` — API to attach/list photos for a comment; remove legacy `comments.Photo` usage. (Legacy `comments.Photo` column is left nullable and cleaned up in the big comments refactoring — do not drop it here.)
- `code/locations.pm`, `code/persons.pm` — display photos where relevant (thumbnails + links).
- `code/brews.pm` — no direct photo column for now; photos attach via a glass or comment. Add a TODO noting this needs revisiting during the comments refactor.
- `export.pm` — include public photos in exports (respect `comments.Username` / visibility rules).
- `static/*` — update the existing photo upload in the comment form to record the new metadata (attached entity, `Public` flag, caption) and add inline edit for photo records (caption, public flag, attached entity).
- `tools/migrate_comments_model.sh` — include the `comments.Photo` → `photos` migration block and safety checks.
- Consider adding a `photos` list page (e.g. `o=Photos`) later for bulk management and review.

Security/visibility:
- Photo display and export must respect `comments.Username` (NULL = public; non‑NULL = private to that user).  
- Allow only authenticated users (or the uploader) to delete/replace photos.

---

## UI interactions (minimal first step)
- Update the existing upload control in the comment form to capture photo metadata (attached target, caption, `Public` toggle).  
- Allow editing photo records (caption, `Public` flag, change attached entity) via a small edit UI.  
- Display thumbnail (small) inline with the comment; clicking opens the full image.  
- Inline delete button for the uploader or admin.  
- Consider adding a `Photos` list/page later for browsing and bulk management; gallery and reorder/caption features can come subsequently.

---

## Tests / verification
- Upload a photo for a comment → photo appears on the comment and in the photos table with `Uploader` = current person's Id (or NULL).  
- Default `Public` behavior: photos attached to a `Location` default to `Public = 1`; all other photos default to `Public = 0`.  
- Photo visibility follows privacy rules (`Public` flag and `comments.Username` where applicable).  
- Support editing a photo record (caption, `Public` flag, attached entity) and verify edits persist.  
- Export: public photos are included in user exports; private photos are only included for superuser or the owning user.  
- Deletion: only uploader or admin can delete a photo.  
- Migration: after migrating legacy `comments.Photo`, ensure row counts match and filenames display correctly.

---

## Rollout plan
1. Implement photo schema + migration script and test on a dev copy.  
2. Add small UI for upload/display behind a feature flag if desired.  
3. Deploy to dev/staging, verify all tests.  
4. Run migration on production backup + staging before live migration.  
5. Deploy UI and enable feature once migration is verified.

Rollback: delete newly created photo rows (or restore DB from backup) if something goes wrong.

---

## Estimated effort
- Schema + migration + basic UI: **~1–2 hours**.  
- Full UI polish (gallery, captions, reorder): **additional 2–4 hours**.

---

## Cross‑refs
- Main comments refactor: `tmp/405-plan.md` (assumes photo support implemented separately).  
