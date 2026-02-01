# Heikki's Beer Tracker

## Overview
This is a simple script to track the beers I drink. I also use it for other
purposes, like remembering restaurants, tracking wines and booze, and displaying
nice graphs.

## WARNING - This manual is badly out of date, and needs an almost complete rewrite

---

## Getting started
When you start, the database is empty. You need to enter all details on the first
beers. Your browser will remember some of those values and suggest them to you.
If you leave values empty, the program will try to make a guess from your history.
This only works if you spell the beer name the same way, so be correct there.
It is handy for picking up the strength and price of beer, etc.

The system is optimized for filing things as you drink, but you can enter data
after the fact. In that case, click on the little ^ to get more fields visible,
and put in the date and time in the two first input fields, as YYYY-MM-DD HH:MM

Most of the time, if you have drunk that beer before, it is easy to find the beer
in the list, and just click on the `copy` buttons. They come in predefined sizes of
25 and 40 cl, and if you drank some other quantity, that gets a copy button too.

On the beer list, almost every word is a link to filter the list. If you click on
the brewery name, the list shows only beers from that brewery. Same for location,
etc. You can also filter only those entries that have ratings on them, or comments.
This is good if you want to look up a beer before buying.

There are dedicated lists for beers, breweries, locations, etc. Those can be
selected from the "show" pull-down in the input form.

---

## Input fields

### Overview

The input form is the primary interface for recording your drinking history. It's designed for quick data entry and can track:
- Glasses of beer, wine, or booze
- Restaurant and bar visits
- General nights out
- Feedback entries

The form is intelligent: most fields auto-populate with values from your most recent entry, making it fast to record multiple drinks at the same location or of the same type. When you click on any input field, the entire value is automatically selected (using `Onfocus='value=value.trim();select();'`), so you can immediately type to replace it, and the value is automatically trimmed of whitespace.

All text fields have `autocapitalize='words'` enabled for better mobile keyboard behavior.

### Date

**Format:** `YYYY-MM-DD` (e.g., `2024-03-15`)

**Validation pattern:** ` ?([LlYy])?(\d\d\d\d-\d\d-\d\d)?`

The date field determines when the glass was consumed. It supports several special behaviors:

**Auto-fill mode (default):**
- When creating a new entry, the field is prefilled with a leading space and the current date (e.g., ` 2024-03-15`)
- The leading space indicates the value is automatically filled and will update to the current date when you click anywhere on the form
- If you want to use the current date, simply leave it as-is

**Special prefixes:**
- **L** (or **l**): Use the date from your latest (Last) entry. The system queries the database and sets the date to 5 minutes after your previous entry.
- **Y** (or **y**): Use Yesterday's date. Automatically calculates yesterday's date.
- **Space prefix:** Auto-filled date that updates when form is clicked (e.g., ` 2024-03-15`)

**Manual entry:**
- Enter a specific date in YYYY-MM-DD format (e.g., `2024-03-15`)
- The date field has HTML5 pattern validation to ensure correct format

**Edit mode behavior:**
When editing an existing entry, if the date field still has a leading space, it keeps the original date from the record instead of auto-filling.

### Time

**Format:** `HH:MM` (24-hour format, e.g., `23:45`)

**Validation pattern:** ` ?\d\d(:?\d\d)?(:?\d\d)?`

The time field records when you had the drink. Like the date field, it auto-fills but accepts many formats:

**Auto-fill mode (default):**
- Prefilled with a leading space and current time (e.g., ` 23:45`)
- Updates to current time when you click on the form
- Leave as-is to use the current time

**Special prefixes:**
- **L** (or **l**): Sets time to 5 minutes after your latest entry (same as date 'L' behavior)
- **Space prefix:** Auto-filled time that updates when form is clicked

**Flexible time formats accepted:**
- `23:55` - Standard HH:MM format
- `2355` - Compact HHMM format (converted to 23:55)
- `235859` - HHMMSS format (converted to 23:58:59)
- `1` - Single digit hour (converted to 01:)
- `15` - Two digit hour (converted to 15:00)
- `15:` - Hour with colon (converted to 15:00)
- `21:00:` - Incomplete seconds (auto-filled with current seconds)

