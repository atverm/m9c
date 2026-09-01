MODULE zarrhttp ;

(* zarr v2 over HTTP in Modula-2, standing on two modules that did not
   exist an hour ago: Json and Http.  Reads .zarray properly (no string
   scanning), fetches chunks over the network, treats 404 as fill_value,
   verifies against the numpy/FPC reference values.                     *)

FROM SYSTEM IMPORT ADR ;
FROM StrLib IMPORT StrCopy, StrConCat ;
FROM NumberIO IMPORT CardToStr ;
FROM printshim IMPORT printd, printn ;
FROM cblosc IMPORT blosc_decompress ;
FROM Json IMPORT Node, Kind, Parse, KindOf, Field, Item, Count,
                 AsInt, StrIs, IsNull, JObject, JErrorK ;
FROM Http IMPORT Get ;

CONST
  Host    = '127.0.0.1' ;
  Port    = 8123 ;
  Base    = '/test.zarr/co2/' ;
  MaxR    = 200 ;
  MaxC    = 200 ;
  MaxBuf  = 65536 ;

VAR
  shapeR, shapeC, chunkR, chunkC : CARDINAL ;
  grid  : ARRAY [0..MaxR-1], [0..MaxC-1] OF REAL ;
  raw   : ARRAY [0..MaxBuf-1] OF CHAR ;
  chunk : ARRAY [0..MaxBuf-1] OF CHAR ;
  NaN   : REAL ;
  labelBuf : ARRAY [0..127] OF CHAR ;

PROCEDURE PrintD (label: ARRAY OF CHAR; v: REAL) ;
BEGIN
  StrCopy (label, labelBuf) ;
  printd (ADR (labelBuf), v)
END PrintD ;

PROCEDURE PrintN (label: ARRAY OF CHAR; n: INTEGER) ;
BEGIN
  StrCopy (label, labelBuf) ;
  printn (ADR (labelBuf), n)
END PrintN ;

PROCEDURE MakeNaN () : REAL ;
VAR
  bits : LONGCARD ;
  r    : POINTER TO REAL ;
BEGIN
  bits := 9221120237041090560 ;   (* 0x7FF8000000000000 *)
  r := ADR (bits) ;
  RETURN r^
END MakeNaN ;

PROCEDURE IsNaN (v: REAL) : BOOLEAN ;
BEGIN
  RETURN NOT (v = v)
END IsNaN ;

PROCEDURE LoadChunk (cr, cc: CARDINAL) ;
VAR
  path, num : ARRAY [0..255] OF CHAR ;
  bodyLen   : CARDINAL ;
  status, rc : INTEGER ;
  d : POINTER TO ARRAY [0..8191] OF REAL ;
  r, c, gr, gc : CARDINAL ;
BEGIN
  StrCopy (Base, path) ;
  CardToStr (cr, 0, num) ;  StrConCat (path, num, path) ;
  StrConCat (path, '.', path) ;
  CardToStr (cc, 0, num) ;  StrConCat (path, num, path) ;

  status := Get (Host, Port, path, ADR (raw), MaxBuf, bodyLen) ;

  IF status = 404 THEN
    (* zarr semantics: absent chunk means fill_value throughout *)
    FOR r := 0 TO chunkR-1 DO
      FOR c := 0 TO chunkC-1 DO
        gr := cr * chunkR + r ;  gc := cc * chunkC + c ;
        IF (gr < shapeR) AND (gc < shapeC) THEN grid[gr][gc] := NaN END
      END
    END ;
    RETURN
  END ;
  IF status # 200 THEN
    PrintN ('unexpected HTTP status: ', status) ;
    HALT
  END ;

  rc := blosc_decompress (ADR (raw), ADR (chunk),
                          VAL (LONGCARD, chunkR * chunkC * 8)) ;
  IF rc < 0 THEN
    PrintN ('blosc error: ', rc) ;
    HALT
  END ;

  d := ADR (chunk) ;
  FOR r := 0 TO chunkR-1 DO
    FOR c := 0 TO chunkC-1 DO
      gr := cr * chunkR + r ;  gc := cc * chunkC + c ;
      IF (gr < shapeR) AND (gc < shapeC) THEN
        grid[gr][gc] := d^[r * chunkC + c]
      END
    END
  END
