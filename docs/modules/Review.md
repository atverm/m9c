# Review

What a reviewer still has to read, as one page.

The checker's work is invisible when it succeeds: a module that
compiles says nothing about what was proved and nothing about what
was merely written down.  This is the printing pass that says it
(docs/wishlist.md item 1, docs/plan-0.14.md stage 1), and its rule
is that it adds NO OPINION: every line is a count of something in
the tree, with the lines where it stands.

An ordinary client, as Doc is: it reads Ast through its published
surface and nothing else.  What the CHECKER examined, and what it
passed over because a type was unknown, is the checker's to count:
the caller hands those counts in (Stat below) and this module
prints them without importing the checker.  The one rule it can
speak for by itself is the one that needs no type: a function
answers on every path (report par 3 rule 4), which this page's
first cut found unenforced on 2026-10-01 by counting it from the
tree.

### TYPE Stat

where the first passed-over sites
stand, as text: `12, 40, 41, ...';
empty when nothing was passed over

### Page (root: PTR Ast.Node ; RO modName: UTF ; checked: BOOL ; RO stats: SLICE OF Stat ; RO writes: SLICE OF UTF ; RO stale: SLICE OF UTF ; RO strs: SLICE OF UTF ; RO adrs: SLICE OF UTF) : UTF

the review page for one parsed file.

  root    -- the NFile node Parse.File answered.
  modName -- what to call it in the heading.
  checked -- TRUE when the caller ran the checker over this
             file and it accepted it, which is what `m9c
             --review` does before it prints.  It decides what
             the first section may CLAIM: with it, that every
             function answers on every path was proved; without
             it the same count is only what the tree shows, and
             the section says so.
  stats   -- the checker's counts, printed under PROVED when
             `checked`: one row each, the examined count and,
             beside it, what was passed over for an unknown
             type.  Empty from a caller that ran no checker.
  writes  -- the THREADs the checker found writing a STATEFUL
             module's state (Sem.ThreadWrite), each `LINE what',
             printed under TRUSTED: the checker cannot see a
             join, so whether two threads meet there is the
             reviewer's to read (report par 6).  Empty from a
             caller that ran no checker.
  stale   -- the calls of a STR procedure whose module declares a
             UTF twin (Sem.StaleCall), each `LINE Mod.P ->
             Mod.PUtf', printed under COUNTED: the deprecated
             forms of the UTF transition a module still uses, the
             edits it owes (docs/utf8-plan.md).  Empty from a
             caller that ran no checker.
  strs    -- the uses of a STR that the UTF-8 switch refuses
             (Sem.StrSite): a subscript, a write through one, a
             LEN, each `LINE KIND what', printed under COUNTED --
             the edits the switch will ask of the module, by name,
             before it comes (docs/utf8-stage4-plan.md, 4b).  Empty
             from a caller that ran no checker.

Four sections: PROVED (or, unchecked, the functions that can
reach their END without answering, named from the tree alone),
what a person DECIDED (each named pool, pool parameter, KEPT,
HEAP, owned allocation, THREAD and module variable), what is
TRUSTED (UNSAFE units, foreign procedures), and what there was
to check.  A section with nothing in it still prints its
zeroes: an absent line and a zero are different claims.