**Time normalization:**
The system automatically normalizes all time formats to `HH:MM:SS` internally:
- Adds leading zeros where needed
- Appends current seconds if only HH:MM provided (for unique timestamps)
- Ensures proper formatting for database storage

**Edit mode behavior:**
When editing an existing entry, if the time still has a leading space, it keeps the original time instead of auto-filling.

### Location

**Type:** Dropdown select with option to create new locations

**Field name:** `Location`

The location field specifies where you had your drink. It's a smart dropdown that:

**Selection behavior:**
- Shows all existing locations from your history
- Defaults to the location from your most recent entry
- Provides a "new location" option to create locations on-the-fly
- When creating a new location, you'll see an inline text input for the location name

**Smart location features:**
- **Click the "Location" label** to auto-select your nearest location based on geolocation (if enabled)
  - Uses JavaScript: `onclick='selectNearest("#dropdown-Location")'`
- Can integrate with geolocation coordinates (handled separately, not shown in basic form)
- Location is required; you cannot submit without selecting or creating one

**Creating new locations:**
- Select "new location" from dropdown
- Enter the name in the text field that appears
- New location is created automatically when you submit the form
- The new location becomes available in the dropdown for future entries

### Record Type (BrewType)

**Type:** Custom dropdown select (replaceSelectWithCustom)

**Field name:** `selbrewtype`

**Options:** Beer, Wine, Booze, Restaurant, Night, Bar, Feedback (dynamically loaded from existing glass types)

The Record Type is a critical field that controls which other fields are shown or hidden. It uses the `data-isempty` attribute system to manage dynamic field visibility.

**"Normal" record types** (Beer, Wine, Booze):
- Show the Brew selection dropdown
- Show Volume, Alcohol, and Price fields
- Hide SubType selection
- Calculate standard drinks based on volume and alcohol percentage

**"Empty" record types** (Restaurant, Night, Bar, Feedback):
- Hide the Brew selection dropdown
- Hide Volume and Alcohol fields
- Show SubType selection
- Show only Price field (volume and alcohol are set to 0)
- Used for tracking visits without specific drink records

**Dynamic field visibility:**
When you change the Record Type, JavaScript (`selbrewchange()` function) automatically:
1. Reads the `data-isempty` attribute from the selected option
2. Finds all elements with `data-empty` attributes in the form
3. Shows/hides elements based on matching rules:
   - `data-empty=1`: Hidden for empty glasses, shown for normal glasses (Brew selection, Volume, Alc)
   - `data-empty=2`: Shown for empty glasses, hidden for normal glasses (SubType selection)
   - `data-empty="BrewType"`: Shown only when that specific BrewType is selected

**Implementation details:**
- Uses a custom select dropdown implementation (`replaceSelectWithCustom()`)
- Dropdown is styled with `max-width:100px; text-overflow:ellipsis; overflow:hidden`
- The `onChange='selbrewchange(this);'` handler triggers the visibility logic

### SubType and Brew Selection

These two fields are mutually exclusive based on the Record Type selection.

#### SubType (for "empty" glasses)

**Type:** Dropdown select

**Field name:** `selbrewsubtype`

**Visibility:** Only shown when Record Type is Restaurant, Night, Bar, or Feedback (`data-empty=2`)

The SubType field categorizes empty glass records. Common examples:
- For Restaurant: Cuisine type, restaurant style
- For Night: Type of venue or event
- For Bar: Specific bar category
- For Feedback: Type of feedback

**Auto-population:**
- Dropdown is populated from historical SubTypes used with "empty" glass types
- Sorted by most recent usage (`ORDER BY last_time DESC`)
- Each option has `data-empty="BrewType"` to indicate which BrewType it's associated with
- Can create new SubTypes on-the-fly

#### Brew Selection (for normal glasses)

**Type:** Dropdown select with option to create new brews

**Field name:** Provided by `brews::selectbrew()` function

