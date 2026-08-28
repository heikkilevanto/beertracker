# Plan 754: Move inline JS/CSS from Perl modules to static files

**Goal:** Move inline `<script>`/`<style>` blocks that define logic/CSS out of the
Perl modules into existing or new `static/*.js` / `static/*.css` files, per the
AGENTS.md convention that JS/CSS should live in `static/`.

## Decisions (confirmed with user)
- Scope: **everything** identified below.
- Modules without a static file (brews, locations, photos, mainlist) get **new
  per-module files**.
- Timing: add `defer` to `jslink` so moved logic runs after DOM parse (matches the
  existing `glasses.pm` `<script defer>initGlassForm();</script>` pattern).

## Background
`index.fcgi` auto-loads a fixed set of `static/*.js` (menu, geo, filter-utils,
inputs, listrecords, beerboard, tap_timeline, glasses, comments, quagga, barcode)
and `static/*.css` (base, layout, menu, inputs, tap_timeline) via `jslink`/`csslink`
(`index.fcgi:489-501`, called in `htmlhead`). Scripts are emitted in `<head>`.

### Inline blocks — keep as-is (data passing / init calls, not logic)
- `taphistory.pm:356` TAP_LOC/DATA JSON vars (dynamic data)
- `util.pm:457` menuData JSON (dynamic data)
- `glasses.pm:260` barcode-map JSON (dynamic data)
- Init calls into existing static fns: `listrecords.pm:275,894-925`,
  `locations.pm:634`, `geo.pm:81`, `inputs.pm:115,437`, `glasses.pm:261`,
  `comments.pm:487`

### Inline blocks — move to static files
1. `listrecords.pm:193-223` — `<style>` block (~30 lines real CSS)
   → append to **`static/listrecords.css`** (already loaded, `index.fcgi:543`).
   Remove inline block.
2. `brews.pm:403-506` — 3 IIFE logic blocks (computeShortName wiring, subtype-dropdown
   filter, producer→country/region copy; uses `computeShortName`/`setDropdownValue`
   from `inputs.js`)
   → new **`static/brews.js`**. Remove the `print <<'JS'…JS` blocks.
3. `locations.pm:334-371` — 3 IIFE logic blocks (computeShortName wiring,
   untappd→scraper autofill, loctype→locsubtype cascade)
   → new **`static/locations.js`**. Remove the `print <<'JS'…JS` blocks.
4. `comments.pm:337-356` — rating-dropdown class-sync IIFE
   → **`static/comments.js`** (already loaded, `index.fcgi:555`).
5. `photos.pm:199-204` + `:637-643` — file auto-submit IIFE + per-photo
   `atype_change_$pid` function
   → new **`static/photos.js`**:
     - `photoAutoSubmit(formId, fileId)`; call inline as
       `<script defer>photoAutoSubmit('${fid}_form','${fid}_file');</script>`.
     - rename `atype_change_$pid` → `atype_change(pid, v)`; update the
       `onchange='atype_change_$pid(this.value)'` at `:626` to
       `onchange='atype_change($pid, this.value)'`.
6. `mainlist.pm:449-459,496-517` — table-click toggle IIFE + dynamic
   `updateAdjustment_$form_id`
   → new **`static/mainlist.js`**:
     - `toggleAdjForm(formId)` (from `:449-459`).
     - `updateAdjustment(formId, expected)` taking `$locprsum` as arg (from `:497`).
     - `initAdjForm(formId)` wrapper for the toggle init (from `:508-516`).
     Update inline invocation sites accordingly.
7. `beerboard.pm:711-726` — background `fetch` setTimeout IIFE (uses `$form_id`)
   → **`static/beerboard.js`** (already loaded, `index.fcgi:550`):
     `scheduleBackgroundUpdate(formId)`; call inline with `$form_id`.

## Execution steps
1. `index.fcgi`:
   - `:500` change `jslink` to emit `<script defer src='$fn?m=$mtime'></script>`.
   - In `htmlhead` (`:545-557`) add `jslink("brews")`, `jslink("locations")`,
     `jslink("photos")`, `jslink("mainlist")`.
2. Create `static/brews.js`, `static/locations.js`, `static/photos.js`,
   `static/mainlist.js` with the moved logic.
3. Append CSS to `static/listrecords.css`; add the logic to `static/comments.js`
   and `static/beerboard.js`.
4. Remove the corresponding inline `<script>`/`<style>` blocks from the `.pm` files.
5. Update inline call sites in `photos.pm`, `mainlist.pm` to the new function names.

## Verification
- `perl -c` each touched `.pm`; `node --check` (or similar) each touched/new `.js`.
- Touch `code/VERSION.pm` (separate call) to force FCGI reload.
- Manual: beer board, brew/location edit forms, comments form, photo upload/edit,
  mainlist adjustment, listrecords styling.

## Side note (not part of this change)
`glasses.pm:192` calls `startBarcodeScanning(...)` which is not defined in any
`static/*.js` (barcode.js / quagga.min.js). Likely a missing/broken handler —
flag for separate fix.
