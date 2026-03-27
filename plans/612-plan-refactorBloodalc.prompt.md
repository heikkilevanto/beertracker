# Plan: Refactor bloodalc to use pre-fetched glass array

Eliminate the extra DB query in `bloodalc` when called from `oneday` by having `oneday` collect records first and pass them to a compute function for in-place BA annotation.

## Steps

### Phase 1 — New bloodalc_compute (mainlist.pm)

1. Add `bloodalc_compute($c, \@glasses)`:
   - Accepts arrayref of glass records (hashrefs with `id`, `timestamp`, `stdrinks`)
   - Since `glassquery` returns DESC order, **iterate from the back** of the array to process in chronological order — no sort needed
   - Runs the existing burn/accumulation loop
   - Sets `$rec->{ba}` on each record in-place (formatted `"%0.2f"`)
   - Returns hashref with `{max, last_alcinbody, last_balctime, bodyweight, burnrate, date}`

2. Update `bloodalc($c, $effdate)` to a thin wrapper:
   - Keeps cache check/set
   - Fetches glasses into a local array via existing SQL
   - Delegates to `bloodalc_compute` and returns result
   - `bloodalcnow`, `graph.pm`, `util.pm` unchanged

### Phase 2 — Refactor oneday (mainlist.pm)

3. Split `oneday` into two passes:
   - **Pass 1**: Collect day's records into `@glasses` (same cursor logic, push instead of render)
   - Call `bloodalc_compute($c, \@glasses)` — stores `$rec->{ba}` on each record; save return as `$balc` for `$balc->{max}` in sumline
   - **Pass 2**: `foreach my $rec (@glasses)` — render, same body as current while loop

4. Update `numbersline($c, $rec)`: drop `$bloodalc` param, use `$rec->{ba}` directly. Update the one call site.

### Phase 3 — Optional: graph.pm (parallel, deferred)

5. Update graph.pm line 90 to use `bloodalc_compute` with a minimal array. Low priority.

## Relevant files
- `code/mainlist.pm` — all changes: `bloodalc_compute`, `bloodalc`, `oneday`, `numbersline`
- `code/graph.pm` — optional step 5 only
- `code/util.pm` — no changes needed

## Verification
1. `perl -c code/mainlist.pm` passes
2. Load mainlist — verify per-glass BA and sumline BA correct
3. Load graph — BA max still plots correctly
4. Topline BA display works (util.pm path unchanged)
5. `bloodalcnow` correct near end-of-session

## Decisions
- Wrapper `bloodalc($c, $effdate)` kept — graph.pm and util.pm unaffected
- No per-ID entries in `bloodalc_compute` return value — BA lives on records directly
- Reverse iteration exploits existing DESC order from `glassquery`
- Step 5 deferred
