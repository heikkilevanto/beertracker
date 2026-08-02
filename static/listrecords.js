// listrecords helpers
// These manage filtering, sorting, and pagination of lists created by listrecords

let filterTimeout;

// Per-table generation tokens: typing in a table bumps its token and cancels
// any in-flight filter pass on that table, without disturbing other tables.
const lrFilterGen = new WeakMap();
function lrTableGen(table) {
  let g = lrFilterGen.get(table);
  if (g === undefined) { g = 0; lrFilterGen.set(table, g); }
  return g;
}

// Per-element normalized cell-text cache. Body cells are static during a page
// session, so we only ever read textContent and normalize once per cell.
const lrNormCache = new WeakMap();

// Rows processed per yield while filtering, so the event loop can preempt.
const LR_FILTER_CHUNK = 300;

function changefilter (inputElement) {
  const table = inputElement.closest('table');
  if (table) lrFilterGen.set(table, lrTableGen(table) + 1); // cancel running pass
  clearTimeout(filterTimeout); // Cancel previous timeout
  filterTimeout = setTimeout(() => {
    dochangefilter(inputElement);
  }, 300); // Adjust delay as needed}
}

function dochangefilter (inputElement, done) {
  const table = inputElement.closest('table');
  if (!table) return;
  const gen = lrTableGen(table) + 1; // claim this pass's generation
  lrFilterGen.set(table, gen);
  table.closest('[data-lr-wrapper]')?.classList.remove('lr-compact');

  const filterinputs = table.querySelectorAll('thead input');

  // Build per-column arrays of filter tokens with mode (contains/not_contains/exact)
  const ALLOWLIST = /[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß., <>=-]/g;
  let filters = [];
  for ( let i=0; i<filterinputs.length; i++) {
    let filterinp = filterinputs[i];
    if ( filterinp ) {
      const col = filterinp.getAttribute("data-col");
      filterinp.value = filterinp.value.replace(/[▲▼]+/g,"");
      const rawTokens = _tokenizeFilterInput(filterinp.value);
      const parsed = [];
      for (let t = 0; t < rawTokens.length; t++) {
        let term = rawTokens[t];
        let mode = 'contains';
        if (term.startsWith('>=')) {
          mode = 'gte';
          term = term.substring(2);
        } else if (term.startsWith('<=')) {
          mode = 'lte';
          term = term.substring(2);
        } else if (term.startsWith('>')) {
          mode = 'gt';
          term = term.substring(1);
        } else if (term.startsWith('<')) {
          mode = 'lt';
          term = term.substring(1);
        } else if (term.startsWith('!=')) {
          mode = 'ne';
          term = term.substring(2);
        } else if (term.startsWith('=')) {
          mode = 'exact';
          term = term.substring(1);
        } else if (term.startsWith('-')) {
          mode = 'not_contains';
          term = term.substring(1);
        }
        term = term.normalize('NFC').replace(ALLOWLIST, '').trim();
        if (term.length > 0 && term !== '-') {
          parsed.push({ mode: mode, term: term.toLowerCase() });
        }
      }
      filters[col] = parsed;
    }
  }

  // Detach table from DOM — all subsequent mutations have zero reflow cost
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const tableParent = wrapper.parentNode;
  const tableSibling = wrapper.nextSibling;
  tableParent.removeChild(wrapper);

  const firstrows = table.querySelectorAll('tbody tr[data-first]');

  // True when no column has an active filter — lets Clear skip all matching.
  let anyFilter = false;
  for (let i = 0; i < filters.length; i++) {
    if (filters[i] && filters[i].length > 0) { anyFilter = true; break; }
  }

  let visibleCount = 0;
  let r = 0;
  let reattached = false;

  function reattach() {
    if (tableSibling) {
      tableParent.insertBefore(wrapper, tableSibling);
    } else {
      tableParent.appendChild(wrapper);
    }
  }

  // Filter a single record (one tbody) and apply its visibility
  function processRow(row) {
    var disp = "";
    let seenFilterCol = {};
    const tbody = row.closest('tbody'); // capture before the walker nulls `row`

    do {
      const cols = row.querySelectorAll('td');
      for (let c = 0; c < cols.length; c++) {
        const colEls = cols[c].querySelectorAll('[data-col]');
        if (!colEls.length) {
          continue;
        }
        for (let ce = 0; ce < colEls.length; ce++) {
          const col = colEls[ce].getAttribute('data-col');
          if ( col && filters[col] && filters[col].length > 0 ) {
            seenFilterCol[col] = true;
            let normText = lrNormCache.get(colEls[ce]);
            if (normText === undefined) {
              normText = colEls[ce].textContent.normalize('NFC').toLowerCase().replace(ALLOWLIST, '');
              lrNormCache.set(colEls[ce], normText);
            }
            const matchAll = filters[col].every(function(f) {
              if (f.mode === 'gt' || f.mode === 'gte' || f.mode === 'lt' || f.mode === 'lte') {
                return _compareRelational(f.mode, normText, f.term);
              } else {
                return _matchAlternatives(normText, f.term, f.mode);
              }
            });
            if ( !matchAll ) {
              disp = "none";
              break;
            }
          }
        }
        if (disp === "none") break;
      }
      if (disp === "none") break;
      row = row.nextElementSibling;
    } while ( row && ! row.hasAttribute("data-first") );

    // Active filter for a column that never appeared in any row → empty value, can't match
    if (disp === "") {
      for (let col = 0; col < filters.length; col++) {
        if ( filters[col] && filters[col].length > 0 ) {
          if ( !seenFilterCol[col] ) {
            disp = "none";
            break;
          }
        }
      }
    }

    tbody.style.display = disp;
    tbody.dataset.lrFs = disp === '' ? '1' : '0';

    if (disp === "") {
      visibleCount++;
    }
  }

  if (!anyFilter) {
    // No active filters — result is the full list, so show the grand total
    // right away instead of the provisional (…/total) count.
    for (let j = 0; j < firstrows.length; j++) {
      const tb = firstrows[j].closest('tbody');
      tb.style.display = "";
      tb.dataset.lrFs = '1';
    }
    table.dataset.lrFiltering = '0';
    table.dataset.currentPage = 1;
    lr_paginate(table);
    reattach();

    const aggEl = wrapper.querySelector('[data-lr-agg]');
    if (aggEl) lr_update_footer(aggEl);

    if (done) done();
    if (inputElement.tagName === 'INPUT') {
      inputElement.focus();
      inputElement.selectionStart = inputElement.selectionEnd = inputElement.value.length;
    }
    return;
  }

  table.dataset.lrFiltering = '1'; // provisional count (…/total) while filtering

  // Cheap: hide every matching row beyond the first page while we work, so only
  // page 1 is ever visible. Without this, all matching rows would briefly show
  // at once and stretch the table (and the row separators) during the pass.
  // Does not touch the nav/count/footer — those are finalized by lr_paginate.
  function keepOnCurrentPage() {
    const pageSize = parseInt(table.dataset.pageSize);
    let shown = 0;
    const tbodies = table.tBodies;
    for (let i = 0; i < tbodies.length; i++) {
      const tb = tbodies[i];
      if ((tb.dataset.lrFs || '1') !== '1') { tb.style.display = 'none'; continue; }
      if (pageSize === 0 || shown < pageSize) { tb.style.display = ''; shown++; }
      else { tb.style.display = 'none'; }
    }
  }

  function step() {
    if (gen !== lrTableGen(table)) {
      // Superseded by newer input — restore the table, let the new pass run
      reattach();
      if (done) done();
      return;
    }
    const end = Math.min(r + LR_FILTER_CHUNK, firstrows.length);
    for (; r < end; r++) {
      processRow(firstrows[r]);
    }
    keepOnCurrentPage();
    if (!reattached) {
      reattached = true;
      reattach();
    }
    if (r < firstrows.length) {
      setTimeout(step, 0);
      return;
    }
    // All rows processed
    table.dataset.lrFiltering = '0';
    table.dataset.currentPage = 1;
    lr_paginate(table);
    reattach();

    const aggEl = wrapper.querySelector('[data-lr-agg]');
    if (aggEl) lr_update_footer(aggEl);

    if (done) done();

    if (inputElement.tagName === 'INPUT') {
      inputElement.focus();
      inputElement.selectionStart = inputElement.selectionEnd = inputElement.value.length;
    }
  }

  step();
}

