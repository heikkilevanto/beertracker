// Tap Timeline page JS (plan 750)
// Globals provided by taphistory.pm: TAP_DETAILS (bid -> info), TAP_LOC (name)

function showDetails(el) {
  var bid = el.dataset.brewid;
  var tap = el.dataset.tap;
  var since = el.dataset.since;
  var gone = el.dataset.gone;
  var days = el.dataset.days;
  var price = el.dataset.price;
  var d = TAP_DETAILS[bid];
  if (!d) return;
  var styleUrl = encodeURIComponent(d.sub);
  var html = "<a href='?o=Full&q=" + styleUrl + "'>"
       + "<span class='stylebadge' style='background:" + d.color + ";color:" + d.fg + "'>"
       + "[" + escHtml(d.sub) + "]</span></a> "
       + "<a href='?o=Location&e=" + d.prodid + "'><span><i>" + escHtml(d.prod) + ":</i></span></a> "
       + "<a href='?o=Brew&e=" + bid + "'><span><b>" + escHtml(d.name) + "</b></span></a>"
       + " <span style='font-size:x-small;'>[" + bid + "]</span><br>";
  html += "Tap #" + tap + (TAP_LOC ? " at " + escHtml(TAP_LOC) : "") + "<br>";
  html += "Since " + since + " &mdash; " + (gone === "still on tap" ? "<b>still on tap</b>" : gone) + "<br>";
  html += "Duration: " + days + " days<br>";
  if (price) html += "Price: " + escHtml(price);
  document.getElementById("details-body").innerHTML = html;
  document.getElementById("details").classList.add("open");
  clearHighlights();
  document.querySelectorAll(".tap-cell[data-brewid='" + bid + "']").forEach(function (cell) {
    cell.classList.add("tap-highlighted");
  });
}

function closeDetails() {
  document.getElementById("details").classList.remove("open");
  clearHighlights();
}

function clearHighlights() {
  document.querySelectorAll(".tap-cell.tap-highlighted").forEach(function (el) {
    el.classList.remove("tap-highlighted");
  });
}

// Navigate to the timeline with the chosen location and day range.
function tapGoto() {
  var loc = document.getElementById("tap-loc").value;
  var days = document.getElementById("tap-days").value;
  var from = document.getElementById("tap-from").value;
  document.location = "?o=Taps&loc=" + encodeURIComponent(loc)
      + "&days=" + days + "&from=" + encodeURIComponent(from);
}

// Click a date legend to anchor the timeline's first column on that date.
function tapSetFrom(d) {
  var loc = document.getElementById("tap-loc").value;
  var days = document.getElementById("tap-days").value;
  document.location = "?o=Taps&loc=" + encodeURIComponent(loc)
      + "&days=" + days + "&from=" + encodeURIComponent(d);
}

// Click the "<<" (Tap) header to clear the anchor back to today.
function tapClearFrom() {
  var loc = document.getElementById("tap-loc").value;
  var days = document.getElementById("tap-days").value;
  document.location = "?o=Taps&loc=" + encodeURIComponent(loc) + "&days=" + days;
}

function escHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
