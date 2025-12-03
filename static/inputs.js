// inputs.js

// Dropdown with filtering and (new)

function initDropdown(container) {
  const filterInput   = container.querySelector(".dropdown-filter");
  const hiddenInput   = container.querySelector("input[type=hidden]");
  const dropdownList  = container.querySelector(".dropdown-list");
  const newDiv        = container.querySelector(".dropdown-new");

  // Select item
  dropdownList.addEventListener("click", (event) => {
    if (!event.target.classList.contains("dropdown-item")) return;

    filterInput.value = event.target.textContent;
    filterInput.oldvalue = "";
    hiddenInput.value = event.target.id;
    dropdownList.style.display = "none";

    if (event.target.id === "new") {
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
    } else {
      // update alc if present
      const alcinp = document.getElementById("alc");
      const selalc = event.target.getAttribute("alc");
      if (alcinp && selalc) alcinp.value = selalc + "%";

      // show note if generic brew
      if ( event.target.textContent.includes("(Gen)") ){
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

function filterItems(filterInput, dropdownList) {
  const selbrewtype = document.getElementById("selbrewtype");
  const filter = filterInput.value.toLowerCase();
  Array.from(dropdownList.children).forEach(item => {
    let disp = '';
    const brewtype = item.getAttribute("brewtype");
    if (selbrewtype && brewtype && selbrewtype.value !== brewtype) {
      disp = 'none';
    }
    if (!item.textContent.toLowerCase().includes(filter)) {
      disp = 'none';
    }
    item.style.display = disp;
  });
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
  display.className = "custom-select-display";
  display.textContent = selectEl.selectedOptions[0]?.textContent || "";
  wrapper.appendChild(display);

  const list = document.createElement("div");
  list.className = "custom-select-list";
  Array.from(selectEl.options).forEach((opt, idx) => {
    const item = document.createElement("div");
    item.className = "custom-select-item";
    item.dataset.value = opt.value;
    item.textContent = opt.textContent;
    item.addEventListener("click", () => {
      selectEl.selectedIndex = idx;
      selectEl.dispatchEvent(new Event("change")); // fires selbrewchange
      display.textContent = opt.textContent;
      list.style.display = "none";
    });
    list.appendChild(item);
  });
  wrapper.appendChild(list);

  selectEl.parentNode.insertBefore(wrapper, selectEl.nextSibling);

  // Initialize the custom select behavior
  initCustomSelect(wrapper);
}

