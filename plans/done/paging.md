# Pagination for listrecords

## Problem

- `listrecords` shows only the first `$maxrecords` (default 20) rows, rest hidden with `hidden` attribute on `<tbody>`
- A single "More..." link reveals ALL hidden rows — no page navigation
- When filtering, JS shows ALL matching rows, which can be thousands, making the DOM slow
- Clr (clear filters) is currently a pseudo-column in SQL views, rendered as a table cell

## Solution

Replace the "More..." link with a pagination header bar. Keep all rows in DOM for instant client-side filtering, but show only one page at a time. Move Clr to the header bar. All listrecords calls always get a pagination header.

---

## 1. Interface change: `$opt` hash

**Before:** 8 positional params after `$c`:
```perl
sub listrecords {
  my $c = shift;
  my $table = shift;
  my $sort = shift;
  my $where = shift || "";
  my $params = shift || undef;
  my $extraparams = shift || undef;
  my $maxrecords = shift || 20;
  my $browsersortcol = shift || undef;
```

**After:** 3 positional + 1 hashref:
```perl
sub listrecords {
  my $c = shift;
  my $table = shift;
  my $sort = shift;
  my $opt = shift || {};
  my $where          = $opt->{where}          || "";
  my $params         = $opt->{params};
  my $extraparams    = $opt->{extraparams};
  my $maxrecords     = $opt->{maxrecords}     || ($c->{mobile} ? 20 : 100);
  my $browsersortcol = $opt->{browsersortcol};
  my $title          = $opt->{title}          || "";
```

Default page size: 20 mobile, 100 desktop (via `$c->{mobile}`).

---

## 2. listrecords.pm — always render header bar

Since all callers pass a title, the header bar is **always** rendered. No conditional logic for titled vs untitled. The old "More..." link code is removed entirely.

### 2a. Skip Clr pseudo-columns

In the field-iterating loop, skip columns that are exactly `Clr` (not IdClr). Since Clr is now in the header bar, no table column needed.

The check changes from `/Clr/i` to `$f eq "Clr"` so `IdClr` is not affected.

### 2b. Fix IdClr to behave like Id

`IdClr` should be treated identically to `Id` in both header and data rendering. In the header chain, check `$f eq "IdClr"` alongside `$f eq "Id"`. In data rendering, the existing `$fn eq "IdClr"` block stays but should produce the same link style as `Id`.

### 2c. Header bar HTML

```html
<div class="lr-wrapper">
  <div class="lr-bar" style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:4px;">
    <div class="lr-bar-left">
      <b>TITLE</b>
      &nbsp;<a href="...?o=$op&e=new"><span>(New)</span></a>
      <!-- "(New)" omitted when title matches /^Photos/i -->
    </div>
    <div class="lr-bar-right">
      <span class="lr-paginator">
        <a href="#" class="lr-prev" onclick="return lr_page(this,-1)">« Prev</a>
        <span class="lr-page-info">
          Page <input type="text" class="lr-page-input" size="3"
                onchange="lr_go(this)" onkeydown="if(event.key==='Enter')lr_go(this)"
                title="Current page — type a number and press Enter" />
          of <span class="lr-page-total">N</span>
        </span>
        <a href="#" class="lr-next" onclick="return lr_page(this,1)">Next »</a>
      </span>
      &nbsp;|&nbsp;
      <span class="lr-clr" onclick="lr_clearfilters(this)"
            style="cursor:pointer; border:1px solid #888; border-radius:4px; padding:0 5px; font-size:x-small">Clr</span>
      &nbsp;|&nbsp;
      <span class="lr-size-group">
        <input type="text" class="lr-size-input" size="4"
              onchange="lr_changesize(this)" onkeydown="if(event.key==='Enter')lr_changesize(this)"
              title="Rows per page (e.g. 20, 50, 100, 200, or All)" />
      </span>
    </div>
  </div>
  <div class="lr-subbar" style="font-size:small; color:#666; margin-bottom:4px;">
    Showing <span class="lr-show-start">1</span>–<span class="lr-show-end">20</span>
    of <span class="lr-show-total">N</span>
    (<span class="lr-grand-total">T</span> total)
  </div>
  <table data-lr-wrapper ...>
```

Page number and page size are `<input type="text">` fields (not `<select>`) for a cleaner UI. The page number input auto-navigates on Enter. Page size input accepts numeric values or "All".

### 2d. Table attributes

Always:
- `data-page-size="100"` (adjustable)
- `data-current-page="1"`
- `data-lr-wrapper` on wrapper div

No `data-maxrecords` anymore (removed).

### 2e. Update cache key

