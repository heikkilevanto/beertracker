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
- **Database Access**: Direct SQL with DBI; `db::open_db($c, "rw")` for POST requests, "ro" for GET requests. Foreign keys enforced.
- **Error Handling**: `util::error()` for fatal errors; database errors logged to STDERR and shown in HTML.
- **Filtering**: Use `q` param for grep-style filtering (e.g., `?q=IPA`); 
- **Links**: Build URLs as `$c->{url}?o=Operation&e=ID`; use `uri_escape_utf8()` for params.
- **Display Helpers**: `util::unit()` for values with units (e.g., "33<small>cl</small>"); `util::datestr()` for dates.
- **Scraping**: Use LWP::UserAgent and XML::LibXML; output JSON to STDOUT for beer lists.
- **UTF-8**: All source and data is UTF-8; set `binmode STDOUT, ":utf8"`.
- **No Frameworks**: Pure Perl, no ORM or web framework; procedural style with modules.

## Code Style Details
- **General Principles**: Write clean, readable, maintainable code. Use meaningful variable and function names. Include comments for complex logic. Follow Perl best practices.
- **Dialog**: Always state first what you are about to do, before doing it.
- **Language Features**: use strict; use warnings; use feature 'unicode_strings'; use utf8; use open ':encoding(UTF-8)'; binmode STDOUT, ":utf8".
- **Code Structure**: Functions start with "sub function_name {". Use "my $c = shift;" for context object. Return values explicitly. Use early returns for error conditions. Functions end with "} # function_name".
- **Variables and Naming**: Use lowercase with underscores: $variable_name. Descriptive names: $beer_list, $location_id. Context object is $c. Database handle is $c->{dbh}. CGI object is $c->{cgi}.
- **HTML Generation**: Use print qq{<html>...}; for HTML output. Escape special characters. Use CSS classes and inline styles. Generate forms with method="POST" for data modification.
- **JavaScript Integration**: Use <script> tags for client-side logic. Inline JavaScript for simple interactions. Use event handlers like onclick. Most JavaScript in separate files under static/.
- **SQL Style**: Use uppercase for keywords: SELECT, INSERT, UPDATE. Use placeholders (?) for parameters. Join tables explicitly. Use meaningful table aliases.
- **Comments**: Use # for single-line comments. Use # TODO for future improvements. Document function purposes. Explain complex algorithms.
- **Control Structures**: Use foreach for loops: foreach my $item (@list). Use if/elsif/else for conditionals. Use early returns to reduce nesting. Use next/last for loop control.
- **Regular Expressions**: Use =~ for matching. Use capturing groups when needed. Prefer simple patterns over complex ones.
- **String Handling**: Use double quotes for interpolation: "Hello $name". Use qq{} for multi-line strings. Handle UTF-8 encoding properly.
- **Arrays and Hashes**: Use -> for hash access: $hash->{key}. Use @ for array operations. Use scalar() for counting: scalar(@array).
- **File Operations**: Use open with lexical filehandles: open my $fh, ">$file". Check open success: or util::error("Could not open $file: $!"). Close filehandles explicitly.
- **External Commands**: Use backticks for command execution: my $output = `command`. Check $? for success. Use timeout for web scraping.
- **JSON Handling**: Use JSON module: JSON->new->utf8->decode($json). Pretty-print for debugging: ->pretty->encode($data).
- **CGI Parameters**: Use util::param($c, "name") for getting parameters. Validate and sanitize input. Handle missing parameters gracefully.
- **Logging**: Use STDERR for server-side logging. Include timestamps when relevant. Log important operations and errors.
- **Testing**: Test syntax with perl -c. Test functionality manually. Check database integrity after changes.
- **Version Control**: Commit logical units of work. Include descriptive commit messages. Keep history clean and meaningful.

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