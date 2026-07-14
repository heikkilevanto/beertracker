// listrecords helpers
// These manage filtering, sorting, and pagination of lists created by listrecords

let filterTimeout;

function changefilter (inputElement) {
  clearTimeout(filterTimeout); // Cancel previous timeout
  filterTimeout = setTimeout(() => {
    dochangefilter(inputElement);
  }, 300); // Adjust delay as needed}
}

function dochangefilter (inputElement) {
  const table = inputElement.closest('table');
  if (!table) return;
  console.time("filter") ;

  const filterinputs = table.querySelectorAll('thead input');

  // Build per-column arrays of cleaned filter tokens (space-separated AND logic)
  const ALLOWLIST = /[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß -]/g;
  let filters = [];
  for ( let i=0; i<filterinputs.length; i++) {
    let filterinp = filterinputs[i];
    if ( filterinp ) {
      const col = filterinp.getAttribute("data-col");
      filterinp.value = filterinp.value.replace(/[▲▼]+/g,"");
      const tokens = filterinp.value.split(/\s+/).filter(function(t) { return t.length > 0; });
      const cleaned = tokens.map(function(t) { return t.replace(ALLOWLIST, ''); });
      filters[col] = cleaned.filter(function(t) { return t.length > 0; });
    }
  }

  // Detach table from DOM — all subsequent mutations have zero reflow cost
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const tableParent = wrapper.parentNode;
  const tableSibling = wrapper.nextSibling;
  tableParent.removeChild(wrapper);

  const firstrows = table.querySelectorAll('tbody tr[data-first]');
  let visibleCount = 0;

  for (let r = 0; r < firstrows.length; r++) {
    var disp = "";
    let row = firstrows[r];
    let seenFilterCol = {};

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
            const text = colEls[ce].textContent;
            const matchAll = filters[col].every(function(token) {
              const normText = text.toLowerCase().replace(ALLOWLIST, '');
              return normText.indexOf(token.toLowerCase()) !== -1;
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

    const tbody = firstrows[r].closest('tbody');
    tbody.style.display = disp;
    tbody.dataset.lrFs = disp === '' ? '1' : '0';

    if (disp === "") {
      visibleCount++;
    }
  }

  // Always paginate (all tables have pagination now)
  table.dataset.currentPage = 1;
  lr_paginate(table);

  // Reattach wrapper — triggers exactly one reflow
  if (tableSibling) {
    tableParent.insertBefore(wrapper, tableSibling);
  } else {
    tableParent.appendChild(wrapper);
  }

  console.timeEnd("filter") ;
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
  const col = target && target.dataset.col ? target.dataset.col : el.getAttribute("data-col");
  const filterinp = table.querySelector('input[data-col="'+col+'"]');
  if ( filterinp ) {
    filterinp.value = filtertext;
    dochangefilter(el);
  }
}

function fieldclick_word(event, el, col) {
  var token = el.textContent;
  token = token.replace(/[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß -]/g, '');
  if ( !token ) return;

  const table = el.closest('table');
  const filterinp = table.querySelector('input[data-col="' + col + '"]');
  if ( filterinp ) {
    if ( filterinp.value ) {
      filterinp.value += ' ' + token;
    } else {
      filterinp.value = token;
    }
    dochangefilter(el);
  }
}

function fieldclick_cell(event, el, col) {
  var text = el.textContent;
  text = text.replace(/\s+/g, ' ').trim();
  text = text.replace(/[^a-zA-Z0-9ñÑåÅæÆøØöÖäÄéÉáÁāĀüÜß -]/g, '');
  if ( !text ) return;

  const table = el.closest('table');
  const filterinp = table.querySelector('input[data-col="' + col + '"]');
  if ( filterinp ) {
    filterinp.value = text;
    dochangefilter(el);
  }
}

function lr_clearfilters(el) {
  const wrapper = el.closest('[data-lr-wrapper]');
  const table = wrapper.querySelector('table');
  table.querySelectorAll('thead td input[data-col]').forEach(inp => { inp.value = ''; });
  const first = table.querySelector('thead input[data-col]');
  if (first) dochangefilter(first);
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
}

function lr_updateInfo(table, currPage, totalVisible, totalPages) {
  const wrapper = table.closest('[data-lr-wrapper]');
  if (!wrapper) return;
  const pageSize = parseInt(table.dataset.pageSize);

  // Update count on first line
  const countSpan = wrapper.querySelector('.lr-count');
  if (countSpan) {
    const grandTotal = table.tBodies.length;
    countSpan.textContent = totalVisible < grandTotal ? totalVisible + '/' + grandTotal + ' ' : grandTotal + ' ';
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
  dochangefilter(input);
  var vis = Array.from(table.tBodies).filter(function(t){return t.style.display !== 'none';});
  if (vis.length === 0) {
    input.value = '';
    dochangefilter(input);
  }
}
