# NbCells

Values handed from one program to the next BY NAME, through files:
what the cells of an M9 notebook share -- each cell is a whole
program (tools/jupyter) and nothing it computed outlives it -- and
what the steps of any pipeline share.  NbCells.PutF64s ('temps',
xs) in one cell, xs := NbCells.GetF64s (pool, 'temps') in a later
one.

WHERE: the directory $M9CELLS names -- the Jupyter kernel sets it
to NOTEBOOK.m9data beside the notebook -- else m9data in the
working directory.

HOW: one Parquet file per name, its kind in the file's name --
NAME.frame.parquet (a Frame), NAME.f64s.parquet and
NAME.i64s.parquet (one column, `value`), NAME.grid.parquet (a GRID
2 OF F64, one column per grid column, c0, c1, ..., a row of the
grid a row of the file).  Values are stored as their bits, NaN
included.  pandas reads every one of them -- read_parquet -- and a
grid's DataFrame .to_numpy () is the matrix.

THE KIND IS CHECKED WHEN A VALUE IS READ BACK, because the
compiler checking one cell cannot see what an earlier cell
stored: a Get of another kind raises WrongType naming both, a name
nothing stored raises Missing.  A name is letters and digits,
beginning with a letter, as an M9 identifier is -- it becomes a
file name, and nothing else may.  A Put replaces whatever the name
held, of any kind; the file is written beside and renamed, so a
reader never sees half of one.

### EXCEPTION Missing

nothing is stored under that name

### EXCEPTION WrongType

the name holds another kind: `stored` is what it is, `wanted`
what the Get asked for -- 'frame', 'f64s', 'i64s' or 'grid'

### Dir (VAR pool: POOL) : STR RAISES ValueRange

the directory the values live in: $M9CELLS, else m9data

### Kind (RO name: STR) : STR RAISES ValueRange, Faults.BadArg

what the name holds -- 'frame', 'f64s', 'i64s' or 'grid' -- or
the empty string when it holds nothing

### PutFrame (f: PTR Frame.Fr ; RO name: STR) RAISES Faults.BadArg, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### GetFrame (VAR pool: POOL ; RO name: STR) : PTR Frame.Fr RAISES Missing, WrongType, Faults.BadArg, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### PutF64s (RO name: STR ; RO KEPT v: SLICE OF F64) RAISES Faults.BadArg, Faults.SizeError, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### GetF64s (VAR pool: POOL ; RO name: STR) : SLICE OF F64 RAISES Missing, WrongType, Faults.BadArg, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### PutI64s (RO name: STR ; RO KEPT v: SLICE OF I64) RAISES Faults.BadArg, Faults.SizeError, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### GetI64s (VAR pool: POOL ; RO name: STR) : SLICE OF I64 RAISES Missing, WrongType, Faults.BadArg, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_

### PutGrid (RO name: STR ; RO g: GRID 2 OF F64) RAISES Faults.BadArg, Faults.SizeError, Io.IOError, ValueRange, Overflow, IndexError

a grid with no columns is refused: its file would have no rows
either, and the grid's first extent would be lost

### GetGrid (VAR pool: POOL ; RO name: STR) : GRID 2 OF F64 RAISES Missing, WrongType, Faults.BadArg, Io.IOError, ValueRange, Overflow, IndexError

_(undocumented)_
