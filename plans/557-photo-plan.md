# Photo plan (split from issue #405)

> This file contains the photo‑specific plan extracted from the comments refactor. `plans/405-comments.md` assumes photo support is already implemented and points to this document.

## Summary
Implement first‑class photo support allowing multiple images on glasses, comments, locations, persons and brews.  
Each photo records an uploader (`persons.Id`, NULL = unknown) and obeys existing visibility/export rules.

Database alterations are handled by `migrate.pm` with an automatic migration on first page load; no external scripts are required.

---

## Status

### Done
- **Schema & migration** (`migrate.pm` mig_002): `photos` table created with all indexes; Heikki inserted as a persons record; legacy `comments.Photo` filenames backfilled with correct timestamps taken from the linked glass, and uploaders resolved via glass username → persons join.
- **`photos.pm` core helpers**:
  - `get_photos($c, $type, $id)` — fetches photo rows for any entity type.
  - `thumbnails_html($c, $type, $id)` — returns an indented block div of thumbnails, each linking to the photo edit page.
  - `imagetag($c, $filename, $width, $link_url)` — renders a thumbnail; optional `$link_url` overrides the href (defaults to full-size in a new tab).
  - `savefile($c, $prefix)` — saves uploaded file; prefix is caller-supplied (e.g. `g-42-2026-02-21+15:54:12`); auto-orients with ImageMagick.
- **`photo_form($c, glass=>$id)`** — a zero-click upload widget: clicking `(Photo)` immediately triggers the OS file picker / camera. On file selection the form auto-submits (no extra button). The form is `display:none` in the DOM; no expand/collapse clutter.
- **`post_photo($c)`** — handles both new uploads (saves file, inserts photos row with human-readable timestamp filename) and metadata edits/deletes (caption, Public flag, delete).
- **`listphotos($c)`** — `o=Photos` GET: all photos for the current user, grouped by date, thumbnails linking to edit page.
- **`editphoto($c)`** — `o=Photos&e=$id` GET: metadata form (caption, Public checkbox, Update/Delete buttons), full-size image below (click opens in new tab).
- **`comments.pm`**: legacy `comments.Photo` display code removed; thumbnails shown via `thumbnails_html`; `(Photo)` widget sits on the same line as `(Add comment)`, attached to the glass (not the comment).
- **`mainlist.pm`**: `photoline` helper prints glass-level photos (before comments); comment-level photos appear after each comment line.
- **Routing**: `index.cgi` dispatches GET and POST `o=Photos` to `photos::listphotos` and `photos::post_photo` respectively.
- **Menu**: Photos listed under "List / Edit".
- **`util.pm`**: `htmlesc()` helper added.

### Still needed

#### Wire into entity pages
- **`locations.pm`** — show location thumbnails (via `thumbnails_html`); add `photo_form` with `public_default=>1`.
- **`persons.pm`** — show person thumbnails; add `photo_form`.
- **`brews.pm`** — show brew thumbnails; add `photo_form` with `public_default=>1`.

#### Security / visibility
- `post_photo` delete path does not yet check that the requester is the uploader or admin. Add an ownership check before the DELETE.
- The `Public` flag is stored but not yet enforced on display. Decide whether non-public photos should be hidden from Dennis's view of Heikki's data (and vice versa), and implement if needed.

#### Caption at upload time
- The `photo_form` widget auto-submits immediately on file pick, so there is no opportunity to enter a caption before upload. Captions can be added after the fact via the edit page. This is an acceptable trade-off for now, but could be revisited if captions at upload time matter.

#### Export
- Deferred to issue #560. Public photos should be included in user data exports.

#### Future / optional
- Retire the `Glass` FK column in photos once the comments refactor (#405) is complete, if all glass-level photos move to a comment instead.
- Bulk photo management / reorder on the `o=Photos` list page.
- Show a single most-recent thumbnail in person/location/brew index lists.

---

## Schema (single source of truth — deployed)

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
  Uploader INTEGER, -- persons.Id; NULL = unknown
  Public INTEGER NOT NULL DEFAULT 0,
  Ts DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_photos_comment  ON photos(Comment);
CREATE INDEX idx_photos_location ON photos(Location);
CREATE INDEX idx_photos_person   ON photos(Person);
CREATE INDEX idx_photos_brew     ON photos(Brew);
CREATE INDEX idx_photos_uploader ON photos(Uploader);
CREATE INDEX idx_photos_public   ON photos(Public);
```

Notes:
- `Filename` stores just the base name. Files live under `beerdata/<username>.photo/`. New uploads get names like `g-42-2026-02-21+15:54:12+orig.jpg`; resized variants append a size suffix, e.g. `+90w.jpg`. `imagefilename()` in `photos.pm` encodes this convention.
- Multiple nullable FK columns allow a photo to attach to more than one entity (e.g. both `Glass` and `Location`). No single-FK constraint is enforced — intentional.
- Brew photos default to `Public = 1`; glass/comment/person photos default to `Public = 0`.

---

## Public default rules
| Attached to | Default `Public` |
|-------------|-----------------|
| Glass       | 0 (private)     |
| Comment     | 0 (private)     |
| Location    | 1 (public)      |
| Person      | 0 (private)     |
| Brew        | 1 (public)      |

---

## Cross-refs
- Main comments refactor: `plans/405-comments.md`.
- Photo export: issue #560.
