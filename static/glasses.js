// glasses.js - JavaScript for the glass input form

function selbrewchange(hiddenInput, clearTap) {
  // Clear tap number — brew type changed (but not on initial page load)
  if (clearTap) {
    const tapInput = document.querySelector('[name=tap]');
    if (tapInput) tapInput.value = '';
  }
  const val = hiddenInput.value;
  // Find the matching dropdown-item div to read data-isempty
  const dd = document.getElementById('dropdown-selbrewtype');
  const item = dd ? dd.querySelector('.dropdown-item[id="' + val + '"]') : null;
  const isempty = item ? item.getAttribute('data-isempty') : null;
  const table = hiddenInput.closest('table');
  if (!table) return;
  for ( const td of table.querySelectorAll("[data-empty]") ) {
    const te = td.getAttribute("data-empty");
    if ( te == 1 ) {
      if ( isempty )
        td.style.display = 'none';
      else
        td.style.display = '';
    } else if ( te == 2 ) {
        if ( isempty )
          td.style.display = '';
        else
          td.style.display = 'none';
      }
    else if ( te ) {
      if ( te == val )
          td.style.display = '';
        else
          td.style.display = 'none';
    }
  }
  // Clear subtype when brew type changes (but not on initial load)
  if (clearTap) {
    const subtypeHidden = document.getElementById('selbrewsubtype');
    if (subtypeHidden) setDropdownValue(subtypeHidden, '');
  }

  // Prefill subtype from location when changing to Restaurant
  if (val === "Restaurant") {
    const locDropdown = document.getElementById("dropdown-Location");
    if (locDropdown) {
      const locHidden = locDropdown.querySelector("input[type=hidden]");
      if (locHidden && locHidden.value) {
        const locItems = locDropdown.querySelectorAll(".dropdown-item");
        locItems.forEach(item => {
          if (item.id === locHidden.value) {
            const locsubtype = item.getAttribute("locsubtype");
            const selbrewsubtype = document.getElementById("selbrewsubtype");
            if (selbrewsubtype && locsubtype) {
              setDropdownValue(selbrewsubtype, locsubtype);
            }
          }
        });
      }
    }
  }
}

function clearinputs() {  // Clear all inputs, used by the 'clear' button
  var inputs = document.getElementsByTagName('input');  // all regular input fields
  for (var i = 0; i < inputs.length; i++ ) {
    if ( inputs[i].type == "text" )
      inputs[i].value = "";
  }
}

function setdate() {  // Set date and time, if not already set by the user
  const dis = document.getElementsByName("date");
  const tis = document.getElementsByName("time");
  const now = new Date();
  for ( const di of dis ) {
    if ( di.value && di.value.startsWith(" ") ) {
      const year = now.getFullYear();
      const month = String(now.getMonth() + 1).padStart(2, '0'); // Zero-padded month
      const day = String(now.getDate()).padStart(2, '0'); // Zero-padded day
      const dat = `${year}-${month}-${day}`;
      di.value = " " + dat;
    }
  }
  for ( const ti of tis ) {
    if ( ti.value && ti.value.startsWith(" ") ) {
      const hh = String(now.getHours()).padStart(2, '0');
      const mm = String(now.getMinutes()).padStart(2, '0');
      const tim = `${hh}:${mm}`;
      ti.value = " " + tim;
    }
  }
}

function shownote() {
  const noteline = document.getElementById("noteline");
  noteline.hidden = false;
  const toggle = document.getElementById("notetag");
  toggle.hidden = true;
  const leftcol = document.getElementById("leftcol");
  leftcol.innerHTML = '<input type="checkbox" name="setdef" />Def';
}

function editrecord() {  // Switch form to edit mode for the current record in-place
  const dateInput = document.getElementById('date');
  const timeInput = document.getElementById('time');
  const tapInput = document.querySelector('[name=tap]');
  const noteInput = document.querySelector('[name=note]');
  dateInput.value = dateInput.dataset.rawval;
  timeInput.value = timeInput.dataset.rawval;
  tapInput.value = tapInput.dataset.rawval;
  noteInput.value = noteInput.dataset.note ?? '';
  shownote();
  document.getElementById('edit-e').disabled = false;
  document.getElementById('new-buttons').style.display = 'none';
  document.getElementById('edit-buttons').style.display = '';
  document.getElementById('new-buttons-right').style.display = 'none';
  document.getElementById('edit-buttons-right').style.display = '';
}

function initGlassForm() {
  setdate();

  // If noteline is already shown (editing with note), set the labels
  if (!document.getElementById("noteline").hidden) {
    document.getElementById("leftcol").innerHTML = '<input type="checkbox" name="setdef" />Def';
  }

  // hide newBrewType, we use SelBrewType always
  var nbt = document.getElementsByName("newbrewBrewType");
  if ( nbt.length > 0 ) {
    nbt[0].hidden = true;
    var br = nbt[0].nextElementSibling;
    br.hidden = true;
  }

  // Clear tap when brew or location changes
  ['Brew', 'Location'].forEach(function(name) {
    const hidden = document.getElementById(name);
    if (hidden) {
      hidden.addEventListener('input', function() {
        const tapInput = document.querySelector('[name=tap]');
        if (tapInput) tapInput.value = '';
      });
    }
  });

  // Wire selbrewchange to the hidden input's input event
  const selbrewtypeHidden = document.getElementById('selbrewtype');
  if (selbrewtypeHidden) {
    selbrewtypeHidden.addEventListener('input', function() {
      selbrewchange(selbrewtypeHidden, true);
    });
    selbrewchange(selbrewtypeHidden, false); // run once on load to set initial visibility
  }
}
