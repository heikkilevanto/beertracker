# 689: Link person names in comments to person edit page

## Problem
When a comment has one or more people attached, names are shown as plain bold text
(e.g. `<b>John, Jane:</b>`). They should link to the person edit page (`?o=Person&e=<ID>`).

## Approach
Use a single SQL field `PeopleData` combining name and ID with a pipe separator:
`group_concat(cp_persons.Name || '|' || cp.Person, ', ') as PeopleData`
This produces `"John|123, Jane|456"` — atomic, no sync issues.

In `commentline()`, when `PeopleData` is present, split and render individual links.
Fall back to plain `PeopleNames`/`PersName` when `PeopleData` is absent (backward compat).

## Phase 1: Main list only

### Changes

**`mainlist.pm:276-284`** — Add `PeopleData` to the SQL:
```perl
group_concat(cp_persons.Name || '|' || cp.Person, ', ') as PeopleData
```

**`comments.pm:55-56`** — Render linked names when `PeopleData` present:
```perl
my $people_data = $cr->{PeopleData} || "";
if ($people_data) {
    my @items = split(/, /, $people_data);
    for (my $i = 0; $i < @items; $i++) {
        my ($name, $pid) = split(/\|/, $items[$i]);
        if ($pid) {
            $s .= "<a href='$c->{url}?o=Person&e=$pid'>" .
                  "<span style='font-weight:bold;'>" . util::htmlesc($name) . "</span></a>";
        } else {
            $s .= "<span style='font-weight:bold;'>" . util::htmlesc($name) . "</span>";
        }
        $s .= ", " if $i < $#items;
    }
    $s .= ":\n";
} else {
    my $people = $cr->{PeopleNames} || $cr->{PersName} || "";
    $s .= "<b>$people:</b>\n" if $people;
}
```

## Database views
The `comments_list` view in `doc/db.schema:455` has `group_concat(persons.Name, ', ') as PersonName`. This is used by `listrecords.pm:241-242` for the `o=Comments` listing page. It's a view (no parameters, can't filter by user), so it would need a separate approach if linked names are wanted there. Not needed for Phase 1.

## Later phases (not in scope of this plan)

All of these use `commentline()` or their own rendering, and would just need a SQL
`PeopleData` field added:

- `locations.pm:65` — `listlocationcomments()` → `commentline()`
- `persons.pm:36` — `showpersondetails()` → `commentline()`
- `comments.pm:448,479,508,536` — `sibling_comments_html()` → `commentline()`
  (note: sibling section 3 aliases `comment_persons` as `cp2`)
- `comments.pm:166` — `listcomments()` → `commentline()`
- `brews.pm:45-46,118-120` — `listbrewcomments()` has separate rendering,
  already attempts links but multi-person case (`$pid` is `"123,456"`) is broken
- `photos.pm:414,450-452` — thumbnail comment display, separate rendering

## Cleanup after all phases
Once every SQL query that feeds `commentline()` has been updated to provide `PeopleData`,
the fallback branch in `commentline()` (the `else` using `PeopleNames`/`PersName`) can be
removed, and the now-unused `PeopleNames` columns can be dropped from those SQL queries.

## Verification
- `perl -c code/comments.pm code/mainlist.pm`
- Visual check of main list: names should link to `?o=Person&e=<id>`
- Other views (locations, persons, brews, etc.) should show names as plain text (unchanged)