// Clicking on a data field sets the filter
function fieldclick(event,el,index) {
  var target = event.target.closest('[data-filter]');
  var filtertext = target ? target.dataset.filter
               : el.dataset.filter
               ? el.dataset.filter
               : el.textContent;
  filtertext = filtertext.replace( /\[|\]/g , "");

  const table = el.closest('table');
  var col = target && target.dataset.col ? target.dataset.col : el.getAttribute("data-col");
  if ( col === null && index !== undefined ) col = index;
  const filterinp = table.querySelector('input[data-col="'+col+'"]');
  if ( filterinp ) {
    filterinp.value = filtertext;
    dochangefilter(filterinp);
  }
}

function fieldclick_word(event, el, col) {
  var token = el.textContent;
  token = token.replace(/[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß &-]/g, '');
  if ( !token ) return;

  const table = el.closest('table');
  const filterinp = table.querySelector('input[data-col="' + col + '"]');
  if ( filterinp ) {
    if ( filterinp.value ) {
      filterinp.value += ' ' + token;
    } else {
      filterinp.value = token;
    }
    dochangefilter(filterinp);
  }
}

function fieldclick_cell(event, el, col) {
  var text = el.textContent;
  text = text.replace(/\s+/g, ' ').trim();
  text = text.replace(/[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß &-]/g, '');
  if ( !text ) return;

  const table = el.closest('table');
  const filterinp = table.querySelector('input[data-col="' + col + '"]');
  if ( filterinp ) {
    filterinp.value = text;
    dochangefilter(filterinp);
  }
}

