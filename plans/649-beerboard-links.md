# Plan: Links in Beer Board (issue #649)

## TL;DR
In the expanded view of each beer board entry, show an external link immediately after
the "On since" date. Pick the first available of: the brew's `DetailsLink` field (labelled
"www"), the producer location's `SearchLink` (labelled with the shortened producer name),
or a DuckDuckGo fallback (labelled "ddg"). All links open in a new tab. Additionally, fix
the full brewery name in the expanded header — it is currently plain text and should link
to the location edit page.

## Decisions
- Only one link is shown; priority order is: `b.DetailsLink` → `pl.SearchLink` → DDG.
- DDG URL format: `https://duckduckgo.com/?q=<uri-encoded "maker beer">`.
- Link text for `SearchLink` fallback is the already-computed shortened producer name
  (`$shortmak`, the plain-text version before HTML linkification).
- `SearchLink` is a full standalone URL (no suffix needed).
- All three external link labels are wrapped in round parentheses: `(www)`, `($shortmak)`, `(ddg)`.
- The full maker name in the expanded header row links to `?o=Location&e=<maker_id>`,
  same pattern as `dispmak` (which already links there).
- No database schema changes needed; `b.DetailsLink` and `pl.SearchLink` already exist.

## Database changes
None required. The fields `DetailsLink` (on `brews`) and `SearchLink` (on `locations`)
already exist in the schema.

## Phases

### Phase 1 — Fetch `DetailsLink` and `SearchLink` in the SQL query
File: `code/beerboard.pm`, function `load_beerlist_from_db`.

- Add `b.DetailsLink AS details_link` to the SELECT clause.
- Add `pl.SearchLink AS maker_search_link` to the SELECT clause
  (the `locations pl` join already exists).
- Add `details_link` and `maker_search_link` to the hash pushed onto `$beerlist`.

### Phase 2 — Compute the external link in `prepare_beer_entry_data`
File: `code/beerboard.pm`, function `prepare_beer_entry_data`.

- Capture the shortened producer name as `$shortmak` (plain text, before it is wrapped
  in HTML) so it can serve as link text.
- After all maker/beer transformations, compute `$extlink` and `$extlink_label`:
  ```
  if ($e->{details_link}) {
      $extlink = $e->{details_link};
      $extlink_label = "(www)";
  } elsif ($e->{maker_search_link}) {
      $extlink = $e->{maker_search_link};
      $extlink_label = "($shortmak)" || "(search)";
  } elsif ($mak || $beer_plain) {
      my $q = uri_escape_utf8("$mak $beer_plain");  # $beer_plain before apostrophe strip
      $extlink = "https://duckduckgo.com/?q=$q";
      $extlink_label = "(ddg)";
  }
  ```
- Add `extlink` and `extlink_label` to the returned hash.

### Phase 3 — Render the link after "On since"
File: `code/beerboard.pm`, function `render_beer_row`.

In the expanded row that prints the "On since" line (currently):
```perl
if ($processed_data->{first_seen_date_formatted}) {
    print " <span style='font-size: x-small;'>On since $processed_data->{first_seen_date_formatted}.</span>";
}
```
Append a link immediately after the period, still inside the `<span>`:
```perl
if ($processed_data->{extlink}) {
    print " <a href='$processed_data->{extlink}' target='_blank'>"
        . "<span>$processed_data->{extlink_label}</span></a>";
}
```
(Or restructure the print so link sits naturally after the formatted date.)

### Phase 4 — Link the full brewery name in the expanded header
File: `code/beerboard.pm`, function `prepare_beer_entry_data`.

Since `$dispbeer` and `$dispmak` are already built here, compute `$dispmak_full` at the
same time — the full (unshortened) maker name wrapped in a location link:
```perl
my $dispmak_full = ($e->{maker_id})
    ? "<a href='$c->{url}?o=Location&e=$e->{maker_id}'><span>$mak</span></a>"
    : $mak;
```
Add `dispmak_full` to the returned hash, then in `render_beer_row` replace:
```perl
print "$processed_data->{mak}: $processed_data->{dispbeer} ";
```
with:
```perl
print "$processed_data->{dispmak_full}: $processed_data->{dispbeer} ";
```

## Open questions
None — `SearchLink` is confirmed to be a full URL; labels are `(www)`, `($shortmak)`, `(ddg)`.
