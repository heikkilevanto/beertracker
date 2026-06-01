# Fix annual and monthly stats for new users starting mid-period

Issue #129: When a user starts tracking beers in the middle of a year or month,
the per-day averages are wrong because the divisor doesn't account for the
partial period before they started.

## Key insight

The distinction is between an established user with a sparse month/year (zero
days count, lowering the average) and a brand new user who simply hasn't had a
chance to drink before their first entry (should count from first occurrence).

For established users, behavior stays exactly the same.

## Changes

### yearstat.pm — `yearsummary`

Problem: Per-day averages use 365 regardless of when the user started tracking
in that year.

Fix:
- Determine the user's overall first year: `SELECT MIN(strftime('%Y', Timestamp, '-06:00')) ...`
- For each year `$y` in the loop:
  - If `$y` is the user's **first year** and is the **current year**: divisor = `datestr("%j") - first_day_of_year + 1`
  - If `$y` is the user's **first year** and is a **past year**: divisor = `365 - first_day_of_year + 1`
  - Otherwise (existing behavior): divisor = 365

The "so far" / projection logic for the current year is unchanged and correct.

### monthstat.pm — `monthstat`

Problem: Past months divide by 30 regardless of when in the month the user
started.

Fix:
- Track the user's overall first month (`$firstym`) from the query results
- Add `MIN(strftime('%d', timestamp, '-06:00'))` to the main SQL query to get
  `$firstday` per month group
- For each month `$calm` in the loop:
  - If `$calm` is the user's **first month** and is the **current month**:
    divisor = `$dayofmonth - $firstday + 1`
  - If `$calm` is the user's **first month** and is a **past month**:
    divisor = `30 - $firstday + 1`
  - Otherwise: existing behavior (30 for past months, `$dayofmonth` for current)

The 30-day-per-month approximation is kept for all other months. Leap years are
not handled specially (365 is good enough).