function lr_clearfilters(el) {
  const wrapper = el.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  table.querySelectorAll('thead td input[data-col]').forEach(inp => { inp.value = ''; });
  const first = table.querySelector('thead input[data-col]');
  if (first) dochangefilter(first);
}

function lr_toggleheaders(el) {
  const wrapper = el.closest('[data-lr-wrapper]');
  wrapper.classList.toggle('lr-compact');
}

function lr_showhelp() {
  const popup = document.getElementById('lr-help-popup');
  if (popup) popup.style.display = 'block';
}

function lr_hidehelp() {
  const popup = document.getElementById('lr-help-popup');
  if (popup) popup.style.display = 'none';
}

/////////////////////
// Sorting the table
let sortTimeout;

function sortTable(el, col) {
  const ascending = ( el.value != " ▲" );

  el.value = ascending ? " ▲▲▲" : " ▼▼▼" ;  // Indicate we are sorting

  clearTimeout(sortTimeout); // Cancel previous timeout
  sortTimeout = setTimeout(() => { // Let the browser render first
    doSortTable(el, col, ascending);
  }, 0);

}

function doSortTable(el, col, ascending) {
  const table = el.closest('table');
  const tbodies = Array.from(table.tBodies);
  const columnIndex = col;

  console.time("sort") ;

  // Detach wrapper from DOM — all subsequent DOM mutations have zero reflow cost
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const wrapperParent = wrapper.parentNode;
  const wrapperSibling = wrapper.nextSibling;
  wrapperParent.removeChild(wrapper);

  // Precompute sort keys
  const sortableTbodies = tbodies.map(tbody => {
    const key = extractSortKey(tbody.rows, columnIndex);
    return { key, tbody };
  });

  // Sort
  sortableTbodies.sort((a, b) => {
      if (a.key === "" ) return 1;
      if (b.key === "" ) return -1;
      if (a.key < b.key) return ascending ? -1 : 1;
      if (a.key > b.key) return ascending ? 1 : -1;
      return 0;
  });

  // Reorder tbodies in sorted order (table is detached, zero reflow cost)
  const fragment = document.createDocumentFragment();
  for (const { tbody } of sortableTbodies) {
    fragment.appendChild(tbody);
  }
  table.appendChild(fragment);

  // Reset to page 1 and re-paginate
  table.dataset.currentPage = 1;
  lr_paginate(table);

  // Reattach wrapper — triggers exactly one reflow
  if (wrapperSibling) {
    wrapperParent.insertBefore(wrapper, wrapperSibling);
  } else {
    wrapperParent.appendChild(wrapper);
  }

  // Clear arrows
  for (let th of table.querySelectorAll('thead input ') ) {
    th.value = th.value.replace(/[▲▼]+/g, "").trim();
  }

  el.value = ascending ? " ▲" : " ▼" ;

  table.dataset.sortCol = col;
  table.dataset.sortDir = ascending ? "asc" : "desc";

  console.timeEnd("sort") ;
}

