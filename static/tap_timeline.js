// Tap Timeline page JS (plan 750)
// Globals provided by taphistory.pm: TAP_DETAILS (bid -> info), TAP_LOC (name)

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
  document.getElementById("details-body").innerHTML = html;
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
      h += tapManageLink(k.id, k.gone ? 1 : 0, k.unusual ? 1 : 0);
    }
    h += "</td></tr>";
  }
  h += "</table>";
  return h;
}

// Render the [manage] link and hidden form for a tap action
function tapManageLink(tapId, isGone, isUnusual) {
  var formId = "tapact_" + tapId;
  var link = "<span style='font-size:x-small; cursor:pointer; color:#888;' "
      + "onclick=\"var f=document.getElementById('" + formId + "');"
      + "f.style.display=(f.style.display==='none'?'block':'none');\">[manage]</span>";
  var items = "";
  if (isGone) {
    items += "<div class='dropdown-item' id='reopen' "
        + "onmousedown=\"this.closest('form').querySelector('input[name=tap_action]').value='reopen';"
        + "this.closest('.dropdown').querySelector('.dropdown-filter').value='Reopen this keg';\">"
        + "Reopen this keg</div>";
  } else {
    items += "<div class='dropdown-item' id='close' "
        + "onmousedown=\"this.closest('form').querySelector('input[name=tap_action]').value='close';"
        + "this.closest('.dropdown').querySelector('.dropdown-filter').value='Close tap';\">"
        + "Close tap</div>";
    items += "<div class='dropdown-item' id='close_reopen' "
        + "onmousedown=\"this.closest('form').querySelector('input[name=tap_action]').value='close_reopen';"
        + "this.closest('.dropdown').querySelector('.dropdown-filter').value='Close & reopen same';\">"
        + "Close &amp; reopen same</div>";
  }
  var form = "<div id='" + formId + "' style='display:none; font-size:x-small; margin-top:2px;'>"
      + "<form method='POST' accept-charset='UTF-8' class='no-print' style='display:inline;'>"
      + "<input type='hidden' name='o' value='Taps'>"
      + "<input type='hidden' name='tap_beers_id' value='" + tapId + "'>"
      + "<input type='hidden' name='loc' value='" + escHtml(TAP_LOC) + "'>"
      + "<input type='hidden' name='redir_op' value='Taps'>"
      + "<div class='dropdown' style='max-width:14em; display:inline-block; vertical-align:middle;'>"
      + "<div class='dropdown-main'>"
      + "<input type='text' class='dropdown-filter' autocomplete='off' placeholder='Leave keg open' value='' readonly"
      + " onfocus=\"var dl=this.parentElement.querySelector('.dropdown-list'); dl.style.display='block'; this.value='';\""
      + " onblur=\"var dl=this.parentElement.querySelector('.dropdown-list'); var self=this; setTimeout(function(){ dl.style.display='none'; self.value=''; }, 200);\""
      + " style='font-size:x-small; width:10em;'>"
      + "<input type='hidden' name='tap_action' value=''>"
      + "<div class='dropdown-list'>" + items + "</div>"
      + "</div></div>"
      + "<br><input type='checkbox' name='mark_unusual' value='1'" + (isUnusual ? " checked" : "") + "> <span>Unusual</span>"
      + "<br><input type='submit' value='Update Keg'>"
      + "</form></div>";
  return link + form;
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
