// menu.js

function initMenu(menuData, containerId, toggleButtonId) {
  const container = document.getElementById(containerId);
  if (!container || !menuData || !menuData.menu) return;

  function buildMenu(items, currentLabel) {
    const ul = document.createElement("ul");

    items.forEach(item => {
      const li = document.createElement("li");

      if (item.children) {
        const span = document.createElement("span");
        span.textContent = item.label;
        span.classList.add("menu-section");

        const childList = buildMenu(item.children, currentLabel);
        childList.style.display = "none";

        span.addEventListener("click", () => {
          childList.style.display =
            childList.style.display === "none" ? "block" : "none";
        });

        li.appendChild(span);
        li.appendChild(childList);

        if (item.children.some(c => c.label === currentLabel)) {
          childList.style.display = "block";
        }

      } else {
        const a = document.createElement("a");
        a.textContent = item.label;
        a.href = window.location.pathname + "?" + item.url;

        if (item.label === currentLabel) {
          a.classList.add("current");
        }

        li.appendChild(a);
      }

      ul.appendChild(li);
    });

    return ul;
  }

  // Clear and build menu
  container.innerHTML = "";

  // Create drawer top bar
  const topBar = document.createElement("div");
  topBar.classList.add("menu-topbar");

  // assume you have the main toggle button in the page
  const mainToggle = document.getElementById("menu-toggle");

  // clone it for the drawer top bar
  const closeBtn = mainToggle.cloneNode(true);


  // override click to close the drawer
  closeBtn.addEventListener("click", () => {
    container.classList.remove("open");
  });

  topBar.appendChild(closeBtn);
  // separate '×' close element
  const closeX = document.createElement("span");
  closeX.textContent = "×";
  closeX.classList.add("close-x");
  closeX.addEventListener("click", () => {
    container.classList.remove("open");
  });

  topBar.appendChild(closeX);
  container.appendChild(topBar);
  // close on Esc or click outside the menu
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && container.classList.contains("open")) {
      container.classList.remove("open");
    }
  });
  document.addEventListener("click", (e) => {
    if (!container.contains(e.target) &&
        container.classList.contains("open") &&
        e.target !== toggleBtn) {
      container.classList.remove("open");
    }
  });

  container.appendChild(buildMenu(menuData.menu, menuData.currentLabel));

  // Open drawer
  const toggleBtn = document.getElementById(toggleButtonId);
  if (toggleButtonId) {
    if (toggleBtn) {
      toggleBtn.addEventListener("click", () => {
        container.classList.toggle("open");
      });
    }
  }
}
