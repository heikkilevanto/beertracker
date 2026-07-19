# 608: Switch editing pages to listrecords-based comment lists

## Summary

Replace custom inline SQL+HTML comment listings on the brew, location, and
comment editing pages with `listrecords` calls using the `COMMENTS_LIST` view.
Add a `show_rating_summary` option to `listrecords` for rating count/average.

The glass editing page (main list / full list) is intentionally not changed — it
is different enough that listrecords doesn't fit.

---

## Phase 1: `show_rating_summary` in listrecords.pm + listrecords.js

### `code/listrecords.pm`

- Add `my $show_rating_summary = $opt->{show_rating_summary} || 0;`
- After the row-rendering loop (line ~711), when `$show_rating_summary` is set:
  - Compute `$ratecount`, `$ratesum`, `$comcount` from column indices of Rate
    and Comment fields (tracked during the loop)
  - Render a `<div class='lr-summary'>` after the table using
    `comments::avgratings()` / `comments::ratingline()` for formatting
- Add `data-col-rate="N"` and `data-col-comment="M"` attributes on the `<table>`
  so JS can find the right columns

### `static/listrecords.js`

- New function `lr_update_summary(table)`:
  - Reads `data-col-rate` and `data-col-comment` from the table
  - Iterates all `<tbody>` where `dataset.lrFs === '1'` (filter-passing rows)
  - Extracts rating from `data-sort-key` on the Rate column cell
  - Counts non-empty Comment column cells
  - Computes sum/avg/count and updates the `.lr-summary` div text
- Call `lr_update_summary(table)` at the end of `dochangefilter()` and
  `lr_paginate()`

### Test

- `perl -c code/listrecords.pm`
- Load any existing listrecords page (e.g. `o=Comment`) — no regression
- Not directly testable until phase 2, but check JS syntax

---

## Phase 2: Brew editing page (`brews.pm`)

### Remove

- Entire `sub listbrewcomments` (lines 31-150)

### Replace call at line 573

```perl
print "<div onclick='toggleElement(this.nextElementSibling);'>";
print "Comments and ratings for <b>$p->{Name}</b><br/>\n";
print "</div>\n";
print "<div style='overflow-x: auto;'>\n";
print listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
    where => q{EXISTS (SELECT 1 FROM comments c2
               LEFT JOIN glasses g2 ON g2.Id = c2.Glass
               WHERE c2.Id = "Id_A_link:Comment"
                 AND (c2.Brew = ? OR g2.Brew = ?))
               AND xUsername = ?},
    params => [$p->{Id}, $p->{Id}, $c->{username}],
    title => "",
    show_rating_summary => 1,
    no_new_link => 1,
});
print "</div>\n";
```

Toggle wrapper matches current behavior (expanded by default). The `title` is
empty because the toggle header serves as the label. Subquery captures both
direct brew comments (`COMMENTS.Brew`) and glass-routed ones (`GLASSES.Brew`).
Price and volume columns are intentionally dropped.

Keep the "(new comment)" link at line 571 and `<hr/>` at line 572 as-is.

### Test

- `perl -c code/brews.pm`
- Open `o=Brew&e=<id>` for a brew with comments
  - Comments table renders via listrecords with filter/sort/pagination
  - Toggle expand/collapse works
  - Rating summary (count + average) is shown below the table
  - "(new comment)" link still works
  - Same data as before (both direct and glass-routed comments)
  - CommentType auto-filter is NOT set (all types shown by default, matching
    current behavior)
- Verify with a brew that has only glass-routed comments (no direct brew
  comments on the comment record)

---

## Phase 3: Location editing page (`locations.pm`)

### Remove

- `sub listlocationcomments` (lines 160-194)
- `sub _location_comment_section` (lines 46-151)

### Replace at line 470

```perl
print listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
    where => q{"LocId_A_link:Location" = ? AND xUsername = ?},
    params => [$p->{Id}, $c->{username}],
    title => "Comments about $p->{Name}",
    initial_filter => { CommentType => "location" },
    show_rating_summary => 1,
    no_new_link => 1,
});
```

The `initial_filter` starts showing only CommentType=location comments. If no
results, `autoFilterTable()` in listrecords.js clears the filter automatically,
which falls back to showing all comment types for this location (including
night, brew, etc.). This replaces the old sections 1-3.

### Producer comments (line 473)

Replace the `_location_comment_section` call with a second listrecords call:

```perl
my $prod_comments = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
    where => q{EXISTS (SELECT 1 FROM comments c2
               LEFT JOIN glasses g2 ON g2.Id = c2.Glass
               WHERE c2.Id = "Id_A_link:Comment"
                 AND (c2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)
                   OR g2.Brew IN (SELECT Id FROM brews WHERE ProducerLocation = ?)))
               AND xUsername = ?},
    params => [$p->{Id}, $p->{Id}, $c->{username}],
    title => "Comments on brews by $p->{Name}",
    show_rating_summary => 1,
    no_new_link => 1,
});
if ($prod_comments) {
    print "<hr/>\n";
    print $prod_comments;
}
```

This captures comments on brews produced by this location (whether the comment
is on the brew directly, or on a glass that poured the brew).

Keep `producerbrews()` at line 481 as-is (already uses listrecords on
`producer_brews_list`).

Keep "(new comment)" link at line 468 as-is.

### Test

