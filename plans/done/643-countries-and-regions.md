# Plan: Countries and Regions (#643)

**TL;DR**: Clean up country codes used for beers and locations by using full country names instead of 2-letter codes. Allow users to still type codes and have them auto-expanded to full names. Also back-populate country/region from producers to brews that are missing them.

---

## Steps

### Phase 1: Database Migration (migrate.pm)
1. Add migration 18:
   - Expand all existing 2-letter country codes to full names in BREWS table
   - Expand all existing 2-letter country codes to full names in LOCATIONS table
   - Back-populate Country/Region from ProducerLocation to brews that are missing them
   - Bump $CODE_DB_VERSION to 18

### Phase 2: Server-side expansion (util.pm)
2. Add `expand_country($code)` function to util.pm that maps common ISO codes to full names
   - Case-insensitive matching (DK, dk, Dk all work)
   - Returns the full name if the code is recognized, otherwise returns the input unchanged

### Phase 3: Use expansion in POST handlers
3. Call `util::expand_country()` on Country field in `postbrew()` in brews.pm
4. Call `util::expand_country()` on Country field in `postlocation()` in locations.pm

### Phase 4: Client-side expansion (static/inputs.js)
5. Add a JS country-code map and blur handler on Country input fields
   - When the Country field loses focus, if the value matches a known code, expand it
   - This gives immediate user feedback before form submission

### Phase 5: Update db.schema comment
6. Update the comment in doc/db.schema to reflect that Country is now a full name

---

## Relevant files
- `code/migrate.pm` — add migration 18
- `code/util.pm` — add expand_country function
- `code/brews.pm` — call expand_country on save
- `code/locations.pm` — call expand_country on save
- `static/inputs.js` — client-side expansion on blur
- `doc/db.schema` — update comment

## Country code map (most common)
DK → Denmark, DE → Germany, SE → Sweden, NO → Norway, FI → Finland,
BE → Belgium, NL → Netherlands, FR → France, GB → United Kingdom,
UK → United Kingdom, US → United States, IT → Italy, CZ → Czech Republic,
AT → Austria, IE → Ireland, CH → Switzerland, ES → Spain, PL → Poland,
AU → Australia, JP → Japan, CA → Canada, NZ → New Zealand, LV → Latvia,
LT → Lithuania, EE → Estonia, PT → Portugal, RU → Russia, HU → Hungary,
SK → Slovakia, SI → Slovenia, HR → Croatia, RS → Serbia, GR → Greece,
LU → Luxembourg, MX → Mexico, BR → Brazil, AR → Argentina
