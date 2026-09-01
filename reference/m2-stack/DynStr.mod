IMPLEMENTATION MODULE DynStr ;

FROM SYSTEM IMPORT ADDRESS ;
FROM StrLib IMPORT StrLen ;
FROM libc IMPORT malloc, realloc, free ;

TYPE
  CharView = POINTER TO ARRAY [0..0FFFFFFH] OF CHAR ;
  DString  = POINTER TO RECORD
    len, cap : CARDINAL ;
    buf      : ADDRESS ;
  END ;

PROCEDURE New () : DString ;
VAR d : DString ;
BEGIN
  d := malloc (SIZE (d^)) ;
  d^.len := 0 ;
  d^.cap := 16 ;
  d^.buf := malloc (d^.cap) ;
  RETURN d
END New ;

PROCEDURE AppendChar (d: DString; c: CHAR) ;
VAR v : CharView ;
BEGIN
  IF d^.len = d^.cap THEN
    d^.cap := d^.cap * 2 ;
    d^.buf := realloc (d^.buf, d^.cap)
  END ;
  v := d^.buf ;
  v^[d^.len] := c ;
  INC (d^.len)
END AppendChar ;

PROCEDURE Append (d: DString; s: ARRAY OF CHAR) ;
VAR i, k : CARDINAL ;
BEGIN
  k := StrLen (s) ;
  i := 0 ;
  WHILE i < k DO
    AppendChar (d, s[i]) ;
    INC (i)
  END
END Append ;

PROCEDURE Len (d: DString) : CARDINAL ;
BEGIN
  IF d = NIL THEN RETURN 0 END ;
  RETURN d^.len
END Len ;

PROCEDURE CharAt (d: DString; i: CARDINAL) : CHAR ;
VAR v : CharView ;
BEGIN
  IF (d = NIL) OR (i >= d^.len) THEN RETURN 0C END ;
  v := d^.buf ;
  RETURN v^[i]
END CharAt ;

PROCEDURE EqualArr (d: DString; s: ARRAY OF CHAR) : BOOLEAN ;
VAR i, k : CARDINAL ;
    v : CharView ;
BEGIN
  IF d = NIL THEN RETURN FALSE END ;
  k := StrLen (s) ;
  IF k # d^.len THEN RETURN FALSE END ;
  v := d^.buf ;
  i := 0 ;
  WHILE i < k DO
    IF v^[i] # s[i] THEN RETURN FALSE END ;
    INC (i)
  END ;
  RETURN TRUE
END EqualArr ;

PROCEDURE Dispose (VAR d: DString) ;
BEGIN
  IF d # NIL THEN
    free (d^.buf) ;
    free (d) ;
    d := NIL
  END
END Dispose ;

END DynStr.
