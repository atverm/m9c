MODULE corodemo ;

(* PIM coroutines: Wirth's 1978 concurrency primitive.  Two coroutines
   hand control back and forth explicitly with TRANSFER -- no scheduler,
   no preemption, no races possible.  Policy is the caller's problem.  *)

FROM SYSTEM IMPORT PROCESS, NEWPROCESS, TRANSFER, ADR ;
FROM printshim IMPORT printn ;
FROM StrLib IMPORT StrCopy ;

VAR
  mainCo, ping, pong : PROCESS ;
  wsp1, wsp2 : ARRAY [0..65535] OF CHAR ;
  lbl : ARRAY [0..63] OF CHAR ;
  turns : CARDINAL ;

PROCEDURE PingProc ;
BEGIN
  LOOP
    StrCopy ('ping, turn ', lbl) ;
    printn (ADR (lbl), VAL (INTEGER, turns)) ;
    TRANSFER (ping, pong)
  END
END PingProc ;

PROCEDURE PongProc ;
BEGIN
  LOOP
    StrCopy ('  pong, turn ', lbl) ;
    printn (ADR (lbl), VAL (INTEGER, turns)) ;
    INC (turns) ;
    IF turns = 3 THEN
      TRANSFER (pong, mainCo)          (* enough; hand back to mainCo *)
    END ;
    TRANSFER (pong, ping)
  END
END PongProc ;

BEGIN
  turns := 0 ;
  NEWPROCESS (PingProc, ADR (wsp1), SIZE (wsp1), ping) ;
  NEWPROCESS (PongProc, ADR (wsp2), SIZE (wsp2), pong) ;
  TRANSFER (mainCo, ping) ;
  StrCopy ('back in mainCo after ', lbl) ;
  printn (ADR (lbl), VAL (INTEGER, turns))
END corodemo.
