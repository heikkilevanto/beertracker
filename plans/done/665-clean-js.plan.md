# Plan: Clean up JS files — issue 665

Source of issues: `plans/665-js-findings.md`

## listrecords.js  (findings 1–6)

**1. Remove dead `filterGeneration` / `gen` parameter.**
- Delete the `gen` parameter from `dochangefilter` signature.
- Remove all `++filterGeneration` increments and the `let filterGeneration` declaration.
- Remove all `gen` arguments from the two call-sites in `changefilter` and `fieldclick`/`clearfilters`.

**2. Remove spurious `'i'` argument from `re.test()`.**
- Change `re.test( cols[c].textContent, 'i' )` → `re.test(cols[c].textContent)`.

**3. Fix `\$` → `$` in two regexes.**
- `fieldclick`: `/^.*(20[0-9-]+) .*\$/` → `/^.*(20[0-9-]+) .*/`  
  and `"\$1"` → `"$1"` (or use a capture group correctly).
- `extractSortKey`: `/\]\$/` → `/\]$/`.

**4. Fix sort-arrow clearing to remove all arrow characters.**
- `th.value.replace(/[▲▼]/,"")` → `th.value.replace(/[▲▼]+/g, "")`.

**6. Remove commented-out `console.log` in `extractSortKey`.**

---

## menu.js  (findings 7–9)

**7. Remove the dead code block in the leaf-node `else` branch.**
- Delete the `if (item.children && ...)` block that references the out-of-scope
  `childList` and `span`.

**8. Remove `id` from the cloned toggle button.**
- After `const closeBtn = mainToggle.cloneNode(true);` add `closeBtn.removeAttribute('id');`.

**9. Remove the always-true `if (toggleButtonId)` guard.**
- Keep the body, drop the outer `if` wrapper.

---

## beerboard.js  (finding 10)

**10. Change `[class^="expanded_"]` to `[class*="expanded_"]`.**
- Three occurrences: in `toggleBeer`, `expandAll`, and `collapseAll`.

---

## inputs.js  (findings 11–12)

**11. Replace polling in `scanBarcodeForDropdown` with an event listener.**
- Remove the `setInterval` + 30 s timeout approach.
- Listen for the `input` event on `tempInput` to get the scanned value, then remove the
  listener and temp element immediately.
- Keep the 30 s safety net as a `setTimeout` that removes the listener and element if
  no scan happens.

**12. Complete the barcode-scan item-selection logic.**
- After selecting a matched item via barcode, fire the same side-effects the click-handler
  does: update Country, Region, `locsubtype`, and show-note-if-generic-brew.
- Best done by extracting the shared post-selection logic from the click-handler into a
  helper function `applyItemSelection(item, filterInput, hiddenInput, dropdownList)` and
  calling it from both places.

---

## barcode.js  (findings 13–14)

**13. Inject the scan `<style>` only once.**
- At module initialisation (top of the IIFE) insert the `@keyframes scan` style block once,
  instead of inside `createScannerOverlay`.

**14. Guard against double-processing a detected barcode.**
- Add a boolean `let resultProcessed = false;` in `startNativeScanning` scope.
- In `processBarcodeResult`, set `resultProcessed = true` on first call and return early
  if it is already true.
- Same guard for the Quagga path in `startQuaggaScanning`.

---

## geo.js  (findings 15–17)

**15. Remove commented-out dead code lines in `geotablecells`.**

**17. Add `'use strict';` at the top of `geo.js`.**

---

## glasses.js  (finding 18)

**18. Guard `noteInput.dataset.note` for missing attribute.**
- Change `noteInput.value = noteInput.dataset.note;`  
  → `noteInput.value = noteInput.dataset.note ?? '';`

---

## Order of work

1. `listrecords.js` — most impactful bugs (regex never-fire, stale sort labels)
   - Type in a filter box; verify rows hide/show correctly.
   - Click on a date cell; verify filter is set to just the year.
   - Sort the same column twice; confirm arrows flip ▲/▼ and no residue like "▲▲".
   - Click "Clear filters"; verify all rows reappear.
   - Test on a paginated list (e.g. Brews); confirm "More..." still works after filtering.

2. `beerboard.js` — quick selector fix
   - Expand a beer, then click Expand All; no rows should disappear.
   - Collapse All should restore compact rows.
   - Toggle individual beers after expand/collapse; works as before.

3. `glasses.js` — single-line safety fix
   - Edit a glass that has a note; note field should populate correctly.
   - Edit a glass with no note; note field should be empty (not the text "undefined").

4. `geo.js` — dead code + strict
   - Use "Here" and "Distance" buttons on geo pages; values should appear.
   - Geo-distance table (e.g. Locations list) should calculate and display distances.
   - Check browser console for no strict-mode errors in geo.js.

5. `menu.js` — structural dead code + id duplicate
   - Open/close the side menu via hamburger and × buttons.
   - Navigate to a leaf page (no children) and to a section page; menu should build without errors.
   - Inspect drawer close button; should have no `id` attribute.
   - Escape / click-outside should close the drawer.

6. `barcode.js` — style injection + double-scan guard
   - Open and close the scanner multiple times; inspect `<head>` for duplicate `@keyframes scan` styles (should be exactly one or none after closing, never growing).
   - Scan a barcode; should fire input event once and close overlay once.
   - Type a barcode manually and press Enter; should work.

7. `inputs.js` — polling→event and logic dedup (most involved)
   - Scan a barcode from a dropdown (e.g. Brew); with exactly one match it should select the brew, fill alc/pr/vol **and** Country/Region where applicable, set locsubtype for Restaurants, and reveal the note field if generic.
   - Scan a barcode that matches multiple brews; dropdown should filter to matches.
   - Normal click-selection of a dropdown item should still behave identically.
   - Tag filtering (`#ipa`) and "All of #tag" links should still work.
