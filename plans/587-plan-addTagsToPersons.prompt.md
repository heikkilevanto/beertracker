# Plan: Add Tags Field to Persons and Locations

**What:** A `Tags TEXT` column on the `persons` and `locations` tables. Tags are space-separated words. The selectperson and selectlocation dropdowns gain `#tag` filter syntax: a dynamic tag-suggestion row appears at the top of the dropdown showing clickable tag chips. Clicking a tag always filters the name list to matching items. Additionally, when exactly one tag matches the current search prefix, an "All of #tag" link appears on the same row to bulk-select all matching items (chip them all in multi-select, or select the first in single-select).

---

## Phase 1 — Database (`migrate.pm`)

1. Add `mig_016_add_tags_to_persons_and_locations`:
   - `ALTER TABLE persons ADD COLUMN Tags TEXT`
   - `ALTER TABLE locations ADD COLUMN Tags TEXT`
   - Rebuild `persons_list` view to include `persons.Tags` as a column (`DROP VIEW / CREATE VIEW`)
   - Rebuild `locations_list` view to include `locations.Tags` as a column (`DROP VIEW / CREATE VIEW`)
   - Bump `$CODE_DB_VERSION` to 16; register `[16, 'add Tags to persons and locations', \&mig_016_add_tags_to_persons_and_locations]` in `@MIGRATIONS` (After the v3.3 comment)

## Phase 2 — Dropdown data

2. **`persons.pm` `selectperson`**: add `PERSONS.Tags` to the SQL SELECT. Emit as `tags='$tags'` HTML attribute on each `dropdown-item` div (HTML-escaped). Mirrors how `seenat` is handled in other dropdowns.

3. **`locations.pm` `selectlocation`**: same — add `LOCATIONS.Tags` to its SQL SELECT and emit `tags='$tags'` on each item div.

## Phase 3 — JavaScript (`static/inputs.js`)

### Tag filtering in `filterItems`

4. Add `isTagFilter = filter.startsWith('#')` branch:
   - `searchTerm = filter.substring(1)` (empty string when just `#` is typed)
   - An item is **visible** if:
     - `searchTerm` is empty and the item has a non-empty `tags` attribute, **OR**
     - any individual tag in the item's space-separated `tags` attribute **starts with** `searchTerm`
     - (word-start match: split tags by whitespace, check `tag.startsWith(searchTerm)`)
   - This avoids partial-word false matches (e.g. `ar` will not match `bar`)
   - The `actions` row is always kept visible

### Tag-suggestion row

5. Each dropdown gets a `dropdown-tag-row` div dynamically managed by JS (created once and **prepended to the top of the dropdown list** on first use). It is shown only when the filter starts with `#`; when shown, the `actions` row (new/scan) is hidden.

   **Content:** unique tags collected from all `dropdown-item`s (not just visible ones) that match the current prefix. Tags are collected **in the order they appear in the list** (which is already sorted by most recent activity), deduplicated by first occurrence, and capped at a small fixed number (e.g. 8) so they fit on one line. Each tag is rendered as a small clickable `<span class='tag-suggestion'>#tag</span>` chip.

   **Clicking a tag chip (both single- and multi-select):**
   - Sets the filter to `#<tag>`, re-runs `filterItems` (name list updates to only matching items)
   - Does **not** auto-select anything — user sees the filtered list and can pick from it

   **"All of #tag" link:** when exactly one tag matches the current prefix, append an `<a class='tag-select-all'>All of #tag</a>` link at the end of the tag row (after the chip). Clicking it:
   - Runs `filterItems` for that exact tag
   - **Multi-select:** adds all now-visible `.dropdown-item`s as chips (deduplicating), then clears the filter
   - **Single-select:** selects the first now-visible `.dropdown-item` (same logic as a click), closes the dropdown

6. Remove the Enter-key approach entirely (not implemented).

---

## Phase 4 — Documentation

7. Update **`doc/design.md`**: describe the Tags field on persons and locations, and the `#tag` filter syntax in dropdowns.

8. Update **`doc/manual.md`**: user-facing description of how to use tags (add them in edit forms, filter with `#` in person/location selectors).

---

## Relevant files
- `code/migrate.pm` — mig_016, CODE_DB_VERSION bump, persons_list + locations_list view rebuild
- `code/persons.pm` — `selectperson`: Tags in SQL + `tags` attr on divs
- `code/locations.pm` — `selectlocation`: Tags in SQL + `tags` attr on divs
- `static/inputs.js` — `filterItems` tag branch + tag-suggestion row
- `static/inputs.css` — style for `.tag-suggestion` chips in the dropdown
- `doc/design.md` and `doc/manual.md` — documentation updates

---

## Verification
1. Run migration; confirm `pragma table_info(persons)` and `pragma table_info(locations)` both show `Tags`
2. Edit a person, add tags `family work`, save — confirm stored, visible in edit form and persons list view
3. Edit a location, add tags `office pub`, save — confirm stored, visible in edit form and locations list view
4. **Multi-select** (comment person selector): type `#` → tag-suggestion row appears with all tags (in recency order), name list shows only persons with any tag; type `#fam` → row shows `family` chip only; click `family` → list filtered to persons tagged `family`; "All of #family" link also appears — clicking it chips all those persons
5. **Single-select** (location selector): type `#pub` → tag row shows `pub` chip + "All of #pub"; click `pub` chip → list filtered to `pub` locations; click "All of #pub" → first such location selected and dropdown closes
6. Verify `(new)`/`(scan)` actions row is hidden while `#` is typed, reappears when filter is cleared

---

## Decisions
- Tags are plain text, space-separated; no separate tags table
- `inputform` / `postrecord` handle edit forms and POST automatically — no code changes needed there
- Tag matching is word-start (each individual tag must start with the typed term), not substring of the whole field
- Typing just `#` shows only items that have at least one tag; items with empty/null Tags are hidden
- Tag-suggestion row is at the top of the dropdown list, created/managed purely in JS; no server-side HTML change needed beyond the `tags` attribute on items
- Tag chips are shown in recency order (order of data rows), deduplicated by first occurrence, capped at ~8 to fit one line
- Clicking a tag chip always filters — never auto-selects; "All of #tag" link (shown only when exactly one tag matches) handles bulk selection
- `(new)`/`(scan)` actions row is hidden while a `#` filter is active
- After implementation, run `tools/dbdump.sh` to update `doc/db.schema` and commit both
