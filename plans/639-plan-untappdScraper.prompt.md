# Plan: Generic Untappd Venue Scraper

## TL;DR
Add `scripts/untappd.pl` — a generic scraper for any venue's public Untappd page. It accepts a short venue ID (e.g. `olsnedkeren/415314`) as a command-line argument, constructs the URL internally, parses the HTML with `XML::LibXML`, filters to the "Tap"-named menu section, and outputs the standard JSON schema. Update `scrapeboard.pm` to use arrays for all scraper entries.

---

## Phase 1 — Investigate HTML structure

1. Fetch raw HTML of `https://untappd.com/v/olsnedkeren/415314` (via `curl` with browser User-Agent) to confirm exact CSS class names / XPath selectors for:
   - Menu section container and section heading (to identify the "Tap" section)
   - Beer name, tap number, style, ABV, maker within items
   - Use `brus.pl` or `oelbaren.pl` as structural starting points; they scrape static HTML pages in the same straightforward way

---

## Phase 2 — Create `scripts/untappd.pl`

2. New script, modelled on `brus.pl` / `oelbaren.pl`:
   - Accept venue ID as `$ARGV[0]` (format: `"olsnedkeren/415314"`); die with usage if missing
   - Construct full URL: `"https://untappd.com/v/$venue_id"`
   - `LWP::UserAgent` with a browser `User-Agent` header and `timeout => 10`
   - `XML::LibXML->load_html(recover => 1, suppress_errors => 1)`
   - Find all menu sections; select where heading contains "tap" (case-insensitive) — handles both "Fadølsudvalg // **Tap** beer" and plain "**Tap** beer"
   - Extract per-item: tap number, beer name (strip leading `"N. "` prefix), style, ABV, maker
   - No prices → placeholder `sizePrice => [{vol => "S"}, {vol => "L"}]`
   - Output via `JSON->new->pretty(1)->ascii(1)->canonical(1)->encode(\@taps)`
   - `$debug` flag for STDERR verbosity

---

## Phase 3 — Update `scrapeboard.pm`

3. Change all `%scrapers` entries to use array refs `["script.pl", "arg"]` — no backward-compat plain strings needed
4. In `updateboard()`, unpack `($script, $arg)` from the array ref and call `` `timeout 5s perl $script $arg` `` — `$arg` is hardcoded, not user input, so no injection risk
5. Add entries for all venues from issue #639:
   - `$scrapers{"Ølsnedkeren"} = ["untappd.pl", "olsnedkeren/415314"]` (keep old `oelsnedkeren.pl` commented out)
   - `$scrapers{"Bootleggers"} = ["untappd.pl", "bootleggers-craft-beer-bar-frb/10845482"]`
   - `$scrapers{"Fermentoren"} = ["untappd.pl", "fermentoren-cph/127076"]` (keep old `fermentoren.pl` commented out)

---

## Relevant files

- `scripts/untappd.pl` — new file; use `brus.pl` or `oelbaren.pl` as structural template
- `code/scrapeboard.pm` — `%scrapers` hash (~line 14) and `updateboard()` invocation (~line 38)

---

## Verification

1. `perl scripts/untappd.pl olsnedkeren/415314` → 18 tap beers in JSON
2. `perl -c scripts/untappd.pl` passes with no errors
3. Visit `?o=Board&loc=Ølsnedkeren` and trigger reload; beers appear correctly

---

## Further Considerations

1. **HTML inspection first**: The exact XPath selectors must be confirmed from raw HTML before writing the parser. The fetched page content strongly suggests server-rendered markup.
2. **Section name language**: The "contains 'tap'" filter works for venues that use English on Untappd. If a venue uses only a local-language section name, a second optional arg for a custom section-name pattern may be needed.
3. **Rate limiting**: If Untappd blocks repeated scraping, the fallback is the Business embed URL approach (`business.untappd.com/locations/ID/themes/ID/js`) — already proven by `fermentoren.pl`.
4. **LLM fallback**: If the page structure keeps changing and XPath selectors become brittle, consider running a local LLM to extract the data from raw HTML instead of hardcoded selectors. More resilient but also more complex to implement.