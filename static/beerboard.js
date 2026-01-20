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
  var allExpandeds = document.querySelectorAll('[class^="expanded_"]');
  var anyVisible = Array.from(allExpandeds).some(row => row.style.display === 'table-row');
  document.getElementById('expand-all').style.display = anyVisible ? 'block' : 'none';
}

function expandAll() {
  var compacts = document.querySelectorAll('[id^="compact_"]');
  var expandeds = document.querySelectorAll('[class^="expanded_"]');
  compacts.forEach(function(row) { row.style.display = 'none'; });
  expandeds.forEach(function(row) { row.style.display = 'table-row'; });
  document.getElementById('expand-all').style.display = 'block';
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}

function collapseAll() {
  var compacts = document.querySelectorAll('[id^="compact_"]');
  var expandeds = document.querySelectorAll('[class^="expanded_"]');
  compacts.forEach(function(row) { row.style.display = 'table-row'; });
  expandeds.forEach(function(row) { row.style.display = 'none'; });
  document.getElementById('expand-all').style.display = 'none';
  setTimeout(() => window.scrollTo(0, document.getElementById('beerboard').offsetTop), 10);
}