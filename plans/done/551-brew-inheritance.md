# Plan: Brew inheritance (issue #551)

## Decisions

- Add a `Parent INTEGER` column to `brews` (nullable; null = no parent) with a FK constraint
  referencing `brews(Id)`.
- Add an index on `brews(Parent)` to support the children query in the relationships section.
- Parent is set automatically when saving a new brew created via the "Duplicate" button.
- Parent is user-editable in the brew edit form (numeric ID input; label is a link when set).
- The relationships panel (parent + children + field-diff) is shown below the edit form,
  similar to existing sections such as comments, taps, and prices.
- `dedupbrews()` must update child `Parent` pointers to the surviving brew when the parent
  is deleted, to keep data clean.
- `tools/dbdump.sh` must be run and `doc/db.schema` committed after the migration.

## Database changes

| Change | Migration |
|--------|-----------|
| `ALTER TABLE brews ADD COLUMN Parent INTEGER REFERENCES brews(Id)` | `mig_022_551_brew_parent` |
| `CREATE INDEX idx_brews_parent ON brews(Parent)` | same migration |

`$CODE_DB_VERSION` bumped to 22.

## Phases

### Phase 1 — DB migration (`code/migrate.pm`)

Add migration sub and register it:

```perl
sub mig_022_551_brew_parent {
  my $c = shift;
  db::execute($c, "ALTER TABLE brews ADD COLUMN Parent INTEGER REFERENCES brews(Id)");
  db::execute($c, "CREATE INDEX idx_brews_parent ON brews(Parent)");
} # mig_022_551_brew_parent
```

Push `[22, '551 add Parent to brews', \&mig_022_551_brew_parent]` to `@MIGRATIONS`.
Set `$CODE_DB_VERSION = 22`.

Run `tools/dbdump.sh` and commit `doc/db.schema`.

---

### Phase 2 — inputs.pm: handle `Parent` field in BREWS input form

`inputs::inputform` calls `db::tablefields`, which marks `INTEGER` columns with a `-` prefix.
`Parent` would be an unmarked special field and currently hits `util::error("...not handled yet")`.

In `inputs.pm`, inside the `if ($special)` branch (after the `elsif ($f =~ /IsGeneric/i)` block),
add a new `elsif ($f =~ /^Parent$/i)` block that:
- Shows a link to the parent brew when `$rec->{Parent}` is set:
  `<a class='field-link-preview' href='?o=Brew&e=$rec->{Parent}'><span>Parent [$rec->{Parent}]</span></a>`
- Renders a plain text `<input name='Parent' value='...' $disabled/>` (numeric ID input)
  in the adjacent `<td>`.

This mirrors how `ProducerLocation` is handled in the same file.

---

### Phase 3 — editbrew() form: pass Parent when duplicating (`code/brews.pm`)

In `editbrew()`, when `$duplicate_id` is set, after loading `$p` from the source brew,
add a hidden input to the rendered form so `db::insertrecord` picks it up automatically
via `util::param($c, "Parent")`:

```perl
print "<input type='hidden' name='Parent' value='$duplicate_id' />\n";
```

Place this just after the existing hidden `id` and `e` inputs, before `inputs::inputform`.

No changes to `postbrew()` or `insertrecord()` are needed — `insertrecord` already reads
all table fields from CGI params, so `Parent` will be picked up naturally.

---

### Phase 4 — editbrew() display: brew relationships section (`code/brews.pm`)

Add a new helper sub `listbrewrelations($c, $brew)` in `code/brews.pm`, called from
`editbrew()` after the existing `brewdeduplist($c, $p)` call.

The sub should:

1. **Show parent** — if `$brew->{Parent}` is set, fetch the parent record and display:
   ```
   Inherits from: <a href='?o=Brew&e=$parent->{Id}'><span>[$parent->{Id}] $parent->{Name}</span></a>
   ```

2. **Show children** — query for brews where `Parent = $brew->{Id}`:
   ```sql
   SELECT Id, Name FROM BREWS WHERE Parent = ? ORDER BY Name
   ```
   If any exist, list them:
   ```
   Variants of this brew: [id1] name1, [id2] name2, ...
   ```
   Each entry links to `?o=Brew&e=$id`.

3. Wrap the whole section in the standard `<hr/>` separator.

If neither parent nor children exist, output nothing.

---

### Phase 5 — editbrew() display: field-diff against parent (`code/brews.pm`)

Inside `listbrewrelations()`, after showing the parent link, add a field-diff block when
`$brew->{Parent}` is set.

Fetch all fields of the parent brew via `db::getrecord($c, "BREWS", $brew->{Parent})`.
Compare every column except `Id` and `Parent`. For each field where the child value differs
from the parent value (including one being undef/empty and the other not), print a row:

```
Field: parent-value → child-value
```

Display as a small table. Empty/undef values should be shown as `—` (em-dash) for clarity.

---

### Phase 6 — dedupbrews(): cascade Parent pointers (`code/brews.pm`)

Inside `dedupbrews()`, after the existing `UPDATE PHOTOS` step and before the `DELETE`,
add:

```perl
$sql = "UPDATE BREWS SET Parent = ? WHERE Parent = ?";
$rows = db::execute($c, $sql, $id, $dup);
util::error("Deduplicate brews: Failed to update child Parent pointers") unless defined $rows;
print { $c->{log} } "Updated $rows child Parent pointers from $dup to $id\n";
```

This ensures brews that inherited from the removed duplicate now point to the surviving brew.

---

## Open questions

_(None — all questions resolved.)_