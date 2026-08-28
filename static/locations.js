// locations.pm edit-form behavior. Loaded with `defer` so the DOM exists.

(function() {
  var nameInp  = document.querySelector("input[name='Name']");
  var shortInp = document.querySelector("input[name='ShortName']");
  if (!nameInp || !shortInp) return;
  nameInp.addEventListener('input', function() {
    var s = computeShortName(this.value);
    if (s !== null) { shortInp.value = s; }
  });
})();

(function() {
  var untappdInput = document.querySelector("input[name='UntappdLink']");
  var scraperInput = document.querySelector("input[name='Scraper']");
  if (!untappdInput || !scraperInput) return;
  untappdInput.addEventListener('input', function() {
    var curScraper = scraperInput.value.trim();
    if (curScraper && !curScraper.match(/^untappd\.pl/i)) return;
    var url = this.value.trim();
    var m = url.match(/untappd\.com\/v\/(.+)/i);
    if (m) {
      scraperInput.value = 'untappd.pl ' + m[1];
    }
  });
})();

(function() {
  var loctypeInput = document.getElementById('LocType');
  var locsubtypeDropdown = document.getElementById('dropdown-LocSubType');
  if (!loctypeInput || !locsubtypeDropdown) return;
  var locsubtypeList = locsubtypeDropdown.querySelector('.dropdown-list');
  var locsubtypeFilter = locsubtypeDropdown.querySelector('.dropdown-filter');
  if (!locsubtypeList) return;
  var selloctype = document.createElement('input');
  selloctype.type = 'hidden';
  selloctype.id = 'selloctype';
  locsubtypeDropdown.parentNode.appendChild(selloctype);
  function filterLocSubTypes() {
    var lt = loctypeInput.value;
    selloctype.value = lt;
    var items = locsubtypeList.querySelectorAll('.dropdown-item');
    var hasMatch = false;
    var i;
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var lta = items[i].getAttribute('loctype');
      if (lta && lta === lt) { hasMatch = true; break; }
    }
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var lta = items[i].getAttribute('loctype');
      if (!lt || !lta || lta === lt || !hasMatch) {
        items[i].style.display = '';
      } else {
        items[i].style.display = 'none';
      }
    }
  }
  loctypeInput.addEventListener('input', filterLocSubTypes);
  filterLocSubTypes();
})();
