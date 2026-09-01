IMPLEMENTATION MODULE Http ;

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM StrLib IMPORT StrCopy, StrConCat, StrLen ;
FROM libc IMPORT read, write, close ;
FROM tcpshim IMPORT tcp_connect ;

CONST
  RecvMax = 1048576 ;

TYPE
  CharView = POINTER TO ARRAY [0..0FFFFFFH] OF CHAR ;

VAR
  recvBuf : ARRAY [0..RecvMax-1] OF CHAR ;

PROCEDURE Get (host: ARRAY OF CHAR; port: CARDINAL;
               path: ARRAY OF CHAR;
               body: ADDRESS; maxLen: CARDINAL;
               VAR bodyLen: CARDINAL) : INTEGER ;
VAR
  req     : ARRAY [0..511] OF CHAR ;
  hostz   : ARRAY [0..255] OF CHAR ;
  fd      : INTEGER ;
  n       : INTEGER ;
  total   : CARDINAL ;
  i, hEnd : CARDINAL ;
  status  : INTEGER ;
  dst     : CharView ;
BEGIN
  bodyLen := 0 ;
  StrCopy (host, hostz) ;
  fd := tcp_connect (ADR (hostz), VAL (INTEGER, port)) ;
  IF fd < 0 THEN RETURN -1 END ;

  StrCopy  ('GET ', req) ;
  StrConCat (req, path, req) ;
  StrConCat (req, ' HTTP/1.0', req) ;
  i := StrLen (req) ;
  req[i] := CHR(13) ;  req[i+1] := CHR(10) ;  req[i+2] := 0C ;
  StrConCat (req, 'Host: ', req) ;
  StrConCat (req, hostz, req) ;
  i := StrLen (req) ;
  req[i]   := CHR(13) ;  req[i+1] := CHR(10) ;
  req[i+2] := CHR(13) ;  req[i+3] := CHR(10) ;  req[i+4] := 0C ;

  IF write (fd, ADR (req), StrLen (req)) < 0 THEN
    n := close (fd) ;
    RETURN -1
  END ;

  total := 0 ;
  LOOP
    n := read (fd, ADR (recvBuf[total]), RecvMax - total) ;
    IF n <= 0 THEN EXIT END ;
    total := total + VAL (CARDINAL, n) ;
    IF total >= RecvMax THEN EXIT END
  END ;
  n := close (fd) ;
  IF total < 12 THEN RETURN -1 END ;

  (* status from "HTTP/1.x NNN" *)
  status := (VAL (INTEGER, ORD (recvBuf[9]))  - 48) * 100 +
            (VAL (INTEGER, ORD (recvBuf[10])) - 48) * 10  +
            (VAL (INTEGER, ORD (recvBuf[11])) - 48) ;

  (* find CRLFCRLF *)
  hEnd := 0 ;
  i := 3 ;
  WHILE (i < total) AND (hEnd = 0) DO
    IF (recvBuf[i-3] = CHR(13)) AND (recvBuf[i-2] = CHR(10)) AND
       (recvBuf[i-1] = CHR(13)) AND (recvBuf[i]   = CHR(10)) THEN
      hEnd := i + 1
    END ;
    INC (i)
  END ;
  IF hEnd = 0 THEN RETURN -1 END ;

  dst := body ;
  i := 0 ;
  WHILE (hEnd + i < total) AND (i < maxLen) DO
    dst^[i] := recvBuf[hEnd + i] ;
    INC (i)
  END ;
  bodyLen := i ;
  RETURN status
END Get ;

END Http.
