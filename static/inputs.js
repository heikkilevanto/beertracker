// inputs.js

// Compute a short name from a location/brew name.
// Mirrors beerboard::compute_short_location_name in beerboard.pm.
// Returns the shortened string, or null if no shortening applies.
function computeShortName(name) {
  if (!name) return null;
  var short = name;
  short = short.replace(/\b(the|brouwerij|brasserie|van|den|Bräu|Brauerei)\b/gi, '');
  short = short.replace(/.*(Schneider).*/i, '$1');
  short = short.replace(/ &amp; /g, '&amp;');
  short = short.replace(/ & /g, '&');
  short = short.replace(/^ +/, '');
  short = short.replace(/[ -].*$/, '');
  if (short === name) return null;
  return short;
}

// Dropdown with filtering and (new)

// Set a dropdown's value (hidden input) and its visible filter display in one step.
// Works for both plain text inputs and dropdown hidden inputs.
// Dispatches an 'input' event on the hidden input so propagation listeners fire.
function setDropdownValue(inp, val) {
  if (!inp) return;
  inp.value = val;
  const filterDisp = inp.closest?.('.dropdown-main')?.querySelector('.dropdown-filter');
  if (filterDisp) { filterDisp.value = val; filterDisp.oldvalue = val; }
  inp.dispatchEvent(new Event('input'));
}

// Tags chip input widget (issue 624)
function initTagsInput(container) {
  if (!container) return;
  const currentDiv  = container.querySelector('.tags-current');
  const availableDiv = container.querySelector('.tags-available');
  const hiddenInput = container.querySelector('input[type=hidden][name=Tags]');
  const newBtn      = container.querySelector('.tag-new-btn');
  const newField    = container.querySelector('.tags-new-field');
  const newInput    = container.querySelector('.tags-new-input');
  const addBtn      = container.querySelector('.tags-add-btn');

  // Delegated remove-chip handler — covers pre-rendered and dynamically added chips
  currentDiv.addEventListener('click', (e) => {
    const removeLink = e.target.closest('.chip-remove');
    if (!removeLink) return;
    e.preventDefault();
    const wrapper = removeLink.closest('.chip-wrapper');
    const tag = wrapper.querySelector('.chip-label').textContent.trim();
    wrapper.remove();
    refreshBreaks(currentDiv, '.chip-wrapper', 5);
    // Re-enable corresponding available chip
    if (availableDiv) {
      const avChip = availableDiv.querySelector(`.tag-available-chip[data-tag="${tag}"]`);
      if (avChip) avChip.classList.remove('used');
    }
  });

  // Click on an available chip → add to current chips
  if (availableDiv) {
    availableDiv.addEventListener('click', (e) => {
      const chip = e.target.closest('.tag-available-chip');
      if (!chip || chip.classList.contains('tag-new-btn') || chip.classList.contains('used')) return;
      const tag = chip.getAttribute('data-tag');
      addCurrentChip(tag);
      chip.classList.add('used');
    });
  }

  // (New tag) chip → reveal text input
  if (newBtn && newField) {
    newBtn.addEventListener('click', () => {
      newField.hidden = false;
      if (newInput) newInput.focus();
    });
  }

  // Commit a new tag from the free-text input
  function commitNewTag() {
    if (!newInput) return;
    const tag = newInput.value.trim().replace(/^#+/, '').toLowerCase();
    if (!tag) return;
    const existing = Array.from(currentDiv.querySelectorAll('.chip-label'))
      .map(el => el.textContent.trim().toLowerCase());
    if (!existing.includes(tag)) {
      addCurrentChip(tag);
      // Grey out in available if it happens to exist there
      if (availableDiv) {
        const avChip = availableDiv.querySelector(`.tag-available-chip[data-tag="${tag}"]`);
        if (avChip) avChip.classList.add('used');
      }
    }
    newInput.value = '';
    if (newField) newField.hidden = true;
  }

  if (addBtn) addBtn.addEventListener('click', commitNewTag);
  if (newInput) {
    newInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter')  { e.preventDefault(); commitNewTag(); }
      if (e.key === 'Escape') { if (newField) newField.hidden = true; newInput.value = ''; }
    });
  }

  // Pre-submit: collect chip labels and write to the hidden Tags input
  const form = container.closest('form');
  if (form && hiddenInput) {
    form.addEventListener('submit', () => {
      const labels = Array.from(currentDiv.querySelectorAll('.chip-label'))
        .map(el => el.textContent.trim())
        .filter(t => t);
      hiddenInput.value = labels.join(' ');
    }, true); // capture phase
  }

  // Helper: create and append a current-tag chip
  function addCurrentChip(tag) {
    const wrapper = document.createElement('span');
    wrapper.className = 'chip-wrapper';
    const chip = document.createElement('span');
    chip.className = 'dropdown-chip';
    const label = document.createElement('span');
    label.className = 'chip-label';
    label.textContent = tag;
    const removeLink = document.createElement('a');
    removeLink.className = 'chip-remove';
    removeLink.href = '#';
    removeLink.textContent = '\u00d7';
    chip.appendChild(label);
    chip.appendChild(removeLink);
    wrapper.appendChild(chip);
    currentDiv.appendChild(wrapper);
    refreshBreaks(currentDiv, '.chip-wrapper', 5);
  }

  // Helper: remove all .tag-line-break elements and re-insert after every nth chip
  function refreshBreaks(div, selector, n) {
    div.querySelectorAll('.tag-line-break').forEach(el => el.remove());
    const items = Array.from(div.querySelectorAll(selector));
    items.forEach((item, i) => {
      if ((i + 1) % n === 0) {
        const br = document.createElement('span');
        br.className = 'tag-line-break';
        item.after(br);
      }
    });
  }
} // initTagsInput