**Visibility:** Only shown when Record Type is Beer, Wine, or Booze (`data-empty=1`)

The Brew field selects which specific beverage you're drinking:

**Selection behavior:**
- Dropdown shows existing brews filtered by the selected BrewType
- Sorted by most recent usage
- Includes a "new brew" option to create brews on-the-fly
- When creating a new brew, inline form fields appear for brew details (Name, Style, Maker, SubType, etc.)

**Smart defaults:**
- When you select an existing brew, the form auto-populates:
  - Volume (from previous entries or brew defaults)
  - Alcohol percentage (from brew data)
  - Price (from tap_beers table, previous entries, or brew defaults)

**Creating new brews:**
- Select "new brew" option
- Fill in brew details inline
- New brew is created and selected automatically on form submission

### Volume

**Format:** Number with optional unit suffix (e.g., `33c`, `L`, `12 oz`)

**Field name:** `vol`

**Placeholder:** `vol`

**Size:** 4 characters, right-aligned

**Visibility:** Hidden for "empty" glass types (`data-empty=1`)

**Auto-population:** Appends 'c' suffix to volume value when displayed

The Volume field specifies how much you drank, in centiliters by default.

**Predefined size codes:**
- **T** = 2cl (Taster)
- **G** = 16cl (Glass of wine)
- **S** = 25cl (Small)
- **M** = 33cl (Medium, typical bottle)
- **L** = 40cl (Large, default)
- **C** = 44cl (Can)
- **W** or **B** = 75cl (Bottle of wine)

**Usage examples:**
- `33c` - 33 centiliters (the 'c' is optional, auto-appended)
- `L` - Expands to 40cl (large beer)
- `M` - Expands to 33cl (medium/bottle size)
- `S` - Expands to 25cl (small)
- `12 oz` - Converts US fluid ounces to centiliters (36cl, calculated as oz × 3)
- `HB` - Half bottle = 37cl (half of 75)
- `HL` - Half large = 20cl (half of 40)

**Half portions:**
- Prefix any size with 'H' to get half: `HM` = 16cl (half of medium 33cl)

**Special values:**
- **X** (or **x**) - Indicates no volume, sets volume to 0, standard drinks to 0
- Default if empty: `L` (40cl large beer)

**Processing:**
1. System checks for 'H' prefix for half portions
2. Converts size codes to numeric centiliters
3. Converts ounces if 'oz' suffix present
4. Stores as numeric value in database
5. Used to calculate standard drinks: `(Volume × Alc%) / onedrink`

### Alcohol Percentage

**Format:** Number with optional '%' suffix (e.g., `4.6%`, `5.5`)

**Field name:** `alc`

**Placeholder:** `alc`

**Size:** 4 characters, right-aligned

**Visibility:** Hidden for "empty" glass types (`data-empty=1`)

**Auto-population:** Appends '%' suffix when displayed

The Alc field records the alcohol content by volume (ABV).

**Usage:**
- Enter as a decimal number: `4.6`, `5.5`, `12.0`
- The '%' suffix is automatically added for display
- System accepts both comma and period as decimal separator (commas converted to periods internally)

**Special values:**
- **X** (or **x**) - Indicates no/unknown alcohol, sets to 0%

**Auto-population:**
- Defaults to the alcohol percentage from the selected brew's previous entries
- If brew has never been recorded, uses brew's stored Alc value (if available)
- If neither is available, defaults to 0

**Standard drinks calculation:**
The alcohol percentage is used with volume to calculate "standard drinks":
```
StandardDrinks = (Volume_in_cl × Alc_percentage) / onedrink
```
Where `onedrink` is typically 12 (Danish system: 33cl @ 4.6% = 1.0 standard drink).

### Price

**Format:** Number with optional '.-' suffix (e.g., `45.-`, `89`)

**Field name:** `pr`

**Placeholder:** `pr`

**Size:** 4 characters, right-aligned

**Required:** Yes (HTML5 `required` attribute)

**Auto-population:** Appends '.-' suffix when displayed