Keep existing cache key format. `$title` is NOT added to the key — the view name (`$table`) already differentiates different lists.

---

## 3. listrecords.js — pagination functions

### 3a. Core pagination

```javascript
function lr_paginate(table) {
  const pageSize = parseInt(table.dataset.pageSize);
  const currPage = parseInt(table.dataset.currentPage);
  const visibleTbodies = Array.from(table.tBodies).filter(t => t.style.display !== 'none');
  const totalVisible = visibleTbodies.length;
  const totalPages = pageSize > 0 ? Math.ceil(totalVisible / pageSize) : 1;

  if (pageSize === 0) {
    visibleTbodies.forEach(t => t.style.display = '');
  } else {
    visibleTbodies.forEach(t => t.style.display = 'none');
    const start = (currPage - 1) * pageSize;
    const end = Math.min(start + pageSize, totalVisible);
    for (let i = start; i < end; i++) visibleTbodies[i].style.display = '';
  }

  lr_updateInfo(table, currPage, totalVisible, totalPages);
}

function lr_updateInfo(table, currPage, totalVisible, totalPages) {
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const pageSize = parseInt(table.dataset.pageSize);
  const pi = wrapper.querySelector('.lr-page-info');
  const pg = wrapper.querySelector('.lr-paginator');
  const ss = wrapper.querySelector('.lr-show-start');
  const se = wrapper.querySelector('.lr-show-end');
  const st = wrapper.querySelector('.lr-show-total');
  const gt = wrapper.querySelector('.lr-grand-total');

  if (pageSize === 0) {
    pg.style.display = 'none';
    ss.textContent = '1';
    se.textContent = totalVisible;
    st.textContent = totalVisible;
  } else {
    pg.style.display = '';
    const start = (currPage - 1) * pageSize + 1;
    const end = Math.min(currPage * pageSize, totalVisible);
    ss.textContent = start;
    se.textContent = end;
    st.textContent = totalVisible;
    wrapper.querySelector('.lr-page-input').value = currPage;
    wrapper.querySelector('.lr-page-total').textContent = totalPages;
    wrapper.querySelector('.lr-prev').style.visibility = currPage > 1 ? 'visible' : 'hidden';
    wrapper.querySelector('.lr-next').style.visibility = currPage < totalPages ? 'visible' : 'hidden';
  }
  gt.textContent = table.tBodies.length;
}
```

### 3b. Navigation handlers

```javascript
function lr_page(el, delta) {
  const wrapper = el.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  let page = parseInt(table.dataset.currentPage) + delta;
  table.dataset.currentPage = Math.max(1, page);
  lr_paginate(table);
  return false;
}

function lr_go(input) {
  const wrapper = input.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  const v = parseInt(input.value);
  if (v > 0) {
    const totalPages = Math.ceil(table.tBodies.length / parseInt(table.dataset.pageSize));
    table.dataset.currentPage = Math.min(v, totalPages);
    lr_paginate(table);
  }
}

function lr_changesize(input) {
  const wrapper = input.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  const v = input.value.toLowerCase().trim();
  const newSize = v === 'all' ? 0 : parseInt(v);
  if (newSize >= 0 && !isNaN(newSize)) {
    table.dataset.pageSize = newSize;
    table.dataset.currentPage = 1;
    lr_paginate(table);
  }
}
```

### 3c. Modify `dochangefilter()`

Replace the `wasExpanded` / `maxRecords` logic block with:

```javascript
// Always paginate (all tables have pagination now)
table.dataset.currentPage = 1;
lr_paginate(table);
```

Also remove the "More..." link show/hide code.

### 3d. Modify `doSortTable()`

After sorting, reset to page 1 and re-paginate:

```javascript
table.dataset.currentPage = 1;
lr_paginate(table);
```

### 3e. `lr_clearfilters()`

```javascript
function lr_clearfilters(el) {
  const wrapper = el.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  table.querySelectorAll('thead td input[data-col]').forEach(inp => { inp.value = ''; });
  // Trigger re-filter via first filter input
  const first = table.querySelector('thead input[data-col]');
  if (first) dochangefilter(first);
}
```

### 3f. Remove unused functions

- `showMoreRecords()` — no longer needed
- Old `clearfilters()` — replaced by `lr_clearfilters()`

---

## 4. Caller changes

### brews.pm (line 26)
```perl
# OLD:
# print "<b>Brews</b> ";
# print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>";
# print "<br/>\n";
# print listrecords::listrecords($c, "BREWS_LIST", "Last-",
#     "xUsername = ?", $c->{username});

# NEW:
print listrecords::listrecords($c, "BREWS_LIST", "Last-",
    { where => "xUsername = ?", params => $c->{username}, title => "Brews" });
```

