---
name: m9-lookup
description: Finding what already exists in M9 before writing it -- which module has a procedure, its exact signature, modes and RAISES set, and whether a module already does the job -- by asking the compiler (m9c --json) rather than remembering. Load before calling any library procedure from a .m9 file or before writing a new M9 module.
---

# Inventory before manufacturing

Two failure modes, both measured in the M9 repository:

* **Calling a name that is not there.**  The checker says `unknown
  procedure: M.P`.  In the baseline session 8 of 9 such names EXISTED
  and the module was simply not imported in the implementation; the
  ninth (`Math.AbsI64`) was guessed from Pascal.  Either way the fix
  is a lookup, and the lookup is a tool call.
* **Writing a module that exists.**  Three times: gm2's
  DynamicStrings reinvented; `Json.SliceEq`, `ZarrStore.Digits/Chars`
  and `Http.Bytes` as three private copies of what became
  `DynStr.Eq/Chars/Bytes`; upper/lower-case asked for in DynStr when
  `Text.Upper/Lower` already had the exact signature.

**This skill carries no names on purpose.**  Its first version had a
table of what Math, Io, Fmt, DynStr and Text contain; `Io.ListDir`
was added the next day and the table was wrong.  A copy drifts; the
compiler does not.

## The procedure

1. **Is the module imported HERE?**  An IMPLEMENTATION MODULE has its
   own IMPORT list; the definition's does not carry over.  Check this
   before anything else -- it is the top cause.

2. **Ask the compiler.**  `m9c --json` writes the DEFINITION module
   as data -- every exported name with its kind, parameters (names,
   mode, type), result, RAISES set and comment:

       cd /tmp && M9LIBRARY=$REPO/corpus $M9C --json $REPO/corpus/Math.m9
       python3 -c 'import json; d=json.load(open("/tmp/Math.json"))
       for x in d["declarations"]: print(x["kind"], x["name"],
           x.get("signature",""))'

   where `$M9C` is `m9c` on PATH from an installed package,
   `out/m9c` after `./build.sh`, or `runtime/test/m9c` after
   `runtime/test/m9c.sh`.  It writes `Math.md` beside the `.json` (the
   same gather rendered twice; the page is what `docs/modules/`
   holds).  For one name:

       python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
       print([x for x in d["declarations"] if x["name"]==sys.argv[2]])' \
           /tmp/Math.json Sqrt

   A module outside the corpus needs its dependencies named or on
   `M9LIBRARY`, exactly as compiling it would.  With a package
   installed, the library sources are in `/usr/lib/m9` (or the
   prefix's `lib/m9`), and `M9LIBRARY` is already set for them.

3. **Or read the page.**  `docs/modules/<M>.md` is the same document
   as prose, kept byte-identical to the compiler by `docdiff.sh`.
   `ls docs/modules` is the catalogue of what the corpus offers; a
   package installs the same pages under `/usr/share/doc/m9/modules`.

4. **Does a module already do the job?**  Grep the corpus (and any
   project beside it) for the CONSTRUCT before writing it:
   `grep -l 'PROCEDURE Split' corpus/*.m9`.  Mind
   the dependency direction -- `Text` imports `DynStr`, so a string
   utility that needs both goes in `Text`, never in `DynStr`.

5. **Read the definition, not the implementation**, for what a
   procedure promises: the DEFINITION MODULE is the contract and the
   checker enforces it both ways.

## Reading an entry

In the JSON, a procedure is

    {"kind":"procedure","name":"AppendChar","line":21,
     "signature":"AppendChar (VAR pool: POOL ; VAR d: PTR DString ; ch: CHAR)",
     "params":[{"names":["pool"],"mode":"VAR","type":"POOL"},
               {"names":["d"],"mode":"VAR","type":"PTR DString"},
               {"names":["ch"],"mode":"","type":"CHAR"}],
     "result":null,"raises":[],"attrib":null,
     "doc":"one scalar onto the end, ...","shared":false}

`mode` is `""` (value: a shared borrow), `VAR`, `OWN` or `RO`;
`result` is null for a proper procedure; `raises` is the list your
own RAISES must absorb when you call it; `attrib` is `SERIAL` or
`REENTRANT` on a foreign procedure.  In the page the heading is the
same signature and the `name -- text` lines are the parameters the
author explained.

## When the lookup finds nothing

Write the three lines rather than the module: an integer `Min` is
`IF a < b THEN RETURN a END ; RETURN b`.  A new module earns its
place by repetition -- the corpus rule is that the third private copy
becomes the shared procedure -- and by a differential test against
something that is not itself: numpy, polars, pyarrow, a raw C API, a
reference implementation.  Every numeric module in the corpus is
gated that way (`runtime/test/*_driver.c`, run by
`runtime/test/build.sh`), and a module without such an oracle is a
module that has only been inspected.