The Price field records how much you paid. This is the only strictly required field.

**Input formats:**
- Enter as a plain number: `45`, `89`, `125`
- System automatically strips any trailing punctuation (commas, periods, dashes)
- Only digits are stored: `45.-` becomes `45`

**Special values:**
- **X** (or **x**) - Indicates no price (free or unknown), sets to 0

**Auto-population (smart price guessing):**
When price is left empty, the system attempts to auto-fill from:
1. **tap_beers table** - If this brew is on tap at this location, matches price by volume (SizeS/PriceS, SizeM/PriceM, SizeL/PriceL)
2. **Previous entries** - Looks for most recent glass of same brew, location, and volume
3. If neither found, leaves empty (but form validation requires a value)

**Currency conversion (future feature):**
- Code includes support for EUR and USD conversion (not currently active)
- Would convert foreign currencies to DKK using fixed rates

**Brew defaults:**
- When recording a brew for the first time (no DefPrice set), this price and volume become the brew's defaults
- The "Def" checkbox (when Note line is revealed) allows manually updating brew defaults

### Tap

**Format:** 2-character numeric field (e.g., `12`, `5`)

**Field name:** `tap`

**Size:** 2 characters

**Visibility:** Only shown when Note line is revealed (click "(more)")

The Tap field records which tap number the beer came from (primarily used for beer board tracking).

**Usage:**
- Enter the tap number: `1`, `12`, `42`
- System strips all non-numeric characters
- Useful for correlating with beer board entries
- Optional field

**Auto-population:**
- When creating new entry, prefixed with space (e.g., ` 12`) to indicate inherited from previous
- Space-prefixed values are not saved unless edited
- When editing existing entry, shows actual value without space prefix

### Note

**Format:** Free text (size 20)

**Field name:** `note`

**Placeholder:** `note`

**Visibility:** Hidden by default, revealed by clicking "(more)" toggle

The Note field allows free-form text notes about your drink.

**Access:**
1. Click the "(more)" text in the left column
2. The note line is revealed with two fields:
   - Tap (2-character field)
   - Note (20-character text input)
3. The "(more)" toggle is hidden
4. A "Def" checkbox appears in the left column

**Special behavior:**
- Not inherited from previous entry (always starts empty for new records)
- When editing an existing entry with a note, the note line is shown by default
- The note is displayed in the full list view

### Def Checkbox

**Field name:** `setdef`

**Type:** Checkbox

**Visibility:** Only shown when Note line is revealed

The Def (set defaults) checkbox updates the selected brew's default price and volume.

**Usage:**
- Check this box when you want the current price and volume to become the brew's defaults
- Useful when a brew's price changes or you typically drink a different size
- Only appears after clicking "(more)" to reveal the note line
- Requires both price and volume to be set

**Implementation:**
When checked, calls `brews::update_brew_defaults($c, $brewid, $glass->{Price}, $glass->{Volume})` to update the brew's DefPrice and DefVol fields.

### Buttons

The form includes several buttons with different behaviors depending on whether you're creating a new entry or editing an existing one.

#### Record Button (new entry mode only)

**Value:** `Record`

**Type:** submit

**Action:** Creates a new glass record

**Behavior:**
- Validates all required fields (Price must be filled)
- Processes timestamp (date/time)
- Normalizes volume and alcohol values
- Calculates standard drinks
- Inserts new record into GLASSES table
- Auto-fills some fields for the next entry (location, brew selection, etc.)

#### Save Button (edit mode only)

**Value:** `Save`

**Type:** submit

**Action:** Updates the existing glass record

**Behavior:**
- Updates all fields in the GLASSES table for the edited record
- Uses `UPDATE GLASSES SET ... WHERE id = ? AND username = ?`
- Record ID is passed via hidden input `e` parameter

#### Del Button (edit mode only)

**Value:** `Del`

**Type:** submit

**Attributes:** `formnovalidate` (bypasses HTML5 validation)

**Action:** Deletes the glass record

