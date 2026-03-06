# Plan: FastCGI In-Process Caching (Issue 570)

## Goal
Cache the results of expensive dropdown/list queries across requests in the
FastCGI process, so repeated page loads don't re-run the same SQL.

---

## 1. New module: `code/cache.pm`

Three functions, all operating on `$c->{cache}`:

```perl
cache::get($c, $key)        # returns value or undef
cache::set($c, $key, $value)  # stores value
cache::clear($c)            # resets $c->{cache} to {}
```

No TTL, no per-key invalidation for now. Clear-all on POST is sufficient.

---

## 2. `index.fcgi` changes

**Outside the while loop** (process-level, survives across requests):
```perl
my $cache = {};   # Persistent cache, lives for the lifetime of the process
```

**Inside the while loop**, add to the `$c` hash:
```perl
'cache' => $cache,
```

**After POST `eval` block** (before the `print redirect` / `next`):
```perl
cache::clear($c);   # Data may have changed; invalidate all cached lists
```

**Add require** in the module list:
```perl
require "./code/cache.pm";   # In-process cache for expensive queries
```

---

## 3. `brews::selectbrew` caching

Cache key: `"selectbrew_opts:$c->{username}:$brewtype"`

On cache miss: run the existing SQL, build `$opts` as today, store in cache.  
On cache hit: use cached `$opts`, skip the big SQL.

In both cases, `$current` (the display name of the selected brew) is looked up
with a small targeted query when `$selected` is non-empty:
```sql
SELECT Name FROM BREWS WHERE Id = ?
```
This is a trivial primary-key lookup and does not need caching.

The rest of `selectbrew` (calling `inputs::dropdown`) is unchanged.

---

## 4. Other candidates (same pattern, follow-up)

These can be cached with the same `cache::get` / `cache::set` pattern once
`selectbrew` is proven:

- `glasses::selectbrewtype` — dropdown of brew types
- `glasses::selectbrewsubtype` — dropdown of subtypes for a given type
- Location dropdowns in `inputs.pm`

Mark with `# TODO: cache this` for now; implement after selectbrew works.

---

## Files changed

| File | Change |
|------|--------|
| `code/cache.pm` | New module |
| `code/index.fcgi` | Add `$cache`, wire into `$c`, clear after POST, require cache.pm |
| `code/brews.pm` | Cache `$opts` in `selectbrew` |

---

## Notes

- Cache is per-process and per-username (key includes username).
- Two Apache workers = two independent caches; that is fine.
- No serialization, no expiry — simplest possible approach.
- On process restart (git pull / file change) cache is naturally empty.
- At the moment, the main list (without graph) takes 1700ms from a cold start and 535ms from
a warm fcgi. Just caching the selectbrew list drop the main list to 90ms. WOnderful. Caching
the location selection dropped it to 66ms. 
- Listbrews takes 628ms on a warm fcgi without caching, 66 from the cache.
- Location list 308ms to 21ms
- Comments list 170ms to 57ms
- Persons list 18ms to 6ms
- Photos 14ms to 9ms