function initDropdown(container) {
  const filterInput   = container.querySelector(".dropdown-filter");
  const hiddenInput   = container.querySelector(".dropdown-main input[type=hidden]");
  const dropdownList  = container.querySelector(".dropdown-list");
  const newDiv        = container.querySelector(".dropdown-new");
  const isMulti       = container.getAttribute('data-multi') === '1';
  const chipsDiv      = container.querySelector('.dropdown-chips');

  // Simplenew: on blur of the simple text input, copy value to hidden+filter and restore view
  if (newDiv && newDiv.getAttribute('data-simplenew') === '1') {
    const simpleInput = newDiv.querySelector('input[type=text]');
    if (simpleInput) {
      simpleInput.addEventListener('blur', () => {
        const val = simpleInput.value.trim();
        setDropdownValue(hiddenInput, val);
        newDiv.hidden = true;
        container.querySelector('.dropdown-main').hidden = false;
      });
    }
  }

  // Delegated removal handler covers both pre-rendered and dynamically added chips
  if (chipsDiv) {
    chipsDiv.addEventListener('click', (e) => {
      const removeBtn = e.target.closest('.chip-remove');
      if (removeBtn) {
        e.preventDefault();
        removeBtn.closest('.chip-wrapper').remove();
      }
    });
  }

  // Select item
  dropdownList.addEventListener("click", (event) => {
    const item = event.target.closest('.dropdown-item');
    if (!item) return;

    // Check if clicking on an action link (scan/new).
    // Only act if the user clicked directly on a .action-link span, not on padding.
    const actionLink = event.target.closest('.action-link');
    if (actionLink) {
      const action = actionLink.getAttribute('data-action');
      if (action === 'scan') {
        // Start barcode scanning
        scanBarcodeForDropdown(container, filterInput, hiddenInput, dropdownList);
        return;
      } else if (action === 'new') {
        // Show new form
        filterInput.value = '(new)';
        filterInput.oldvalue = "";
        hiddenInput.value = 'new';
        dropdownList.style.display = "none";
        container.querySelector(".dropdown-main").hidden = true;
        if (newDiv) {
          newDiv.hidden = false;
          const inputs = newDiv.querySelectorAll('[data-required="1"]');
          inputs.forEach(inp => {
            if (inp.offsetParent != null) inp.setAttribute("required", "required");
            else inp.removeAttribute("required");
          });
          newDiv.querySelector("input")?.focus();
          // Propagate Country/Region typed in the new-producer sub-form up to the brew fields
          if (hiddenInput.name.match(/ProducerLocation$/i)) {
            const fieldPrefix   = hiddenInput.name.replace(/ProducerLocation$/i, '');
            const newCountryInp = newDiv.querySelector("[name$='Country']");
            const newRegionInp  = newDiv.querySelector("[name$='Region']");
            const targetCountry = document.querySelector("[name='" + fieldPrefix + "Country']");
            const targetRegion  = document.querySelector("[name='" + fieldPrefix + "Region']");
            if (newCountryInp && targetCountry) {
              const propagateCountry = () => { setDropdownValue(targetCountry, newCountryInp.value); };
              newCountryInp.addEventListener('input', propagateCountry);
              newCountryInp.addEventListener('blur',  propagateCountry);
            }
            if (newRegionInp && targetRegion) {
              newRegionInp.addEventListener('input', () => { setDropdownValue(targetRegion, newRegionInp.value); });
            }
          }
        }
        return;
      }
    }

    // Don't treat the actions row as a selectable item
    if (item.id === 'actions') return;

    // Regular item selection
    if (isMulti && chipsDiv) {
      addChip(chipsDiv, hiddenInput, item);
      filterInput.value = '';
      filterInput.oldvalue = '';
      filterItems(filterInput, dropdownList);
    } else {
      applyItemSelection(item, filterInput, hiddenInput, dropdownList);
    }
  });

  // Focus
  filterInput.addEventListener("focus", () => {
    dropdownList.style.display = "block";
    filterInput.oldvalue = filterInput.value;
    filterInput.value = "";
    filterItems(filterInput, dropdownList);
  });

  // Blur
  filterInput.addEventListener("blur", () => {
    if (filterInput.oldvalue) filterInput.value = filterInput.oldvalue;
    setTimeout(() => dropdownList.style.display = "none", 200);
  });

  // Typing
  filterInput.addEventListener("input", () => {
    filterItems(filterInput, dropdownList);
  });

  // Escape
  filterInput.addEventListener("keydown", (event) => {
    if (event.key === "Escape" || event.keyCode === 27) filterInput.blur();
  });
}

  // Scan barcode and filter dropdown
  function scanBarcodeForDropdown(container, filterInput, hiddenInput, dropdownList) {
    const tempInput = document.createElement('input');
    tempInput.type = 'hidden';
    tempInput.id = 'temp-barcode-scan-' + Date.now();
    document.body.appendChild(tempInput);

    let cleanedUp = false;

    function onScanned() {
      if (cleanedUp) return;
      cleanedUp = true;
      clearTimeout(safetyTimer);
      tempInput.removeEventListener('input', onScanned);
      const scannedCode = tempInput.value;
      tempInput.remove();

      const items = Array.from(dropdownList.children);
      const matches = items.filter(item => {
        const itemBarcode = item.getAttribute('barcode');
        return itemBarcode && itemBarcode === scannedCode;
      });

      if (matches.length === 1) {
        applyItemSelection(matches[0], filterInput, hiddenInput, dropdownList);
      } else if (matches.length > 1) {
        items.forEach(item => {
          item.style.display = matches.includes(item) ? '' : 'none';
        });
        filterInput.value = '[' + matches.length + ' matches for ' + scannedCode + ']';
        dropdownList.style.display = 'block';
      } else {
        filterInput.value = 'No brew found with barcode ' + scannedCode;
        setTimeout(() => {
          filterInput.value = '';
          filterInput.focus();
        }, 2000);
      }
    }

    tempInput.addEventListener('input', onScanned);

    const safetyTimer = setTimeout(() => {
      if (!cleanedUp) {
        cleanedUp = true;
        tempInput.removeEventListener('input', onScanned);
        tempInput.remove();
      }
    }, 30000);

    startBarcodeScanning(tempInput.id);
  }