**Behavior:**
- Deletes the record from GLASSES table
- Uses `formnovalidate` so it bypasses required field validation (can delete even if form is incomplete)
- Clears edit mode
- Clears graph cache files

#### Clr Button (new entry mode only)

**Value:** `Clr`

**Type:** button (not submit)

**Action:** Clears all text inputs in the form

**Behavior:**
- JavaScript function `clearinputs()` finds all `<input type="text">` elements
- Sets their values to empty string
- Does not clear dropdowns or hidden fields
- Does not submit the form

#### Cancel Link (edit mode only)

**Value:** "cancel" (text link, not button)

**Action:** Exits edit mode and returns to normal view

**Behavior:**
- Link to `$c->{url}?o=$c->{op}` (current operation without edit parameter)
- Discards any unsaved changes
- Returns to normal list view with input form in "new entry" mode

### Special Behaviors & Smart Features

#### Auto-Population System

The form intelligently populates fields from your most recent entry:
- **Location**: Defaults to previous location
- **BrewType**: Defaults to previous type
- **Brew**: If same brew selected, inherits volume, alcohol, price
- **Volume**: Inherits from brew defaults or previous entry
- **Alcohol**: Inherits from brew data or previous entry  
- **Price**: Smart guessing from tap_beers table or previous entries
- **Note**: NOT inherited (always starts empty)
- **Tap**: Inherited with space prefix (only saved if edited)

#### Date/Time Auto-Fill with Leading Space

Both date and time fields use a clever "leading space" system:
- New entries get ` YYYY-MM-DD` and ` HH:MM` (note leading space)
- Leading space indicates "auto-filled, will update"
- JavaScript `setdate()` function updates these when you click anywhere on the form
- This gives you "current time" behavior without JavaScript running continuously
- In edit mode, leading space indicates "keep original value"

#### Dynamic Field Visibility

The form uses `data-empty` attributes to show/hide fields:
- **data-empty=1**: Hidden for empty glasses (Restaurant/Night/Bar/Feedback), shown for normal glasses
  - Applied to: Brew selection, Volume field, Alc field
- **data-empty=2**: Shown for empty glasses, hidden for normal glasses
  - Applied to: SubType selection
- **data-empty="BrewType"**: Shown only when specific BrewType is selected
  - Applied to: SubType options for specific record types

JavaScript `selbrewchange()` function handles the visibility logic when Record Type changes.

#### Field Selection Behavior

All text inputs use `Onfocus='value=value.trim();select();'`:
- When you click a field, the value is trimmed of whitespace
- The entire value is selected
- Start typing to immediately replace the value
- Or use arrow keys to position cursor and edit

#### Autocapitalize

All text fields have `autocapitalize='words'` attribute:
- Mobile keyboards automatically capitalize the first letter of each word
- Improves data consistency for proper nouns (beer names, locations, etc.)

### Advanced Features & Edge Cases

#### Creating Entities On-The-Fly

You can create new locations, brews, and subtypes directly from the input form:
- **New Location**: Select "new location" from Location dropdown, enter name inline
- **New Brew**: Select "new brew" from Brew dropdown, fill in brew details inline
- **New SubType**: Simply enter a new value in SubType field

All new entities are created during form submission via the `postglass.pm` handler.

#### Timestamp Shortcuts

**Date shortcuts:**
- **Space prefix** (` 2024-03-15`): Auto-filled current date, updates on form click
- **L**: 5 minutes after your latest entry date
- **Y**: Yesterday's date

**Time shortcuts:**
- **Space prefix** (` 23:45`): Auto-filled current time, updates on form click  
- **L**: 5 minutes after your latest entry time

The 'L' (Last) shortcut queries: 
```sql
SELECT strftime('%Y-%m-%d %H:%M:%S', Timestamp, '+5 minutes') 
FROM GLASSES WHERE username = ? ORDER BY Timestamp DESC LIMIT 1
```

#### Seconds Auto-Fill

Time seconds are automatically added from current time:
- If you enter `23:45`, system appends current seconds: `23:45:37`
- Makes timestamps unique and properly sortable
- Seconds are rarely displayed but important for database ordering

