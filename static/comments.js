// comments.js - JavaScript for the comment editing form
// Depends on glassIsEmpty global set inline by comments.pm before this runs.

function initCommentForm() {
  var showAll = false;
  var entityRows = ['row-person', 'row-brew', 'row-location'];
  var typeToRow = {
    brew:     'row-brew',
    meal:     'row-brew',
    glass:    null,
    night:    null,
    location: 'row-location',
    person:   'row-person'
  };

  function hasValue(rowId) {
    var row = document.getElementById(rowId);
    if (!row) return false;
    var h = row.querySelector(
      'input[type=hidden][name="Location"], input[type=hidden][name="Brew"]');
    if (h && h.value) return true;
    return row.querySelectorAll('input[name=person_id]').length > 0;
  }

  function updateCommentFields() {
    var typeEl = document.getElementById('commenttype');
    var type   = typeEl ? typeEl.value : 'brew';

    // Context row (night/glass read-only text)
    var contextRow = document.getElementById('row-context');
    var nightDisp  = document.getElementById('night-display');
    var glassDisp  = document.getElementById('glass-display');
    if (type === 'night') {
      if (contextRow) contextRow.hidden = false;
      if (nightDisp)  nightDisp.hidden  = false;
      if (glassDisp)  glassDisp.hidden  = true;
    } else if (type === 'glass') {
      if (contextRow) contextRow.hidden = false;
      if (nightDisp)  nightDisp.hidden  = true;
      if (glassDisp)  glassDisp.hidden  = false;
    } else {
      if (contextRow) contextRow.hidden = true;
    }

    // Entity rows: show primary unconditionally, others only if populated or showAll
    // Also always show person row for empty glasses (Night/Meal/Restaurant)
    var primaryRowId = typeToRow[type];
    entityRows.forEach(function (rowId) {
      var row = document.getElementById(rowId);
      if (!row) return;
      var isPersonRow = rowId === 'row-person';
      row.hidden = !(rowId === primaryRowId || showAll || hasValue(rowId) || (isPersonRow && glassIsEmpty));
    });

    // Extra rows revealed by showAll
    if (showAll) {
      ['row-ts', 'row-public'].forEach(function (id) {
        var row = document.getElementById(id);
        if (row) row.hidden = false;
      });
    }
  }

  function showAllCommentFields() {
    showAll = true;
    updateCommentFields();
    var link = document.getElementById('show-all-link');
    if (link) link.hidden = true;
  }

  var showAllLink = document.getElementById('show-all-link');
  if (showAllLink) {
    showAllLink.addEventListener('click', function (e) {
      e.preventDefault();
      showAllCommentFields();
    });
  }

  var ctypeEl = document.getElementById('commenttype');
  if (ctypeEl) {
    ctypeEl.addEventListener('input', updateCommentFields);
    updateCommentFields();
  }
}
