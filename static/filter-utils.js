// Shared filter utilities for listrecords.js and inputs.js

// Tokenize filter input respecting "..." quoting.  Returns array of strings.
// Quoted segments become single tokens (with quotes removed).
// Unquoted segments are split by whitespace.
function _tokenizeFilterInput(value) {
  const tokens = [];
  const re = /"([^"]*)"|(\S+)/g;
  let m;
  while ((m = re.exec(value)) !== null) {
    if (m[1] !== undefined) {
      tokens.push(m[1]); // quoted content as one token
    } else {
      tokens.push(m[2]); // unquoted token
    }
  }
  return tokens;
}

// Match text against a set of comma-separated alternatives using the given mode.
// Splits `alternativesStr` by comma, trims each, filters empties.
// Returns true if ANY alternative matches `text` (OR logic).
// mode 'not_contains' inverts: true only if NO alternatives match.
function _matchAlternatives(text, alternativesStr, mode) {
  const alts = alternativesStr.split(',').map(function(a) { return a.trim(); }).filter(function(a) { return a; });
  if (alts.length === 0) return true;
  var anyMatch = alts.some(function(alt) {
    if (mode === 'exact') {
      return text === alt;
    } else {
      return text.indexOf(alt) !== -1;
    }
  });
  return mode === 'not_contains' ? !anyMatch : anyMatch;
}
