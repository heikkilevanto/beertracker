// listrecords helpers
// These manage filtering and sorting of lists created by listrecords

let filterTimeout;
let filterGeneration = 0;

function changefilter (inputElement) {
  clearTimeout(filterTimeout); // Cancel previous timeout
  filterTimeout = setTimeout(() => {
    dochangefilter(inputElement, ++filterGeneration);
  }, 150); // Adjust delay as needed}
}

function dochangefilter (inputElement, gen) {
  // Find the table from the input's ancestor
  const table = inputElement.closest('table');
  if (!table) return; // should not happen
  console.time("filter") ;

  const filterinputs = table.querySelectorAll('thead input');

  // Get the filters
  let filters = [];
  for ( let i=0; i<filterinputs.length; i++) {
    let filterinp = filterinputs[i];
    if ( filterinp ) {
      const col = filterinp.getAttribute("data-col");
      filterinp.value = filterinp.value.replace(/[▲▼]/,"");
      filters[col] = new RegExp(filterinp.value, 'i')
    }
  }
  const firstrows = table.querySelectorAll('tbody tr[data-first]');
  for (let r = 0; r < firstrows.length; r++) {
    if (gen !== filterGeneration) {
      console.log("Filtering aborted");
      console.timeEnd("filter");
      return;
    }
    var disp = ""; // default to showing the row
    let row = firstrows[r];
    do {
      const cols = row.querySelectorAll('td');
      for (let c = 0; c < cols.length; c++) {
        const col = cols[c].getAttribute('data-col');
        if ( col ) {
          if ( filters[col] ) {
            const re = filters[col];
            if ( !re.test( cols[c].textContent, 'i' ) ) {
              disp = "none";
              break;
            }
          }
        }
      }
      row = row.nextElementSibling;
    } while ( row && ! row.hasAttribute("data-first") );
    let ro = firstrows[r];
    do {
      ro.style.display = disp;
      ro = ro.nextElementSibling;
    } while ( ro && ! ro.hasAttribute("data-first") );

  }
  console.timeEnd("filter") ;

}

// Clicking on a data field sets the filter
function fieldclick(el,index) {
  var filtertext = el.textContent;
  filtertext = filtertext.replace( /\[|\]/g , ""); // Remove brackets [Beer,IPA]
  filtertext = filtertext.replace( /^.*(20[0-9-]+) .*\$/ , "\$1"); // Just the date
    // Note the double escapes, since this is still a perl string

  // Get the filters
  const table = el.closest('table');
  const col = el.getAttribute("data-col");
  const filterinp = table.querySelector('input[data-col="'+col+'"]');
  if ( filterinp ) {
    filterinp.value = filtertext;
    dochangefilter(el,++filterGeneration);
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
  dochangefilter(el,++filterGeneration);
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

  // Clear arrows
  for (let th of table.querySelectorAll('thead input ') ) {
    th.value = th.value.replace(/[▲▼]/,"").trim();
  }

  el.value = ascending ? " ▲" : " ▼" ;

  table.dataset.sortCol = col;
  table.dataset.sortDir = ascending ? "desc" : "asc";

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
        text = text.replace( /\]\$/, "");
        if ( isNaN(text) || ! text) {
          text = text.toLowerCase().trim();
        } else {
          text = parseFloat(text);
        }
        //console.log("sortkey for col " + columnIndex + " of '" + cell.textContent + "' is '" + text + "' m=" + match);
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
