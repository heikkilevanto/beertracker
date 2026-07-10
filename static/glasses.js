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
  const georow = document.getElementById("georow");
  if (georow) georow.hidden = false;
  const toggle = document.getElementById("notetag");
  toggle.hidden = true;
  const leftcol = document.getElementById("leftcol");
  leftcol.innerHTML = '<input type="checkbox" name="setdef" />Def';
}

function updateGeoFromLocation() {
  const locId = document.getElementById('Location').value;
  const latInput = document.getElementById('geoLat');
  const lonInput = document.getElementById('geoLon');
  const updateCheck = document.getElementById('updateGeo');
  if (!latInput || !lonInput || !updateCheck) return;
  if (!locId || !navigator.geolocation) return;

  navigator.geolocation.getCurrentPosition(
    function(pos) {
      var lat = pos.coords.latitude.toFixed(6);
      var lon = pos.coords.longitude.toFixed(6);
      latInput.value = lat;
      lonInput.value = lon;

      // Also fill new-location lat/lon if those fields exist
      var newlocLat = document.getElementById('newlocLat');
      var newlocLon = document.getElementById('newlocLon');
      if (newlocLat) newlocLat.value = lat;
      if (newlocLon) newlocLon.value = lon;

      var hasCoords = false;
      if (locId !== 'new') {
        var dropdown = document.getElementById('dropdown-Location');
        if (dropdown) {
          var item = dropdown.querySelector('.dropdown-item[id="' + locId + '"]');
          if (item) {
            var span = item.querySelector('span[lat]');
            hasCoords = span && span.getAttribute('lat') && span.getAttribute('lon');
          }
        }
      }
      updateCheck.checked = !hasCoords;
      latInput.disabled = hasCoords;
      lonInput.disabled = hasCoords;
    },
    function(err) { console.log("Geo Error: " + err.message); }
  );
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

  // If noteline is already shown (editing with note), set the labels and show georow
  if (!document.getElementById("noteline").hidden) {
    document.getElementById("leftcol").innerHTML = '<input type="checkbox" name="setdef" />Def';
    var georow = document.getElementById("georow");
    if (georow) georow.hidden = false;
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

  // Update geo fields when location changes
  const locHidden = document.getElementById('Location');
  if (locHidden) {
    locHidden.addEventListener('input', updateGeoFromLocation);
  }

  // Propagate current selbrewtype to the newbrew sub-form's BrewType dropdown
  const brewHidden = document.getElementById('Brew');
  if (brewHidden) {
    brewHidden.addEventListener('input', function() {
      if (this.value === 'new') {
        const src = document.getElementById('selbrewtype');
        const tgt = document.getElementById('BrewType');
        if (src && tgt && src.value) setDropdownValue(tgt, src.value);
      }
    });
  }

  // Cascading for BrewType/SubType in the newbrew sub-form
  (function() {
    var bt = document.getElementById('BrewType');
    var st = document.getElementById('dropdown-SubType');
    if (!bt || !st) return;
    var localBt = document.createElement('input');
    localBt.type = 'hidden';
    localBt.setAttribute('data-brewtype-scope', '1');
    st.appendChild(localBt);
    function syncSubType() {
      localBt.value = bt.value;
      var flt = st.querySelector('.dropdown-filter');
      var lst = st.querySelector('.dropdown-list');
      if (flt && lst) filterItems(flt, lst);
    }
    bt.addEventListener('input', syncSubType);
    syncSubType();
  })();

  // Wire selbrewchange to the hidden input's input event
  const selbrewtypeHidden = document.getElementById('selbrewtype');
  if (selbrewtypeHidden) {
    selbrewtypeHidden.addEventListener('input', function() {
      selbrewchange(selbrewtypeHidden, true);
      // Re-filter the brew dropdown to show only matching brew types
      const brewDropdown = document.getElementById('dropdown-Brew');
      if (brewDropdown) {
        // Sync any scoped brewtype value inside the brew dropdown (from the
        // newbrew sub-form's SubType cascade) so filterItems uses the right type.
        const scoped = brewDropdown.querySelector('[data-brewtype-scope]');
        if (scoped) scoped.value = selbrewtypeHidden.value;
        const brewFilter = brewDropdown.querySelector('.dropdown-filter');
        const brewList = brewDropdown.querySelector('.dropdown-list');
        if (brewFilter && brewList) filterItems(brewFilter, brewList);
      }
    });
    selbrewchange(selbrewtypeHidden, false); // run once on load to set initial visibility
  }

  // Disable lat/lon inputs when checkbox is unchecked, enable when checked
  function syncGeoDisabled() {
    var cb = document.getElementById('updateGeo');
    var lat = document.getElementById('geoLat');
    var lon = document.getElementById('geoLon');
    if (!cb || !lat || !lon) return;
    lat.disabled = !cb.checked;
    lon.disabled = !cb.checked;
  }
  var updateCb = document.getElementById('updateGeo');
  if (updateCb) {
    updateCb.addEventListener('change', syncGeoDisabled);
    syncGeoDisabled(); // initial state before GPS responds
  }

  // Autofill geo from GPS on page load if a location is already selected
  // (syncGeoDisabled is called again inside the GPS callback after checkbox is set)
  updateGeoFromLocation();
}
