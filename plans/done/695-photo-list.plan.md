# 695: Photo list filtering and sorting via listrecords

## Summary

Replace the custom `listphotos` implementation with a `PHOTOS_LIST` view + `listrecords` call. Layout uses a multi-row table: thumbnail on the left (rowspan via `_R4` suffix on the field name), text fields grouped 2-per-row on the right. Each text field is clickable for column filtering. No ID numbers displayed.

## Layout (per photo)

```
+----------+---------------------------+
|          | Caption: group shot       |
| Thumbnail| Person: John Doe          |
| (rowspan +---------------------------+
|  = 4)    | Brew: Sierra Nevada PA    |
|          | Location: @ The Pub       |
|          +---------------------------+
|          | Glass: Producer: Brew     |
|          |        @ Location         |
|          +---------------------------+
|          | Comment: (7) Nice!        |
|          +---------------------------+
|          | 2024-01-15               |
+----------+---------------------------+
```

Most photos attach to only one entity, so most entity cells appear empty.

## Changes

### 1. New migration #27 — `PHOTOS_LIST` view (`code/migrate.pm`)

Register migration 27 and add `mig_005_photos_list_view`:

```sql
CREATE VIEW photos_list AS
  SELECT
    p.Id,
    p.Filename AS Photo_R4,
    p.Caption,
    CASE WHEN p.Person IS NOT NULL THEN p2.Name END AS Person,
    '' AS TR1,
    CASE WHEN p.Brew IS NOT NULL THEN b.Name END AS Brew,
    CASE WHEN p.Location IS NOT NULL THEN l.Name END AS Location,
    '' AS TR2,
    CASE WHEN p.Glass IS NOT NULL THEN
      TRIM(
        CASE WHEN pl_g.Name IS NOT NULL THEN pl_g.Name || ':' ELSE '' END ||
        CASE WHEN b_g.Name IS NOT NULL THEN ' ' || b_g.Name ELSE '' END ||
        CASE WHEN b_g.Name IS NULL AND g_g.BrewType IS NOT NULL
             THEN ' [' || g_g.BrewType || ']' ELSE '' END ||
        CASE WHEN l_g.Name IS NOT NULL THEN ' @ ' || l_g.Name ELSE '' END
      )
    END AS Glass,
    CASE WHEN p.Comment IS NOT NULL THEN
      TRIM(
        CASE WHEN c.Rating IS NOT NULL THEN '(' || c.Rating || ') ' ELSE '' END ||
        COALESCE(c.Comment, '')
      )
    END AS Comment,
    '' AS TR3,
    p.Ts,
    p.Glass AS xGlass,
    p.Comment AS xComment,
    p.Location AS xLocation,
    p.Person AS xPerson,
    p.Brew AS xBrew,
    p.Uploader AS xUploader,
    p.Public AS xPublic
  FROM photos p
  LEFT JOIN persons p2     ON p2.Id = p.Person
  LEFT JOIN brews b        ON b.Id = p.Brew
  LEFT JOIN locations l    ON l.Id = p.Location
  LEFT JOIN glasses g_g    ON g_g.Id = p.Glass
  LEFT JOIN brews b_g      ON b_g.Id = g_g.Brew
  LEFT JOIN locations l_g  ON l_g.Id = g_g.Location
  LEFT JOIN locations pl_g ON pl_g.Id = b_g.ProducerLocation
  LEFT JOIN comments c     ON c.Id = p.Comment
```

Bump `$CODE_DB_VERSION` from 26 to 27.

### 2. Changes to `code/listrecords.pm`

#### a. Suffix processing for field names

After `my @fields = db::tablefields(...)` and `%field_idx`, add suffix handling. Planned suffixes: `_R(\d+)` for rowspan, `_C(\d+)` for colspan, `_(\d+px)` for column width. Suffixes are stripped from the field name for display.

