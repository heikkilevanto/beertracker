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
    if (mode === 'exact' || mode === 'ne') {
      return text === alt;
    } else {
      return text.indexOf(alt) !== -1;
    }
  });
  return (mode === 'not_contains' || mode === 'ne') ? !anyMatch : anyMatch;
}

// Relational comparison: try numeric first (parseFloat), fall back to alphabetical.
// `text` and `term` should be pre-lowercased.
// Comma-separated terms (e.g. ">2,<1") are OR-ed.
function _compareRelational(op, text, term) {
  function _compareOne(op, text, term) {
    const numA = parseFloat(text);
    const numB = parseFloat(term);
    if (!isNaN(numA) && !isNaN(numB)) {
      switch (op) {
        case 'gt': return numA > numB;
        case 'gte': return numA >= numB;
        case 'lt': return numA < numB;
        case 'lte': return numA <= numB;
      }
    }
    switch (op) {
      case 'gt': return text > term;
      case 'gte': return text >= term;
      case 'lt': return text < term;
      case 'lte': return text <= term;
    }
    return false;
  }

  // Comma → OR: each comma-separated part is its own relational expression
  if (term.indexOf(',') !== -1) {
    const parts = term.split(',');
    return parts.some(function(part) {
      let pmode = op;
      let pterm = part;
      if (part.startsWith('>=') && part.length > 2) { pmode='gte'; pterm=part.substring(2); }
      else if (part.startsWith('<=') && part.length > 2) { pmode='lte'; pterm=part.substring(2); }
      else if (part.startsWith('>') && part.length > 1) { pmode='gt'; pterm=part.substring(1); }
      else if (part.startsWith('<') && part.length > 1) { pmode='lt'; pterm=part.substring(1); }
      return _compareOne(pmode, text, pterm);
    });
  }
  return _compareOne(op, text, term);
}
