# Plan: Issue #405 — Comments data-model (phased)

**TL;DR:** Schema lands in one migration sweep (mig_005). Then iterative phases, each independently testable: display mainlist → display other lists → postglass form → post comments → rest. Multi-person selection extends the existing `initDropdown` with `data-multi="1"`.

---

## Phase 1 — Schema + migrate.pm (mig_005)

All schema work in a single migration. Consolidate into one mig_005:
- `ALTER TABLE comments ADD COLUMN` for `CommentType`, `Ts`, `Location`, `Username` + indexes
- `CREATE TABLE comment_persons` + index
- Data backfill:
  - `comment_persons` from `comments.Person`
  - `comments.Location` from empty glasses (Brew IS NULL only)
  - `comments.Username` from `glasses.username` where `Glass IS NOT NULL`
  - `CommentType` inference chain (in order):
    - `brew` — glass has a Brew
    - `meal` — empty glass, BrewType IN ('Restaurant','Meal')
    - `night` — empty glass BrewType 'Night', OR location + people (regardless of whether a glass is present, since brew/meal are already handled)
    - `location` — Location set, no people
    - `person` — person in comment_persons, no glass
    - `glass` — fallback (anything remaining)
- Rebuild `compers` view: drop `comments.Photo` ref, fix duplicate `com_cnt`, join `comment_persons` for people concat
- Rebuild `persons_list` view: join `comment_persons` instead of `comments.Person`
- Rebuild `loc_ratings` / `location_ratings` views: include direct `comments.Location = l.id` path alongside glass-routed path
- Rebuild `comments_list` view: add `CommentType`, drop `Photo` column
- **Do not drop** `comments.Person` or `comments.Photo` yet — kept as dead columns until Phase 6

Run `tools/dbdump.sh` to update `code/db.schema`.

**Testable:** site loads without errors; existing data unchanged; views return sensible data; `perl -c` all modules.

---

## Phase 2 — Mainlist display

Update `code/mainlist.pm` and `code/comments.pm` display path only (no posting changes yet):
- `listcomments($c, $glassid)`: join `comment_persons` with `GROUP_CONCAT(persons.Name, ', ')` for people; show a small `CommentType` badge when not `brew`
- Mainlist glass rows: use `CommentType` from `compers` view if needed
- No form changes — existing comment form still posts as before

**Testable:** mainlist renders correctly with multi-person names and type badges; existing single-person comments unaffected.

---

## Phase 3 — Other display pages

Update display (read) paths only:
- `code/locations.pm` `listlocationcomments()`: rewrite query to show direct location comments first (`comments.Location = ?`), then brew/glass comments (`glasses.Location = ?`); join `comment_persons`; respect `Username IS NULL OR Username = ?`; use `listrecords()` for rendering (not hand-rolled HTML)
- `code/persons.pm` `showpersondetails()`: replace `comments.Person` subquery with `comment_persons` join; show `CommentType = 'person'` comments initially
- `code/comments.pm` `listallcomments()`: add `CommentType` column to display

**Testable:** location page shows direct comments + brew comments in correct order; person page shows person-type comments via `comment_persons`.

**Display rule (applies across all display phases):** prefer `glasses.Timestamp` for ordering and display when `Glass` is set; otherwise fall back to `comments.Ts`.

---

## Phase 4 — Multi-person chip UI (inputs.js / inputs.css)

Build the chip infrastructure before it is wired into the comment form in Phase 5. No Perl changes in this phase:
- `static/inputs.js`: add `data-multi="1"` branch to `initDropdown` — on item select, append a chip `<span>Name <a class='remove'>×</a></span>` and a hidden `<input name="person_id" value="N">` to the form; do not replace the filter text or close the list (allows adding more people); on chip `×` click, remove chip and its hidden input
- `static/inputs.css`: minimal pill-chip styles (rounded, remove button)
- Add `data-multi="1"` to the existing person dropdown in the comment form (`selectPerson` in `comments.pm`) so the chip UI is live and testable — posting still only saves the first `person_id` (or the legacy `Person` column) until Phase 5 wires up the full loop

**Testable:** comment form shows chip UI; multiple people can be added/removed visually; chips produce hidden inputs; posting still works (saves one person as before).

---

## Phase 5 — Posting comments

Update `postcomment()` in `code/comments.pm`:
- Read `CommentType` from form — form always provides an explicit value; default to `brew` if glass has a brew, else `glass`
- Read `location_id` param for glass-less comments; write to `comments.Location`
- Write `Username`, `Ts`, `Location`, `CommentType` on INSERT and UPDATE
- Loop `person_id[]` params → INSERT into `comment_persons` after comment INSERT; keep `person=new` path working (opens person edit form as fallback, same as the existing `data-action='new'` link in the dropdown)
- Remove legacy `UPDATE comments SET Photo = ?` path (photos handled by `photos::post_photo`)
- Remove single-`Person` column from INSERT/UPDATE SQL
- Update comment form HTML:
  - `CommentType` selector (`<select>` styled via `initCustomSelect`): `brew`, `night`, `meal`, `location`, `person`, `glass` — auto-infer default from context
  - Replace single-person dropdown with `data-multi="1"` version (chip UI from Phase 4)
  - `Username` privacy toggle: lock icon / checkbox "Private" — checked = `$c->{username}`, unchecked = NULL

**Testable:** new comments save with type + multiple people + privacy; edit existing comment round-trips correctly.

---

## Phase 6 — Rest + cleanup

- `code/listrecords.pm`, `code/brews.pm`: update any `comments.Photo` / `comments.Person` column references
- `export.pm`: filter `WHERE comments.Username IS NULL OR comments.Username = ?` (skip other users' private comments)
- Drop `comments.Person` and `comments.Photo` columns (SQLite table-recreate) in a new `mig_006`; rebuild `comments_list` view a second time (first rebuild in Phase 1 removed the `Photo` column reference; this rebuild removes the column itself from the view definition) — run `tools/dbdump.sh` again
- Final manual verification of all test cases

**Testable:** export works; no remaining references to dropped columns; DB schema is clean.

---

## Verification (across all phases)
- After Phase 1: `perl -c` all modules, browse the site, inspect `compers` and `persons_list` row counts
- After each display phase: visually verify the relevant page
- After Phase 5: full comment round-trip, multi-person, privacy toggle
- Before Phase 6 prod deploy: take a DB backup, then `git pull` (migrations run automatically on first page load)
