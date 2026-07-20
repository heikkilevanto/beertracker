# List Page Principles

List pages use a shared rendering engine (`listrecords.pm`) driven by SQL views. Each entity gets a dedicated view named `${ENTITY}_LIST` that encapsulates all joins, aggregations, and computed columns. The Perl code is minimal — just a heading, optional "New" link, and a call to `listrecords::listrecords()`.

## Architecture

1. **SQL View as data layer** — Each list has a `CREATE VIEW ${ENTITY}_LIST AS SELECT ...` in the database schema. The view does all the heavy lifting: joins, grouping, subqueries for thumbnails, date formatting with the `-06:00` offset, rating aggregations. The Perl code never builds complex SQL.

2. **Shared renderer** — `listrecords::listrecords($c, $viewname, $sort, $where, \@params, $extraparams)` handles everything: column metadata, sorting, filtering, pagination, HTML output, and caching.

3. **Per-module wrapper** — `entity.pm` provides a thin `list${entity}s($c)` sub that prints a heading, checks `$c->{edit}` (delegates to edit form if set), and calls `listrecords()`.

4. **Dispatch** — `index.fcgi` routes based on `o=<Entity>` to the list sub. POST goes to a separate `post${entity}()` sub.

## View Column Naming

Column names encode display semantics via suffixes parsed by `listrecords.pm`:

| Suffix | Purpose |
|--------|---------|
| `_link:Entity` | Turns value into `<a href='?o=Entity&e=value'><span>value</span></a>` |
| `_cont` | Merge this column into the previous cell (continued content) |
| `_contline` | All following columns inherit `_cont` until a `TR` |
| `_A` | Auto-width column |
| `_R<N>` | Rowspan (photo thumbnails: `_R8`, `_R2`, `_R3`) |
| `_C<N>` | Colspan |
| `_filter` | Click puts the whole field value into the filter (default is per-word token filtering) |
| `_nofilter` | No filter input in header |
| `_noheader` | No header cell |
| `_as:DisplayName` | Show column under a different name |
| `<N>px` | Fixed pixel width |
| `x` prefix | Hidden column (for WHERE filtering) |
| `'' as TR<N>` | Row break (pseudo-column) |
| `Chk`, `Clr`, `Sim` | Special pseudo-fields |

## Link Conventions

- Entity links use `$c->{url}?o=Entity&e=$id`
- Link text goes inside `<span>`: `<a href='...'><span>text</span></a>`
- Primary name links use `<b>`: `<a href='...'><span><b>$name</b></span></a>`
- External/utility links use `util::extlink()` or entity-specific helpers like `util::brewlinks()`, `util::locationlinks()`
- Links in list tables should be minimal — prefer word-click filtering as the default navigation mechanism
- For name columns (and similar identifiers), precede the display value with a link to the entity's Id column (e.g., `Id_link:Entity` followed by `Name_A` showing the name alongside the linked Id)

## Photo Thumbnails

Most lists include a `Photo_R<N>` column (not all — e.g. producers do not). Typically placed on the rightmost side. Uses a subquery: `(SELECT Filename FROM photos WHERE ... ORDER BY Ts DESC LIMIT 1)`. Rowspan spans the number of visual data rows (including `TR<N>` breaks).

## Sorting

- Default sort is `"Last-"` (most recent first by timestamp descending)
- Override via `s` URL parameter stored in `$c->{sort}`
- Sort key matches a column name; `-` suffix = DESC

## Filtering

- **Client-side**: Each column gets an `<input>` in `<thead>` — JavaScript filters rows as you type
- **Per-word token filtering is the default**: Cell values are split into clickable `<span>` tokens, each setting that column's filter to the clicked word
- `_filter` suffix overrides this: clicking puts the **whole field value** into the filter (not per-word)
- **Server-side**: Only used for access control (e.g., `PHOTOS_LIST` restricts to user-visible photos via WHERE clause)

## Caching

- Rendered HTML is cached via `cache::get`/`cache::set`
- Cache key includes username, view name, sort, WHERE, params, maxrecords, mobile flag
- Cache cleared after any POST request, or when the fcgi script is restarted

## Pagination

- `maxrecords` defaults to 20
- Rows beyond the limit are hidden (not removed from DOM) — a "More..." link reveals them
- Each record is wrapped in its own `<tbody>` for grouping multiline records, show/hide, and sorting

## "New" Entries

Omitted if creation doesn't make sense for the entity (photos are always attachments). Otherwise: `<a href="$c->{url}?o=$c->{op}&e=new"><span>(New)</span></a>` next to the heading.
