# 695: Photo list filtering and sorting via listrecords

## Summary

Replace the custom `listphotos` implementation with a `PHOTOS_LIST` view + `listrecords` call, giving the photo list the same column-based filtering, sorting, and pagination as brews, locations, persons, and comments.

## Changes

### 1. New migration #27 — `PHOTOS_LIST` view (`code/migrate.pm`)

Register migration 27 and add `mig_005_photos_list_view`:

```sql
CREATE VIEW photos_list AS
  SELECT
    p.Id,
    p.Filename AS Photo,
    p.Glass   AS AtGlass,
    p.Location AS AtLocation,
    p.Person  AS AtPerson,
    p.Brew    AS AtBrew,
    p.Comment AS AtComment,
    p.Caption,
    p.Uploader,
    p.Ts,
    p.Glass   AS xGlass,
    p.Comment AS xComment,
    p.Location AS xLocation,
    p.Person  AS xPerson,
    p.Brew    AS xBrew,
    p.Public  AS xPublic
  FROM photos p
```

Each photo row has the thumbnail, then separate entity columns (AtGlass, AtLocation, etc.). Only the column corresponding to the photo's actual attachment has content; the others are empty/collapsed. The `x*` columns are hidden, used only in the visibility WHERE clause.

Bump `$CODE_DB_VERSION` from 26 to 27.

### 2. Add entity field handlers (`code/listrecords.pm`)

Insert `my %field_idx = map { $fields[$_] => $_ } 0..$#fields;` after `my @fields = db::tablefields(...)` (line 71), before the order loop.

In the big `elsif` chain (around line 293), add before the `Comment` handler:

```perl
} elsif ( $fn eq "AtGlass" ) {
    $v = photos::photo_attached_str($c, { Glass => $v }) if $v;
} elsif ( $fn eq "AtLocation" ) {
    $v = photos::photo_attached_str($c, { Location => $v }) if $v;
} elsif ( $fn eq "AtPerson" ) {
    $v = photos::photo_attached_str($c, { Person => $v }) if $v;
} elsif ( $fn eq "AtBrew" ) {
    $v = photos::photo_attached_str($c, { Brew => $v }) if $v;
} elsif ( $fn eq "AtComment" ) {
    $v = photos::photo_attached_str($c, { Comment => $v }) if $v;
}
```

Each handler calls `photo_attached_str()` with only the relevant FK, producing the same rich HTML (links, names) as the current display — but limited to one entity type per column.

### 3. Replace `listphotos` body (`code/photos.pm`)

Lines 321-370 (the SQL query and rendering loop) → single `listrecords` call:

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
       OR lower(Uploader) = lower(?) )
       AND ( lower(Uploader) = lower(?) OR xPublic = 1 )
    };
    print listrecords::listrecords($c, "PHOTOS_LIST", "Ts-", $where,
        [$c->{username}, $c->{username}, $c->{username}, $c->{username}]);
} # listphotos
```

### 4. No change to `code/index.fcgi`

`jslink("listrecords")` is already in `htmlhead()` (line 495) for all pages.

### 5. Update `doc/db.schema`

Run `tools/dbdump.sh` after migration to capture the new view. Will be committed along with the migration.

## What we gain vs. lose

| Gain | Lose |
|---|---|
| Column filtering (type in header inputs) | Date grouping headers (flat table) |
| Column sorting (double-click header) | |
| "More..." pagination (20 rows initially) | |
| Caching (listrecords caches HTML) | |
| Separate, filterable entity columns | |
| `q`/`s` parameter support | |

## Trade-offs

- `photo_attached_str()` runs per row per entity column (same total DB queries as today — one entity per photo means one call per row).
- listrecords caching makes subsequent views instant.
- `Id` shows `[N]` for direct edit access; thumbnail links to full-size image (consistent with other listrecords views).
- Entity columns are flat (one row per photo), not stacked vertically like the current table.
