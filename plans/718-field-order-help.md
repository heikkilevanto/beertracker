# Issue #718 — Field ordering and help texts for inputform

## Summary
Add optional field ordering and per-field help texts to `inputform()` via a new 9th parameter `$field_order` (array of `[fieldname, help]` pairs). The help text is shown/hidden via a toggle button (question mark in a circle) next to each field.

## New parameter
```perl
$field_order = [
  [ "Name",        "The name of the brew" ],
  [ "BrewType",    "Type of beer (IPA, Stout, etc.)" ],
  [ "Alc",         "Alcohol percentage" ],
  [ "SubType" ],   # just ordering, no help
]
```

- `fieldname` matches DB column names case-insensitively (no `-` prefix for INTEGER/REAL columns)
- `help` is optional — omit or pass empty string if only ordering is needed
- Fields not mentioned in the config appear at the end in PRAGMA column order
- Unknown field names in the config trigger a `warn` to STDERR

## Implementation stages

### Stage 1 (this PR): Core machinery in `code/inputs.pm`
- Add 9th `$field_order` param to `inputform()` (default `undef`)
- Build merged field list before the loop: configured fields in order, then remaining fields
- Render help toggle button + hidden help `<div>` at end of each field's `<td>`
- Add `fieldorder` key to `dropdown()`'s `$opt` hash, pass through to `inputform` for inline forms

No visible change until a caller passes `$field_order`.

### Stage 2: Wire up a caller (e.g., `code/brews.pm`)
- Add a `$field_order` array with desired ordering and help texts
- Verify fields reorder and help toggles work

### Future (optional)
- Wire up `persons.pm`, `locations.pm`
- Wire up dropdown inline forms that need help texts
- Refactor positional params to hash

## Help toggle behavior
- A `<span class='help-link'>?</span>` (circle with `?`, same style as main form) appears in the **label column** after the field name
- Text is stored in `data-help` attribute, HTML-escaped via `util::htmlesc()`
- On click, calls existing `showHelpPopup(text, element)` from `static/glasses.js` — renders a fixed-position overlay popup near the button
- Clicking outside the popup closes it (handled by existing `hideHelpPopup` event listener)
- Uses `data-help` attribute and `this.dataset.help` to avoid single-quote escaping issues in JS
