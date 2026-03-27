# Plan: commentline letter-based flag parameter (issue 629)

## TL;DR
Extend `commentline()` in `comments.pm` to accept a string of letter flags controlling which extra info
is shown, replacing the binary `1`/`0` `$showtimestamp` parameter. Keep `1` for backward compatibility.
Add `brewname` and `time` columns to the sibling section SQL queries to support the new `b` and `t` flags.
Use the comment editing form's sibling sections as the test case (change `1` → `"dl"` there).

## Flags
- `d` = date (YYYY-MM-DD, first 10 chars of `$cr->{effdate}`)
- `t` = time (HH:MM from `$cr->{time}`, new SQL column)
- `l` = location (link using `$cr->{loc}` / `$cr->{locname}`)
- `b` = brew name (from `$cr->{brewname}`, new SQL column)
- `p` = persons — reserved for future; persons always show anyway (no-op now)
- `y` = show `[CommentType]` badge (currently always shown; with letter flags, only shown when `y` present)
- `1` (legacy) = current behavior: date + location, type badge shown (equivalent to "dly")

## Steps

### Phase 1 — SQL changes in `sibling_comments_html` (comments.pm lines ~462–580)
For each of the 4 section queries (glass, brew, person, location):
- Add `LEFT JOIN brews br ON br.Id = c.Brew` to the FROM/JOIN clause
- Add `br.Name AS brewname` to the SELECT list
- Add `strftime('%H:%M', COALESCE(g.Timestamp, c.Ts)) AS time` to the SELECT list

### Phase 2 — `_sibling_section` signature (comments.pm ~line 437)
- Add `$flags` parameter between `$label` and `$sql`:
  `my ($c, $com, $label, $flags, $sql, @params) = @_;`
- Change `commentline($c, $cr, 1)` → `commentline($c, $cr, $flags)`
- Update all 4 call sites in `sibling_comments_html` to pass `"dl"` as 4th arg (test case: show date+location, no type badge)

### Phase 3 — `commentline` refactor (comments.pm lines ~43–71)
- Rename parameter `$showtimestamp` → `$flags`
- Determine show-flags:
  - if `$flags eq '1'` (or is truthy non-string): show date+location+type (current backward-compat behavior)
  - else: parse letter string
- Move type badge logic:
  - Currently: show `[ctype]` unless ctype is 'brew'
  - New: show only if `$flags eq '1'` OR flags string contains `y`
- Conditional display per flag:
  - `d`: show date part of `$cr->{effdate}` (substr 0..9)
  - `t`: show `$cr->{time}` (HH:MM) if present
  - `l`: show location link `$cr->{loc}` / `$cr->{locname}`
  - `b`: show brew link/name `$cr->{brewname}` (link to `?o=Brew&e=$cr->{Brew}` if `$cr->{Brew}` exists)
  - `p`: no-op currently
  - After d/t/l/b block: add `<br/>` before comment text if any of d/t/l/b was shown AND there is comment text
- Keep fallback `1` path identical to current behavior

## Relevant Files
- `code/comments.pm` — `commentline()` (~L43), `_sibling_section()` (~L437), `sibling_comments_html()` (~L455)
- `code/persons.pm` — call site ~L72: keep as `1` (no change)
- `code/locations.pm` — call site ~L121: no flags (no change)
- `code/mainlist.pm` — call site ~L279: no flags (no change)

## Verification
1. Check syntax: `perl -c code/comments.pm`
2. Load comment editing form for an existing comment — sibling sections show date+location, no type badge
3. Visit persons page — comment lines still show date+location+type badge (unchanged, uses `1`)
4. Test `b` flag manually by temporarily using `"dlb"` in one sibling section — verify brew name appears
5. Test `t` flag manually by temporarily using `"dlt"` — verify time appears

## Decisions
- `p` flag is reserved (no-op); persons always display
- New SQL fields: `brewname` (LEFT JOIN brews), `time` (strftime HH:MM, consistent with persons.pm alias)
- `y` flag controls type badge display; without it (in letter-flag mode), type badge hidden
- `1` preserves exact current behavior (date + location + type badge)
- `b` flag shows brew as a link to `?o=Brew&e=ID` when `Brew` ID is available
- Test case: change `_sibling_section` calls from `1` to `"dl"` — date+location, no type badge
