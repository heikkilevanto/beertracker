# v4.0 Release Notes

## New Features

- **Tags for persons and locations** — full tag editor with search, bulk-select, and exact-match click (#587, #623, #679)
- **Country/region support** — country codes expanded to full names in brews and locations, dropdown selectors, link management, propagation on POST (#541, #643–647)
- **Brew inheritance** — track related brews (#551)
- **Untappd scrapers** — Warpigs, Væskebalancen; improved scrapeall with per-site configuration (#639, #640)
- **Short names persisted in DB** — no more auto-generated shortening, explicit short names stored and editable (#637)
- **Annual graph** — new yearly consumption graph (#176)
- **More links throughout** — links in DB for brews/locations, DuckDuckGo search replacing Google, improved display with scraper links (#648–655, #662)
- **Negative prices for bottles and boxes** (#657)
- **Fresh geolocation** — recalculate nearest location on tab focus if moved more than 50 m (#677)
- **Log tail improvements** — nlines parameter, auto-scroll to end (#669)
- **Adjustment lines show percentage** (#672)
- **Branch/dirty indicator in top header** (#636)
- **Empty glass type** — ghost entries for non-brew glasses in lists
- **Photo UX improvements** — glass type displayed next to photo, margin fixes, more comment/photo links
- **Debug page** — extended with file listing and line counts for JS/CSS
- **Cronjob support** — accept 127.0.0.1 for automated scripts
- **New brewtype allowed** — free-text brew type input (#675)

## Bug Fixes

- Yearstat broken (#673), topstat price/zero bloodalc fixes
- Duplicate tap numbers handled (#680)
- Forms hidden after CSS cleanup — restored (#666)
- Undefined colors, deduplicated log messages (#667, #670)
- Copy glass with negative price now handles correctly (#674)
- Scraper links lost from DB — restored (#662)
- Beer board links restored (#649), search link fixed (#653)
- Select-to-dropdown hack removed (#660)
- Commentline letter flags cleaned up (#629)
- Persons added to comments on night view (#655)
- Photo margins, scanner issues
- Various minor fixes across scrapeall, brewsubtype input, "On since" display, producer links in brew edit

## Internal Changes

- **Major JavaScript cleanup** — extracted inline JS from Perl modules into standalone files (comments.js, glasses.js, debug.js, listrecords.js) (#413, #665)
- **styles.pm refactored** (#671), CSS cleanup (#666)
- **Housekeeping** — dead code removed from superuser, login, about, graph, taps, cache, geo, photo modules; old migrations removed; "Feedback" type glasses/comments removed; empty glass list cleaned
- **Beer board optimization** — skip unchanged taps, reduce duplicate DB lookups (#632, #633)
- **Logging reduction** — less noise in taps.pm, cleaner $util::log
- **Plan files** — cleaned up and archived