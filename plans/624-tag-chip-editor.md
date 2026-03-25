# Plan: Chip-Based Tag Editor for Persons and Locations (Issue #624)

**Goal:** Replace the plain text `Tags` input on person/location edit forms with an interactive
chip UI — current tags shown as removable chips, all available tags from the DB shown below as
"add" chips. No separate tags table; tags remain space-separated strings.

---

## What changes

### 1. `code/db.pm` — new helper `get_all_tags($c, $table)`

Add a small helper that reads every `Tags` value from the given table, splits them on whitespace,
deduplicates, and returns a sorted list.  Reused by both persons and locations via `inputform`.

```perl
sub get_all_tags {
  my $c     = shift;
  my $table = shift;   # "PERSONS" or "LOCATIONS"
  my $sth   = db::query($c,
      "SELECT Tags FROM $table WHERE Tags IS NOT NULL AND Tags != ''");
  my %seen;
  while (my ($tags) = $sth->fetchrow_array) {
    $seen{$_}++ for split /\s+/, $tags;
  }
  return sort keys %seen;
}
```

### 2. `code/inputs.pm` — new `tagsInput()` + hook in `inputform()`

#### New function `tagsInput($c, $fieldname, $current_tags, @available_tags)`

Returns HTML for:
- A hidden `<input name="Tags" value="...">` (submitted value)
- A `div.tag-current-chips` showing each current tag as a removable chip
  (same `.dropdown-chip` / `.chip-remove` markup already used in person multi-select)
- A `div.tag-available-chips` showing all available tags as small add-chips,
  with the ones already active given a dimmed/disabled look
- A `<script>initTagInput(...)</script>` to wire the element

The container gets `data-disabled="1"` when `$disabled` is set (for existing-record edit mode).

#### Hook in `inputform()`

In the regular-field branch, before the generic `<input>`, add:

```perl
} elsif ( $f eq 'Tags' ) {
    my @avail = db::get_all_tags($c, $table);
    $field = inputs::tagsInput($c, $inpname, $rec->{$f} // "", $disabled, @avail);
```

No other caller changes are needed — `postperson` / `postlocation` already call
`util::clean_tags(util::param($c, 'Tags'))` before saving, so the hidden input's
space-separated value is handled correctly.

---

### 3. `static/inputs.js` — new `initTagInput(container)`

```
initTagInput(container)
  - finds hidden input, current-chips div, available-chips div
  - if container has data-disabled="1": exit early (read-only until Edit clicked)
  - currentDiv click → chip-remove → remove chip wrapper, call updateHidden()
  - availableDiv click → available-tag chip →
      if tag not already active: create chip (clone .dropdown-chip style),
      append to currentDiv, call updateHidden()
  - updateHidden(): read all current chips' data-tag attributes, join with space,
      set hidden input value
```

Reuse of existing code:
- Chip HTML structure (`.chip-wrapper / .dropdown-chip / .chip-remove`) is identical
  to `addChip()` — can call the same builder or share a helper.
- `chip-remove` click handling mirrors the existing handler in `initDropdown()`.

#### `enableEditing()` update (lines 405-432)

Add one line after existing logic to enable tag inputs inside the form:

```javascript
form.querySelectorAll('.tag-input-container[data-disabled]')
    .forEach(el => el.removeAttribute('data-disabled'));
form.querySelectorAll('.tag-input-container').forEach(initTagInput);
```

---

### 4. `static/inputs.css` — minimal additions

The active tag chips can reuse `.dropdown-chip` / `.chip-remove` without changes.

Only two new rules needed:
- `.tag-available-chips` — flex-wrap row with small gap, top border or margin to separate
  from current chips
- `.available-tag` — same shape as `.tag-suggestion` (already defined), cursor pointer;
  add a dimmed variant (`.available-tag.already-active`) for tags already in use

---

## What does NOT need to change

- `persons.pm editperson()` — already calls `inputs::inputform()`; no change.
- `locations.pm editlocation()` — same.
- `postperson` / `postlocation` — already call `util::clean_tags()` on the Tags param.
- Database schema / migrations — Tags columns already exist.
- Any scraper or list view — they read Tags but don't edit it via this form.

---

## Reuse summary

| Existing asset | Reused for |
|---|---|
| `.dropdown-chip` / `.chip-remove` CSS | Active-tag chip appearance |
| `addChip()` JS helper | Building chip DOM in initTagInput |
| `.tag-suggestion` CSS | Available-tag chip appearance |
| `enableEditing()` JS | Already enables form; just needs one extra block for tag containers |
| `util::clean_tags()` Perl | Still called by post handlers, no change |

---

## File list

- `code/db.pm` — add `get_all_tags()`
- `code/inputs.pm` — add `tagsInput()`, hook in `inputform()` for `Tags` field
- `static/inputs.js` — add `initTagInput()`, update `enableEditing()`
- `static/inputs.css` — two new rules for `.tag-available-chips` and `.available-tag`

---

## Verification

1. Edit a person who has no tags: available-chips row shows all tags from DB; clicking one adds it; submitting saves it.
2. Edit a person who already has tags: current chips shown; remove one, add another; save confirms updated value.
3. Edit a location: same as above.
4. New person / new location: tag input works interactively from the start (no disabled state).
5. Existing record: tag chips are non-interactive until "Edit" is clicked; after click they become interactive.
6. Already-active tags in the available row are visually dimmed and cannot be double-added.
