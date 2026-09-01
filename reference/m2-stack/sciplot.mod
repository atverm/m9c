MODULE sciplot ;

(* The Modula-2 scientific stack, assembled: read the co2 zarr array,
   compute column statistics and an anomaly field with Mat (no FOR
   loops out here), and render matplotlib-styled SVGs with Plot.      *)

FROM FIO IMPORT File, OpenToRead, Close, ReadNBytes, Exists ;
FROM SYSTEM IMPORT ADR ;
FROM StrLib IMPORT StrCopy, StrConCat ;
FROM NumberIO IMPORT CardToStr ;
FROM printshim IMPORT printd, printn ;
FROM cblosc IMPORT blosc_decompress ;
FROM Json IMPORT Node, Parse, Field, Item, AsInt, StrIs ;
FROM Mat IMPORT Matrix, New, Set, Get, ColReduce, SubRowVector, RMean,
                RMin, RMax ;
FROM Plot IMPORT ClearFigure, AddLine, Render, RenderHeat,
                 CViridis, CCoolwarm ;

CONST
  StoreDir = '/home/claude/test.zarr/co2/' ;
  MaxBuf   = 65536 ;

VAR
  raw, chunk : ARRAY [0..MaxBuf-1] OF CHAR ;
  shapeR, shapeC, chunkR, chunkC : CARDINAL ;
  grid : Matrix ;
  NaN  : REAL ;
  labelBuf : ARRAY [0..127] OF CHAR ;

PROCEDURE PrintD (label: ARRAY OF CHAR; v: REAL) ;
BEGIN
  StrCopy (label, labelBuf) ;
  printd (ADR (labelBuf), v)
END PrintD ;

PROCEDURE MakeNaN () : REAL ;
VAR
  bits : LONGCARD ;
  r    : POINTER TO REAL ;
BEGIN
  bits := 9221120237041090560 ;
  r := ADR (bits) ;
  RETURN r^
END MakeNaN ;

PROCEDURE ReadWhole (VAR name: ARRAY OF CHAR) : CARDINAL ;
VAR
  f : File ;
  n : CARDINAL ;
BEGIN
  IF NOT Exists (name) THEN RETURN 0 END ;
  f := OpenToRead (name) ;
  n := ReadNBytes (f, MaxBuf, ADR (raw)) ;
  Close (f) ;
  RETURN n
END ReadWhole ;

PROCEDURE LoadChunk (cr, cc: CARDINAL) ;
VAR
  name, num : ARRAY [0..255] OF CHAR ;
  n : CARDINAL ;
  rc : INTEGER ;
  d : POINTER TO ARRAY [0..8191] OF REAL ;
  r, c, gr, gc : CARDINAL ;
BEGIN
  StrCopy (StoreDir, name) ;
  CardToStr (cr, 0, num) ;  StrConCat (name, num, name) ;
  StrConCat (name, '.', name) ;
  CardToStr (cc, 0, num) ;  StrConCat (name, num, name) ;
  n := ReadWhole (name) ;
  FOR r := 0 TO chunkR-1 DO
    FOR c := 0 TO chunkC-1 DO
      gr := cr * chunkR + r ;  gc := cc * chunkC + c ;
      IF (gr < shapeR) AND (gc < shapeC) THEN
        IF n = 0 THEN
          Set (grid, gr, gc, NaN)
        END
      END
    END
  END ;
  IF n = 0 THEN RETURN END ;
  rc := blosc_decompress (ADR (raw), ADR (chunk),
                          VAL (LONGCARD, chunkR * chunkC * 8)) ;
  d := ADR (chunk) ;
  FOR r := 0 TO chunkR-1 DO
    FOR c := 0 TO chunkC-1 DO
      gr := cr * chunkR + r ;  gc := cc * chunkC + c ;
      IF (gr < shapeR) AND (gc < shapeC) THEN
        Set (grid, gr, gc, d^[r * chunkC + c])
      END
    END
  END
END LoadChunk ;

VAR
  name : ARRAY [0..255] OF CHAR ;
  len, cr, cc, i : CARDINAL ;
  meta, a : Node ;
  colMean, colMin, colMax, xs : ARRAY [0..199] OF REAL ;
  anom : Matrix ;
BEGIN
  NaN := MakeNaN () ;

  StrCopy (StoreDir, name) ;
  StrConCat (name, '.zarray', name) ;
  len := ReadWhole (name) ;
  meta := Parse (ADR (raw), len) ;
  IF (AsInt (Field (meta, 'zarr_format')) # 2) OR
     (NOT StrIs (Field (meta, 'dtype'), '<f8')) THEN
    PrintD ('bad metadata', 0.0) ;
    HALT
  END ;
  a := Field (meta, 'shape') ;
  shapeR := VAL (CARDINAL, AsInt (Item (a, 0))) ;
  shapeC := VAL (CARDINAL, AsInt (Item (a, 1))) ;
  a := Field (meta, 'chunks') ;
  chunkR := VAL (CARDINAL, AsInt (Item (a, 0))) ;
  chunkC := VAL (CARDINAL, AsInt (Item (a, 1))) ;

  grid := New (shapeR, shapeC) ;
  FOR cr := 0 TO (shapeR + chunkR - 1) DIV chunkR - 1 DO
    FOR cc := 0 TO (shapeC + chunkC - 1) DIV chunkC - 1 DO
      LoadChunk (cr, cc)
    END
  END ;

  (* ---- the numpy moment: statistics without visible loops ---- *)
  ColReduce (grid, RMean, colMean) ;
  ColReduce (grid, RMin,  colMin) ;
  ColReduce (grid, RMax,  colMax) ;
  anom := SubRowVector (grid, colMean) ;

  PrintD ('colMean[0]  = ', colMean[0]) ;
  PrintD ('colMean[25] = ', colMean[25]) ;
  PrintD ('colMax[49]  = ', colMax[49]) ;

  FOR i := 0 TO shapeC - 1 DO
    xs[i] := VAL (REAL, i)
  END ;

  ClearFigure ;
  AddLine (xs, colMax,  shapeC, 1, 'column max') ;
  AddLine (xs, colMean, shapeC, 0, 'column mean') ;
  AddLine (xs, colMin,  shapeC, 2, 'column min') ;
  Render ('/home/claude/m2/co2_columns.svg',
          'CO2 column statistics (zarr via Modula-2)',
          'column index', 'CO2 [ppm]') ;

  RenderHeat ('/home/claude/m2/co2_field.svg',
              'CO2 field - white block is the missing chunk (fill=NaN)',
              grid, CViridis, FALSE) ;

  RenderHeat ('/home/claude/m2/co2_anomaly.svg',
              'CO2 anomaly vs column mean (Mat.SubRowVector)',
              anom, CCoolwarm, TRUE) ;

  PrintD ('plots written', 3.0)
END sciplot.
