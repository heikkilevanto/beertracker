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
  
  // Temporarily clear all hidden attributes to process all rows
  const hiddenRows = table.querySelectorAll('tr[hidden]');
  hiddenRows.forEach(row => {
    row.removeAttribute('hidden');
  });
  
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
    
    let ro = firstrows[r];
    do {
      ro.style.display = disp;
      ro = ro.nextElementSibling;
    } while ( ro && ! ro.hasAttribute("data-first") );
    
    if (disp === "") {
      visibleCount++;
    }
  }
  
  // If list wasn't expanded and we have maxRecords limit, hide beyond top N
  if (!wasExpanded && maxRecords > 0) {
    let recordCount = 0;
    for (let r = 0; r < firstrows.length; r++) {
      if (firstrows[r].style.display !== "none") {
        recordCount++;
        if (recordCount > maxRecords) {
          let currentRow = firstrows[r];
          do {
            currentRow.setAttribute('hidden', '');
            currentRow = currentRow.nextElementSibling;
          } while (currentRow && currentRow.dataset.first !== "1");
        }
      }
    }
    if (moreLink && visibleCount > maxRecords) {
      moreLink.style.display = '';
    } else if (moreLink) {
      moreLink.style.display = 'none';
    }
  } else if (moreLink) {
    moreLink.style.display = 'none';
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
  const tbody = table.tBodies[0];
  const columnIndex = col;

  console.time("sort") ;

  // Check if user has already expanded the list ("More..." link is hidden)
  const maxRecords = parseInt(table.dataset.maxrecords) || 0;
  const moreLink = table.nextElementSibling;
  const wasExpanded = moreLink && moreLink.tagName === 'DIV' && 
                      moreLink.querySelector('a[onclick*="showMoreRecords"]') &&
                      moreLink.style.display === 'none';
  
  // Temporarily unhide all rows for sorting
  const hiddenRows = table.querySelectorAll('tr[hidden]');
  hiddenRows.forEach(row => {
    row.removeAttribute('hidden');
  });

  // Detach tbody
  const parent = tbody.parentNode;
  parent.removeChild(tbody);

  // Group rows into records
  const rows = Array.from(tbody.rows);
  const records = [];
  let currentRecord = [];

  for (const row of rows) {
      if (row.dataset.first === "1") {
          if (currentRecord.length) records.push(currentRecord);
          currentRecord = [row];
      } else {
          currentRecord.push(row);
      }
  }
  if (currentRecord.length) records.push(currentRecord);

  // Precompute sort keys
  const sortableRecords = records.map(record => {
    const key = extractSortKey(record, columnIndex);
    return { key, record };
  });


  // Sort the cached records
  sortableRecords.sort((a, b) => {
      if (a.key === "" ) return 1;
      if (b.key === "" ) return -1;
      if (a.key < b.key) return ascending ? -1 : 1;
      if (a.key > b.key) return ascending ? 1 : -1;
      return 0;
  });

  // Rebuild tbody
  tbody.innerHTML = "";
  for (const { record } of sortableRecords) {
      for (const row of record) {
          tbody.appendChild(row);
      }
  }

  // Reattach tbody
  parent.appendChild(tbody);

  // Re-hide rows beyond maxRecords only if list wasn't already expanded
  if (!wasExpanded && maxRecords > 0) {
    const allRecords = tbody.querySelectorAll('tr[data-first="1"]');
    let recordCount = 0;
    allRecords.forEach(row => {
      recordCount++;
      if (recordCount > maxRecords) {
        // Hide this record and any continuation rows
        let currentRow = row;
        do {
          currentRow.setAttribute('hidden', '');
          currentRow = currentRow.nextElementSibling;
        } while (currentRow && currentRow.dataset.first !== "1");
      }
    });
    // Show the "More..." link again
    if (moreLink) {
      moreLink.style.display = '';
    }
  }
  // If was expanded, keep it expanded (moreLink stays hidden)

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
  // Find the table before this link
  const moreDiv = link.parentElement;
  const table = moreDiv.previousElementSibling;
  
  if (table && table.tagName === 'TABLE') {
    const hiddenRows = table.querySelectorAll('tr[hidden]');
    hiddenRows.forEach(row => {
      row.removeAttribute('hidden');
    });
    
    // Remove the "More..." link after revealing all rows
    moreDiv.style.display = 'none';
  }
}
