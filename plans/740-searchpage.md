# Issue #740 — Full-text search page over comments and glass notes

## Summary
Add a dedicated search page (`o=Search`) that does a full-text-style search over
the current user's comments and per-glass notes. No schema changes: both live in
existing tables (`comments.Comment`, `glasses.Note`).

## Scope
- Search text fields only: `comments.Comment` and `glasses.Note`.
- Search only the current user's own data, with the same ownership rule as the
  comments list: `COALESCE(glasses.Username, comments.Username) = ?`.
  Public comments stay visible; other users' comments do not leak.
- Query words are AND-ed; each word must match `Comment` or `Note`.
- No migration, no `doc/db.schema` change, no new JS/CSS.

## New module `code/search.pm`

`sub searchpage($c)`:
1. Render a small GET form: `<input name='q'>` sharing the existing `q` grep
   param convention (`$c->{qry}` is already set up by index.fcgi).
2. If `q` is empty, just show the form and stop.
3. Split `q` into words (whitespace). For each word build a `LIKE '%word%'
   ESCAPE '\'` clause; escape `%`, `_`, and `\` via a small local `like_escape`
   helper. AND the per-word clauses together; OR across the Comment/Note columns.
4. Run a UNION query so that glasses which have a matching note but no (matching)
   comment are found too. Shape:
   ```sql
   SELECT ts, src, ... FROM (
     SELECT g.Timestamp AS ts, 'comment' AS src, c.Rating AS rating,
            c.Id AS cid, g.Id AS gid, b.Id AS bid, b.Name AS brewname,
            l.Id AS lid, l.Name AS locname, c.Comment AS txt,
            g.Username, c.Username AS cUsername
     FROM comments c JOIN glasses g ON g.Id = c.Glass
     UNION ALL
     SELECT g.Timestamp AS ts, 'note', NULL, NULL, g.Id, b.Id, b.Name,
            l.Id, l.Name, g.Note AS txt, g.Username, NULL
     FROM glasses g JOIN brews b ON b.Id = g.Brew
     LEFT JOIN locations l ON l.Id = g.Location
     WHERE g.Note IS NOT NULL
   )
   WHERE COALESCE(Username, cUsername) = ?
     AND (txt LIKE ? ESCAPE '\' OR ... )   -- one pair per query word
   ORDER BY ts DESC LIMIT 500
   ```
   (Exact column names/joins to be finalized during implementation; the key
   points are the UNION of comment-branch and note-branch, and OR-across-column
   word matching.)
5. Render a lightweight HTML table: date/time, either a comment-id link to
   `o=Comment&e=$cid` or a glass-id link to `o=Full&e=$gid&date=$date&ndays=1`,
   rating badge for comment hits, brew + location links, and the matched text
   with the query words `<b>`-highlighted via `util::htmlesc`. No `listrecords`
   dependency.

## Changes to existing files

- `code/index.fcgi`
  - `require "./code/search.pm";`
  - GET dispatch: `elsif ( $c->{op} =~ /Search/i ) { search::searchpage($c); }`
- `code/util.pm`
  - `showmenu()`: add `{ label => "Search", url => "o=Search" }` under "Main ...".

## Notes and limitations
- SQLite `LIKE` folds ASCII case only; non-ASCII (å, ø, æ ...) is matched
  case-sensitively. Acceptable for now.
- Searching the word '8' does not match rating 8; ratings are intentionally out
  of scope.

## Verification
- `perl -c code/search.pm code/util.pm`.
- Manually: `?o=Search&q=Saison` → comment and note hits with working links;
  `?o=Search` with no `q` shows an empty form.
- Touch `code/VERSION.pm` (in a separate step) to reload the FCGI script.