### brews.pm dedup (line 347)
```perl
# OLD:
# print listrecords::listrecords($c, "BREWS_DEDUP_LIST", $sort,
#     "Id <> $brew->{Id} AND xUsername = ?", $c->{username}, $extra, undef, "Sim");

# NEW:
print listrecords::listrecords($c, "BREWS_DEDUP_LIST", $sort,
    { where => "Id <> $brew->{Id} AND xUsername = ?",
      params => $c->{username}, extraparams => $extra,
      browsersortcol => "Sim", title => "Similar brews" });
```

### locations.pm (line 37)
```perl
# OLD:
# print "<b>Locations</b>";
# print "&nbsp;<a href=\"$c->{url}?o=$c->{op}&e=new\"><span>(New)</span></a>\n";
# print listrecords::listrecords($c, "LOCATIONS_LIST", $sort,
#     "", "", $extraparams);

# NEW:
print listrecords::listrecords($c, "LOCATIONS_LIST", $sort,
    { extraparams => $extraparams, title => "Locations" });
```

### locations.pm producerbrews (line 250)
```perl
# OLD:
# my $nbrews = db::queryrecord($c, $countsql, $p->{Name}, $c->{username});
# print "<b>$nbrews->{cnt} Brews by $p->{Name} </b><br/>\n";
# print listrecords::listrecords($c, "producer_brews_list", "Last-",
#     "xProducer = ? AND xUsername = ?", [$p->{Name}, $c->{username}]);

# NEW:
print listrecords::listrecords($c, "producer_brews_list", "Last-",
    { where => "xProducer = ? AND xUsername = ?",
      params => [$p->{Name}, $c->{username}],
      title => "Brews by $p->{Name}" });
```

### locations.pm dedup (line 280)
```perl
# OLD:
# print listrecords::listrecords($c, "LOCATIONS_DEDUP_LIST", $sort,
#     "Id <> $loc->{Id}", undef, $extra, undef, "Sim");

# NEW:
print listrecords::listrecords($c, "LOCATIONS_DEDUP_LIST", $sort,
    { where => "Id <> $loc->{Id}", extraparams => $extra,
      browsersortcol => "Sim", title => "Similar locations" });
```

### comments.pm (line 157)
```perl
# OLD:
# print "<b>Comments by $c->{username}</b> ";
# print "&nbsp;<a href='...'><span>(New)</span></a>";
# print "<br/>\n";
# print listrecords::listrecords($c, "COMMENTS_LIST", "Last-",
#     "xUsername=?", $c->{username});

# NEW:
print listrecords::listrecords($c, "COMMENTS_LIST", "Last-",
    { where => "xUsername=?", params => $c->{username},
      title => "Comments by $c->{username}" });
```

### photos.pm (line 329)
```perl
# OLD:
# print "<b>Photos for $c->{username}</b><br/>\n";
# print listrecords::listrecords($c, "PHOTOS_LIST", "Ts-", $where,
#     [$c->{username}, ...]);

# NEW:
print listrecords::listrecords($c, "PHOTOS_LIST", "Ts-",
    { where => $where, params => [$c->{username}, $c->{username},
       $c->{username}, $c->{username}],
      title => "Photos for $c->{username}" });
```

### persons.pm (line 21)
```perl
# OLD:
# print "&nbsp;Persons <a href=\"...\"><span>(New)</span></a>";
# print listrecords::listrecords($c, "PERSONS_LIST", $sort);

# NEW:
print listrecords::listrecords($c, "PERSONS_LIST", $sort,
    { title => "Persons" });
```

---

## 5. Edge cases

1. **Empty table (0 rows)**: Header bar shows "Showing 0 of 0 (0 total)". Page nav hidden.
2. **Filter fits on one page**: Page input shows "1", prev/next hidden, "of 1".
3. **Page size > total records**: Typing "200" on 35 records = page 1 of 1 (All effectively).
4. **"All" in page size**: All rows shown, page nav controls hidden.
5. **Mobile**: Default page size 20. Header bar wraps with flex-wrap.
6. **Cache**: Key uses view name — no change needed.
7. **Multiple tables per page**: `data-lr-wrapper` attribute pairs each header with its table.

---

## 6. Verification

- `perl -c code/listrecords.pm` and each modified caller module.
- Manually test each list page under dev Apache.
- Check Clr button works in header bar.
- Check IdClr displays correctly (like Id).
- Check page navigation, page size changes, All mode.
- Check filter resets to page 1.
- Check sort resets to page 1.
