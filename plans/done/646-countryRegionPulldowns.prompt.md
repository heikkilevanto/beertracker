# Plan: Country/Region Pulldowns (#646)

**TL;DR**: Replace plain text inputs for Country and Region in both BREWS and LOCATIONS edit forms with regular dropdowns (using the existing `dropdown()` mechanism), populated from DISTINCT values in the database. Region dropdown filters on focus based on the currently selected country. New values allowed via a simple "(new)" text input. Remove all `expandCountry` logic.

---

## Phase 1: util.pm — Reverse the Country Code Map

1. Flip `%COUNTRY_CODES` from `code => name` to `name => code`, used to generate display suffixes:
   ```perl
   our %COUNTRY_CODES = (
     'Denmark'        => 'DK',
     'United Kingdom' => 'UK, GB, Eng',
     'Germany'        => 'DE',
     ...
   );
   ```
2. Remove the `expand_country()` and `country_expand_js()` functions from `util.pm` — no longer needed.

## Phase 2: Location Helpers (locations.pm)

3. Add `locations::distinct_countries_and_regions($c)` — a single function that queries both countries and regions together:
   ```sql
   SELECT DISTINCT Country, Region FROM BREWS
   UNION
   SELECT DISTINCT Country, Region FROM LOCATIONS
   WHERE Country IS NOT NULL AND Country != ''
   ORDER BY Country, Region
   ```
   Returns a hashref `{ countries => [...sorted country strings...], regions => [...sorted {country, region} hashrefs...] }`. Cache in `$c->{cache}{countries_regions}` (invalidated on POST, consistent with `cache.pm` pattern).
## Phase 3: inputs.pm — Country and Region Dropdowns

5. Extend `dropdown()` with a new optional trailing parameter `$simplenew` (default `""`). When set to `"simplenew"`:
   - Add a `(new)` action link (same as the existing `$tablename` path).
   - Render a `<div class='dropdown-new' data-simplenew='1'>` containing just a single `<input type="text" autocapitalize="words" placeholder="New value...">`, instead of a full sub-form. No Add button — the user types the value and moves on; the form's own submit button handles the rest.
   - No need to insert the new value back into the dropdown list — it only needs to land in the hidden form field.

6. In `inputform()`, add special handling for Country and Region fields (replacing the existing `expandCountry` onblur case):

   Call `locations::distinct_countries_and_regions($c)` to get both lists in one query. Use `->{countries}` for the country items and `->{regions}` for the region items.

   **Country field** — build dropdown items from the `countries` list:
   ```
   <div class='dropdown-item' id='Denmark'>Denmark [DK]</div>
   <div class='dropdown-item' id='Belgium'>Belgium [BE]</div>
   ```
   The display text includes the `[CODE]` suffix (from the reversed `%COUNTRY_CODES` — no suffix emitted if country is not in the map). The `id` is the plain country name, so the hidden input submits just "Denmark". Call `dropdown($c, "${inputprefix}Country", $currentvalue, $currentvalue, $options, "", "", "", "", "", "", "", "simplenew")`.

   **Region field** — build dropdown items from the `regions` list:
   ```
   <div class='dropdown-item' id='Amager' regioncountry='Denmark'>Amager</div>
   <div class='dropdown-item' id='Bordeaux' regioncountry='France'>Bordeaux</div>
   ```
   Call `dropdown()` similarly with `"simplenew"`. Also emit `data-country-input="${inputprefix}Country"` on the dropdown container so JS knows which Country hidden input to read when filtering.

7. Remove the existing Country special case in `inputform()` (the `country_expand_js()` call and `onblur='expandCountry(this)'`).

## Phase 4: inputs.js — Simple New + Region Filtering

8. In `initDropdown()`, add handling for the `"simplenew"` new-value form:
   - The `data-action='new'` click already shows `#newdiv-$inputname`.
   - Detect simplenew by `data-simplenew='1'` on the `dropdown-new` div. Attach a `blur` handler on the text input inside it: on blur, copy its value into the hidden input and the filter display input, then collapse the dropdown-new div.
9. Add region-filtering on dropdown open: in `initDropdown()`, if the container has `data-country-input`, attach a `focus` handler on the filter input that:
   - Reads the current value of the hidden input named by `data-country-input`.
   - Shows all region items whose `regioncountry` matches (case-insensitive), hides the rest.
   - If country is empty or unset, shows all region items.

10. The existing ProducerLocation auto-fill logic (lines 197-205) fills `Country`/`Region` hidden inputs by field name. Since the hidden inputs are now named `${inputprefix}Country` / `${inputprefix}Region` (same as before), this continues to work unchanged — the field names in nested forms already carry the prefix (e.g., `newbrewCountry`).

## Phase 5: Remove expandCountry Everywhere

11. `code/inputs.pm` — remove the `elsif ($f =~ /^Country$/i)` block that emits `country_expand_js()` and `onblur='expandCountry(this)'`.
12. `code/brews.pm` — remove any `util::expand_country()` call in `postbrew()`.
13. `code/locations.pm` — remove any `util::expand_country()` call in `postlocation()`.
14. Verify no other callers of `expand_country` or `country_expand_js` remain.

---

## Relevant Files

- `code/util.pm` — reverse `%COUNTRY_CODES`, remove `expand_country()` and `country_expand_js()`
- `code/locations.pm` — add `distinct_countries_and_regions()` with caching
- `code/inputs.pm` — extend `dropdown()` with `$simplenew`; add Country/Region cases in `inputform()`; remove old `expandCountry` case
- `static/inputs.js` — add simplenew blur handler; add region filter-on-focus logic
- `static/inputs.css` — minor tweaks if the simplenew div needs styling
- `code/brews.pm`, `code/locations.pm` — remove `expand_country()` POST calls

## Verification

1. Main list, enter new glass → expand new brew → Country dropdown shows existing countries with `[CODE]` suffixes; typing "DK" filters to Denmark.
2. In the same form, expand new producer within the new brew → nested Country/Region dropdowns work with the field prefix (e.g., `newbrewCountry`).
3. Select a country → Region dropdown on focus shows only that country's regions.
4. Select a ProducerLocation → auto-fill of Country/Region hidden inputs still works (most common path: existing producer fills in the country).
5. Click "(new)" in Country dropdown → simple text input appears; type "Iceland", tab/click away → "Iceland" submitted.
6. Region with empty country → all regions shown.
7. Brew edit form and Location edit form: same dropdown behavior.
8. Grep for `expandCountry` and `expand_country` — no surviving references.

## Decisions

- Extend `dropdown()` rather than adding a new function.
- Item `id` = plain value (country name / region name) — no escaping issues for typical names.
- Display text includes `[CODE]` suffix from reversed `%COUNTRY_CODES`; countries not in the map get no suffix.
- United Kingdom special case: suffix `[UK, GB, Eng]`.
- Region filtering: onFocus only; no re-filter on country change (list collapses on blur anyway).
- Remove ALL `expandCountry` logic — dropdown replaces it.
- Distinct value source: `BREWS + LOCATIONS` tables.
- No DB schema changes or new migrations needed.
