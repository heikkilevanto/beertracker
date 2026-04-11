## Plan: Country/Region on Producers (#541)

**TL;DR**: Add `Country` and `Region` columns to the `LOCATIONS` table (where producers are stored). When a producer is selected in the brew form dropdown, auto-populate the brew's `Country`/`Region` fields (only if empty), using the same JS attribute-copy pattern already used for `alc`/`defprice`/`defvol`.

---

**Steps**

### Phase 1: Database
1. **`code/migrate.pm`**: Add migration 17
   - Bump `$CODE_DB_VERSION` to 17
   - Register `[17, 'add Country and Region to locations', \&mig_017_...]`
   - Sub: `ALTER TABLE locations ADD COLUMN Country TEXT`, same for `Region TEXT`
   - Drop + recreate `locations_list` view to include Country and Region columns
   - Back-populate `Country` and `Region` on existing producers from their brews (most frequent non-empty value):
     ```sql
     UPDATE locations
     SET Country = (
       SELECT Country FROM brews
       WHERE brews.ProducerLocation = locations.Id
         AND brews.Country IS NOT NULL AND brews.Country != ''
       GROUP BY Country ORDER BY COUNT(*) DESC LIMIT 1
     ),
     Region = (
       SELECT Region FROM brews
       WHERE brews.ProducerLocation = locations.Id
         AND brews.Region IS NOT NULL AND brews.Region != ''
       GROUP BY Region ORDER BY COUNT(*) DESC LIMIT 1
     )
     WHERE locations.LocType = 'Producer';
     ```

### Phase 2: Backend
2. **`code/locations.pm`** (`selectlocation` function):
   - Add `LOCATIONS.Country`, `LOCATIONS.Region` to the cached SQL query
   - Emit `country='...'` and `region='...'` HTML attributes on each `<div class='dropdown-item'>` (same pattern as existing `locsubtype` and `tags` attributes)

### Phase 3: Frontend
3. **`static/inputs.js`** (dropdown click handler, after the existing `defvol` block):
   - Add auto-fill for Country: `document.querySelector("[name='Country']")` — only fills if currently empty
   - Add auto-fill for Region: `document.querySelector("[name='Region']")` — only fills if currently empty
   - Uses `querySelector("[name='...']")` rather than `getElementById` since `inputform()` doesn't set IDs on regular inputs

### Phase 4: Defaults (no change needed)
4. **`code/brews.pm`** line 365: The `$p->{Country} = "DK"` default is kept as-is — still useful as a fallback when no producer is selected for a new brew.

---

**Relevant files**
- `code/migrate.pm` — migration 17, follows pattern of `mig_016_add_tags_to_persons_and_locations`
- `code/locations.pm` — `selectlocation()` ~line 435 (SQL) and ~line 449 (opts loop)
- `static/inputs.js` — dropdown click handler ~line 191, after the `defvol` block
- `code/brews.pm` — line 365 (no change needed)

**Verification**
1. `perl -c` on changed files after edits
2. Touch `code/VERSION.pm` to reload FastCGI
3. Navigate to a Producer location in dev → verify Country/Region fields appear in edit form
4. Set Country to e.g. `"BE"` on a producer, save
5. Create a new brew → select that producer → confirm Country auto-fills to `"BE"`
6. Edit a brew with Country already set → select a producer → confirm Country is NOT overwritten
7. Run `tools/dbdump.sh` and commit updated `doc/db.schema`

**Decisions**
- Country + Region both added (confirmed)
- Auto-fill only when brew field is currently empty (confirmed)
- Columns added to all LOCATIONS rows (not just producers) — consistent with how Tags works; benefit is country on restaurants too
- `Country = "DK"` brew default kept as-is — still useful fallback
- Cache auto-invalidates after each POST, so no explicit cache-busting needed
