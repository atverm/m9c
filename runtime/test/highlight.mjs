// The M9 highlighter (tools/jupyter/highlight/src/m9mode.js) against the
// lexer: run its `token` over one file, line by line, as CodeMirror's
// StreamLanguage does, and print what it marked as KEYWORD or STRING,
// one per line, `LINE:COL KIND`, COL counted in bytes as the FPC
// lexer's dump counts it.  highlight.sh compares this with lexdump's
// keyword and StrLit tokens: a keyword inside a comment, a string
// ended early, a nested comment closed at its first `*)` -- each shows
// as a line one side has and the other has not.
//
// usage: node highlight.mjs KEYWORDS.json FILE.m9

import { readFileSync } from 'node:fs';
import { makeM9 } from '../../tools/jupyter/highlight/src/m9mode.js';

// the part of CodeMirror's StringStream a stream parser uses
class Stream {
  constructor (s) { this.string = s; this.pos = 0; this.start = 0; }
  eol () { return this.pos >= this.string.length; }
  sol () { return this.pos === 0; }
  peek () { return this.string.charAt(this.pos) || undefined; }
  next () { if (this.pos < this.string.length) return this.string.charAt(this.pos++); }
  eatSpace () {
    const s = this.pos;
    while (/[\s ]/.test(this.string.charAt(this.pos))) ++this.pos;
    return this.pos > s;
  }
  match (p) {
    if (typeof p === 'string') {
      if (this.string.substr(this.pos, p.length) === p) { this.pos += p.length; return true; }
      return null;
    }
    const m = this.string.slice(this.pos).match(p);
    if (m && m.index > 0) return null;
    if (m) this.pos += m[0].length;
    return m;
  }
}

const [kwPath, file] = process.argv.slice(2);
const mode = makeM9(Object.keys(JSON.parse(readFileSync(kwPath, 'utf8'))));
const lines = readFileSync(file, 'utf8').split('\n');
const state = mode.startState();
const out = [];
lines.forEach((line, i) => {
  const s = new Stream(line);
  while (!s.eol()) {
    s.start = s.pos;
    const style = mode.token(s, state);
    if (s.pos === s.start) throw new Error(`${file}:${i + 1}: no progress at ${s.pos}`);
    const col = Buffer.byteLength(line.slice(0, s.start), 'utf8') + 1;
    if (style === 'keyword') out.push(`${i + 1}:${col} ${line.slice(s.start, s.pos)}`);
    else if (style === 'string') out.push(`${i + 1}:${col} StrLit`);
  }
});
process.stdout.write(out.join('\n') + (out.length ? '\n' : ''));
