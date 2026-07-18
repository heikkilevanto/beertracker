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