#### Standard Drinks Calculation

For normal (non-empty) glasses, standard drinks are calculated:
```
StDrinks = (Volume_in_cl × Alc_percentage) / onedrink
```
Where `onedrink` is typically 12 (configurable per user).

Danish system: 33cl @ 4.6% = (33 × 4.6) / 12 = 1.265 ≈ 1.0 standard drink

#### Brew Defaults Auto-Set

When recording a brew for the first time (brew has no DefPrice):
- Current price and volume become the brew's default values
- Automatically updates: `UPDATE BREWS SET DefPrice = ?, DefVol = ? WHERE Id = ?`
- Future entries of this brew will use these defaults

#### Pattern Validation

HTML5 pattern validation ensures data quality:

**Date pattern:** ` ?([LlYy])?(\d\d\d\d-\d\d-\d\d)?`
- Optional leading space
- Optional L or Y prefix
- Standard YYYY-MM-DD format (or empty)

**Time pattern:** ` ?\d\d(:?\d\d)?(:?\d\d)?`
- Optional leading space
- Two-digit hour (required)
- Optional colon and two-digit minute
- Optional colon and two-digit second

#### Half Portions

Prefix any size code with 'H' for half portions:
- `HL` = Half Large = 20cl (half of 40)
- `HM` = Half Medium = 16cl (half of 33)
- `HB` = Half Bottle = 37cl (half of 75)

System processing: `/^(H)(.+)$/` captures H prefix, then `$vol = int($vol / 2)`

#### Ounces Conversion

US fluid ounces are converted to centiliters:
- Pattern: `/([0-9]+) *oz/i`
- Conversion: `oz × 3` (actually 2.95735, rounded for simplicity)
- Example: `12 oz` becomes 36cl

### Workflow Tips

#### Quick Entry Workflow

Recording drinks quickly while at a bar:

1. Form loads with defaults from last entry (location, time auto-fills)
2. Select Record Type (Beer/Wine/Booze) - often already correct
3. Select or type brew name - if you've had it before, volume/alc/price auto-fill
4. Adjust volume if different (type `S`, `M`, or `L` for standard sizes)
5. Adjust price if different
6. Click "Record"
7. Form resets with most fields pre-filled for next entry
8. Repeat for next drink

**Optimization**: If drinking the same beer, just adjust the time and click Record.

#### Restaurant Visit Workflow

Recording a restaurant visit without specific drinks:

1. Select Record Type: "Restaurant"
   - Brew, Volume, and Alc fields automatically hide
   - SubType field appears
2. Select or create location
3. Enter SubType (e.g., "Italian", "Fine Dining", "Casual")
4. Enter Price (total meal cost)
5. Optionally click "(more)" to add notes about the meal
6. Click "Record"

#### Editing an Entry Workflow

Fixing or updating a previous entry:

1. Find the entry in the list below
2. Click the "Edit" link next to it
3. Form loads with entry's data
   - "Id N" shown at top indicating which record
   - Date/time prefixed with space (will keep original if not edited)
4. Modify fields as needed
5. Click "Save" to update, or "Del" to delete, or "cancel" to abort
6. Form returns to normal "new entry" mode

#### Backfilling Historical Data

Entering drinks from a previous date:

1. Click the up-arrow (if hidden fields not visible) - currently not explicitly in the form code, but mentioned in old docs
2. Clear the date field and enter date: `2024-01-15`
3. Clear the time field and enter time: `20:30`
4. Fill in all other fields (location, brew, volume, etc.)
5. Click "Record"
6. For next entry from same session, use "L" shortcut:
   - Date: `L` (5 minutes after last)
   - Time: `L` (5 minutes after last)
7. Continue recording

#### Using the Def Checkbox

Updating a brew's default price/volume:

1. Record the glass normally
2. Before clicking Record, click "(more)" to reveal Note line
3. Check the "Def" checkbox
4. Click "Record"
5. This brew's defaults are now updated
6. Future entries will use these new defaults for price and volume

