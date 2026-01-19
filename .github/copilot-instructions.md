# BeerTracker AI Coding Guidelines

## Architecture Overview
BeerTracker is a procedural Perl CGI web application for personal beer tracking. It uses SQLite for data storage and runs under Apache. The main entry point is `code/index.cgi`, which dispatches requests to focused modules in `code/` based on the `o` parameter (e.g., `o=Board` for beerboard.pm).

Key components:
- **Database**: SQLite file `beerdata/beertracker.db` with schema in `code/db.schema`. Tables: glasses (drinking events), brews (beverages), locations (places), persons, comments.
- **Modules**: ~20 Perl modules in `code/` for specific functionalities (e.g., beerboard.pm for bar beer lists, db.pm for database helpers).
- **Scraping**: Perl scripts in `scripts/` scrape beer menus from bar websites (e.g., oelbaren.pl).
- **Static Assets**: CSS/JS in `static/`, served with cache-busting timestamps.

Data flows from browser forms to index.cgi, which calls module post*() functions for writes, then redirects to display pages.

## Development Workflow
- **Dev Environment**: Work in `beertracker-dev` directory (blue background indicates dev mode).
- **Database Changes**: Edit schema in SQLite, run `tools/dbdump.sh` to update `code/db.schema`, commit. Git post-merge hook warns if schema changed. Use `tools/dbchange.sh` to apply schema updates in production.
- **Versioning**: Git pre-commit hook runs `tools/makeversion.sh` to update `code/VERSION.pm` with commit count.
- **Testing**: No automated tests; manually test CGI under Apache. Use `superuser::copyproddata()` to sync production data to dev.
- **Deployment**: Git pull code to production, run `tools/dbchange.sh` if schema changed.

## Key Patterns and Conventions
- **Context Hash**: Pass `$c` hash containing globals (username, dbh, url, etc.) to all functions.
- **Parameter Handling**: Use `util::param($c, "key")` for CGI params; handles GET/POST uniformly.
- **Database Access**: Direct SQL with DBI; `db::open_db($c, "rw")` for writes, "ro" for reads. Foreign keys enforced.
- **Error Handling**: `util::error()` for fatal errors; database errors logged to STDERR and shown in HTML.
- **Filtering**: Use `q` param for grep-style filtering (e.g., `?q=IPA`); `filt()` helper creates filter links.
- **Links**: Build URLs as `$c->{url}?o=Operation&e=ID`; use `uri_escape_utf8()` for params.
- **Display Helpers**: `util::unit()` for values with units (e.g., "33<small>cl</small>"); `util::datestr()` for dates.
- **Scraping**: Use LWP::UserAgent and XML::LibXML; output JSON to STDOUT for beer lists.
- **UTF-8**: All source and data is UTF-8; set `binmode STDOUT, ":utf8"`.
- **No Frameworks**: Pure Perl, no ORM or web framework; procedural style with modules.

## Common Tasks
- **Add New Operation**: Add dispatch in index.cgi (POST in eval block, GET in main if-elsif chain), create module in `code/`.
- **Database Query**: Prepare with `$sth = $c->{dbh}->prepare($sql); $sth->execute(@params);` while loop for results.
- **Form Handling**: Hidden inputs for state; `accept-charset='UTF-8'`; redirect after POST.
- **Beer Board**: Scrape to JSON, store in tap_beers table, display in beerboard.pm with expand/collapse JS.
- **Debugging**: Print to STDERR for logs; `$c->{devversion}` for dev-specific behavior.

## Examples
- **Dispatch Pattern**: `if ($c->{op} =~ /Board/i) { beerboard::beerboard($c); }`
- **SQL Insert**: `$c->{dbh}->do("INSERT INTO glasses (Username, Timestamp) VALUES (?, ?)", undef, $c->{username}, time());`
- **Filter Link**: `filt($c, "IPA", "span", "IPA beers")` creates `<a href='...?q=IPA'>IPA beers</a>`
- **Context Usage**: `my $username = $c->{username}; my $url = $c->{url};`
- **Scraping Output**: `print encode_json({ maker => $maker, beer => $beer, alc => $alc });`

Focus on direct SQL, context passing, and CGI dispatch. Avoid over-abstraction; prioritize readability and direct data manipulation.