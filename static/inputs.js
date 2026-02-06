// inputs.js

// Dropdown with filtering and (new)

function initDropdown(container) {
  const filterInput   = container.querySelector(".dropdown-filter");
  const hiddenInput   = container.querySelector("input[type=hidden]");
  const dropdownList  = container.querySelector(".dropdown-list");
  const newDiv        = container.querySelector(".dropdown-new");

  // Select item
  dropdownList.addEventListener("click", (event) => {
    const item = event.target.closest('.dropdown-item');
    if (!item) return;

    // Check if clicking on an action link (scan/new)
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

    // Regular item selection
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

function filterItems(filterInput, dropdownList) {
  const selbrewtype = document.getElementById("selbrewtype");
  const filter = filterInput.value.toLowerCase();
  const isLocationFilter = filter.startsWith('@');
  const isDotFilter = filter === '.' || filter === '@';
  let searchTerm = filter;
  
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
    let disp = '';
    const brewtype = item.getAttribute("brewtype");
    if (selbrewtype && brewtype && selbrewtype.value !== brewtype) {
      disp = 'none';
    }
    
    // Filter by location (seenat) if starts with @ or is just a dot, otherwise by display text
    if (isLocationFilter || isDotFilter) {
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

