# Plan: Add comment checkbox for empty glasses

**Status: Ready to implement**

## Problem
When clicking "Add empty" on a location footer (e.g., adding a "Night" glass), the user is
redirected back to the main list (`?o=Graph`). They then have to scroll down to find the new
record and manually click to add a comment. This is tedious for a common workflow — adding
an empty glass and immediately noting what happened.

## Solution
Add a "comment" checkbox in two places. When checked, after creating the empty glass,
redirect to the comment form for that glass instead of back to the main list.

## Changes

### 1. `code/mainlist.pm` — checkbox in location footer "Add empty" form (line ~466)

Add a checkbox label before the submit button in the "Add empty" `<form>`:

```perl
<label style='font-size:small; margin-left:0.5em;'>
  <input type='checkbox' name='addcomment' value='1'/> comment
</label>
```

Insert between the `<select>` (line 466) and the `<button>` (line 467).

### 2. `code/glasses.pm` — checkbox on the price line (lines 218-221)

Place the checkbox on the same `<tr>` as the price input (where vol and alc normally appear).
Uses `data-empty=2` so it is **always visible** when an empty brew type is selected (no need
to click "(more)"). The existing `selbrewchange()` JavaScript handles showing/hiding via this
attribute.

```perl
$html .= "<input name='pr' id='pr' placeholder='pr' $sz4 value='$pr' />\n";
$html .= "<label data-empty=2 style='font-size:small; margin-left:0.5em;'><input type='checkbox' name='addcomment' id='addcomment' /> comment</label>\n";
```

H: No, see my previous note.

### 4. `code/postglass.pm` — redirect logic after INSERT (line ~204)

After the INSERT on line 204, check the `addcomment` param and redirect to the comment
form instead of back to the main list:

```perl
# Check if user wants to add a comment to the new glass
if ( util::param($c, "addcomment") ) {
  my $commenttype;
  if ( $glass->{BrewType} eq 'Night' ) {
    $commenttype = 'night';
  } elsif ( $glass->{BrewType} =~ /^(Restaurant|Meal|Bar)$/ ) {
    $commenttype = 'location';
  } else {
    $commenttype = 'brew';
  }
  $c->{redirect_url} = "$c->{url}?o=Comment&e=new&glass=$id&commenttype=$commenttype";
}
```

## Visibility Matrix

| Scenario | Location footer checkbox | Main form checkbox |
|---|---|---|
| New glass, regular brew type | Visible, unchecked | Hidden (`data-empty=2`) |
| New glass, empty type (Night/Meal/Restaurant) | Visible, unchecked | Visible after clicking "(more)" |
| Editing glass | N/A | Visible if brew type is empty |

## Behavior

| Checkbox State | Redirect To |
|---|---|
| Unchecked | `?o=Graph` (current behavior, back to main view) |
| Checked | `?o=Comment&e=new&glass=<ID>&commenttype=<TYPE>` (comment form) |

Comment type derivation:
- `Night` → `night`
- `Restaurant`, `Meal`, `Bar` → `location`
- Other → `brew`

## Files to Edit
1. `code/mainlist.pm` — 3 lines (checkbox in location footer "Add empty" form)
2. `code/glasses.pm` — 2 lines (checkbox on price line with `data-empty=2`)
3. `code/postglass.pm` — ~10 lines (redirect logic after INSERT)

## Notes
- No changes to `static/glasses.js` — `data-empty=2` is handled by existing `selbrewchange()` logic.
- No database changes needed — the `addcomment` param is read from the form POST.
- The comment form already shows the glass context (date, location, brewtype).
- After saving the comment, user is redirected to `?o=Full&date=<DATE>&ndays=1`.
- The `addcomment` param is only checked for new glass creation, not for edits.

## Visibility

| Scenario | Location footer checkbox | Main form checkbox |
|---|---|---|
| New glass, regular brew type | Visible, unchecked | Hidden (`data-empty=2`) |
| New glass, empty type (Night/Meal/Restaurant) | Visible, unchecked | **Always visible** on price line |
| Editing glass | N/A | Visible if brew type is empty (via `data-empty=2`)