// Add a chip to the chips container for a given dropdown item (deduplicates by id)
function addChip(chipsDiv, hiddenInput, item) {
  const already = Array.from(chipsDiv.querySelectorAll('input[type=hidden]'))
    .some(h => h.value === item.id);
  if (already) return;
  const wrapper = document.createElement('span');
  wrapper.className = 'chip-wrapper';
  const chip = document.createElement('span');
  chip.className = 'dropdown-chip';
  chip.textContent = item.textContent.trim() + ' ';
  const removeBtn = document.createElement('a');
  removeBtn.className = 'chip-remove';
  removeBtn.href = '#';
  removeBtn.textContent = '\u00d7';
  removeBtn.addEventListener('click', (e) => { e.preventDefault(); wrapper.remove(); });
  chip.appendChild(removeBtn);
  const chipHidden = document.createElement('input');
  chipHidden.type = 'hidden';
  chipHidden.name = hiddenInput.name + '_id';
  chipHidden.value = item.id;
  wrapper.appendChild(chip);
  wrapper.appendChild(chipHidden);
  chipsDiv.appendChild(wrapper);
} // addChip

// Apply the side-effects of selecting a dropdown item (used by click and barcode scan)
function applyItemSelection(item, filterInput, hiddenInput, dropdownList) {
  filterInput.value = item.textContent;
  filterInput.oldvalue = "";
  hiddenInput.value = item.id;
  hiddenInput.dispatchEvent(new Event('input'));
  dropdownList.style.display = "none";

  // update alc if present
  const alcinp = document.getElementById("alc");
  const selalc = item.getAttribute("alc");
  if (alcinp && selalc) alcinp.value = selalc + "%";

  // update pr if present
  const prinp = document.getElementById("pr");
  const selpr = item.getAttribute("defprice");
  if (prinp && selpr && selpr.trim()) prinp.value = selpr + ".-";

  // update vol if present
  const volinp = document.getElementById("vol");
  const selvol = item.getAttribute("defvol");
  if (volinp && selvol && selvol.trim()) volinp.value = selvol + "c";

  // update Country and Region from producer (only for ProducerLocation dropdowns)
  if (hiddenInput.name.match(/ProducerLocation$/i)) {
    const fieldPrefix = hiddenInput.name.replace(/ProducerLocation$/i, '');
    const countryinp = document.querySelector("[name='" + fieldPrefix + "Country']");
    const selcountry = item.getAttribute("country");
    if (countryinp && selcountry && !countryinp.value.trim()) setDropdownValue(countryinp, selcountry);
    const regioninp = document.querySelector("[name='" + fieldPrefix + "Region']");
    const selregion = item.getAttribute("region");
    if (regioninp && selregion && !regioninp.value.trim()) setDropdownValue(regioninp, selregion);
  }

  // update subtype if Restaurant brewtype
  const selbrewtype = document.getElementById("selbrewtype");
  const selbrewsubtype = document.getElementById("selbrewsubtype");
  const locsubtype = item.getAttribute("locsubtype");
  if (selbrewtype && selbrewsubtype && locsubtype && selbrewtype.value === "Restaurant") {
    setDropdownValue(selbrewsubtype, locsubtype);
  }

  // show note if generic brew
  if (item.textContent.includes("(Gen)")) {
    const noteline = document.getElementById("noteline");
    if (noteline) noteline.hidden = false;
    const toggle = document.getElementById("notetag");
    if (toggle) toggle.hidden = true;
  }
} // applyItemSelection

