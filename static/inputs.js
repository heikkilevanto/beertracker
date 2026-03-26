// inputs.js

// Dropdown with filtering and (new)

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
      filterInput.value = item.textContent;
      filterInput.oldvalue = "";
      hiddenInput.value = item.id;
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
      if (volinp && selvol && selvol.trim()) volinp.value = selvol + "c"

      // update subtype if Restaurant brewtype
      const selbrewtype = document.getElementById("selbrewtype");
      const selbrewsubtype = document.getElementById("selbrewsubtype");
      const locsubtype = item.getAttribute("locsubtype");
      if (selbrewtype && selbrewsubtype && locsubtype && selbrewtype.value === "Restaurant") {
        selbrewsubtype.value = locsubtype;
      }

      // show note if generic brew
      if ( item.textContent.includes("(Gen)") ){
        const noteline = document.getElementById("noteline");
        if ( noteline ) noteline.hidden = false;
        const toggle = document.getElementById("notetag");
        if (toggle) toggle.hidden = true;
      }
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
  // Create a temporary hidden input for the scanner
  const tempInput = document.createElement('input');
  tempInput.type = 'hidden';
  tempInput.id = 'temp-barcode-scan-' + Date.now();
  document.body.appendChild(tempInput);
  
  // Start scanning
  startBarcodeScanning(tempInput.id);
  
  // Poll for when the barcode is filled
  const checkInterval = setInterval(() => {
    if (tempInput.value) {
      clearInterval(checkInterval);
      const scannedCode = tempInput.value;
      tempInput.remove();
      
      // Filter dropdown items by barcode
      const items = Array.from(dropdownList.children);
      const matches = items.filter(item => {
        const itemBarcode = item.getAttribute('barcode');
        return itemBarcode && itemBarcode === scannedCode;
      });
      
      if (matches.length === 1) {
        // Exactly one match - select it
        const match = matches[0];
        filterInput.value = match.textContent;
        hiddenInput.value = match.id;
        dropdownList.style.display = 'none';
        
        // Trigger the same updates as clicking the item
        const alcinp = document.getElementById("alc");
        const selalc = match.getAttribute("alc");
        if (alcinp && selalc) alcinp.value = selalc + "%";
        
        const prinp = document.getElementById("pr");
        const selpr = match.getAttribute("defprice");
        if (prinp && selpr && selpr.trim()) prinp.value = selpr + ".-";
        
        const volinp = document.getElementById("vol");
        const selvol = match.getAttribute("defvol");
        if (volinp && selvol && selvol.trim()) volinp.value = selvol + "c";
      } else if (matches.length > 1) {
        // Multiple matches - show only those
        items.forEach(item => {
          item.style.display = matches.includes(item) ? '' : 'none';
        });
        filterInput.value = `[${matches.length} matches for ${scannedCode}]`;
        dropdownList.style.display = 'block';
      } else {
        // No match - show message
        filterInput.value = `No brew found with barcode ${scannedCode}`;
        setTimeout(() => {
          filterInput.value = '';
          filterInput.focus();
        }, 2000);
      }
    }
  }, 100);
  
  // Timeout after 30 seconds
  setTimeout(() => {
    clearInterval(checkInterval);
    tempInput.remove();
  }, 30000);
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


// Replacement for a regular select component, following our styles
function initCustomSelect(container) {
  const display = container.querySelector(".custom-select-display");
  const list    = container.querySelector(".custom-select-list");

  display.addEventListener("click", () => {
    list.style.display = list.style.display === "block" ? "none" : "block";
  });

  list.addEventListener("click", (event) => {
    if (!event.target.classList.contains("custom-select-item")) return;
    display.textContent = event.target.textContent;
    list.style.display = "none";
  });

  // Close on outside click
  document.addEventListener("click", (e) => {
    if (!container.contains(e.target)) list.style.display = "none";
  });
}


function replaceSelectWithCustom(selectEl) {
  if (!selectEl) return;

  selectEl.style.display = "none";   // hide but keep <select>

  const wrapper = document.createElement("div");
  wrapper.className = "custom-select";

  const display = document.createElement("div");
  display.className = "custom-select-display " + (selectEl.selectedOptions[0]?.className || "");
  display.textContent = selectEl.selectedOptions[0]?.textContent || "";
  wrapper.appendChild(display);

  const list = document.createElement("div");
  list.className = "custom-select-list";
  Array.from(selectEl.options).forEach((opt, idx) => {
    const item = document.createElement("div");
    item.className = "custom-select-item " + opt.className;
    item.dataset.value = opt.value;
    item.textContent = opt.textContent;
    item.addEventListener("click", () => {
      selectEl.selectedIndex = idx;
      selectEl.dispatchEvent(new Event("change")); // fires selbrewchange
      display.textContent = opt.textContent;
      display.className = "custom-select-display " + opt.className;
      list.style.display = "none";
    });
    list.appendChild(item);
  });
  wrapper.appendChild(list);

  selectEl.parentNode.insertBefore(wrapper, selectEl.nextSibling);

  // Initialize the custom select behavior
  initCustomSelect(wrapper);
}

