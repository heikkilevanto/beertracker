# 720: Listrecords header toggle + help button

## Summary

Add a toggle button next to Clr in `listrecords` to show/hide column headers (thead) and navigation (.lr-page-nav-div) — controlled by the user via a click, with an optional `$opt` default. Add a help button with a centered popup summarizing sorting/filtering. Remove the old `compact_on_small` mechanism.

## Changes

### `code/listrecords.pm`

1. **New `$opt` parameter**: `hide_headers_default` (boolean, default 0). When truthy, headers start hidden on page load. Add to cache key.

2. **Remove `compact_on_small`**: Delete variable (line 77), cache key inclusion (line 93), and conditional script block (lines 763-765). Keep the `.lr-compact` CSS rules (lines 202-203) — they're reused by the toggle.

3. **Add "Hdr" toggle button** after Clr (line ~217):
   - Renders as `<span class='lr-hdr' onclick='lr_toggleheaders(this)'>Hdr</span>`
   - Styled similarly to Clr
   - Toggles `lr-compact` class on `[data-lr-wrapper]`
   - If `hide_headers_default` is set, emit JS to add `lr-compact` on page load

4. **Add "?" help button** after the Hdr toggle:
   - Renders as `<span class='lr-help' onclick='lr_showhelp()'>?</span>`
   - Styled as a circle similar to glasses.pm's `.help-link`
   - Shows a centered modal/popup overlay

5. **Help popup content**: Centered `<div class='lr-help-popup'>` with a close button, containing:
   - **Sorting**: Click a column header to sort ascending, click again for descending. Sort arrow (▲/▼) shown in the filter input.
   - **Filtering**: Type text in any column header input to filter rows. Multiple words = AND. Prefix with `-` to exclude, `=` for exact match.
   - **Clear**: The "Clr" button clears all filters at once.
   - **Pagination**: Use the page size selector, Prev/Next links, or the page dropdown to navigate.

### `static/listrecords.js`

1. **Add `lr_toggleheaders(el)`**: Finds `[data-lr-wrapper]` from el, toggles `lr-compact` class on it.

2. **Add `lr_showhelp()`**: Creates a centered popup div (or shows a pre-rendered one) with the help text. Close button removes it. Click-outside-to-dismiss is nice-to-have.

3. **Remove `wrapper.classList.remove('lr-compact')`** from `lr_clearfilters` (line 193). Clr no longer touches header visibility.

### Callers: replace `compact_on_small => 1` with `hide_headers_default => 1`

- `code/brews.pm:524`
- `code/locations.pm:386, 403`
- `code/comments.pm:431, 452, 476`

### Static CSS

Add styles for `.lr-help-popup` (fixed centered modal, z-index, dark theme bg, border, padding, close button) to `static/listrecords.css` — or inline in listrecords.pm's existing `<style>` block.

## Open questions (answered)

- Toggle label: "Hdr" ✓
- Help popup style: centered modal ✓
- Persistence: not needed ✓
- Clr interaction: leaves header visibility alone ✓
- Help text: my suggestion is the starting point, user will refine ✓
