function toggleBeer(id) {
  var compact = document.getElementById('compact_' + id);
  var expanded = document.querySelectorAll('.expanded_' + id);
  if (compact.style.display === 'none') {
    compact.style.display = 'table-row';
    expanded.forEach(function(row) { row.style.display = 'none'; });
  } else {
    compact.style.display = 'none';
    expanded.forEach(function(row) { row.style.display = 'table-row'; });
  }
  var allExpandeds = document.querySelectorAll('[class*="expanded_"]');
  var anyVisible = Array.from(allExpandeds).some(row => row.style.display === 'table-row');
  document.getElementById('expand-all').style.display = anyVisible ? 'block' : 'none';
}

function expandAll() {
  var compacts = document.querySelectorAll('[id^="compact_"]');
  var expandeds = document.querySelectorAll('[class*="expanded_"]');
  compacts.forEach(function(row) { row.style.display = 'none'; });
  expandeds.forEach(function(row) { row.style.display = 'table-row'; });
  document.getElementById('expand-all').style.display = 'block';
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}

function collapseAll() {
  var compacts = document.querySelectorAll('[id^="compact_"]');
  var expandeds = document.querySelectorAll('[class*="expanded_"]');
  compacts.forEach(function(row) { row.style.display = 'table-row'; });
  expandeds.forEach(function(row) { row.style.display = 'none'; });
  document.getElementById('expand-all').style.display = 'none';
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}

// Toggle the collapsible controls section (#board-controls)
function toggleControls() {
  var ctrl = document.getElementById('board-controls');
  if (ctrl) {
    ctrl.style.display = (ctrl.style.display === 'none') ? 'block' : 'none';
  }
}

// Tokenize filter input (reusing the shared filter-utils.js logic)
function tokenizeFilterInput(value) {
  if (typeof _tokenizeFilterInput === 'function') {
    return _tokenizeFilterInput(value);
  }
  return value.trim().split(/\s+/).filter(t => t);
}

// Build a searchable haystack from a row's data attributes
function rowHaystack(row) {
  return (row.getAttribute('data-style') || '') + ' ' +
         (row.getAttribute('data-maker') || '') + ' ' +
         (row.getAttribute('data-name') || '') + ' ' +
         (row.getAttribute('data-brewtype') || '');
}

// Apply a client-side filter to the beer board rows.
// Each token must match (AND logic) at least one of the data attributes.
// Empty query restores all rows to their initial server-rendered display state.
// Rows that were auto-expanded (initial display none) stay hidden when matched.
function applyBoardFilter(query) {
  var rows = document.querySelectorAll('#beerboard tr[id^="compact_"]');
  var tokens = tokenizeFilterInput(query || "");
  rows.forEach(function(row) {
    var id = row.id.replace('compact_', '');
    var initialDisplay = row.dataset.initialDisplay || 'table-row';
    var matched = !tokens.length || tokens.every(function(token) {
      return rowHaystack(row).toLowerCase().indexOf(token.toLowerCase()) !== -1;
    });
    if (matched) {
      // Restore to initial state (may be 'none' for auto-expanded beers)
      row.style.display = initialDisplay;
    } else {
      row.style.display = 'none';
      // Hide expanded rows for hidden beers
      document.querySelectorAll('.expanded_' + id).forEach(function(r) {
        r.style.display = 'none';
      });
    }
  });
  // Update expand-all visibility
  var allExpandeds = document.querySelectorAll('[class*="expanded_"]');
  var anyVisible = Array.from(allExpandeds).some(r => r.style.display === 'table-row');
  var ea = document.getElementById('expand-all');
  if (ea) ea.style.display = anyVisible ? 'block' : 'none';
}

// Open the controls section and apply a filter
function openControlsAndFilter(query) {
  var ctrl = document.getElementById('board-controls');
  if (ctrl) ctrl.style.display = 'block';
  var filterInput = document.getElementById('board-filter');
  if (filterInput) filterInput.value = query || '';
  applyBoardFilter(query);
}

// Apply the PA (Pale Ale / IPA) filter — sets filter text to "PA"
function applyPAFilter() {
  openControlsAndFilter('PA');
}

// Clear the board filter and show all rows (restoring initial display state)
function clearBoardFilter() {
  var filterInput = document.getElementById('board-filter');
  if (filterInput) filterInput.value = '';
  applyBoardFilter('');
}

// Wire up the filter input for live filtering
document.addEventListener('DOMContentLoaded', function() {
  // Store initial display state for each compact row (handles auto-expanded beers)
  var compactRows = document.querySelectorAll('#beerboard tr[id^="compact_"]');
  compactRows.forEach(function(row) {
    row.dataset.initialDisplay = row.style.display || 'table-row';
  });

  var filterInput = document.getElementById('board-filter');
  if (filterInput) {
    filterInput.addEventListener('input', function() {
      applyBoardFilter(this.value);
    });
  }
});

// Schedule a background POST of the board-controls form a few seconds after load,
// so server-side filtering/state updates happen without blocking the page.
function scheduleBackgroundUpdate(formId, url) {
  setTimeout(function() {
    var form = document.getElementById(formId);
    if (!form) return;
    fetch(url, {
      method: 'POST',
      body: new FormData(form)
    }).then(function(response) {
      if (response.ok) {
        console.log('Background update completed successfully');
      } else {
        console.error('Background update failed with status', response.status);
      }
    }).catch(function(error) {
      console.error('Background update error:', error);
    });
  }, 3000);
}
