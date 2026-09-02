# Lex

The M9 lexer, in M9 -- the first thousandth of the self-hosted
compiler (P5 stage 1), restated from host/fpc/M9Lex.pas, which
now serves as its differential oracle: both must emit identical
token streams over every corpus and museum file.
Kinds are I64 codes, stable and documented: 0 EOF, 1 Error,
2 Ident, 3 IntLit, 4 RealLit, 5 CharLit, 6 StrLit, then keywords
from 7 and operators from 200.  Codes are identifiers, not
positions in a sorted list: a new keyword APPENDS at the next
free code rather than renumbering its alphabetical neighbours.
Errors are tokens carrying their message; lexing continues.
STATEFUL for one small truth: the unexpected-character message
is composed in a module buffer.

### TYPE Token

verbatim source; for Error, message

### TYPE Lexer

A comment, for the callers that want the documentation rather
than the program.  text is VERBATIM and includes the opening
`(*` and closing `*)`, because a reader that wants them stripped
can strip them and one that wants the nesting cannot put them
back.

### TYPE Comment

_(undocumented)_

### Init (VAR lx: Lexer ; RO KEPT src: STR)

the lexer keeps the source slice; keep it alive while lexing --
the Json.Parse contract again

### Next (VAR lx: Lexer ; VAR t: Token)

the next token, skipping blanks and nested comments on the way.

ERRORS ARE TOKENS: a bad character or an unterminated comment
comes back as an Error token carrying the message and its
line:col, and lexing CONTINUES.  There is no error state to
check and no exception to handle, so a caller can report every
mistake in a file in one pass -- which is what lextest does.

  t -- VAR rather than a result because a Token is a record and
       this is called once per token; the caller reuses one.

Comments leave no trace here at all: they cost zero tokens, so
the count lextest.golden records is a count of code.

### KindName (k: I64) : STR

the FPC oracle's names, for dumps and diagnostics

### Collect (on: BOOL)

arm or disarm.  Arming also CLEARS what was collected, so one
process can lex several files and keep them apart; disarming
keeps it, so a caller can arm, parse one file, disarm, and then
read the comments of that file only while its dependencies go
past uncollected.  That is exactly what m9c --doc needs.

### ComCount () : I64

_(documented with the group below)_

### ComAt (i: I64) : Comment RAISES IndexError

what was collected, in source order.

i -- 0 .. ComCount - 1.  An UNTERMINATED comment is not in
     here at all: it never closed, so it has no end line and
     no text, and the Error token Next answers is the whole
     of what is known about it.