END LoadChunk ;

VAR
  path : ARRAY [0..255] OF CHAR ;
  len  : CARDINAL ;
  status : INTEGER ;
  meta, a : Node ;
  cr, cc, r, c, n : CARDINAL ;
  sum : REAL ;
BEGIN
  NaN := MakeNaN () ;

  StrCopy (Base, path) ;
  StrConCat (path, '.zarray', path) ;
  status := Get (Host, Port, path, ADR (raw), MaxBuf, len) ;
  IF status # 200 THEN
    PrintN ('.zarray fetch failed, HTTP ', status) ;
    HALT
  END ;

  meta := Parse (ADR (raw), len) ;
  IF KindOf (meta) # JObject THEN
    PrintN ('.zarray is not a JSON object', 0) ;
    HALT
  END ;

  (* real metadata handling at last: validated, not scraped *)
  IF AsInt (Field (meta, 'zarr_format')) # 2 THEN
    PrintN ('not zarr v2', 0) ;  HALT
  END ;
  IF NOT StrIs (Field (meta, 'dtype'), '<f8') THEN
    PrintN ('dtype is not <f8', 0) ;  HALT
  END ;
  IF NOT StrIs (Field (meta, 'order'), 'C') THEN
    PrintN ('order is not C', 0) ;  HALT
  END ;
  IF NOT StrIs (Field (Field (meta, 'compressor'), 'id'), 'blosc') THEN
    PrintN ('compressor is not blosc', 0) ;  HALT
  END ;
  IF NOT (StrIs (Field (meta, 'fill_value'), 'NaN') OR
          IsNull (Field (meta, 'fill_value'))) THEN
    PrintN ('unsupported fill_value', 0) ;  HALT
  END ;

  a := Field (meta, 'shape') ;
  shapeR := VAL (CARDINAL, AsInt (Item (a, 0))) ;
  shapeC := VAL (CARDINAL, AsInt (Item (a, 1))) ;
  a := Field (meta, 'chunks') ;
  chunkR := VAL (CARDINAL, AsInt (Item (a, 0))) ;
  chunkC := VAL (CARDINAL, AsInt (Item (a, 1))) ;

  PrintN ('shape rows : ', VAL (INTEGER, shapeR)) ;
  PrintN ('shape cols : ', VAL (INTEGER, shapeC)) ;
  PrintN ('chunk rows : ', VAL (INTEGER, chunkR)) ;
  PrintN ('chunk cols : ', VAL (INTEGER, chunkC)) ;

  FOR cr := 0 TO (shapeR + chunkR - 1) DIV chunkR - 1 DO
    FOR cc := 0 TO (shapeC + chunkC - 1) DIV chunkC - 1 DO
      LoadChunk (cr, cc)
    END
  END ;

  PrintD ('co2[0,0]   = ', grid[0][0]) ;
  PrintD ('co2[99,49] = ', grid[99][49]) ;
  PrintD ('co2[42,17] = ', grid[42][17]) ;
  PrintD ('co2[10,5]  = ', grid[10][5]) ;

  sum := 0.0 ;  n := 0 ;
  FOR r := 0 TO shapeR-1 DO
    FOR c := 0 TO shapeC-1 DO
      IF NOT IsNaN (grid[r][c]) THEN
        sum := sum + grid[r][c] ;
        INC (n)
      END
    END
  END ;
  PrintD ('nanmean    = ', sum / VAL (REAL, n)) ;
  PrintN ('n          = ', VAL (INTEGER, n))
END zarrhttp.