// Get or create the tag-suggestion row (prepended to the top of the list)
function getOrCreateTagRow(dropdownList) {
  let tagRow = dropdownList.querySelector('.dropdown-tag-row');
  if (!tagRow) {
    tagRow = document.createElement('div');
    tagRow.className = 'dropdown-tag-row';
    tagRow.id = 'tag-row';
    dropdownList.prepend(tagRow);
  }
  return tagRow;
} // getOrCreateTagRow

// Render tag chips and optional "All of #tag" link into tagRow.
// tagSearch is the lowercased text after '#' (empty string means show all items with any tag).
// A trailing space in tagSearch means exact (case-insensitive) match instead of prefix match.
function renderTagRow(tagRow, tagSearch, dropdownList, filterInput) {
  const container = dropdownList.closest('.dropdown');
  const isMulti   = container && container.getAttribute('data-multi') === '1';
  const chipsDiv  = container && container.querySelector('.dropdown-chips');
  const hiddenInput = container && container.querySelector('.dropdown-main input[type=hidden]');

  // Trailing space triggers exact match; otherwise prefix match
  const isExact = tagSearch.endsWith(' ');
  const searchKey = isExact ? tagSearch.trimEnd() : tagSearch;

  // Collect unique matching tags from all items, in list (recency) order, cap at 8
  const seenTags = new Set();
  const matchingTags = [];
  Array.from(dropdownList.querySelectorAll('.dropdown-item')).forEach(item => {
    if (item.id === 'tag-row' || item.id === 'actions') return;
    const rawTags = (item.getAttribute('tags') || '').trim();
    if (!rawTags) return;
    rawTags.split(/\s+/).forEach(tag => {
      if (!tag) return;
      const tagLower = tag.toLowerCase();
      if (seenTags.has(tagLower)) return;
      if (searchKey === '' || (isExact ? tagLower === searchKey : tagLower.startsWith(searchKey))) {
        seenTags.add(tagLower);
        matchingTags.push(tag);
      }
    });
  });

  tagRow.innerHTML = '';

  // Show "no tags" message when search is non-empty but nothing matches
  if (matchingTags.length === 0 && searchKey !== '') {
    const msg = document.createElement('span');
    msg.className = 'tag-no-match';
    msg.textContent = 'no tags like #' + searchKey;
    tagRow.appendChild(msg);
    return;
  }

  matchingTags.slice(0, 8).forEach(tag => {
    const chip = document.createElement('span');
    chip.className = 'tag-suggestion';
    chip.textContent = '#' + tag;
    chip.addEventListener('mousedown', e => e.preventDefault());
    chip.addEventListener('click', e => {
      e.stopPropagation();
      // Trailing space triggers exact match on this specific tag
      filterInput.value = '#' + tag.toLowerCase() + ' ';
      filterItems(filterInput, dropdownList);
      filterInput.focus();
    });
    tagRow.appendChild(chip);
  });

  // "All of #tag" link — only when exactly one tag matches
  if (matchingTags.length === 1) {
    const tag = matchingTags[0];
    const link = document.createElement('a');
    link.className = 'tag-select-all';
    link.href = '#';
    link.textContent = 'All of #' + tag;
    link.addEventListener('mousedown', e => e.preventDefault());
    link.addEventListener('click', e => {
      e.preventDefault();
      // Use exact match (trailing space) to avoid selecting items from similarly-named tags
      filterInput.value = '#' + tag.toLowerCase() + ' ';
      filterItems(filterInput, dropdownList);
      const visible = Array.from(dropdownList.querySelectorAll('.dropdown-item'))
        .filter(item => item.id !== 'tag-row' && item.id !== 'actions' && item.style.display !== 'none');
      if (isMulti && chipsDiv && hiddenInput) {
        visible.forEach(item => addChip(chipsDiv, hiddenInput, item));
        filterInput.value = '';
        filterInput.oldvalue = '';
        filterItems(filterInput, dropdownList);
      } else if (hiddenInput && visible.length > 0) {
        const first = visible[0];
        filterInput.value = first.textContent.trim();
        filterInput.oldvalue = '';
        hiddenInput.value = first.id;
        dropdownList.style.display = 'none';
      }
    });
    tagRow.appendChild(link);
  }
} // renderTagRow