### Hidden Fields and Parameters

The form includes several hidden fields for operation control:

- **o** (operation): Current operation mode, usually "Glasses" or similar
- **e** (edit): When editing, contains the record ID to update
- **submit**: The value of the button clicked ("Record", "Save", "Del")

These are automatically managed by the form and should not be manually edited.

---

## Editing
The input form is also used for editing old records. In that case there are
a few small differences:
* At the top there is a text telling which record you are editing. The records
are identified by their timestamps.
* The regular input fields are as before, but filled in with the values from
the record.
* There is a 'Del' button for deleting the record, and a 'Cancel' link to get
out of the edit mode.
* There is no 'Record' button, you should use the 'Save' button to save your
changes to that record.

---

## The main menu
The "Show" menu allows you to choose what gets shown under the input form.

### Full list
It shows a list of beers you have had, most recent first. There are many ways
to filter that list.

At the top of the list are some links to filter the list:
* Ratings - Shows only the beer entries where you have filled in a rating
* Comments - Shows only the beers that you have commented on
There is also a link to show Extra Info for each beer. Ratings, when last seen,
and such.

The list itself is divided into days, and those can be divided into locations,
if you have been drinking at different places.

The first line of each beer has the time, brewery, and name of the beer. These
can be marked with 'new' if it looks like it is the first time you enter such.
That is useful for catching spelling errors. The brewery and beer names are links
that cause the list to be filtered so that only that beer or brewery is shown.
That makes it easier to see what you have thought about the beer, or what else
the brewery has made.

Next comes a number of small facts about the beer. They are on a line of their
own when seen on a phone, or appended to the first line on a wider computer
screen.
* Style. This is solor-coded to match the graph (see below). It is also a link
to filter the list by this style.
* Price
* Volume
* Alc
* "Standard drinks"
* Blood alc (only if showing Extra Info). This is a rough estimate, based on
some formulas I found on the net, and my own body weight.

The next line has the rating you have given the beer, and comments, if you
entered any.

If you asked to show Extra Info, it will be on the next lines. These include
how many times the system has seen the beer, how many ratings we have for it,
and the average of them, as well as the geo location for that entry (mostly
for debugging the geo stuff)

The last line has a link for editing the entry - that puts all the values in
the input fileds above, where you can correct mistakes. (See above.)
That line also has a few "Copy" buttons, defaulting to most likely sizes you
might drink again. You can click those buttons on any beer entry, and the system
will create a new entry for todays date and time, with that amount of that beer.
That is by far the easiest way to enter data.

At the end of each day or location there will be summaries on how much you have
drank there.

### Graph
Shows a graph of your drinking. Time is on the X-axis, with different background
color for weekend (Fri, Sat, and Sun). On Y is the number of drinks:

* Each drink is a little bar of its own. Color coded to indicate the beer style.
* Each change of location is indicated by a thin white line
* For days with no drinks, there is a green dot in the bottom. For consecutive
days, the dot moves a bit higher, up to 7 days.
* There is a white line that is a floating average of the past 30 days, with
higher weights for the more recent days.
* There is a green line that shows the (arithmetic) average for the last 7
days, including today.

Under the graph are navigation buttons:
* "<<" and ">>" move the graph earlier and later in time
* "2w", "Month", "3m", "6m", "Year", "2y", and "All" adjsut how long time is
shown in the graph
* [-] and [+] fine tune the zoom factor

Clicking on the graph itself zooms it to double the size. Clicking again zooms
back.

Under the graph is the usual full list. Since we have calculated the floating
averages for the graph, they are shown in the list for each day too.

### Beer Board
This is a list of beers available on the current location (or Ølbaren, if no
list available for that location). There is a pull-down for selecting the location
out of the few I have scripted access to. There are couple of links nex to it:
* www links to the home page of the bar, if known
* (PA) filters the list so it only shows Pale Ales, IPAs and suchlike, as those
are what I most often drink.
* (Reload) forces a reload of the beer list. Otherwise the system caches the
list for a couple of hours to make things go faster. Useful if you see the
bartender writing a new one on the blackboard.
* (all) expands all the entries, making the list more informative, but also
using up much more space on the screen.

