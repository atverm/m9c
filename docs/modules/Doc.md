# Doc

The DEFINITION module, as documentation.

M9 already puts the whole contract of a module in one place, and
the corpus already writes prose under every declaration there.
Nothing read those comments until now: the lexer threw them away
before a token was made, so there was nothing in the tree to
print.  Lex.Collect is the side channel that keeps them; this is
the client that gives them meaning.

AN ORDINARY CLIENT, on purpose -- the OpenApi precedent.  OpenApi
describes HttpServer's routes through the public accessors and has
no privileged access, which is what makes "the server cannot
disagree with its documentation" a checkable claim rather than a
promise.  The same applies here: this module reads Ast and Lex
through their published surfaces, renders signatures through
Print (the same procedure Sem uses to decide whether two
declarations are the same declaration), and adds no opinion of its
own about what M9 syntax looks like.

THE CONVENTION IS THE INDENT, and it was measured rather than
invented.  In a DEFINITION module:

  - an INDENTED comment belongs to the declaration above it;
  - a comment at COLUMN 1 is a section banner and belongs to
    nothing;
  - the first comment of the unit, before any declaration, is the
    module's own.

Over the corpus that rule attaches every comment correctly.  The
seven it declines to attach are all at column 1 and all really are
banners -- Print's `*Text` group heading, NetCDF's `---- reading
----`, Math's single-precision divider.  A rule that ignored the
indent would have mis-attributed every one of them.

A doc block is PROSE.  It may end with a blank line followed by a
run of `name -- what it is` lines, one per parameter; the block is
optional, no parameter need appear, and every name in one must be
a parameter of that procedure -- which is checked, and is the one
thing a caller can get wrong that this module reports as an error
rather than as a gap.  The blank line is required because three
comments in the corpus contain a mid-paragraph phrase of that
shape and are not parameter blocks.

### TYPE Stats

definition units, and documented

### Json (VAR pool: POOL ; root: PTR Ast.Node ; RO modName: STR ; VAR st: Stats) : STR RAISES IndexError

The same declarations as DATA.  One object: "module", "doc"
(the module's own comment, or null), and "declarations" -- for
every exported name its "kind" (procedure, type, const, var,
exception), "name", "line" and "doc"; for a procedure also the
rendered "signature", the "params" as a list of {names, mode,
type} with mode one of "", "VAR", "OWN", "RO", the "result"
(null for a proper procedure), the "raises" list, and the
"attrib" (null, or the bracketed word).  Every string is the
one Text prints, so a tool that reads this and a person who
reads the page are reading the same document; the gather is
shared and the renderers differ.

It exists so that "does M.P exist, and what does it take" is a
tool call and not a grep: the one class of error a fluent
generator makes most is a real name it did not look up, or a
guessed one, and a table copied into a prompt drifts in a day
(docs/skills-plan.md par 1, par 4).

### Text (VAR pool: POOL ; root: PTR Ast.Node ; RO modName: STR ; VAR st: Stats) : STR RAISES IndexError

the Markdown reference for one file, and its measurements.

  root     -- the NFile node Parse.File answered, for a source
              that was lexed with Lex.Collect ARMED.  Without
              that there are no comments to attach and every
              declaration reports as undocumented; the emptiness
              would be silent, which is why the caller arms it
              and this cannot.
  modName  -- what to call the module in the heading.
  st       -- ACCUMULATED into, not reset, so a caller
              documenting a whole library sums as it goes.

Only DEFINITION units are read.  An IMPLEMENTATION comment is a
note to whoever maintains the code, not part of the contract,
and publishing it would be publishing the wrong thing.