function filterItems(filterInput, dropdownList) {
  const selbrewtype = document.getElementById("selbrewtype");
  const filter = filterInput.value.toLowerCase();
  const isTagFilter      = filter.startsWith('#');
  const isLocationFilter = !isTagFilter && filter.startsWith('@');
  const isDotFilter      = !isTagFilter && (filter === '.' || filter === '@');
  let searchTerm = filter;

  // Compute country filter value for region dropdowns (data-country-input attribute)
  const dropdownContainer = dropdownList.closest('.dropdown');
  const countryInputName  = dropdownContainer ? dropdownContainer.getAttribute('data-country-input') : null;
  let countryFilterVal = '';
  if (countryInputName) {
    const countryHidden = document.querySelector("input[type=hidden][name='" + countryInputName + "']");
    countryFilterVal = (countryHidden ? countryHidden.value : '').trim().toLowerCase();
  }

  // Manage tag-suggestion row and actions row visibility
  const tagRow     = getOrCreateTagRow(dropdownList);
  const actionsItem = dropdownList.querySelector('[id="actions"]');
  if (isTagFilter) {
    if (actionsItem) actionsItem.style.display = 'none';
    tagRow.style.display = '';
    renderTagRow(tagRow, filter.substring(1), dropdownList, filterInput);
  } else {
    tagRow.style.display = 'none';
    // actionsItem visibility is handled by the normal text-match pass below
  }

  // If user types just a dot or @, use the current selected location
  if (isDotFilter) {
    const locationInput = document.querySelector('input[name="Location"][type="hidden"]');
    if (locationInput && locationInput.value) {
      // Get the location name from the visible input
      const locationFilter = locationInput.closest('.dropdown').querySelector('.dropdown-filter');
      if (locationFilter && locationFilter.value) {
        // Remove everything after the first '[' and trim
        let locName = locationFilter.value.split('[')[0].trim();
        searchTerm = locName.toLowerCase();
      }
    }
  } else if (isLocationFilter) {
    searchTerm = filter.substring(1);
  }

  Array.from(dropdownList.children).forEach(item => {
    if (item.id === 'tag-row') return; // managed above
    if (isTagFilter && item.id === 'actions') return; // already hidden above

    let disp = '';
    const brewtype = item.getAttribute("brewtype");
    if (selbrewtype && brewtype && selbrewtype.value !== brewtype) {
      disp = 'none';
    }

    // Region filtering: hide items whose regioncountry doesn't match the selected country
    if (countryFilterVal && disp === '') {
      const rc = (item.getAttribute('regioncountry') || '').toLowerCase();
      if (rc && rc !== countryFilterVal) disp = 'none';
    }

    if (isTagFilter) {
      const tagSearch = filter.substring(1);
      const isExact = tagSearch.endsWith(' ');
      const searchKey = isExact ? tagSearch.trimEnd() : tagSearch;
      const rawTags = (item.getAttribute('tags') || '').trim();
      if (searchKey === '') {
        if (!rawTags) disp = 'none';
      } else {
        const tagList = rawTags ? rawTags.split(/\s+/).filter(t => t) : [];
        if (isExact) {
          if (!tagList.some(t => t.toLowerCase() === searchKey)) disp = 'none';
        } else {
          if (!tagList.some(t => t.toLowerCase().startsWith(searchKey))) disp = 'none';
        }
      }
    // Filter by location (seenat) if starts with @ or is just a dot, otherwise by display text
    } else if (isLocationFilter || isDotFilter) {
      const seenat = (item.getAttribute("seenat") || "").toLowerCase();
      if (!seenat.includes(searchTerm)) {
        disp = 'none';
      }
    } else {
      if (!item.textContent.toLowerCase().includes(searchTerm)) {
        disp = 'none';
      }
    }

    item.style.display = disp;
  });
}


