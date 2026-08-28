// mainlist.pm adjustment-form behavior. Loaded with `defer` so the DOM exists.

// Toggle visibility of the adjustment form for a given row.
function toggleAdjForm(formId) {
  var form = document.getElementById('adjform_' + formId);
  if (form) {
    form.style.display = form.style.display === 'none' ? 'inline' : 'none';
  }
}

// Compute diff/percentage and stash into hidden fields before submit.
function updateAdjustment(formId, expected) {
  var actualInput = document.getElementById('actualpaid_' + formId);
  var actual = parseFloat(actualInput.value) || 0;
  var diff = actual - expected;
  document.getElementById('pr_' + formId).value = diff;
  var pct = expected > 0 ? Math.round((diff / expected) * 100) : 0;
  document.getElementById('note_' + formId).value =
    'Expected: ' + expected + '.-, Paid: ' + actual + '.-, Diff: ' + diff + '.- =' + pct + '%';
  document.getElementById('subtype_' + formId).value = diff >= 0 ? 'Up' : 'Dn';
  return true;
}

// Wire the last table's click to toggle its adjustment form.
function initAdjForm(formId) {
  var tables = document.querySelectorAll('table');
  var lastTable = tables[tables.length - 1];
  if (!lastTable) return;
  lastTable.style.cursor = 'pointer';
  lastTable.onclick = function() { toggleAdjForm(formId); };
}
