IMPLEMENTATION MODULE Mat ;

FROM Storage IMPORT ALLOCATE ;
FROM SYSTEM IMPORT ADDRESS ;

TYPE
  Data   = POINTER TO ARRAY [0..0FFFFFFH] OF REAL ;
  Matrix = POINTER TO RECORD
    r, c : CARDINAL ;
    d    : Data ;
  END ;

PROCEDURE IsNaN (v: REAL) : BOOLEAN ;
BEGIN
  RETURN NOT (v = v)
END IsNaN ;

PROCEDURE New (rows, cols: CARDINAL) : Matrix ;
VAR
  m : Matrix ;
  a : ADDRESS ;
BEGIN
  ALLOCATE (a, SIZE (m^)) ;
  m := a ;
  m^.r := rows ;
  m^.c := cols ;
  ALLOCATE (a, rows * cols * SIZE (REAL)) ;
  m^.d := a ;
  RETURN m
END New ;

PROCEDURE Rows (m: Matrix) : CARDINAL ;
BEGIN
  RETURN m^.r
END Rows ;

PROCEDURE Cols (m: Matrix) : CARDINAL ;
BEGIN
  RETURN m^.c
END Cols ;

PROCEDURE Get (m: Matrix; r, c: CARDINAL) : REAL ;
BEGIN
  RETURN m^.d^[r * m^.c + c]
END Get ;

PROCEDURE Set (m: Matrix; r, c: CARDINAL; v: REAL) ;
BEGIN
  m^.d^[r * m^.c + c] := v
END Set ;

PROCEDURE ColReduce (m: Matrix; op: ReduceOp; VAR out: ARRAY OF REAL) ;
VAR
  r, c, n : CARDINAL ;
  acc, v  : REAL ;
BEGIN
  FOR c := 0 TO m^.c - 1 DO
    n := 0 ;
    acc := 0.0 ;
    FOR r := 0 TO m^.r - 1 DO
      v := m^.d^[r * m^.c + c] ;
      IF NOT IsNaN (v) THEN
        IF n = 0 THEN
          CASE op OF
            RMin, RMax : acc := v
          ELSE
            acc := v
          END
        ELSE
          CASE op OF
            RMean, RSum : acc := acc + v |
            RMin        : IF v < acc THEN acc := v END |
            RMax        : IF v > acc THEN acc := v END |
            RCount      :
          END
        END ;
        INC (n)
      END
    END ;
    IF c <= HIGH (out) THEN
      IF n = 0 THEN
        out[c] := 0.0 / 0.0            (* honest NaN for empty column *)
      ELSE
        CASE op OF
          RMean  : out[c] := acc / VAL (REAL, n) |
          RCount : out[c] := VAL (REAL, n)
        ELSE
          out[c] := acc
        END
      END
    END
  END
END ColReduce ;

PROCEDURE SubRowVector (m: Matrix; VAR v: ARRAY OF REAL) : Matrix ;
VAR
  res  : Matrix ;
  r, c : CARDINAL ;
BEGIN
  res := New (m^.r, m^.c) ;
  FOR r := 0 TO m^.r - 1 DO
    FOR c := 0 TO m^.c - 1 DO
      res^.d^[r * m^.c + c] := m^.d^[r * m^.c + c] - v[c]
    END
  END ;
  RETURN res
END SubRowVector ;

PROCEDURE MinMax (m: Matrix; VAR mn, mx: REAL) ;
VAR
  i, total : CARDINAL ;
  v        : REAL ;
  seen     : BOOLEAN ;
BEGIN
  total := m^.r * m^.c ;
  seen := FALSE ;
  mn := 0.0 ;  mx := 0.0 ;
  FOR i := 0 TO total - 1 DO
    v := m^.d^[i] ;
    IF NOT IsNaN (v) THEN
      IF NOT seen THEN
        mn := v ;  mx := v ;  seen := TRUE
      ELSE
        IF v < mn THEN mn := v END ;
        IF v > mx THEN mx := v END
      END
    END
  END
END MinMax ;

END Mat.