```perl
my @extra_attr = ("") x scalar(@fields);  # Extra HTML attributes per column
for (my $i = 0; $i < scalar(@fields); $i++) {
    my $f = $fields[$i];
    if ($f =~ s/^(.+)_R(\d+)$/$1/) {
        $extra_attr[$i] = "rowspan='$2'";
    } elsif ($f =~ s/^(.+)_C(\d+)$/$1/) {
        $extra_attr[$i] = "colspan='$2'";
    } elsif ($f =~ s/^(.+)_(\d+px)$/$1/) {
        $styles[$i] = "style='max-width:$2; min-width:0'";
    }
}
```

Note: this runs AFTER `%field_idx` is built, so field indices still point to correct positions. Since `$styles` is set before the suffix loop, the `_(\d+px)` case will be overwritten. Place the suffix loop after the header style section (after `@styles` is fully populated), or use a separate `@style_overrides` approach.

(Alternative: run suffix processing before the header loop to strip display names, but defer style overrides to after the header loop. Either way works.)

#### b. Include `$extra_attr` in header cell

In the header rendering loop (around line 178), add `$extra_attr[$i]` to the `<td>`:

```perl
$s .= "<td $sty $extra_attr[$i]>";
```

#### c. Include `$extra_attr` in data cell

In the data rendering (line 336), add `$extra_attr[$i]`:

```perl
$tds .= "<td $styles[$i] $extra_attr[$i] $data $onclick>$v</td>\n";
```

#### d. Photo handler: suppress onclick, link to edit

```perl
} elsif ( $fn eq "Photo" ) {
    my $editurl = "$c->{url}?o=Photos&e=$rec[0]";
    $v = photos::imagetag($c, $v, $c->{mobile} ? "small" : "thumb", $editurl);
    $onclick = "";
}
```

#### e. Style: widen Photo column

```perl
} elsif ( $f =~ /^Photo$/ ) {
    $sty = "style='width:96px; text-align:center; padding:1px'";
}
```

#### f. Style: Ts alongside Last

```perl
} elsif ( $f =~ /^(Last|Ts)$/ ) {
    $sty = "style='max-width:100px; text-align:center'" if ($c->{mobile});
}
```

### 3. Replace `listphotos` body (`code/photos.pm`)

```perl
sub listphotos {
    my $c = shift;
    if ( $c->{edit} ) {
        editphoto($c);
        return;
    }
    print "<b>Photos for $c->{username}</b><br/>\n";
    my $where = q{
        ( xGlass   IN (SELECT Id FROM glasses WHERE Username = ?)
       OR xComment IN (SELECT c.Id FROM comments c
                         JOIN glasses g ON g.Id = c.Glass
                        WHERE g.Username = ?)
       OR lower(xUploader) = lower(?) )
       AND ( lower(xUploader) = lower(?) OR xPublic = 1 )
    };
    print listrecords::listrecords($c, "PHOTOS_LIST", "Ts-", $where,
        [$c->{username}, $c->{username}, $c->{username}, $c->{username}]);
} # listphotos
```

### 4. No change to `code/index.fcgi`

`jslink("listrecords")` is already in `htmlhead()` for all pages.

### 5. Update `doc/db.schema`

Run `tools/dbdump.sh` after migration to capture the new view. Will be committed along with the migration.

## What we gain vs. lose

| Gain | Lose |
|---|---|
| Column filtering per entity field | Date grouping headers (flat table) |
| Column sorting (double-click header) | Uploader field in single-photo display |
| "More..." pagination (20 rows initially) | Rich entity display (photo_attached_str) |
| Clickable text fields for instant filtering | |
| `q`/`s` parameter support | |
| Caching (listrecords caches HTML) | |

## Trade-offs

- View has 8 LEFT JOINs — but most are NULL for any given photo (only one entity per photo), so they're cheap.
- No `[N]` edit links: clicking the thumbnail opens the edit page (via imagetag link_url).
- Empty entity cells are invisible but occupy column space.
- Non-empty cells within a sub-row share horizontal space (2 per sub-row for rows 1-3, 1 for row 4).
- Brew column shows plain brew name (no producer prefix) for cleaner filtering.
- Timestamp clicking extracts date only via existing fieldclick JS regex.
