// brews.pm edit-form behavior. Loaded with `defer` so the DOM exists.

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
  var brewTypeInput = document.getElementById('BrewType');
  var subTypeDropdown = document.getElementById('dropdown-SubType');
  if (!brewTypeInput || !subTypeDropdown) return;
  var subTypeList = subTypeDropdown.querySelector('.dropdown-list');
  var subTypeFilter = subTypeDropdown.querySelector('.dropdown-filter');
  if (!subTypeList) return;
  // Add a selbrewtype hidden input so filterItems() uses it for brewtype filtering
  var selbrewtype = document.createElement('input');
  selbrewtype.type = 'hidden';
  selbrewtype.id = 'selbrewtype';
  subTypeDropdown.parentNode.appendChild(selbrewtype);
  function filterSubTypes() {
    var bt = brewTypeInput.value;
    selbrewtype.value = bt;
    var items = subTypeList.querySelectorAll('.dropdown-item');
    var hasMatch = false;
    var i;
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var bta = items[i].getAttribute('brewtype');
      if (bta && bta === bt) { hasMatch = true; break; }
    }
    for (i = 0; i < items.length; i++) {
      if (items[i].id === 'actions') continue;
      var bta = items[i].getAttribute('brewtype');
      if (!bt || !bta || bta === bt || !hasMatch) {
        items[i].style.display = '';
      } else {
        items[i].style.display = 'none';
      }
    }
  }
  brewTypeInput.addEventListener('input', filterSubTypes);
  filterSubTypes();
})();

(function() {
  var prodDropdown = document.getElementById('dropdown-ProducerLocation');
  var countryDropdown = document.getElementById('dropdown-Country');
  var regionDropdown = document.getElementById('dropdown-Region');
  if (!prodDropdown || !countryDropdown || !regionDropdown) return;

  function getProdData() {
    var prodHidden = prodDropdown.querySelector('input[type=hidden]');
    if (!prodHidden || !prodHidden.value) return null;
    var item = prodDropdown.querySelector('.dropdown-item[id="' + prodHidden.value + '"]');
    if (!item) return null;
    return { country: item.getAttribute('country'), region: item.getAttribute('region') };
  }

  function copyFromProducer() {
    var data = getProdData();
    if (!data) return;
    var countryHidden = countryDropdown.querySelector('input[type=hidden]');
    var regionHidden = regionDropdown.querySelector('input[type=hidden]');
    if (countryHidden && data.country) setDropdownValue(countryHidden, data.country);
    if (regionHidden && data.region) setDropdownValue(regionHidden, data.region);
  }

  // On producer change: fill only if country or region is empty
  var prodHidden = prodDropdown.querySelector('input[type=hidden]');
  if (prodHidden) {
    prodHidden.addEventListener('input', function() {
      var c = countryDropdown.querySelector('input[type=hidden]');
      var r = regionDropdown.querySelector('input[type=hidden]');
      if (!c || !r || !c.value.trim() || !r.value.trim()) copyFromProducer();
    });
  }

  // On Country/Region label click: always copy
  var form = document.querySelector('form');
  if (form) {
    var cells = form.querySelectorAll('td');
    for (var i = 0; i < cells.length; i++) {
      var text = cells[i].textContent.trim();
      if (text === 'Country' || text === 'Region') {
        cells[i].style.cursor = 'pointer';
        cells[i].title = 'Fill from producer';
        cells[i].addEventListener('click', copyFromProducer);
      }
    }
  }
})();
