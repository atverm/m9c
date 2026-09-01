MODULE srcdemo ;

(* Inheritance by hand, the way M2 (and C, and pre-1988 everything)
   did it: a base record whose first field is a dispatch procedure,
   "subclasses" that embed the base as their first member, and an
   unchecked downcast inside each method.  One call site, two
   transports: the polymorphism our FPC ZarrStore faked with an
   IF FIsHttp branch.                                               *)

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM Storage IMPORT ALLOCATE ;
FROM FIO IMPORT File, OpenToRead, Close, ReadNBytes, Exists ;
FROM StrLib IMPORT StrCopy, StrConCat ;
FROM printshim IMPORT printn ;
IMPORT Http ;

TYPE
  Source     = POINTER TO SourceDesc ;
  FetchProc  = PROCEDURE (Source, ARRAY OF CHAR,
                          ADDRESS, CARDINAL, VAR CARDINAL) : BOOLEAN ;
  SourceDesc = RECORD
    fetch : FetchProc ;                  (* one-slot vtable *)
  END ;

  FileSource = POINTER TO FileSourceDesc ;
  FileSourceDesc = RECORD
    base : SourceDesc ;                  (* embedding = inheritance *)
    dir  : ARRAY [0..255] OF CHAR ;
  END ;

  HttpSource = POINTER TO HttpSourceDesc ;
  HttpSourceDesc = RECORD
    base : SourceDesc ;
    host : ARRAY [0..127] OF CHAR ;
    path : ARRAY [0..255] OF CHAR ;
    port : CARDINAL ;
  END ;

VAR
  labelBuf : ARRAY [0..127] OF CHAR ;

PROCEDURE PrintN (label: ARRAY OF CHAR; n: INTEGER) ;
BEGIN
  StrCopy (label, labelBuf) ;
  printn (ADR (labelBuf), n)
END PrintN ;

(* ---- "method" of FileSource ---- *)
PROCEDURE FileFetch (s: Source; rel: ARRAY OF CHAR;
                     buf: ADDRESS; max: CARDINAL;
                     VAR len: CARDINAL) : BOOLEAN ;
VAR
  fs   : FileSource ;
  a    : ADDRESS ;
  name : ARRAY [0..511] OF CHAR ;
  f    : File ;
BEGIN
  a := s ;  fs := a ;                    (* the unchecked downcast, PIM style *)
  StrCopy (fs^.dir, name) ;
  StrConCat (name, rel, name) ;
  len := 0 ;
  IF NOT Exists (name) THEN RETURN FALSE END ;
  f := OpenToRead (name) ;
  len := ReadNBytes (f, max, buf) ;
  Close (f) ;
  RETURN TRUE
END FileFetch ;

(* ---- "method" of HttpSource ---- *)
PROCEDURE HttpFetch (s: Source; rel: ARRAY OF CHAR;
                     buf: ADDRESS; max: CARDINAL;
                     VAR len: CARDINAL) : BOOLEAN ;
VAR
  hs   : HttpSource ;
  a    : ADDRESS ;
  path : ARRAY [0..511] OF CHAR ;
BEGIN
  a := s ;  hs := a ;
  StrCopy (hs^.path, path) ;
  StrConCat (path, rel, path) ;
  RETURN Http.Get (hs^.host, hs^.port, path, buf, max, len) = 200
END HttpFetch ;

(* ---- constructors ---- *)
PROCEDURE NewFileSource (dir: ARRAY OF CHAR) : Source ;
VAR
  fs : FileSource ;
  a  : ADDRESS ;
BEGIN
  ALLOCATE (a, SIZE (FileSourceDesc)) ;
  fs := a ;
  fs^.base.fetch := FileFetch ;
  StrCopy (dir, fs^.dir) ;
  a := fs ;
  RETURN a                               (* upcast: safe, first member *)
END NewFileSource ;

PROCEDURE NewHttpSource (host: ARRAY OF CHAR; port: CARDINAL;
                         path: ARRAY OF CHAR) : Source ;
VAR
  hs : HttpSource ;
  a  : ADDRESS ;
BEGIN
  ALLOCATE (a, SIZE (HttpSourceDesc)) ;
  hs := a ;
  hs^.base.fetch := HttpFetch ;
  StrCopy (host, hs^.host) ;
  StrCopy (path, hs^.path) ;
  hs^.port := port ;
  a := hs ;
  RETURN a
END NewHttpSource ;

VAR
  sources : ARRAY [0..1] OF Source ;
  buf     : ARRAY [0..65535] OF CHAR ;
  i, len  : CARDINAL ;
  ok      : BOOLEAN ;
BEGIN
  sources[0] := NewFileSource ('/home/claude/test.zarr/co2/') ;
  sources[1] := NewHttpSource ('127.0.0.1', 8123, '/test.zarr/co2/') ;

  FOR i := 0 TO 1 DO
    (* one call site; the record decides who runs *)
    ok := sources[i]^.fetch (sources[i], '.zarray',
                             ADR (buf), 65536, len) ;
    IF ok THEN
      PrintN ('source fetched .zarray, bytes = ', VAL (INTEGER, len))
    ELSE
      PrintN ('source failed, index ', VAL (INTEGER, i))
    END
  END
END srcdemo.
