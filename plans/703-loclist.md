# 703: Improve Locations List with suffixes, two-line layout, country/region helper

## Summary

Refactor `locations_list` SQL view to use `_suffix` annotations (like `photos_list`),
add a two-line row layout with photo spanning both lines, and create a
`util::locdesc()` helper for compact country/region display.

---

## 1. Update `locations_list` View (new migration `mig_030`)

- LocType + LocSubType combined in SQL into one field
- Name uses `_cont` to share a cell with the combined type ("combine loc name and style into one TD")
- Ratings (Stats) before distance (Geo) — more related to the location
- Photo on row 1 with `_R2` spans both rows, rightmost column
- Second row uses `_C2` colspan to fill the space below name+type

```sql
CREATE VIEW locations_list AS
SELECT
  locations.Id AS "Id_link:Location",
  locations.Name AS "Name_A_as:LocName_cont",
  CASE
    WHEN locations.LocType IS NOT NULL AND locations.LocType != '' AND
         locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
    THEN '[' || locations.LocType || ', ' || locations.LocSubType || ']'
    WHEN locations.LocType IS NOT NULL AND locations.LocType != ''
    THEN '[' || locations.LocType || ']'
    WHEN locations.LocSubType IS NOT NULL AND locations.LocSubType != ''
    THEN '[' || locations.LocSubType || ']'
    ELSE ''
  END AS "LocType_A",
  (SELECT Filename FROM photos WHERE Location = locations.Id ORDER BY Ts DESC LIMIT 1) AS "Photo_R2",
  '' AS TR1,
  r.rating_count || ';' || r.rating_average || ';' || r.comment_count AS "Ratings_C2_contline_as:Stats",
  locations.lat || ' ' || locations.lon AS "Geo_cont",
  COALESCE(locations.Country,'') || '|' || COALESCE(locations.Region,'') AS "CountryRegion_A_cont",
  strftime('%Y-%m-%d %w ', max(glasses.Timestamp), '-06:00') ||
    strftime('%H:%M', max(glasses.Timestamp)) AS "Last_cont",
  locations.Tags AS xTags
FROM locations
LEFT JOIN glasses ON glasses.Location = locations.Id
LEFT JOIN location_ratings r ON r.id = locations.Id
GROUP BY locations.Id;
```

### How suffixes work:

| Column | Suffixes | Effect |
|--------|----------|--------|
| `Id` | `_link:Location` | Renders `L[123]` as edit link |
| `Name` | `_A_as:LocName_cont` | Auto-width, `@Name`, continues to next col |
| `LocType` | `_A` | Auto-width, wrapped in `[]`, appended in same cell as Name |
| `Photo` | `_R2` | Rowspan 2, spans both rows on the right |
| `TR1` | (none) | Inserts `</tr><tr>` — row break |
| `Ratings` (`_as:Stats`) | `_C2_contline_as:Stats` | `colspan=2`, named `Ratings` to avoid `text-align:center` from `Stats` regex match; `_as:Stats` routes back to Perl handler |
| `Geo` | `_cont` | Appends distance in same cell |
| `CountryRegion` | `_A_cont` | Auto-width, appended in same cell (no `_nofilter` — user can type in header filter to search by country/region) |
| `Last` | `_cont` | Appends in same cell (closes cell) |
| `Tags` | `x`-prefix | Hidden column, used for filtering |

### Rendered structure:

```
Row 1: [L[123]]  [@The Bar — Bar, Beer]  [Photo r2]
Row 2: [★7.5/3  2.3km  UK, London  2026-06-20 Mon]   (colspan=2)  [Photo r2]
```

Row 1 has 3 visible columns: Id link, Name+Type (merged via `_cont`), and Photo (r2).
Row 2 merges Stats+Geo+CountryRegion+Last into one `<td colspan="2">` cell filling
columns 0-1, while Photo at column 2 spans from row 1. Stats (ratings) comes before
distance since it's more location-related.

---

## 2. New Helper: `util::locdesc($c, $country, $region)`

**File:** `code/util.pm` (before the `1;` line)

Logic using the existing `%COUNTRY_CODES` hash:

| Country | Region | Output |
|---------|--------|--------|
| Denmark | Amager | `"Amager"` |
| Denmark | (null) | `"DK"` |
| United Kingdom | London | `"UK, London"` |
| Spain | (null) | `"Spain"` |
| Spain | Catalonia | `"ES, Catalonia"` |
| (null) | (null) | `""` |

```perl
sub locdesc {
  my $c      = shift;
  my $country = shift // '';
  my $region  = shift // '';
  my $r       = $region ? trim($region) : '';

  return $r if $country eq 'Denmark' && $r;
  return 'DK' if $country eq 'Denmark';
  if ($r) {
    my $code = exists $COUNTRY_CODES{$country}
               ? (split /,\s*/, $COUNTRY_CODES{$country})[0]
               : $country;
    return "$code, $r";
  }
  return $country;
} # locdesc
```

Uses `%COUNTRY_CODES` for short codes (`"United Kingdom"` → `"UK"`). When no
region, shows full name (`"Spain"` not `"ES"`). Denmark with region shows just
the region; Denmark without region shows `"DK"`.

---

## 3. New `CountryRegion` Handler in `listrecords.pm`

Add a branch in the data-rendering `elsif` chain (after `LocName`, before `Stats`):

```perl
} elsif ( $fn eq "CountryRegion" ) {
  my ($country, $region) = split(/\|/, $v, 2);
  $v = util::locdesc($c, $country, $region);
  $v .= "&nbsp;&nbsp;" if $v;
  $word_split = 0;
}
```

`$word_split = 0` prevents splitting the formatted text into clickable words.
Trailing `&nbsp;&nbsp;` adds visual separation between country/region and the
following timestamp in the merged cell. Filtering by country/region still works
via the header filter input (substring search on cell text).

---

## 4. Update `locations.pm::listlocations`

No changes needed — function already calls
`listrecords::listrecords($c, "LOCATIONS_LIST", $sort, "", "", $extraparams)`
with `$extraparams->{lat} = '?'` for Geo distance.

---

## 5. CSS / Styling

Check if the existing `.top-border td { border-top: 2px solid white; }` provides
enough visual separation between records. May need:

```css
tr[data-first=1] td { border-top: 2px solid white; }
```

This ensures each "first row" of a multi-row record gets a top border, visually
grouping the two lines into one record.

---

## 6. Migration Registration

In `code/migrate.pm`:
- Add `mig_030_locations_list_suffixes` sub that drops+creates the view
- Register: `[30, '703 locations_list use suffixes', \&mig_030_locations_list_suffixes]`
- Bump `$CODE_DB_VERSION` to 30

---

## Files Changed

| File | Change |
|------|--------|
| `code/util.pm` | Add `locdesc()` helper |
| `code/listrecords.pm` | Add `CountryRegion` handler branch |
| `code/migrate.pm` | Add migration 30 with new view definition |
| `doc/db.schema` | Update via `tools/dbdump.sh` after migration |
| `static/layout.css` or `static/base.css` | Optional: record-separator border |