In the simple form, each beer is on a line of its own. The lines can get wider
than your phone screen, you can scroll sideways to read the rest. The important
details are in the beginning of the line.
* Tap number. Color coded for beer style. Clicking on this expands that one
beer entry.
* Two buttons for entering the beer into the system. One for a small beer, the
other for a large one. Usually 25 and 40 cl, but can vary depending on what sizes
the beer is served.
* Alc percentage
* Beer name
* Brewer
* Country
* Style (simplified)

If you selected the Extended display, each beer takes up a few lines. Where we
have it, there will be a line telling how many times we have seen that beer
before, when was the last time, how many ratings and their average, compressed
into something like "3 rat=6.3"

Before the beer board is always the graph (see bove), and under it the display
continues as the full list (see above).

### Stats
Shows some statistics for each day, month, or year. On top is a line with links
to each statistic. When selected from the menu, this starts as the monthly
statistic.

#### Days
Shows a line for each day with
* Date and weekday
* How many drinks
* How much money
* Highest blood alc for the day
* Locations where I have been that day, in reverse order. Some are abbreviated,
like "Øb" for Ølbaren and "H" for Home.

Consecutive days with no drinks are compressed in one line like "... (3 days)..."

#### Months
This shows a graph of average daily consumption for each month. Each year is
plotted with a different color. The most recent years are plotted with thicker
lines.

Underneath is the same data in a table form. For each month we have average
drinks per day and week, and amount of money spent. For the current month there
is also a projection where we might end at the same speed.

There are also averages for each calendar month, and averages and sums for
each year.

#### Years
This shows in a table form where I have spent most money for each year, with the
biggest spending locations first. The list shows also the number of drinks at
the location. The sorting defaults to money, but can be changed to number of
drinks.

### Small lists
There are a number of "small" lists. The main menu only has the Beer List, but
from that it is easy to navigate to the other ones. All the lists default to
chronological order with the most recent first, but can be sorted alphabetically.

There is also a search box that filters only the lines matching what ever you
enter there.

#### Location
Shows a list of the most recent watering holes you have visited. For each there
is
* Name of the place. Clicking on this gets you to the full list, filtered by
that location.
* Link to the beer board of the location, if known to the system
* Link to the bars web page, if known to the system
* Link to a google search of the place name
* Last time you visited, and how many visits the system knows about
* The last beer you drank there: Brewery and name. These are links that filter
the location list by that beer or brewery.

#### Brewery
Shows the most recent breweries you have been enjoying, with about the same data
as for the location list, except that it lists where you had the beer last.
The list excludes all "special" breweries that have a comma in their names.

#### Beer
Lists the beers you have had. On the left is the beer name with a count how many
of them you have had, and on the right side when and where you had it last, and
the style, alcohol, and brewery of the beer. Also this list excludes the "special"
breweries, so it only shows things that really are beers.

#### Wine and Booze
Much like the beer list, these show record types "Wine" and "Booze".

#### Restaurant
Shows a list of the "Restaurant" type records. Shows the style of the place,
what you had there, how much you spent (total price, for one person), and ratings
if you rated the place.

#### Style
Lists all beer styles known to the system, when and where you last had one.

### About
Contains the copyright message, and all kind of useful details I didn't know
where else to put.
* Link to the source code and bug tracker on GitHub
* Links to RateBeer and Untappd, as well as some of my favourite watering holes
* Summary of the abbreviations for various volumes
* Debug info, including a download of the whole data file or just the tail of it.


---


## Problems
If you are just starting, I may be willing to help with technical issues, especially
if I have set up an account for you on my system. If you are self-hosting, I hope you
can manage most technical problems yourself, and/or look in the code to see what
is going on.

If you run into bugs and real problems, please file them as issues on GitHub, at
https://github.com/heikkilevanto/beertracker/issues. Even better, if you can fix it
yourself, file a pull request.

See also the [README](./README.md)
