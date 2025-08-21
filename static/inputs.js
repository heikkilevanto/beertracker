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
      if (alcinp && selalc) alcinp.value = selalc;
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


// custom select
function initCustomSelect(container) {
  const display = container.querySelector(".custom-select-display");
  const list    = container.querySelector(".custom-select-list");
  const hidden  = container.querySelector("input[type=hidden]");

  display.addEventListener("click", () => {
    console.log("click");
    list.style.display = list.style.display === "block" ? "none" : "block";
  });

  list.addEventListener("click", (event) => {
    if (!event.target.classList.contains("custom-select-item")) return;
    display.textContent = event.target.textContent;
    hidden.value = event.target.dataset.value;
    list.style.display = "none";
  });

  // Close on outside click
  document.addEventListener("click", (e) => {
    if (!container.contains(e.target)) list.style.display = "none";
  });
}

// Convert an existing <select> into a custom select
function replaceSelectWithCustom(selectEl) {
  if (!selectEl) return;

  // Create wrapper
  const wrapper = document.createElement("div");
  wrapper.className = "custom-select";

  // Display div
  const display = document.createElement("div");
  display.className = "custom-select-display";
  display.textContent = selectEl.selectedOptions[0]?.textContent || "";
  wrapper.appendChild(display);

  // Hidden input
  const hidden = document.createElement("input");
  hidden.type = "hidden";
  hidden.name = selectEl.name;
  hidden.value = selectEl.value;
  wrapper.appendChild(hidden);

  // Options list
  const list = document.createElement("div");
  list.className = "custom-select-list";
  Array.from(selectEl.options).forEach(opt => {
    const item = document.createElement("div");
    item.className = "custom-select-item";
    item.dataset.value = opt.value;
    item.textContent = opt.textContent;
    list.appendChild(item);
  });
  wrapper.appendChild(list);

  // Replace <select> in DOM
  selectEl.parentNode.replaceChild(wrapper, selectEl);

  // Initialize the custom select behavior
  initCustomSelect(wrapper);
}

