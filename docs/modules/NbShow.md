# NbShow

A value shown in a notebook cell.

A cell holding only an expression shows its value
(docs/kernel-show-plan.md): `m9c --show` asks the checker for the
expression's type and writes a one-line program that calls the
procedure below made for that type.  So nothing here guesses a
type, and a type with no procedure is refused by m9c, by name.

Every procedure prints a plain-text form.  A table (a GRID, a
Frame) also prints an HTML form, between two marker lines the
kernel takes out and shows as the cell's rich output; outside a
notebook they are two lines of control characters around a table.

Three promises.  A real is printed by Fmt.Short, so what is shown
reads back to the same double.  A cut-down display says what it
left out: a list over 20 values shows the first and last 10 and
how many more, a grid likewise by rows and columns, a frame over
60 rows its first and last 5 (pandas' rule, Alex 2026-10-05).  And
a missing value in a frame is `null`, never a number.

### CONST MaxList

a list or grid side longer than this is cut

### CONST MaxRows

a frame longer than this shows 5 + 5 rows

### Int (v: I64)

_(documented with the group below)_

### Real (v: F64)

_(documented with the group below)_

### Bool (v: BOOL)

_(documented with the group below)_

### Char (c: CHAR)

_(documented with the group below)_

### Str (RO s: STR)

_(documented with the group below)_

### Ints (RO v: SLICE OF I64)

_(documented with the group below)_

### Reals (RO v: SLICE OF F64)

_(documented with the group below)_

### Bools (RO v: SLICE OF BOOL)

_(documented with the group below)_

### Strs (RO v: SLICE OF STR)

_(documented with the group below)_

### Grid (RO g: GRID 2 OF F64)

_(documented with the group below)_

### Table (f: PTR Frame.Fr)

_(documented with the group below)_

### Series (ts: PTR Frame.Ts)

each prints its value; Grid, Table and Series the HTML form too

### Raised (RO what: STR)

the expression raised `what` instead of answering: said on the
error stream, and the program exits 1

### StrText (RO s: STR) : STR

in quotes, ' unless the string holds one; over 1000 characters
the first 1000, then ` ... (n characters)'

### IntsText (RO v: SLICE OF I64) : STR

_(documented with the group below)_

### RealsText (RO v: SLICE OF F64) : STR

_(documented with the group below)_

### BoolsText (RO v: SLICE OF BOOL) : STR

_(documented with the group below)_

### StrsText (RO v: SLICE OF STR) : STR

[a, b, c]; over MaxList values the first and last 10 with
`... n more ...` between them and the count after

### GridText (RO g: GRID 2 OF F64) : STR

_(documented with the group below)_

### GridHtml (RO g: GRID 2 OF F64) : STR

_(documented with the group below)_

### TableText (f: PTR Frame.Fr) : STR

_(documented with the group below)_

### TableHtml (f: PTR Frame.Fr) : STR

_(documented with the group below)_

### SeriesText (ts: PTR Frame.Ts) : STR

_(documented with the group below)_

### SeriesHtml (ts: PTR Frame.Ts) : STR

the texts the procedures above print, for a test to hold
