# Plan: Issue 624 — Tags Chip UI for Persons and Locations

## Goal
Replace the plain `<input>` for the `Tags` field in person/location edit forms with a
two-part chip UI:
- **Top**: current tags as removable chips
- **Below**: all existing tags (collected from DB) as addable chips

Available tags are scoped per table: PERSONS tags for person edit, LOCATIONS tags for
location edit. Tags are extracted by scanning all non-null Tags columns (space-separated
words), deduplicating, and sorting alphabetically.


## Changes

### 1. `code/db.pm` — new `all_tags($c, $table)` helper
- Query all non-null `Tags` from the given table.  
- Split each row on whitespace, deduplicate, sort alphabetically.
- Return a sorted arrayref of unique tag strings.

### 2. `code/inputs.pm` — new `tagsinput` sub + hook in `inputform`
- New `tagsinput($c, $current_tags_str, $available_tags_aref, $disabled)`:
  - Renders a `<div class="tags-input" id="tags-input-Tags">` with:
    - `<div class="tags-current">` — one `chip-wrapper` per current tag
    - `<div class="tags-available">` — one addable chip per available tag +
      a special "(New tag)" chip at the end that reveals a text input + Add button
    - `<input type="hidden" name="Tags" id="Tags">` — updated by JS before submit
  - When `$disabled` is set: renders current chips without × buttons and with
    `tags-available` div hidden (display:none). JS is still initialised but inert.
  - Calls `initTagsInput(el)` from inputs.js on the container.
- In `inputform`, when `$f` is `Tags`, call `tagsinput` instead of the plain `<input>`.
- Add an optional `$available_tags_ref` parameter to `inputform` (arrayref). If undef,
  falls back to a plain text `<input>` for Tags (safe default for other callers).

### 3. `code/persons.pm` — pass available tags to `inputform`
- In `editperson`, call `db::all_tags($c, "PERSONS")` and pass as the new last arg
  to `inputs::inputform`.

### 4. `code/locations.pm` — same
- In `editlocation`, call `db::all_tags($c, "LOCATIONS")` and pass to `inputs::inputform`.

### 5. `static/inputs.js` — `initTagsInput(container)` function
- On init: if the container has `data-disabled`, do nothing (read-only view).
- Click `.tag-available-chip` (that is not the "new tag" chip):
  - Add tag to current chips (see below), grey/disable the available chip.
- Click `.chip-remove` on a current chip:
  - Remove chip, re-enable the corresponding available chip.
- The "(New tag)" chip click:
  - Reveal the hidden text input + "Add" button next to it.
- "Add" button / Enter in the text input:
  - `clean_tags` normalisation (strip leading `#`, lowercase, trim).
  - If not empty and not a duplicate: add as a current chip, clear the text input.
  - Hide the text input again.
- On form `submit`: collect all `.tags-current .chip-wrapper` label texts →
  join with space → write to hidden `#Tags` input.
- `enableEditing(form)` (already in inputs.js or menu.js) un-disables inputs; the
  tags-available div should also be unhidden at that point. Hook into `enableEditing`
  or use CSS: `.edit-enabled .tags-available { display: block }`.

### 6. `static/inputs.css` — minimal new styles
- `.tags-available` — flex-wrap row, small gap, shown only in edit mode.
- `.tag-available-chip` — reuse existing chip look, cursor:pointer.
- `.tag-available-chip.used` — greyed out, pointer-events:none.
- `.tags-new-input` — small inline text field + add button.


## Data flow
1. Page loads for existing record with Tags = "staff regular".
2. `tagsinput` renders two current chips ("staff", "regular") and all DB tags as
   available chips. "staff" and "regular" available chips are rendered with class `used`.
3. Form is initially disabled; × buttons hidden, `.tags-available` hidden.
4. User clicks "Edit" → `enableEditing` un-disables. × buttons appear, available chips appear.
5. User clicks available chip "vip" → added to current chips; its available chip greyed.
6. User clicks × on "staff" → removed from current, its available chip re-enabled.
7. User clicks "(New tag)" → text field appears; types "cellar"; clicks Add →
   "cellar" chip added to current (no available chip for it since it's brand new).
8. Submit → JS writes "regular vip cellar" to hidden `Tags` input →
   `clean_tags()` normalises → `postrecord` saves.


## Notes
- No schema changes.
- `postperson` and `postlocation` already call `util::clean_tags()` before saving — no
  changes needed there.
- The `inputform` change is backward-compatible: only persons.pm and locations.pm pass
  the available_tags arg; all other callers (e.g. embedded new-record forms) get the
  plain text input as before.
