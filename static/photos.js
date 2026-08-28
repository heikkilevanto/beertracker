// photos.pm behavior. Loaded with `defer` so the DOM exists.

// Auto-submit the photo upload form as soon as a file is picked.
function photoAutoSubmit(formId, fileId) {
  var f = document.getElementById(fileId);
  if (!f) return;
  f.addEventListener('change', function() {
    if (this.files.length) { document.getElementById(formId).submit(); }
  });
}

// Show/hide the attachment-type target selectors.
function atype_change(pid, v) {
  ['person', 'location', 'brew'].forEach(function(t) {
    var el = document.getElementById('atype_' + t + '_' + pid);
    if (el) el.style.display = (t === v) ? '' : 'none';
  });
}
