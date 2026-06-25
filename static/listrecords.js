// listrecords helpers
// These manage filtering and sorting of lists created by listrecords

let filterTimeout;

function changefilter (inputElement) {
  clearTimeout(filterTimeout); // Cancel previous timeout
  filterTimeout = setTimeout(() => {
    dochangefilter(inputElement);
  }, 150); // Adjust delay as needed}
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
  
  // Check if user has already expanded the list ("More..." link is hidden)
  const maxRecords = parseInt(table.dataset.maxrecords) || 0;
  const moreLink = table.nextElementSibling;
  const wasExpanded = moreLink && moreLink.tagName === 'DIV' && 
                      moreLink.querySelector('a[onclick*="showMoreRecords"]') &&
                      moreLink.style.display === 'none';
  
  // Detach table from DOM — all subsequent mutations have zero reflow cost
  const tableParent = table.parentNode;
  const tableSibling = table.nextSibling;
  tableParent.removeChild(table);

  // Clear all hidden attributes to process all records
  const hiddenTbodies = table.querySelectorAll('tbody[hidden]');
  for (const tbody of hiddenTbodies) {
    tbody.removeAttribute('hidden');
  }
  
  const firstrows = table.querySelectorAll('tbody tr[data-first]');
  let visibleCount = 0;
  
  for (let r = 0; r < firstrows.length; r++) {
    var disp = "";
    let row = firstrows[r];
    do {
      const cols = row.querySelectorAll('td');
      for (let c = 0; c < cols.length; c++) {
        const colEls = cols[c].querySelectorAll('[data-col]');
        if (!colEls.length) continue;
        for (let ce = 0; ce < colEls.length; ce++) {
          const col = colEls[ce].getAttribute('data-col');
          if ( col && filters[col] && filters[col].length > 0 ) {
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
      row = row.nextElementSibling;
    } while ( row && ! row.hasAttribute("data-first") );
    
    firstrows[r].closest('tbody').style.display = disp;
    
    if (disp === "") {
      visibleCount++;
    }
  }
  
  // If list wasn't expanded and we have maxRecords limit, hide beyond top N
  if (!wasExpanded && maxRecords > 0) {
    let recordCount = 0;
    const tbodies = table.tBodies;
    for (let t = 0; t < tbodies.length; t++) {
      if (tbodies[t].style.display !== "none") {
        recordCount++;
        if (recordCount > maxRecords) {
          tbodies[t].setAttribute('hidden', '');
        }
      }
    }
  }

  // Reattach table — triggers exactly one reflow
  if (tableSibling) {
    tableParent.insertBefore(table, tableSibling);
  } else {
    tableParent.appendChild(table);
  }

  // Show/hide the "More..." link
  if (moreLink) {
    if (!wasExpanded && maxRecords > 0 && visibleCount > maxRecords) {
      moreLink.style.display = '';
    } else {
      moreLink.style.display = 'none';
    }
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

function clearfilters(el) {
  // Get the filters
  const table = el.closest('table');
  const filters = table.querySelectorAll('thead td input[data-col]');
  for ( let i=0; i<filters.length; i++) {
    const filterinp = filters[i];
    if ( filterinp ) {
      filterinp.value = '';
    }
  }
  dochangefilter(el);
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

  // Check if user has already expanded the list ("More..." link is hidden)
  const maxRecords = parseInt(table.dataset.maxrecords) || 0;
  const moreLink = table.nextElementSibling;
  const wasExpanded = moreLink && moreLink.tagName === 'DIV' && 
                      moreLink.querySelector('a[onclick*="showMoreRecords"]') &&
                      moreLink.style.display === 'none';
  
  // Detach table from DOM — all subsequent DOM mutations have zero reflow cost
  const tableParent = table.parentNode;
  const tableSibling = table.nextSibling;
  tableParent.removeChild(table);

  // Unhide all tbodies
  const hiddenTbodies = table.querySelectorAll('tbody[hidden]');
  for (const tbody of hiddenTbodies) {
    tbody.removeAttribute('hidden');
  }

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

  // Re-hide tbodies beyond maxRecords only if list wasn't already expanded
  if (!wasExpanded && maxRecords > 0) {
    let recordCount = 0;
    for (const tbody of table.tBodies) {
      recordCount++;
      if (recordCount > maxRecords) {
        tbody.setAttribute('hidden', '');
      }
    }
  }
  // If was expanded, keep it expanded (moreLink stays hidden)

  // Reattach table — triggers exactly one reflow
  if (tableSibling) {
    tableParent.insertBefore(table, tableSibling);
  } else {
    tableParent.appendChild(table);
  }

  // Show/hide the "More..." link
  if (moreLink) {
    if (!wasExpanded && maxRecords > 0) {
      moreLink.style.display = '';
    } else {
      moreLink.style.display = 'none';
    }
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

// Show more records by removing the hidden attribute from all hidden TR elements
function showMoreRecords(link) {
  const moreDiv = link.parentElement;
  const table = moreDiv.previousElementSibling;
  
  if (table && table.tagName === 'TABLE') {
    // Detach table from DOM — mutations have zero reflow cost
    const tableParent = table.parentNode;
    const tableSibling = table.nextSibling;
    tableParent.removeChild(table);

    const hiddenTbodies = table.querySelectorAll('tbody[hidden]');
    for (const tbody of hiddenTbodies) {
      tbody.removeAttribute('hidden');
    }

    // Reattach table — triggers one reflow
    if (tableSibling) {
      tableParent.insertBefore(table, tableSibling);
    } else {
      tableParent.appendChild(table);
    }

    moreDiv.style.display = 'none';
  }
}
