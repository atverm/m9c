MODULE excdemo ;

(* ISO Modula-2 exceptions, over Wirth's dead body: an explicit RAISE
   caught in a handler, then a runtime array-bounds violation caught
   and identified via M2EXCEPTION.                                    *)

FROM EXCEPTIONS IMPORT ExceptionSource, AllocateSource, RAISE,
                       IsCurrentSource ;
FROM M2EXCEPTION IMPORT M2Exceptions, M2Exception, IsM2Exception ;
FROM STextIO IMPORT WriteString, WriteLn ;
FROM SWholeIO IMPORT WriteInt ;

VAR
  src : ExceptionSource ;

PROCEDURE Risky (ppm: INTEGER) ;
BEGIN
  IF ppm < 0 THEN
    RAISE (src, 1, 'negative concentration is not physics')
  END ;
  WriteString ('accepted ppm = ') ;
  WriteInt (ppm, 0) ;
  WriteLn
END Risky ;

PROCEDURE TryRisky (ppm: INTEGER) ;
BEGIN
  Risky (ppm)
EXCEPT
  IF IsCurrentSource (src) THEN
    WriteString ('caught domain exception: bad input ') ;
    WriteInt (ppm, 0) ;
    WriteLn ;
    RETURN                         (* handled: complete the call *)
  END
END TryRisky ;

PROCEDURE OutOfBounds ;
VAR
  a : ARRAY [0..9] OF INTEGER ;
  i : INTEGER ;
BEGIN
  i := 42 ;
  a[i] := 1 ;                      (* runtime check should raise *)
  WriteString ('unreachable') ; WriteLn
EXCEPT
  IF IsM2Exception () THEN
    IF M2Exception () = indexException THEN
      WriteString ('caught indexException: a[42] on ARRAY [0..9]') ;
      WriteLn ;
      RETURN
    END
  END
END OutOfBounds ;

BEGIN
  AllocateSource (src) ;
  TryRisky (415) ;
  TryRisky (-3) ;
  WriteString ('still running after domain exception') ; WriteLn ;
  OutOfBounds ;
  WriteString ('still running after bounds exception') ; WriteLn
END excdemo.
