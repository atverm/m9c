# .m9f, written by hand

These programs are written in the `.m9f` notation of M9 (the M9 report,
Appendix A), not converted from M9. Each one sits where the line-break
rule has to decide whether a line ends a statement.

- `Breaks.m9f`: continued lines, brackets, comments between statements,
  `}` on its own line before `else` and `elsif`, and the two backslashes
  the rule needs.
- `Shapes.m9f` with `Tally.m9f`: a constant table, `case` with
  `default`, `loop` with `exit`, names written `to_` and `in_`, and the
  `;` a definition module still writes.

Run one with m9c, which writes each `NAME.m9` beside its `.m9f`:

```
m9c --run Breaks.m9f
```

`Breaks.out` and `Shapes.out` hold what they print. The gate
`runtime/test/m9f.sh` runs both, and checks that `Breaks.m9f` is refused
without its backslashes.
