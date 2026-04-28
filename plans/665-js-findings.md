# JS Code Review Findings — issue 665

## listrecords.js

**1. `filterGeneration` / `gen` param is dead code.**
`dochangefilter(el, gen)` receives `gen` but never uses it. The generation counter is
incremented on every call but has no effect. The debounce timeout is the only real guard
against stale-filter runs.

**2. `re.test(cols[c].textContent, 'i')` passes a spurious argument.**
`RegExp.prototype.test` takes only one argument; the `'i'` is silently ignored. Harmless
since the regex is already compiled with the `i` flag, but misleading.

**3. Two regex literals use `\$` instead of `$` (end-of-string anchor).**
In `fieldclick`:
```js
filtertext.replace( /^.*(20[0-9-]+) .*\$/ , "\$1");
```
And in `extractSortKey`:
```js
text.replace( /\]\$/, "");
```
Both were written as Perl string literals where `\$` suppresses interpolation, then moved
to a static JS file. `\$` in JS regex matches a literal `$` character, not end-of-string,
so neither regex ever matches. The date-extraction replacement in `fieldclick` therefore
**never fires**.

**4. Sort-arrow clearing only removes the first arrow character.**
`th.value.replace(/[▲▼]/,"")` replaces a single character, leaving `" ▲▲"` or `" ▼▼"`
as residue after a sort. Should use `/[▲▼]+/g`.

**5. `table.dataset.sortDir` stores the inverted direction.**
When `ascending=true` the code writes `"desc"`, and vice versa. If any future code reads
`sortDir` it will interpret it backwards.

**6. Commented-out `console.log` in `extractSortKey`** should be removed.

---

## menu.js

**7. Dead/broken code block in the leaf-node branch of `buildMenu`.**
Inside the `else` branch (when `item.children` is falsy), there is:
```js
if (item.children && item.children.some(c => c.url === currentLabel)) {
  childList.style.display = "block";   // ReferenceError — not in scope
  span.classList.add("open-parent");   // ReferenceError — not in scope
}
```
`childList` and `span` are only declared in the `if (item.children)` branch. The
condition always short-circuits (because `item.children` is falsy here), so this is
pure dead code. Should be removed.

**8. `mainToggle.cloneNode(true)` duplicates the element's `id`.**
The cloned button inherits the same `id="menu-toggle"`, creating a duplicate ID.
The id should be removed from the clone.

**9. `if (toggleButtonId)` guard is always true.**
`toggleButtonId` is a required parameter and always a truthy string. The guard is dead.

---

## beerboard.js

**10. `[class^="expanded_"]` selector is fragile.**
`^=` matches only when the attribute *starts with* the value. An element with
`class="foo expanded_1"` would not be found. Used in `toggleBeer`, `expandAll`, and
`collapseAll`. Should be `[class*="expanded_"]`.

---

## inputs.js

**11. `scanBarcodeForDropdown` uses polling instead of an event listener.**
Creates a temp hidden `<input>`, then calls `setInterval` every 100 ms for up to 30 s
waiting for its value to change. The barcode scanner already dispatches an `input` event
when it fills the value — an event listener is simpler and more reliable.

**12. `scanBarcodeForDropdown` duplicates dropdown item-selection logic incompletely.**
The regular click-handler updates `alc`, `pr`, `vol`, `Country`, `Region`, `locsubtype`,
and note visibility. The barcode path only updates `alc`, `pr`, and `vol` — omitting
Country, Region, locsubtype and the generic-brew note. A barcode scan leaves the form in a
partially-updated state.

---

## barcode.js

**13. Repeated injection of `<style>` into `<head>` on each scanner open.**
`createScannerOverlay` always calls `document.head.appendChild(style)`. Opening and
closing the scanner multiple times accumulates identical `@keyframes scan` rules.

**14. No guard against double-processing a barcode before `stopScanning` fires.**
After `processBarcodeResult` is called it schedules `stopScanning` via a 800 ms
`setTimeout`, but `requestAnimationFrame` keeps calling `detectBarcode`. A second barcode
could be processed in that window, triggering the input event twice and calling
`stopScanning` twice.

---

## geo.js

**15. Commented-out dead code at the top of `geotablecells`.**
Two orphaned lines serve no purpose:
```js
//pos.coords.latitude.toFixed(6);
//loninp.value = pos.coords.longitude.toFixed(6);
```

**16. `geodist` passes `toFixed(7)` strings to `haversineKm`.**
`lat1`/`lon1` are assigned as strings (via `toFixed(7)`) then passed to a function that
multiplies them by `Math.PI/180`. JS coerces silently, but the variables should be kept
as numbers.

**17. No `'use strict'` declaration.**
All other JS files either use `'use strict'` or are wrapped in an IIFE with `'use strict'`.
`geo.js` is the only exception.

---

## glasses.js

**18. `editrecord()` sets `noteInput.value = noteInput.dataset.note` without a null-check.**
If the `data-note` attribute is absent, `noteInput.value` is set to the string
`"undefined"`.
