# Photo plan (split from issue #405)

> This file contains the photo‑specific plan extracted from the comments refactor. `plans/405-comments.md` assumes photo support is already implemented and points to this document.

## Summary
Implement first‑class photo support allowing multiple images on glasses, comments, locations, persons and brews.  
Each photo records an uploader (username as `text`, NULL = unknown) and obeys existing visibility/export rules.

Database alterations are handled by `migrate.pm` with an automatic migration on first page load; no external scripts are required.

---

## Status

### Done
- **Schema & migration** (`migrate.pm` mig_002): `photos` table created with all indexes; legacy `comments.Photo` filenames backfilled with correct timestamps taken from the linked glass.
- **`photos.pm` core helpers**:
  - `get_photos($c, $col, $id)` — fetches photo rows; `$col` is the capitalised DB column name (`Glass`, `Comment`, `Location`, `Person`, `Brew`).
  - `thumbnails_html($c, $col, $id)` — returns an indented block div of thumbnails, each linking to the photo edit page. Same `$col` convention.
  - `imagetag($c, $filename, $width, $link_url)` — renders a thumbnail; named sizes: `thumb` (90px), `small` (40px, for list rows), `mob` (240px), `pc` (640px). Optional `$link_url` overrides the href.
  - `savefile($c, $prefix)` — saves uploaded file; prefix is caller-supplied (e.g. `g-42-2026-02-21+15:54:12`); auto-orients with ImageMagick.
- **`photo_form($c, <type>=>$id)`** — a zero-click upload widget accepting any entity type (`glass`, `location`, `person`, `brew`, `comment`). Clicking `(Photo)` immediately triggers the OS file picker / camera. On file selection the form auto-submits. The form is `display:none` in the DOM.
- **`post_photo($c)`** — entity-agnostic: detects which entity type was submitted, builds the filename prefix and column name dynamically. `Uploader` set to `$c->{username}` directly.
- **`listphotos($c)`** — `o=Photos` GET: table layout, one photo per row, grouped by date; thumbnails link to edit page. Visibility filtered: only photos uploaded by the current user or marked Public.
- **`editphoto($c)`** — `o=Photos&e=$id` GET: table-layout metadata form (caption, Public checkbox, Update/Delete/Back buttons); entity attachment displayed as `G[id]`, `C[id]`, `L[id]`, `P[id]`, `B[id]` with linked IDs for Location/Person/Brew; full-size image below. Visibility enforced — error if photo is private and not uploaded by current user.
- **Multiple attachments**: "Also attach to…" collapsed `<details>` form on the edit page; inserts a new `photos` row for the same `Filename` pointing to a Person, Location, or Brew; redirects to the new record's edit page. Siblings (other records sharing the same `Filename`) are listed above with `Also` links.
- **Delete cleanup**: when the last `photos` record for a `Filename` is deleted, the physical `+orig.jpg` and all `+*w.jpg` scaled variants are unlinked.
- **`photo_attached_str($c, $p)`** — shared helper returning an HTML string of attached-entity summaries; used by both `listphotos` and `editphoto`.
- **`comments.pm`**: legacy `comments.Photo` display code removed; thumbnails shown via `thumbnails_html('Comment', ...)`; `(Photo)` widget sits on the same line as `(Add comment)`, attached to the glass (not the comment).
- **`mainlist.pm`**: glass-level and comment-level photos shown via `thumbnails_html`.
- **`locations.pm`** — `editlocation`: shows `thumbnails_html('Location', ...)` and `photo_form(location=>..., public_default=>1)` for existing records.
- **`persons.pm`** — `editperson`: shows `thumbnails_html('Person', ...)` and `photo_form(person=>...)` for existing records.
- **`brews.pm`** — `editbrew`: shows `thumbnails_html('Brew', ...)` and `photo_form(brew=>..., public_default=>1)` for existing records.
- **`listrecords.pm`**: `Photo` column rendered via `imagetag` — `small` (40px) on mobile, `thumb` (90px) on desktop. Column header styled narrow and centred.
- **`locations_list` view** (mig_003): correlated subquery adds most-recent `Photo` filename per location.
- **`persons_list` view** (mig_004): correlated subquery adds most-recent `Photo` filename per person.
- **`brews_list` view** (mig_004): correlated subquery adds most-recent `Photo` filename per brew.
- **Routing**: `index.cgi` dispatches GET and POST `o=Photos` to `photos::listphotos` and `photos::post_photo` respectively.
- **Menu**: Photos listed under "List / Edit".
- **`util.pm`**: `htmlesc()` helper added.

### Still needed

#### Security
- `post_photo` update/delete path has no ownership check — anyone who knows a photo ID can modify or delete it. Add a check that `$c->{username}` matches `lower(Uploader)` before allowing writes.

#### Caption at upload time
- The `photo_form` widget auto-submits immediately on file pick, so there is no opportunity to enter a caption before upload. Captions can be added after the fact via the edit page. This is an acceptable trade-off for now, but could be revisited if captions at upload time matter. Probably not.

#### Export
- Deferred to issue #560. Public photos should be included in user data exports.

#### Future / optional
- Retire the `Glass` FK column in photos once the comments refactor (#405) is complete, if all glass-level photos move to a comment instead. Probably not, I think I like my photos to point to glasses, except when directly related to a comment
- Bulk photo management / reorder on the `o=Photos` list page. Use listrecords()

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
  Uploader TEXT, -- username; NULL = unknown
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
- `Uploader` stores the username string directly (not a foreign key to persons); case-insensitive comparisons use `lower()`.
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
