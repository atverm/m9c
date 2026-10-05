// M9 for CodeMirror 6 as a stream parser (StreamLanguage.define).
//
// makeM9 (keywords) answers the parser; the keywords are handed in --
// tools/edit/keywords.json, which the edit gate holds to the lexer's
// own table in both directions -- so this file carries no list of
// its own to drift.  runtime/test/highlight.sh runs `token` over every
// corpus and museum file and holds each keyword and string it marks
// to where the FPC lexer (host/fpc/lexdump) puts one.
//
// Lexis, report par 2: (* *) comments NEST (the depth is the state,
// and it crosses lines); strings in ' or " with NO escapes; char
// literals are hex digits with a C suffix and begin with a digit;
// 0x hex; a real needs digits on both sides of its point; a first
// line beginning #! belongs to the operating system.

const CONSTANTS = new Set(['TRUE', 'FALSE', 'NONE', 'ALL', 'HEAP']);
const TYPES = new Set(['I8', 'I16', 'I32', 'I64', 'U8', 'U16', 'U32', 'U64',
                       'F32', 'F64', 'BYTE', 'BOOL', 'CHAR', 'STR']);
const ATTRIBUTES = /^\[\s*(SERIAL|REENTRANT|PURE|READONLY|STATEFUL)\s*\]/;

export function makeM9(keywords) {
  const KEYWORDS = new Set(keywords);

  function comment(stream, state) {
    while (!stream.eol()) {
      if (stream.match('(*')) {
        state.depth++;
      } else if (stream.match('*)')) {
        state.depth--;
        if (state.depth === 0) return 'comment';
      } else {
        stream.next();
      }
    }
    return 'comment';
  }

  return {
    name: 'm9',
    startState: () => ({ depth: 0, first: true }),
    copyState: (s) => ({ depth: s.depth, first: s.first }),
    token(stream, state) {
      const first = state.first;
      state.first = false;
      if (state.depth > 0) return comment(stream, state);
      if (first && stream.sol() && stream.match(/^#!.*/)) return 'meta';
      if (stream.eatSpace()) return null;
      if (stream.match('(*')) {
        state.depth = 1;
        return comment(stream, state);
      }
      const ch = stream.peek();
      if (ch === "'" || ch === '"') {
        stream.next();
        while (!stream.eol()) {
          if (stream.next() === ch) break;
        }
        return 'string';
      }
      if (stream.match(/^0x[0-9A-Fa-f]+/) ||
          stream.match(/^[0-9][0-9A-Fa-f]*C(?![A-Za-z0-9])/) ||
          stream.match(/^[0-9]+\.[0-9]+(E[+-]?[0-9]+)?/) ||
          stream.match(/^[0-9]+/)) {
        return 'number';
      }
      if (stream.match(ATTRIBUTES)) return 'meta';
      const word = stream.match(/^[A-Za-z][A-Za-z0-9]*/);
      if (word) {
        const w = word[0];
        if (KEYWORDS.has(w)) return 'keyword';
        if (TYPES.has(w)) return 'typeName';
        if (CONSTANTS.has(w)) return 'atom';
        return null;
      }
      if (stream.match(/^(:=|\.\.|\+%|-%|\*%|<=|>=|[#=<>+\-*\/^|&~])/)) return 'operator';
      stream.next();
      return null;
    },
    languageData: { commentTokens: { block: { open: '(*', close: '*)' } } }
  };
}
