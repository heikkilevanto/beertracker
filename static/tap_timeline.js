// Tap Timeline page JS (plan 750)
// Globals provided by taphistory.pm: TAP_DETAILS (bid -> info),
// TAP_KEGS (bid -> keg list), and the hidden #tapforms stash of manage blocks

function showDetails(el) {
  var bid = el.dataset.brewid;
  var kegid = el.dataset.kegid;
  var d = TAP_DETAILS[bid];
  if (!d) return;
  var styleUrl = encodeURIComponent(d.sub);
  var html = "<a href='?o=Full&q=" + styleUrl + "'>"
       + "<span class='stylebadge' style='background:" + d.color + ";color:" + d.fg + "'>"
       + "[" + escHtml(d.sub) + "]</span></a> "
       + "<a href='?o=Location&e=" + d.prodid + "'><span><i>" + escHtml(d.prod) + ":</i></span></a> "
       + "<a href='?o=Brew&e=" + bid + "'><span><b>" + escHtml(d.name) + "</b></span></a>"
       + " <span style='font-size:x-small;'>[" + bid + "]</span>"
       + (d.alc ? " <span class='alc'>" + escHtml(d.alc) + "%</span>" : "")
       + "<br>";
  html += kegHistory(bid, kegid);
  var body = document.getElementById("details-body");
  releaseTapManage(body);
  body.innerHTML = html;
  installTapManage(body);
  document.getElementById("details").classList.add("open");
  clearHighlights();
  document.querySelectorAll(".tap-cell[data-brewid='" + bid + "']").forEach(function (cell) {
    cell.classList.add("tap-highlighted");
  });
}

// Build a small table of every keg of this brew seen in the displayed window.
function kegHistory(bid, kegid) {
  var ks = TAP_KEGS[bid];
  if (!ks || !ks.length) return "";
  ks = ks.slice().sort(function (a, b) {
    return a.first < b.first ? 1 : (a.first > b.first ? -1 : 0);
  });
  var h = "<table class='keg-hist'>"
       + "<tr><th>Tap</th><th>On</th><th>Off</th><th>Days</th><th>Price</th><th></th></tr>";
  for (var i = 0; i < ks.length; i++) {
    var k = ks[i];
    var off = k.gone ? k.gone : "(still on)";
    var pr = (k.prices && k.prices.length) ? k.prices.join(" ") : "";
    var hl = (String(k.id) === String(kegid)) ? " class='hl'" : "";
    var unusual = k.unusual ? " <span style='color:#c44;'>Unusual</span>" : "";
    h += "<tr" + hl + "><td>#" + k.tap + "</td><td>" + escHtml(k.first) + "</td><td>"
       + escHtml(off) + "</td><td>" + k.days + "</td><td>" + escHtml(pr)
       + "<td>" + unusual;
    if (i === 0) {
      h += "<div class='tapmanage-slot' data-kegid='" + k.id
         + "' style='display: inline;'></div>";
    }
    h += "</td></tr>";
  }
  h += "</table>";
  return h;
}

// The [manage] block is rendered server-side by taps::tap_action_form_html()
// into the hidden #tapforms stash. Move it into the details panel, and put any
// block left over from a previous selection back first - replacing innerHTML
// would otherwise destroy it for good.
function releaseTapManage(body) {
  var stash = document.getElementById("tapforms");
  var block = body.querySelector(".tapact");
  if (!stash || !block) return;
  var form = block.querySelector(".tapact-form");
  if (form) form.style.display = "none";
  stash.appendChild(block);
}

function installTapManage(body) {
  var slot = body.querySelector(".tapmanage-slot");
  var stash = document.getElementById("tapforms");
  if (!slot || !stash) return;
  var block = stash.querySelector("#tapact_" + slot.dataset.kegid);
  if (block) slot.appendChild(block);
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
