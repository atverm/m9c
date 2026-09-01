IMPLEMENTATION MODULE Json ;

FROM Storage IMPORT ALLOCATE ;
FROM SYSTEM IMPORT ADDRESS ;
FROM StrLib IMPORT StrLen ;
IMPORT DynStr ;

TYPE
  CharView = POINTER TO ARRAY [0..0FFFFFFH] OF CHAR ;

  Node = POINTER TO NodeRec ;
  NodeRec = RECORD
    kind    : Kind ;
    num     : REAL ;
    inum    : INTEGER ;
    bval    : BOOLEAN ;
    str     : DynStr.DString ;
    name    : DynStr.DString ;              (* member name inside object *)
    first   : Node ;                        (* children (object/array)  *)
    next    : Node ;                        (* sibling                  *)
    count   : CARDINAL ;
  END ;

VAR
  src : CharView ;
  pos, srcLen : CARDINAL ;

PROCEDURE NewNode (k: Kind) : Node ;
VAR n : Node ;
BEGIN
  ALLOCATE (n, SIZE (NodeRec)) ;
  n^.kind := k ;   n^.first := NIL ;  n^.next := NIL ;
  n^.count := 0 ;
  n^.str := NIL ;  n^.name := NIL ;
  n^.num := 0.0 ;  n^.inum := 0 ;  n^.bval := FALSE ;
  RETURN n
END NewNode ;

PROCEDURE Cur () : CHAR ;
BEGIN
  IF pos < srcLen THEN RETURN src^[pos] ELSE RETURN 0C END
END Cur ;

PROCEDURE Skip ;
BEGIN
  WHILE (pos < srcLen) AND
        ((src^[pos] = ' ') OR (src^[pos] = CHR(9)) OR
         (src^[pos] = CHR(10)) OR (src^[pos] = CHR(13))) DO
    INC (pos)
  END
END Skip ;

