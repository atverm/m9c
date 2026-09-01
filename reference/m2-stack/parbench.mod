MODULE parbench ;

(* Preemptive SMP parallelism in Modula-2: N pthreads decompress and
   reduce the 64 chunks of the 102 MB benchmark store concurrently.
   No GIL.  Per-thread buffers, blosc context API, join, combine.    *)

FROM SYSTEM IMPORT ADR, ADDRESS ;
FROM StrLib IMPORT StrCopy, StrConCat ;
FROM NumberIO IMPORT CardToStr ;
FROM printshim IMPORT printd, printn ;
FROM cblosc IMPORT blosc_decompress_ctx ;
FROM thrshim IMPORT run_parallel, now_ms, slurp ;

CONST
  NChunks   = 64 ;
  ChunkElem = 250000 ;                  (* 500 x 500 f8 *)
  RawMax    = 2200000 ;
  MaxThr    = 8 ;

VAR
  paths  : ARRAY [0..NChunks-1], [0..127] OF CHAR ;
  raw    : ARRAY [0..MaxThr-1], [0..RawMax-1] OF CHAR ;
  chunk  : ARRAY [0..MaxThr-1], [0..ChunkElem*8-1] OF CHAR ;
  sums   : ARRAY [0..MaxThr-1] OF REAL ;
  counts : ARRAY [0..MaxThr-1] OF CARDINAL ;
  nThreads : CARDINAL ;
  labelBuf : ARRAY [0..127] OF CHAR ;

PROCEDURE PrintD (label: ARRAY OF CHAR; v: REAL) ;
BEGIN
  StrCopy (label, labelBuf) ;
  printd (ADR (labelBuf), v)
END PrintD ;

PROCEDURE Worker (arg: ADDRESS) ;
VAR
  idp : POINTER TO INTEGER ;
  id, k : CARDINAL ;
  n, rc, i : INTEGER ;
  d : POINTER TO ARRAY [0..ChunkElem-1] OF REAL ;
  s : REAL ;
BEGIN
  idp := arg ;
  id := VAL (CARDINAL, idp^) ;
  sums[id] := 0.0 ;
  counts[id] := 0 ;
  k := id ;
  WHILE k < NChunks DO
    n := slurp (ADR (paths[k]), ADR (raw[id]), RawMax) ;
    rc := blosc_decompress_ctx (ADR (raw[id]), ADR (chunk[id]),
                                VAL (LONGCARD, ChunkElem * 8), 1) ;
    d := ADR (chunk[id]) ;
    s := 0.0 ;
    FOR i := 0 TO ChunkElem - 1 DO
      IF d^[i] = d^[i] THEN            (* NaN-aware, no calls in hot loop *)
        s := s + d^[i] ;
        INC (counts[id])
      END
    END ;
    sums[id] := sums[id] + s ;
    k := k + nThreads
  END
END Worker ;

PROCEDURE Bench (nt: CARDINAL) ;
VAR
  t0, tot : REAL ;
  i, n, rc : CARDINAL ;
BEGIN
  nThreads := nt ;
  t0 := now_ms () ;
  rc := VAL (CARDINAL, run_parallel (Worker, VAL (INTEGER, nt))) ;
  tot := 0.0 ;  n := 0 ;
  FOR i := 0 TO nt - 1 DO
    tot := tot + sums[i] ;
    n := n + counts[i]
  END ;
  StrCopy ('threads', labelBuf) ;
  printn (ADR (labelBuf), VAL (INTEGER, nt)) ;
  PrintD ('  wall ms = ', now_ms () - t0) ;
  PrintD ('  nansum  = ', tot) ;
  StrCopy ('  n       = ', labelBuf) ;
  printn (ADR (labelBuf), VAL (INTEGER, n))
END Bench ;

VAR
  cr, cc, i : CARDINAL ;
  num : ARRAY [0..15] OF CHAR ;
BEGIN
  i := 0 ;
  FOR cr := 0 TO 7 DO
    FOR cc := 0 TO 7 DO
      StrCopy ('/home/claude/bench.zarr/co2/', paths[i]) ;
      CardToStr (cr, 0, num) ;  StrConCat (paths[i], num, paths[i]) ;
      StrConCat (paths[i], '.', paths[i]) ;
      CardToStr (cc, 0, num) ;  StrConCat (paths[i], num, paths[i]) ;
      INC (i)
    END
  END ;
  Bench (1) ;
  Bench (2) ;
  Bench (4) ;
  Bench (8)
END parbench.