- `perl -c code/locations.pm`
- Open `o=Location&e=<id>` for a location with various comment types
  - Starts with CommentType=location filter applied
  - If no location-type comments, filter auto-clears and shows all
  - Rating summary updates when changing filters
  - Clear filter shows all comments at this location (location/night/brew)
  - If the location is a producer, the "Comments on brews by..." section shows
    comments on the brews it produces
  - "(new comment)" link still works
- Compare with production data — same set of comments visible (just differently
  presented)

---

## Phase 4: Comment editing page (`comments.pm`)

### Remove

- `sub sibling_comments_html` (lines 439-573)
- `sub _sibling_section` (lines 418-433)

### Replace at line 406

Inside `commentform()`, determine the sibling context:

```perl
my $context_brew  = $com->{Brew};
my $context_loc   = $com->{Location};
my $context_person = undef;
if ($glassid && !$context_brew && !$context_loc) {
    ($context_brew, $context_loc) = db::queryarray($c,
        "SELECT Brew, Location FROM glasses WHERE Id = ?", $glassid);
}
my $sibling_html = "";
```

Then select ONE context (first match wins):

**Brew context** — if `$context_brew`:
```perl
$sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
    where => q{EXISTS (SELECT 1 FROM comments c2
               LEFT JOIN glasses g2 ON g2.Id = c2.Glass
               WHERE c2.Id = "Id_A_link:Comment"
                 AND (c2.Brew = ? OR g2.Brew = ?))
               AND xUsername = ?},
    params => [$context_brew, $context_brew, $c->{username}],
    title => "Other comments on this brew",
    initial_filter => { CommentType => "brew" },
    show_rating_summary => 1,
    no_new_link => 1,
    maxrecords => 0,
});
```

**Location context** — elsif `$context_loc`:
```perl
$sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
    where => q{"LocId_A_link:Location" = ? AND xUsername = ?},
    params => [$context_loc, $c->{username}],
    title => "Other comments at this location",
    initial_filter => { CommentType => "location" },
    show_rating_summary => 1,
    no_new_link => 1,
    maxrecords => 0,
});
```

**Person context** — elsif `$com->{Id}` and `$com->{CommentType} eq 'person'`:
```perl
my $pid = db::queryarray($c,
    "SELECT Person FROM comment_persons WHERE Comment = ?", $com->{Id});
if ($pid) {
    $sibling_html = listrecords::listrecords($c, "COMMENTS_LIST", "Last-", {
        where => q{EXISTS (SELECT 1 FROM comment_persons cp
                   WHERE cp.Comment = "Id_A_link:Comment" AND cp.Person = ?)
                   AND xUsername = ?},
        params => [$pid, $c->{username}],
        title => "Other comments mentioning this person",
        initial_filter => { CommentType => "person" },
        show_rating_summary => 1,
        no_new_link => 1,
        maxrecords => 0,
    });
}
```

Append to `$s` with a separator:
```perl
if ($sibling_html) {
    $s .= "<hr style='border-color:#444; margin:0.5em 0'>\n";
    $s .= $sibling_html;
}
```

`maxrecords => 0` shows all siblings without pagination (matching current
behavior where all sibling comments are shown inline). Person context uses the
first person from `comment_persons` only (simpler than one section per person).

### Test

- `perl -c code/comments.pm`
- Open `o=Comment&e=<id>` for each comment type:
  - **brew comment**: shows other comments on the same brew, with rating
    summary, auto-filtered to CommentType=brew
  - **location comment**: shows other comments at the same location,
    auto-filtered to CommentType=location
  - **person comment**: shows other comments mentioning the same person,
    auto-filtered to CommentType=person
  - **glass comment** (no direct brew/location): derives brew from the glass,
    shows other brew comments
  - **night/meal comment**: falls back to location from glass
- Verify the current comment is excluded (the SQL doesn't exclude it, but the
  initial_filter + maxrecords=0 means it will be in the list — may need to add
  `AND c2.Id != ?` to the brew/location WHERE clauses, or rely on the user just
  seeing it in the list). Actually, the current `sibling_comments_html` has
  explicit exclusion logic (`next if $com->{Id} && $cr->{Id} == $com->{Id}`).
  The WHERE clause should include `AND "Id_A_link:Comment" != ?` to exclude the
  current comment. Add `$com->{Id}` as an extra param.
- "(Add another comment)" link still works

---

## Phase 5: Final cleanup

- `perl -c` on all modified files
- Touch `code/VERSION.pm`
- Test all three editing pages manually under Apache
- Run `tools/dbdump.sh` if any schema changes were made (none expected for this
  change — COMMENTS_LIST view is unchanged)

---

## Files changed

| File | Change |
|------|--------|
| `code/listrecords.pm` | Add `show_rating_summary` option + rendering |
| `static/listrecords.js` | Add `lr_update_summary()` + hooks |
| `code/brews.pm` | Remove `listbrewcomments()`, replace with listrecords call |
| `code/locations.pm` | Remove `listlocationcomments()` + `_location_comment_section()`, two listrecords calls |
| `code/comments.pm` | Remove `sibling_comments_html()` + `_sibling_section()`, context-aware listrecords call |

## Not in scope

- Glass editing page (`glasses.pm` / main list) — uses `comments::listcomments()`
  which is fundamentally different
- `mainlist.pm::commentlines` — shared with glass page, not changed
- The `COMMENTS_LIST` view definition — no changes needed
