# Plan: Persons list sort by last (issue #583)

## Decisions

- No database schema changes (no new tables or columns).
- The `Last` column in the `persons_list` view must fall back to `comments.Ts`
  when a comment is not tied to a glass (`comments.Glass` is NULL or the glass
  was deleted). This covers standalone person-comments (CommentType = 'person').
- The `GROUP BY persons.Id` with `max(COALESCE(...))` already handles the
  multiple-persons-per-comment case correctly: the `comment_persons` join
  produces one row per (person, comment) pair, and the per-person aggregation
  remains correct regardless of how many persons share a comment.
- **Current state confirmed broken**: the view uses `max(glasses.Timestamp)`
  with no fallback, so `Last` is NULL for any person whose comments have no
  glass association.
- `tools/dbdump.sh` must be run after the migration is applied.

## Database changes

No table or column changes. The only change is a DROP/CREATE of the
`persons_list` view, done via a new migration.

| # | Change | Migration |
|---|--------|-----------|
| 1 | Rebuild `persons_list` to use `COALESCE(glasses.Timestamp, comments.Ts)` | mig_020 |

## Phases

### Phase 1 — Add migration `mig_020` in `code/migrate.pm`

- After `mig_019_add_link_fields`, add:

```perl
sub mig_020_fix_persons_last_seen {
  my $c = shift;

  db::execute($c, "DROP VIEW IF EXISTS persons_list");
  db::execute($c, q{
    CREATE VIEW persons_list AS
    SELECT
      persons.Id,
      persons.Name,
      'trmob' AS trmob,
      count(DISTINCT comments.Id) - 1 AS Com,
      strftime('%Y-%m-%d %w ', max(COALESCE(glasses.Timestamp, comments.Ts)), '-06:00') ||
        strftime('%H:%M', max(COALESCE(glasses.Timestamp, comments.Ts))) AS Last,
      locations.Name AS Location,
      'tr' AS tr,
      'Clr' AS Clr,
      persons.description,
      (SELECT Filename FROM photos WHERE Person = persons.Id ORDER BY Ts DESC LIMIT 1) AS Photo,
      persons.Tags
    FROM persons
    LEFT JOIN comment_persons cp ON cp.Person = persons.Id
    LEFT JOIN comments ON comments.Id = cp.Comment
    LEFT JOIN glasses ON glasses.Id = comments.Glass
    LEFT JOIN locations ON locations.Id = glasses.Location
    GROUP BY persons.Id
  });

} # mig_020_fix_persons_last_seen
```

- Add `mig_020_fix_persons_last_seen($c)` to the `migrate($c)` dispatch block.
- Bump `$CODE_DB_VERSION` from 19 to 20.

**Files**: `code/migrate.pm`

### Phase 2 — Update the view copy in `doc/db.schema`

- Run `tools/dbdump.sh` — do not edit `doc/db.schema` by hand.

### Phase 3 — Manual verification

- Create or find a person who is mentioned only in a standalone comment (no
  glass). Confirm that `Last` now shows a date rather than being blank.
- Confirm that the persons list sorts correctly by `Last-` (most recently seen
  first).
- Confirm persons with no comments at all still show a blank `Last` (expected).

## Open questions

None — requirements are clear and implementation is straightforward.