function extractSortKey(recordRows, columnIndex) {
  for (const row of recordRows) {
      const sel = "[data-col='" + columnIndex +"']";
      const cell = row.querySelector(sel);
      if (cell) {
        if (cell.dataset.sortKey) {
          let key = cell.dataset.sortKey;
          if (isNaN(key) || !key) {
            return key.toLowerCase().trim();
          } else {
            return parseFloat(key);
          }
        }
        let text = cell.textContent;
        const match = text.match(/20[0-9][0-9]-[0-9 :-]+/);
        if ( match ) { text = match[0]; }
        text = text.replace( /^\[/, "");
        text = text.replace( /\]$/, "");
        if ( isNaN(text) || ! text) {
          text = text.toLowerCase().trim();
        } else {
          text = parseFloat(text);
        }
        return text;
      }
  }
  return ""; // fallback key
}

/////////////////////
// Pagination

function lr_paginate(table) {
  const pageSize = parseInt(table.dataset.pageSize);
  const currPage = parseInt(table.dataset.currentPage);

  const allTbodies = Array.from(table.tBodies);
  const visibleTbodies = allTbodies.filter(t => (t.dataset.lrFs || '1') === '1');
  const totalVisible = visibleTbodies.length;
  const totalPages = pageSize > 0 ? Math.ceil(totalVisible / pageSize) : 1;

  // Compute which filter-visible tbodies belong on this page
  const visibleSet = new Set();
  if (pageSize === 0) {
    visibleTbodies.forEach(t => visibleSet.add(t));
  } else {
    const start = (currPage - 1) * pageSize;
    const end = Math.min(start + pageSize, totalVisible);
    for (let i = start; i < end; i++) visibleSet.add(visibleTbodies[i]);
  }

  // Single pass: set display based on filter + pagination
  for (let i = 0; i < allTbodies.length; i++) {
    const tbody = allTbodies[i];
    const filteredIn = (tbody.dataset.lrFs || '1') === '1';
    tbody.style.display = (filteredIn && visibleSet.has(tbody)) ? '' : 'none';
  }

  lr_updateInfo(table, currPage, totalVisible, totalPages);
  const wrapper = table.closest('[data-lr-wrapper]');
  const aggEl = wrapper ? wrapper.querySelector('[data-lr-agg]') : null;
  if (aggEl) lr_update_footer(aggEl);
}

function lr_updateInfo(table, currPage, totalVisible, totalPages) {
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const pageSize = parseInt(table.dataset.pageSize);

  // Update count on first line
  const countSpan = wrapper.querySelector('.lr-count');
  if (countSpan) {
    const grandTotal = Array.from(table.tBodies).filter(function(t) { return t.rows.length > 0; }).length;
    if (table.dataset.lrFiltering === '1') {
      countSpan.textContent = '…/' + grandTotal + ' ';
    } else {
      countSpan.textContent = totalVisible < grandTotal ? totalVisible + '/' + grandTotal + ' ' : grandTotal + ' ';
    }
  }

  const prev = wrapper.querySelector('.lr-prev');
  const next = wrapper.querySelector('.lr-next');
  if (prev) prev.style.display = totalPages <= 1 || currPage <= 1 ? 'none' : '';
  if (next) next.style.display = totalPages <= 1 || currPage >= totalPages ? 'none' : '';

  const pageSelect = wrapper.querySelector('.lr-page-select');
  if (pageSelect) {
    if (totalPages <= 1) {
      pageSelect.style.display = 'none';
    } else {
      pageSelect.style.display = '';
      pageSelect.innerHTML = '';
      for (let i = 1; i <= totalPages; i++) {
        const opt = document.createElement('option');
        const start = (i - 1) * pageSize + 1;
        const end = Math.min(i * pageSize, totalVisible);
        opt.value = start;
        opt.textContent = start + '-' + end;
        if (i === currPage) opt.selected = true;
        pageSelect.appendChild(opt);
      }
    }
  }
}