PROCEDURE ParseString (VAR dest: DynStr.DString) : BOOLEAN ;
(* unbounded now: DynStr grows as needed *)
VAR c : CHAR ;
BEGIN
  IF Cur () # '"' THEN RETURN FALSE END ;
  INC (pos) ;
  dest := DynStr.New () ;
  WHILE (pos < srcLen) AND (src^[pos] # '"') DO
    c := src^[pos] ;
    IF c = '\' THEN
      INC (pos) ;                (* keep escaped char literally; enough *)
      c := src^[pos]             (* for metadata; \uXXXX not handled    *)
    END ;
    DynStr.AppendChar (dest, c) ;
    INC (pos)
  END ;
  IF Cur () # '"' THEN RETURN FALSE END ;
  INC (pos) ;
  RETURN TRUE
END ParseString ;

PROCEDURE ParseNumber (n: Node) ;
VAR
  neg, negE : BOOLEAN ;
  ip        : INTEGER ;
  frac, sc  : REAL ;
  ex        : INTEGER ;
BEGIN
  neg := FALSE ;
  IF Cur () = '-' THEN neg := TRUE ; INC (pos) END ;
  ip := 0 ;
  WHILE (Cur () >= '0') AND (Cur () <= '9') DO
    ip := ip * 10 + VAL (INTEGER, ORD (Cur ()) - ORD ('0')) ;
    INC (pos)
  END ;
  n^.num := VAL (REAL, ip) ;
  IF Cur () = '.' THEN
    INC (pos) ;
    frac := 0.0 ;  sc := 0.1 ;
    WHILE (Cur () >= '0') AND (Cur () <= '9') DO
      frac := frac + sc * VAL (REAL, ORD (Cur ()) - ORD ('0')) ;
      sc := sc / 10.0 ;
      INC (pos)
    END ;
    n^.num := n^.num + frac
  END ;
  IF (Cur () = 'e') OR (Cur () = 'E') THEN
    INC (pos) ;
    negE := FALSE ;
    IF Cur () = '-' THEN negE := TRUE ; INC (pos)
    ELSIF Cur () = '+' THEN INC (pos) END ;
    ex := 0 ;
    WHILE (Cur () >= '0') AND (Cur () <= '9') DO
      ex := ex * 10 + VAL (INTEGER, ORD (Cur ()) - ORD ('0')) ;
      INC (pos)
    END ;
    WHILE ex > 0 DO
      IF negE THEN n^.num := n^.num / 10.0 ELSE n^.num := n^.num * 10.0 END ;
      DEC (ex)
    END
  END ;
  IF neg THEN
    n^.num := -n^.num ;
    ip := -ip
  END ;
  n^.inum := ip
END ParseNumber ;

PROCEDURE Match (lit: ARRAY OF CHAR) : BOOLEAN ;
VAR i, k : CARDINAL ;
BEGIN
  k := StrLen (lit) ;
  IF pos + k > srcLen THEN RETURN FALSE END ;
  FOR i := 0 TO k - 1 DO
    IF src^[pos + i] # lit[i] THEN RETURN FALSE END
  END ;
  pos := pos + k ;
  RETURN TRUE
END Match ;

(* gm2 permits use-before-declaration at module scope, so the
   ParseValue <-> ParseObject/ParseArray mutual recursion needs no
   FORWARD (which PIM never had anyway -- that was my Pascal accent). *)

PROCEDURE ParseObject () : Node ;
VAR
  n, child, last : Node ;
  nm : DynStr.DString ;
BEGIN
  n := NewNode (JObject) ;
  INC (pos) ;                                  (* consume '{' *)
  Skip ;
  last := NIL ;
  IF Cur () = '}' THEN INC (pos) ; RETURN n END ;
  LOOP
    Skip ;
    IF NOT ParseString (nm) THEN n^.kind := JErrorK ; RETURN n END ;
    Skip ;
    IF Cur () # ':' THEN n^.kind := JErrorK ; RETURN n END ;
    INC (pos) ;
    Skip ;
    child := ParseValue () ;
    IF (child = NIL) OR (child^.kind = JErrorK) THEN
      n^.kind := JErrorK ; RETURN n
    END ;
    child^.name := nm ;         (* pointer handover: nm is fresh each pass *)
    IF last = NIL THEN n^.first := child ELSE last^.next := child END ;
    last := child ;
    INC (n^.count) ;
    Skip ;
    IF Cur () = ',' THEN INC (pos)
    ELSIF Cur () = '}' THEN INC (pos) ; RETURN n
    ELSE n^.kind := JErrorK ; RETURN n END
  END
END ParseObject ;

PROCEDURE ParseArray () : Node ;
VAR n, child, last : Node ;
BEGIN
  n := NewNode (JArray) ;
  INC (pos) ;                                  (* consume '[' *)
  Skip ;
  last := NIL ;
  IF Cur () = ']' THEN INC (pos) ; RETURN n END ;
  LOOP
    child := ParseValue () ;
    IF (child = NIL) OR (child^.kind = JErrorK) THEN
      n^.kind := JErrorK ; RETURN n
    END ;
    IF last = NIL THEN n^.first := child ELSE last^.next := child END ;
    last := child ;
    INC (n^.count) ;
    Skip ;
    IF Cur () = ',' THEN INC (pos) ; Skip
    ELSIF Cur () = ']' THEN INC (pos) ; RETURN n
    ELSE n^.kind := JErrorK ; RETURN n END
  END
END ParseArray ;

PROCEDURE ParseValue () : Node ;
VAR n : Node ;
BEGIN
  Skip ;
  CASE Cur () OF
    '{' : RETURN ParseObject () |
    '[' : RETURN ParseArray () |
    '"' : n := NewNode (JString) ;
          IF NOT ParseString (n^.str) THEN n^.kind := JErrorK END ;
          RETURN n
  ELSE
    IF Match ('true') THEN
      n := NewNode (JBool) ;  n^.bval := TRUE ;  RETURN n
    ELSIF Match ('false') THEN
      n := NewNode (JBool) ;  n^.bval := FALSE ;  RETURN n
    ELSIF Match ('null') THEN
      RETURN NewNode (JNull)
    ELSIF (Cur () = '-') OR ((Cur () >= '0') AND (Cur () <= '9')) THEN
      n := NewNode (JNumber) ;
      ParseNumber (n) ;
      RETURN n
    ELSE
      RETURN NewNode (JErrorK)
    END
  END
END ParseValue ;

PROCEDURE Parse (buf: ADDRESS; len: CARDINAL) : Node ;
BEGIN
  src := buf ;
  srcLen := len ;
  pos := 0 ;
  RETURN ParseValue ()
END Parse ;

PROCEDURE KindOf (n: Node) : Kind ;
BEGIN
  IF n = NIL THEN RETURN JErrorK END ;
  RETURN n^.kind
END KindOf ;

PROCEDURE Field (obj: Node; name: ARRAY OF CHAR) : Node ;
VAR c : Node ;
BEGIN
  IF (obj = NIL) OR (obj^.kind # JObject) THEN RETURN NIL END ;
  c := obj^.first ;
  WHILE c # NIL DO
    IF DynStr.EqualArr (c^.name, name) THEN RETURN c END ;
    c := c^.next
  END ;
  RETURN NIL
END Field ;

PROCEDURE Item (arr: Node; i: CARDINAL) : Node ;
VAR c : Node ;
BEGIN
  IF (arr = NIL) OR (arr^.kind # JArray) THEN RETURN NIL END ;
  c := arr^.first ;
  WHILE (c # NIL) AND (i > 0) DO
    c := c^.next ;
    DEC (i)
  END ;
  RETURN c
END Item ;

PROCEDURE Count (arr: Node) : CARDINAL ;
BEGIN
  IF arr = NIL THEN RETURN 0 END ;
  RETURN arr^.count
END Count ;

PROCEDURE AsInt (n: Node) : INTEGER ;
BEGIN
  IF (n = NIL) OR (n^.kind # JNumber) THEN RETURN 0 END ;
  RETURN n^.inum
END AsInt ;

PROCEDURE AsReal (n: Node) : REAL ;
BEGIN
  IF (n = NIL) OR (n^.kind # JNumber) THEN RETURN 0.0 END ;
  RETURN n^.num
END AsReal ;

PROCEDURE StrIs (n: Node; s: ARRAY OF CHAR) : BOOLEAN ;
BEGIN
  IF (n = NIL) OR (n^.kind # JString) THEN RETURN FALSE END ;
  RETURN DynStr.EqualArr (n^.str, s)
END StrIs ;

PROCEDURE IsNull (n: Node) : BOOLEAN ;
BEGIN
  RETURN (n # NIL) AND (n^.kind = JNull)
END IsNull ;

END Json.
