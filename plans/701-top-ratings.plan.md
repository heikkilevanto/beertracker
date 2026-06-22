# Plan: Top Rated Glasses on Rating Stats Page

Add a new section to the ratings statistics page (`o=Ratings`) showing the
user's top-rated individual drinking sessions (glasses), deduplicated by brew.

## Summary

New subroutine `ratestats::top_rated_glasses()` produces an HTML table of
top-rated glasses, showing:
- Rank number
- Brew name (linked to `o=Brew&e=ID`)
- Date of the glass
- Location (linked to `o=Location&e=ID`)
- Glass rating (plain number, colored by rating class)
- Brew overall average ratings in `(5.7/3)` format (only if multiple ratings)
- Volume, Price, Alcohol

Deduplication: if two glasses share the same brew, only the highest-rated
(ties broken by most recent timestamp) survives.

## Changes

### `code/ratestats.pm`

**New subroutine: `top_rated_glasses($c, $filter)`**

- Accepts the same `$filter` hashref as `histogram_data` (year, brew_type, loc_type)
- Reads `maxl` URL parameter (default 20) — same convention as `yearstat.pm`
- SQL uses `ROW_NUMBER() OVER (PARTITION BY g.Brew ORDER BY AVG(c.Rating) DESC, g.Timestamp DESC)`
  to pick the best glass per brew
- Joins with `brew_ratings` view for brew-level average stats
- Renders an HTML `<table border="1" cellpadding="5" cellspacing="0" class="data">`
- Glass rating displayed as a plain `<b>` with `comments::get_rating_class()` CSS class
- Brew avg displayed via `comments::avgratings()` — only when `rating_count > 1`
- Links and unit formatting follow existing conventions

**Integration in `ratings_histogram()`**

After `$html .= data_table(...)`, append `$html .= top_rated_glasses($c, $filter)`.

### No other files touched

`comments::avgratings()` and `comments::get_rating_class()` already exist
and do exactly what we need.

## SQL

```sql
SELECT ranked.Id, ranked.Brew, ranked.Timestamp, ranked.Volume, ranked.Price,
       ranked.Alc, ranked.BrewName, ranked.Location, ranked.glass_avg,
       br.average_rating, br.rating_count, br.comment_count,
       l.Name AS LocName
FROM (
  SELECT g.Id, g.Brew, g.Timestamp, g.Volume, g.Price, g.Alc, g.Location,
         b.Name AS BrewName,
         AVG(c.Rating) AS glass_avg,
         ROW_NUMBER() OVER (
           PARTITION BY g.Brew
           ORDER BY AVG(c.Rating) DESC, g.Timestamp DESC
         ) AS rn
  FROM glasses g
  JOIN comments c ON c.Glass = g.Id AND c.CommentType = 'brew' AND c.Rating IS NOT NULL
  JOIN brews b ON b.Id = g.Brew
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
ORDER BY ranked.glass_avg DESC, ranked.Timestamp DESC
LIMIT ?
```

## Display reference

```
#1  BrewName  2024-03-15 @Location  8  (7.2/5)  33cl  4.50€  5.2%
```

- `8` = glass rating (colored by rating class)
- `(7.2/5)` = brew avg — only shown when `rating_count > 1`