function lr_page(el, delta) {
  const wrapper = el.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  let page = parseInt(table.dataset.currentPage) + delta;
  if (page < 1) page = 1;
  table.dataset.currentPage = page;
  lr_paginate(table);
  return false;
}

function lr_gopage(select) {
  const wrapper = select.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  const pageSize = parseInt(table.dataset.pageSize);
  const startRec = parseInt(select.value);
  table.dataset.currentPage = Math.floor((startRec - 1) / pageSize) + 1;
  lr_paginate(table);
}

function lr_changesize(select) {
  const wrapper = select.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  table.dataset.pageSize = parseInt(select.value);
  table.dataset.currentPage = 1;
  lr_paginate(table);
}

// Toggle visibility of an element, used in brews.pm and locations.pm
//  print "<div onclick='toggleElement(this.nextElementSibling);'>";
//  print "Comments and ratings ... \n";
//  print "</div>\n";
//  print "<div style='overflow-x: auto;'>";  # Actual data to be displayed or not
function toggleElement(element) {
  if (element) {
    element.style.display = (element.style.display === 'none') ? 'block' : 'none';
  }
}

// Update aggregate footer for tables with data-aggregate attributes
function lr_update_footer(aggEl) {
  const wrapper = aggEl.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const table = wrapper.querySelector('table');
  if (!table) return;
  if (table.dataset.lrFiltering === '1') return; // defer until pass completes
  const cells = aggEl.querySelectorAll('span[data-aggregate]');
  if (!cells.length) return;
  const visibleTbodies = table.querySelectorAll('tbody[data-lr-fs="1"]');
  cells.forEach(function(cell) {
    const col = cell.dataset.col;
    const ag = cell.dataset.aggregate;
    let sum = 0, count = 0;
    visibleTbodies.forEach(function(tbody) {
      const span = tbody.querySelector('span[data-col="' + col + '"]');
      if (!span) return;
      if (ag === 'cnt') {
        if (span.textContent.trim()) count++;
        return;
      }
      const val = span.dataset.aggVal;
      if (val === undefined) return;
      const num = parseFloat(val);
      if (isNaN(num)) return;
      sum += num;
      count++;
    });
    let result;
    if (ag === 'sum') result = sum;
    else if (ag === 'avg') result = count ? (sum / count).toFixed(1) : '';
    else if (ag === 'cnt') result = count;
    if (cell.dataset.rate && result !== '' && ag === 'avg') {
      let rclass = 'rating-gold';
      if (result <= 3) rclass = 'rating-rubbish';
      else if (result <= 5) rclass = 'rating-bronze';
      else if (result <= 7) rclass = 'rating-silver';
      cell.innerHTML = cell.innerHTML.replace(/:.*/, ': <b class="' + rclass + '">' + result + '</b>');
    } else {
      cell.textContent = cell.textContent.replace(/:.*/, ': ' + result);
    }
  });
}

// Auto-sort a table by a given column index on page load
function autoSortTable(tableId, col, ascending) {
  const table = document.getElementById(tableId);
  if (!table) return;
  const input = table.querySelector('thead input[data-col="' + col + '"]');
  if (input) doSortTable(input, col, ascending);
}

// Auto-filter a table by a given column on page load
function autoFilterTable(col, token) {
  const table = document.querySelector('[data-autofilter]');
  if (!table) return;
  const input = table.querySelector('thead input[data-col="' + col + '"]');
  if (!input) return;
  input.value = token;
  dochangefilter(input, function() {
    var vis = Array.from(table.tBodies).filter(function(t){return t.style.display !== 'none';});
    if (vis.length === 0) {
      var hasData = Array.from(table.tBodies).some(function(t) {
        return t.querySelector('tr');
      });
      if (hasData) {
        input.value = '';
        dochangefilter(input);
      }
    }
  });
}
