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

**5. Fix `sortDir` storing the inverted value.**
- When `ascending=true` write `"asc"`, when false write `"desc"`.

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

**16. Use numeric values for `lat1`/`lon1` in `geodist`.**
- Change `pos.coords.latitude.toFixed(7)` → `pos.coords.latitude` (keep as number).
- Same for longitude. Only format to string when displaying.

**17. Add `'use strict';` at the top of `geo.js`.**

---

## glasses.js  (finding 18)

**18. Guard `noteInput.dataset.note` for missing attribute.**
- Change `noteInput.value = noteInput.dataset.note;`  
  → `noteInput.value = noteInput.dataset.note ?? '';`

---

## Order of work

1. `listrecords.js` — most impactful bugs (regex never-fire, stale sort labels)
2. `beerboard.js` — quick selector fix
3. `glasses.js` — single-line safety fix
4. `geo.js` — dead code + strict
5. `menu.js` — structural dead code + id duplicate
6. `barcode.js` — style injection + double-scan guard
7. `inputs.js` — polling→event and logic dedup (most involved)
