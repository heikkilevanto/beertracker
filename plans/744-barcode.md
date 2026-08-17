# Issue #744 — Barcode lives on the glass; scan via embedded barcode map

## Summary
Move the barcode's primary residence from brews to glasses, but keep all
matching **client-side** (no JSON API endpoint — consistent with how dropdown
data and `menuData` are embedded in pages):

- Each glass records the actual barcode scanned at that drinking event.
- The page embeds a **barcode map** (per user), built at render time from the
  latest of my own glasses per (Brew, Barcode), plus every `brews.Barcode`
  fallback. Each entry carries the brew id **and** vol/price/alc (from the
  latest matching glass, or from the brew's defaults for the fallback entries).
- Scanning a code is a lookup in that map: select the matching brew item and
  pre-fill vol/price/alc from the entry.
- `brews.Barcode` stays as a fallback/seed (single canonical code).
- When filing a glass with a barcode and the brew has none, **auto-store** that
  code on the brew; an **override checkbox** in the form forces an update even
  when the brew already has one.
- A scanned code with no map entry is still stored on the glass (user fills in
  the brew manually), so the history builds itself.
- Note: this embedded map is a natural first step if the system ever moves
  toward a JSON API — the data shape is already there.

## Model
- `glasses.Barcode` (nullable text) — the exact code scanned at the event.
  Index on `(Username, Barcode, Timestamp)` for building the map.
- `brews.Barcode` stays untouched (fallback seed; brew edit form unchanged).
- No schema drops, no data loss.

## Database migration (`code/migrate.pm`)
- `ALTER TABLE glasses ADD COLUMN Barcode text` (nullable).
- `CREATE INDEX idx_glasses_barcode ON glasses (Username, Barcode, Timestamp);`
- After migrating, run `tools/dbdump.sh` to refresh `doc/db.schema`.
- Alter-table steps documented in the commit message (AGENTS.md convention).

## Embedded barcode map (`code/glasses.pm`, `maininputform`)
Built per render, `encode_json`'d into a
`<script id='barcode-map' type='application/json'>` blob on the page
(precedent: `var menuData` in `util.pm`). Shape:

```json
{"1234567890123": {"brew": 42, "vol": 33, "price": 40, "alc": 5.5, "def": "1234567890123"},
 "9876543210987": {"brew": 42, "vol": 50, "price": 0,  "alc": 5.5, "def": "1234567890123"},
 "5554443332221": {"brew": 42, "vol": 50, "price": 62, "alc": 5.5, "def": ""}}
```

Every entry carries `def` = the **brew's current default barcode**
(`brews.Barcode`, may be `""`). This is what drives the override-checkbox
state after a scan (three cases, see Scan JS):
- `def == ""` → brew has no default code → pre-check the override checkbox.
- `def != "" && def != <scanned code>` → the brew already has a *different*
  code → checkbox left unchecked, user may opt in.
- `def == <scanned code>` → this *is* the brew's code → no update possible;
  checkbox and barcode display are disabled.

Built from two throwaway queries:
1. `SELECT Brew, Barcode, Volume, Price, Alc FROM glasses
   WHERE Username = ? AND Barcode IS NOT NULL AND Barcode != ''
   ORDER BY Timestamp DESC` — keep the first (i.e. latest) row per
   (Brew, Barcode) in Perl. (No window functions needed at personal scale.)
2. `SELECT Id, Barcode, DefVol, DefPrice, Alc FROM brews
   WHERE Barcode IS NOT NULL AND Barcode != ''` — provides every brew's
   `def` (its Barcode) plus its defaults.
3. Merge: start from the glass-derived entries (1), then
   - set each entry's `def` from the brew record (2);
   - add a `{brew, vol:DefVol, price:DefPrice, alc:Alc, def:Barcode}` entry
     for each brew fallback code (2) *not already in the map*.

The map must be cheap and consistent with the cached form: it is part of the
`maininputform` HTML, and that cache is cleared after every POST, so a newly
scanned code is known on the very next render.

## Main input form (`code/glasses.pm`, `maininputform`)
- In the "(more)" row (`tr id='noteline'`, revealed by `shownote()`), add:
  - a single barcode input `id='barcode' name='barcode'` (value from
    `$rec->{Barcode}`; a disabled input simply won't submit — see Scan JS),
    with a small "Scan" button beside it
    (`startBarcodeScanning('barcode')`, cf. `inputs::barcodeInput`). That
    button only fills the field; the full resolution (brew pick + defaults +
    checkbox state) happens via the Brew dropdown's scan link. The
    placeholder notes that `X` clears the barcode.
  - an override checkbox `name='setbrewcode'` (label e.g. "brew code").
- The checkbox is read by postglass; unchecked+disabled when the scanned code
  already is the brew's default. Its default rendered state is unchecked,
  enabled, empty barcode (for manual entry without scanning).
- Clear `$rec->{Barcode}` unless editing
  (`$rec->{Barcode} = "" unless ($c->{edit})`, mirroring the Note handling at
  `glasses.pm:168`) — otherwise the hidden row's inputs would submit the
  *previous* glass's code on every new glass.

## POST handling (`code/postglass.pm`)
- Real-glass branch only, after the other input values are read:
  ```perl
  # Barcode: 'X' clears it, otherwise take the input. On edit with an
  # empty/disabled input, keep the stored value (already in $glass from
  # findrec). On a new glass, never inherit from the previous record.
  my $barcode = util::param($c, "barcode");   # "" when absent/disabled
  if ( $barcode =~ /^x/i ) {
    $glass->{Barcode} = undef;                # 'X' = delete the barcode
  } elsif ( $barcode ne "" ) {
    $glass->{Barcode} = $barcode;
  } elsif ( !$c->{edit} ) {
    $glass->{Barcode} = undef;                # new glass: never inherit
  }
  ```
  Empty string is stored as NULL.
- Empty/adjustment glasses get no barcode (never set).
- Add `Barcode` to the INSERT and UPDATE column lists.
- After save, near the existing DefPrice auto-update block
  (`postglass.pm:188`), add:
  ```perl
  # If the brew has no barcode, remember this glass's code.
  # The override checkbox forces the update even when one exists.
  if ( $brew && $glass->{Barcode} ) {
    my $forcecode = util::param($c, "setbrewcode");
    my $brewcode  = $brew->{Barcode} // "";
    if ( $forcecode || !$brewcode ) {
      db::execute($c, "UPDATE brews SET Barcode = ? WHERE Id = ?",
        $glass->{Barcode}, $brew->{Id});
      print { $c->{log} } "postglass: Set brew '$brew->{Id}' Barcode to '$glass->{Barcode}'\n";
    }
  }
  ```
  Note: a NULL/cleared `$glass->{Barcode}` (X or empty) never fires this
  block — clearing the barcode on a glass never touches the brew's code.

## Scan JS (`static/inputs.js`, `scanBarcodeForDropdown`)
- On a scanned code (`code`):
  1. Write `code` into the hidden submission input `name='barcode'` and the
     visible display input `#barcode` (so it is stored even on a no-match).
  2. Look up `code` in the embedded `#barcode-map` JSON.
  3. Found: locate the dropdown item by `entry.brew`, call
     `applyItemSelection(item, ...)` — this keeps the #743 brewtype sync and
     name/alc/vol/pr defaults — then override the vol/pr/alc inputs with the
     entry's values, and set the override-checkbox + barcode state:
     - `entry.def == ""` → checkbox `checked`, enabled; display input enabled.
       (Brew has no default code — it gets this one on save, unless unchecked.)
     - `entry.def != code` → checkbox unchecked, enabled; display input
       enabled. (Brew has a different code — optional override.)
     - `entry.def == code` → checkbox unchecked and `disabled`; display input
       `disabled`. (This is already the brew's code — nothing to update.)
  4. Not found: show "No glass or brew found with barcode X", keep `code` in
     the input (and leave checkbox at its rendered default) so the manually
     chosen brew still records it. The barcode input stays enabled here.
- Why disabling without a hidden copy is fine: the only case where the input is
  disabled is when the scanned code already *is* the brew's default — in which
  case there is nothing new to record or update, so not submitting it loses
  nothing.

## Cleanup
- `selectbrew` (`brews.pm`): remove the `barcode='...'` attribute from dropdown
  items and drop `BREWS.Barcode` from its SELECT (`brews.pm:662`/`700`/`709`) —
  the fallback is now covered by the embedded map.
- Keep the rest of `brews.Barcode` machinery (brew edit field) as-is.

## Files touched
- `code/migrate.pm` — migration step (adds `glasses.Barcode` + index).
- `code/glasses.pm` — barcode input + override checkbox in "(more)" row;
  embed `#barcode-map` JSON blob.
- `code/postglass.pm` — store Barcode on glass; auto/forced brew barcode
  update.
- `static/inputs.js` — scan looks up the embedded map.
- `code/brews.pm` — drop `barcode` DOM attr from dropdown items.
- `code/index.fcgi` — unchanged (no new op, no JSON endpoint).
- `doc/db.schema` — refreshed via `tools/dbdump.sh` after migrating.

## Documentation
- `doc/design.md` — update the `glasses` section (mention the per-glass
  barcode) and the `brews` section (Barcode is now just a fallback seed for
  scanning; the primary record is on glasses). This file is edited by hand.
- `doc/manual.md` — if it describes scanning/barcode input, note the new
  behavior (scan resolves from the user's glass history, override checkbox to
  update the brew's default barcode, barcode shown behind "(more)").
- `doc/db.schema` — covered above via `tools/dbdump.sh`.
- The v3.x release-notes file, if we keep one per release, should mention the
  change (compare `doc/v3.4-release-notes.md`).

## Notes and limitations
- The page payload grows with scanned history (one small JSON entry per
  distinct code). Fine for a personal tracker; documented as the future API
  seed.
- "Latest own glass" data keeps the map per-user (glasses are per-user);
  brews stay shared.
- The brew's single `Barcode` becomes "the first/dominant code seen" via
  auto-store; full per-package detail lives in the glass history
  (`SELECT Barcode, Volume, Brew, COUNT(*) FROM glasses ... GROUP BY Barcode`).
- Override-checkbox states after a scan (driven by the entry's `def`):
  no brew code → pre-checked (updates brew); different brew code → unchecked,
  opt-in; same as brew code → unchecked + disabled, and the barcode input is
  disabled too. A disabled input isn't submitted, so on a **new** glass such a
  scan doesn't record the code on the glass (accepted — it is already the
  brew's default code, so nothing is lost). On **edit**, postglass copies the
  stored value over, so nothing is wiped.
- Manual entry (typing a code without scanning, or a no-match scan + manual
  brew pick) leaves the checkbox at its rendered default (unchecked, enabled).
- `X` in the barcode field deletes the barcode from the glass (consistent
  with the `X` convention for volume/price). It never clears the brew's code.
- Empty/missing barcode is stored as NULL, so the map queries' `Barcode != ''`
  filter stays correct.
- The barcode input's own "Scan" button only fills the field; the Brew
  dropdown's scan link is the full resolver (brew pick + vol/pr/alc + checkbox
  state).

## Verification
- `perl -c` on changed `.pm` files; review `inputs.js`.
- Manual dev test:
  - Scan a code on a brew with **no** default barcode → checkbox pre-checked;
    save stores the code on the glass *and* on the brew.
  - Uncheck the box on that same flow → glass only.
  - Scan a code whose brew already has a **different** default → checkbox
    unchecked but enabled; checking it replaces the brew's code on save.
  - Scan the code that **equals** the brew's default → checkbox + barcode
    input disabled; nothing is submitted or changed.
  - Scan an unknown code → prompt, pick brew manually, code recorded.
  - Editing a glass shows the barcode behind "(more)".
  - Two codes for the same brew (can vs bottle) both resolve to the brew with
    their own volumes.
  - Typing `X` in the barcode field and saving clears the stored barcode.
  - Editing a glass whose barcode input was disabled (scanned code == brew's
    default) keeps the stored barcode.
- Touch `code/VERSION.pm` (separate call) and reload; POST clears caches.