// Enable editing mode for forms that start in display-only mode
function enableEditing(form) {
  // Enable all disabled inputs
  const inputs = form.querySelectorAll('input[disabled], textarea[disabled], select[disabled]');
  inputs.forEach(input => input.removeAttribute('disabled'));
  
  // Enable dropdown filters
  const dropdownFilters = form.querySelectorAll('.dropdown-filter');
  dropdownFilters.forEach(filter => filter.removeAttribute('disabled'));
  
  // Show geo edit links
  const geoLinks = form.querySelectorAll('.geo-edit-links');
  geoLinks.forEach(link => link.hidden = false);
  
  // Show barcode scan links
  const barcodeLinks = form.querySelectorAll('.barcode-scan-link');
  barcodeLinks.forEach(link => link.hidden = false);

  // Hide URL preview and record-link icons while editing
  const linkPreviews = form.querySelectorAll('.field-link-preview');
  linkPreviews.forEach(a => a.style.display = 'none');

  // Show tags-available sections and chip-remove links
  const tagsAvailableDivs = form.querySelectorAll('.tags-available');
  tagsAvailableDivs.forEach(div => div.hidden = false);
  const tagChipRemoves = form.querySelectorAll('.tags-input .chip-remove');
  tagChipRemoves.forEach(a => a.hidden = false);

  // Hide Edit button, show Submit button(s)
  const editBtn = form.querySelector('.edit-enable-btn');
  if (editBtn) editBtn.hidden = true;
  
  const submitBtns = form.querySelectorAll('.edit-submit-btn');
  submitBtns.forEach(btn => btn.hidden = false);
  
  // Focus first enabled input
  const firstInput = form.querySelector('input:not([type=hidden]):not([disabled])');
  if (firstInput) firstInput.focus();
}

// Helper to find the location with smallest distance, and to select that
function selectNearest(dropdownId) {
  const root = document.querySelector(dropdownId);
  if ( ! root ) {
    console.log ("Did not find ", dropdownId);
    return;
  }
  const items = root.querySelectorAll('.dropdown-item span');
  let best = null, min = Infinity;

  items.forEach(span => {
    const val = parseFloat(span.textContent.replace('>', ''));
    if (val < min) { min = val; best = span.parentElement; }
  });

  if (best) {
    root.querySelector('.dropdown-filter').value = best.textContent.trim();
    root.querySelector('input[type=hidden]').value = best.id;
  }
}

