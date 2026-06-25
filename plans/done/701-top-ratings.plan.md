# Plan: Top Rated Glasses on Rating Stats Page

Add a new section to the ratings statistics page (`o=Ratings`) showing the
user's top-rated individual drinking sessions (glasses), deduplicated by brew.
Also handles non-brew items (Night, Location, Meal, etc.) — each such glass
is its own "group" (no dedup).

## Summary

New subroutine `ratestats::top_rated_glasses()` produces an HTML table with
columns:
- **Rating** (combined): glass rating as a bold colored number + brew overall
  average in `(5.7/3)` format (only shown when `rating_count > 1`)
- **Brew**: brew name (linked to `o=Brew&e=ID`), or BrewType for non-brew items
- **Location**: location name (linked to `o=Location&e=ID`)
- **Date**: date of the glass (linked to `o=Full&e=ID`), with `&shy;` after
  first dash for mobile line wrapping

Also supports a "bottom" mode (worst-rated first) and configurable count.

## Changes

### `code/ratestats.pm`

**Subroutine: `top_rated_glasses($c, $filter)`**

- Accepts the same `$filter` hashref as `histogram_data` (year, brew_type, loc_type)
- Reads `maxl` URL parameter (default 20) — same convention as `yearstat.pm`
- Reads `bottom` URL parameter — flips to bottom-rated (ascending sort)
- SQL:
  - Joins `comments` on `c.Glass = g.Id` (ALL CommentTypes, no restriction)
  - Uses `COALESCE(b.Name, g.BrewType)` as GlassName — shows brew name when
    available, otherwise the glass's BrewType (e.g. "Night")
  - `PARTITION BY CASE WHEN g.Brew IS NULL THEN -g.Id ELSE g.Brew END` — each
    non-brew glass is its own partition, brews are deduplicated
  - Window `ROW_NUMBER()` per partition orders by `AVG(c.Rating) DESC/ASC`
    (tied sorted by most recent timestamp)
  - Left joins `brew_ratings` for brew-level average stats (NULL for non-brew)
  - ORDER BY `glass_avg DESC/ASC, COALESCE(br.average_rating,0) DESC/ASC, Timestamp DESC`
- Renders a 4-column HTML table
- After table: links for `Show: 10 20 50 100 200 | top/bottom` that carry
  filter params and bottom flag

**Integration in `ratings_histogram()`**

After `$html .= data_table(...)`, append `$html .= top_rated_glasses($c, $filter)`.

### No other files touched

`comments::avgratings()`, `comments::get_rating_class()`, `util::htmlesc()`
already exist and are reused.

## SQL

```sql
SELECT ranked.Id, ranked.Brew, ranked.Timestamp, ranked.Location,
       ranked.GlassName, ranked.glass_avg,
       br.average_rating, br.rating_count, br.comment_count,
       l.Name AS LocName
FROM (
  SELECT g.Id, g.Brew, g.Timestamp, g.Location,
         COALESCE(b.Name, g.BrewType) AS GlassName,
         AVG(c.Rating) AS glass_avg,
         ROW_NUMBER() OVER (
           PARTITION BY CASE WHEN g.Brew IS NULL THEN -g.Id ELSE g.Brew END
           ORDER BY AVG(c.Rating) DESC, g.Timestamp DESC
         ) AS rn
  FROM glasses g
  JOIN comments c ON c.Glass = g.Id AND c.Rating IS NOT NULL
  LEFT JOIN brews b ON b.Id = g.Brew
  LEFT JOIN locations loc ON g.Location = loc.Id
  WHERE g.Username = ?
    [AND strftime('%Y', g.Timestamp) = ?]
    [AND g.BrewType = ?]
    [AND loc.LocType = ?]
  GROUP BY g.Id
) ranked
LEFT JOIN locations l ON l.Id = ranked.Location
LEFT JOIN brew_ratings br ON br.brew = ranked.Brew AND br.Username = ?
WHERE ranked.rn = 1
ORDER BY ranked.glass_avg DESC, COALESCE(br.average_rating, 0) DESC, ranked.Timestamp DESC
LIMIT ?
```

## Display reference

```
8 (7.2/5)  BrewName        @Location   2024-&shy;03-15
7          Night           @Home       2024-&shy;06-20
9 (8.1/7)  AnotherBrew     @Bar        2024-&shy;01-10
```

- `8` = glass rating (bold, colored by `get_rating_class()`)
- `(7.2/5)` = brew avgratings — only shown when `rating_count > 1`
- Brew column links to `o=Brew` when `Brew IS NOT NULL`, plain text otherwise
- Location column links to `o=Location` when set
- Date column links to `o=Full&e=ID`
