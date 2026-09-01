IMPLEMENTATION MODULE Plot ;

FROM FIO IMPORT File, OpenToWrite, Close, WriteNBytes ;
FROM SYSTEM IMPORT ADR ;
FROM StrLib IMPORT StrCopy, StrLen ;
FROM fmtshim IMPORT fmt_g ;
FROM Mat IMPORT Matrix, Rows, Cols, Get, MinMax ;

CONST
  OutMax   = 4194303 ;
  MaxSer   = 4 ;
  MaxPts   = 1024 ;
  FigW     = 720.0 ;
  FigH     = 440.0 ;
  MLeft    = 70.0 ;
  MRight   = 25.0 ;
  MTop     = 45.0 ;
  MBottom  = 55.0 ;

VAR
  out  : ARRAY [0..OutMax] OF CHAR ;
  olen : CARDINAL ;

  serX, serY : ARRAY [0..MaxSer-1], [0..MaxPts-1] OF REAL ;
  serN       : ARRAY [0..MaxSer-1] OF CARDINAL ;
  serCol     : ARRAY [0..MaxSer-1] OF CARDINAL ;
  serLbl     : ARRAY [0..MaxSer-1], [0..63] OF CHAR ;
  nSer       : CARDINAL ;

PROCEDURE IsNaN (v: REAL) : BOOLEAN ;
BEGIN
  RETURN NOT (v = v)
END IsNaN ;

(* ---------- output buffer ---------- *)

PROCEDURE Emit (s: ARRAY OF CHAR) ;
VAR i, k : CARDINAL ;
BEGIN
  k := StrLen (s) ;
  i := 0 ;
  WHILE (i < k) AND (olen < OutMax) DO
    out[olen] := s[i] ;
    INC (olen) ;
    INC (i)
  END
END Emit ;

PROCEDURE EmitR (v: REAL) ;
VAR
  buf : ARRAY [0..31] OF CHAR ;
  n   : INTEGER ;
  i   : CARDINAL ;
BEGIN
  n := fmt_g (ADR (buf), v) ;
  i := 0 ;
  WHILE (i < VAL (CARDINAL, n)) AND (olen < OutMax) DO
    out[olen] := buf[i] ;
    INC (olen) ;
    INC (i)
  END
END EmitR ;

PROCEDURE Flush (fname: ARRAY OF CHAR) ;
VAR
  f : File ;
  n : CARDINAL ;
BEGIN
  f := OpenToWrite (fname) ;
  n := WriteNBytes (f, olen, ADR (out)) ;
  Close (f)
END Flush ;

(* ---------- style ---------- *)

PROCEDURE ColorOf (idx: CARDINAL; VAR s: ARRAY OF CHAR) ;
BEGIN
  CASE idx OF
    0 : StrCopy ('#1f77b4', s) |          (* matplotlib C0 *)
    1 : StrCopy ('#ff7f0e', s) |          (* C1 *)
    2 : StrCopy ('#2ca02c', s) |          (* C2 *)
    3 : StrCopy ('#d62728', s)            (* C3 *)
  ELSE
    StrCopy ('#333333', s)
  END
END ColorOf ;

VAR
  hexDigits : ARRAY [0..16] OF CHAR ;

PROCEDURE HexByte (v: CARDINAL; VAR s: ARRAY OF CHAR; at: CARDINAL) ;
BEGIN
  s[at]   := hexDigits[v DIV 16] ;
  s[at+1] := hexDigits[v MOD 16]
END HexByte ;

PROCEDURE CmapColor (cmap: Cmap; t: REAL; VAR s: ARRAY OF CHAR) ;
(* piecewise-linear approximations of viridis and coolwarm *)
VAR
  seg : CARDINAL ;
  f   : REAL ;
  r0, g0, b0, r1, g1, b1 : CARDINAL ;

  PROCEDURE Pt (c: Cmap; i: CARDINAL; VAR r, g, b: CARDINAL) ;
  BEGIN
    IF c = CViridis THEN
      CASE i OF
        0 : r := 68  ; g := 1   ; b := 84  |
        1 : r := 59  ; g := 82  ; b := 139 |
        2 : r := 33  ; g := 145 ; b := 140 |
        3 : r := 94  ; g := 201 ; b := 98
      ELSE
        r := 253 ; g := 231 ; b := 37
      END
    ELSE (* coolwarm *)
      CASE i OF
        0 : r := 59  ; g := 76  ; b := 192 |
        1 : r := 124 ; g := 159 ; b := 249 |
        2 : r := 221 ; g := 221 ; b := 221 |
        3 : r := 245 ; g := 156 ; b := 125
      ELSE
        r := 180 ; g := 4 ; b := 38
      END
    END
  END Pt ;

BEGIN
  IF t < 0.0 THEN t := 0.0 END ;
  IF t > 1.0 THEN t := 1.0 END ;
  f := t * 4.0 ;
  seg := TRUNC (f) ;
  IF seg > 3 THEN seg := 3 END ;
  f := f - VAL (REAL, seg) ;
  Pt (cmap, seg, r0, g0, b0) ;
  Pt (cmap, seg + 1, r1, g1, b1) ;
  s[0] := '#' ;
  HexByte (TRUNC (VAL (REAL, r0) + f * (VAL (REAL, r1) - VAL (REAL, r0))), s, 1) ;
  HexByte (TRUNC (VAL (REAL, g0) + f * (VAL (REAL, g1) - VAL (REAL, g0))), s, 3) ;
  HexByte (TRUNC (VAL (REAL, b0) + f * (VAL (REAL, b1) - VAL (REAL, b0))), s, 5) ;
  s[7] := 0C
END CmapColor ;

(* ---------- nice tick spacing (the Heckbert classic) ---------- *)

PROCEDURE NiceStep (span: REAL) : REAL ;
VAR mag, s : REAL ;
BEGIN
  s := span / 5.0 ;
  mag := 1.0 ;
  WHILE mag < s DO mag := mag * 10.0 END ;
  WHILE mag / 10.0 >= s DO mag := mag / 10.0 END ;
  (* mag/10 < s <= mag ; pick 1,2,5 * mag/10 *)
  IF s <= mag / 5.0 THEN RETURN mag / 5.0
  ELSIF s <= mag / 2.0 THEN RETURN mag / 2.0
  ELSE RETURN mag END
END NiceStep ;

(* ---------- public: line figure ---------- *)

PROCEDURE ClearFigure ;
BEGIN
  nSer := 0
END ClearFigure ;

PROCEDURE AddLine (VAR xs, ys: ARRAY OF REAL; n: CARDINAL;
                   colorIdx: CARDINAL; label: ARRAY OF CHAR) ;
VAR i : CARDINAL ;
BEGIN
  IF nSer >= MaxSer THEN RETURN END ;
  IF n > MaxPts THEN n := MaxPts END ;
  FOR i := 0 TO n - 1 DO
    serX[nSer][i] := xs[i] ;
    serY[nSer][i] := ys[i]
  END ;
  serN[nSer] := n ;
  serCol[nSer] := colorIdx ;
  StrCopy (label, serLbl[nSer]) ;
  INC (nSer)
END AddLine ;

PROCEDURE FloorMul (v, step: REAL) : REAL ;
(* largest multiple of step not exceeding v; safe for negative v *)
VAR k : INTEGER ;
BEGIN
  k := TRUNC (ABS (v) / step) ;
  IF v >= 0.0 THEN
    RETURN step * VAL (REAL, k)
  ELSE
    RETURN -step * VAL (REAL, k + 1)
  END
END FloorMul ;

PROCEDURE Render (fname, title, xlabel, ylabel: ARRAY OF CHAR) ;
VAR
  s, i : CARDINAL ;
  xmin, xmax, ymin, ymax, pad, step, t : REAL ;
  seen, pen : BOOLEAN ;
  px, py : REAL ;
  col : ARRAY [0..15] OF CHAR ;
  ly  : REAL ;

  PROCEDURE PX (x: REAL) : REAL ;
  BEGIN
    RETURN MLeft + (x - xmin) / (xmax - xmin) * (FigW - MLeft - MRight)
  END PX ;

  PROCEDURE PY (y: REAL) : REAL ;
  BEGIN
    RETURN FigH - MBottom - (y - ymin) / (ymax - ymin) * (FigH - MTop - MBottom)
  END PY ;

BEGIN
  IF nSer = 0 THEN RETURN END ;
  (* data limits over all series, NaN-aware *)
  seen := FALSE ;
  xmin := 0.0 ; xmax := 1.0 ; ymin := 0.0 ; ymax := 1.0 ;
  FOR s := 0 TO nSer - 1 DO
    FOR i := 0 TO serN[s] - 1 DO
      IF NOT (IsNaN (serX[s][i]) OR IsNaN (serY[s][i])) THEN
        IF NOT seen THEN
          xmin := serX[s][i] ; xmax := xmin ;
          ymin := serY[s][i] ; ymax := ymin ;
          seen := TRUE
        ELSE
          IF serX[s][i] < xmin THEN xmin := serX[s][i] END ;
          IF serX[s][i] > xmax THEN xmax := serX[s][i] END ;
          IF serY[s][i] < ymin THEN ymin := serY[s][i] END ;
          IF serY[s][i] > ymax THEN ymax := serY[s][i] END
        END
      END
    END
  END ;
  pad := (ymax - ymin) * 0.08 ;
  IF pad = 0.0 THEN pad := 1.0 END ;
  ymin := ymin - pad ;  ymax := ymax + pad ;

  olen := 0 ;
  Emit ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 440" ') ;
  Emit ('font-family="DejaVu Sans, Helvetica, sans-serif">') ;
  Emit ('<rect width="720" height="440" fill="white"/>') ;

  (* grid + ticks *)
  step := NiceStep (ymax - ymin) ;
  t := FloorMul (ymin, step) ;
  WHILE t < ymin DO t := t + step END ;
  WHILE t <= ymax DO
    Emit ('<line x1="') ; EmitR (MLeft) ; Emit ('" y1="') ; EmitR (PY (t)) ;
    Emit ('" x2="') ; EmitR (FigW - MRight) ; Emit ('" y2="') ; EmitR (PY (t)) ;
    Emit ('" stroke="#e0e0e0" stroke-width="1"/>') ;
    Emit ('<text x="') ; EmitR (MLeft - 8.0) ; Emit ('" y="') ;
    EmitR (PY (t) + 4.0) ;
    Emit ('" font-size="11" fill="#444" text-anchor="end">') ;
    EmitR (t) ;
    Emit ('</text>') ;
    t := t + step
  END ;
  step := NiceStep (xmax - xmin) ;
  t := FloorMul (xmin, step) ;
  WHILE t < xmin DO t := t + step END ;
  WHILE t <= xmax DO
    Emit ('<line x1="') ; EmitR (PX (t)) ; Emit ('" y1="') ; EmitR (MTop) ;
    Emit ('" x2="') ; EmitR (PX (t)) ; Emit ('" y2="') ;
    EmitR (FigH - MBottom) ;
    Emit ('" stroke="#e0e0e0" stroke-width="1"/>') ;
    Emit ('<text x="') ; EmitR (PX (t)) ; Emit ('" y="') ;
    EmitR (FigH - MBottom + 18.0) ;
    Emit ('" font-size="11" fill="#444" text-anchor="middle">') ;
    EmitR (t) ;
    Emit ('</text>') ;
    t := t + step
  END ;

  (* spines *)
  Emit ('<line x1="') ; EmitR (MLeft) ; Emit ('" y1="') ; EmitR (MTop) ;
  Emit ('" x2="') ; EmitR (MLeft) ; Emit ('" y2="') ; EmitR (FigH - MBottom) ;
  Emit ('" stroke="black" stroke-width="1.2"/>') ;
  Emit ('<line x1="') ; EmitR (MLeft) ; Emit ('" y1="') ;
  EmitR (FigH - MBottom) ;
  Emit ('" x2="') ; EmitR (FigW - MRight) ; Emit ('" y2="') ;
  EmitR (FigH - MBottom) ;
  Emit ('" stroke="black" stroke-width="1.2"/>') ;

  (* series: NaN lifts the pen, giving matplotlib-style gaps *)
  FOR s := 0 TO nSer - 1 DO
    ColorOf (serCol[s], col) ;
    Emit ('<path d="') ;
    pen := FALSE ;
    FOR i := 0 TO serN[s] - 1 DO
      IF IsNaN (serX[s][i]) OR IsNaN (serY[s][i]) THEN
        pen := FALSE
      ELSE
        px := PX (serX[s][i]) ;
        py := PY (serY[s][i]) ;
        IF pen THEN Emit ('L ') ELSE Emit ('M ') END ;
        EmitR (px) ; Emit (' ') ; EmitR (py) ; Emit (' ') ;
        pen := TRUE
      END
    END ;
    Emit ('" fill="none" stroke="') ;
    Emit (col) ;
    Emit ('" stroke-width="1.8"/>') ;
  END ;

  (* legend, top-right inside axes *)
  ly := MTop + 14.0 ;
  FOR s := 0 TO nSer - 1 DO
    ColorOf (serCol[s], col) ;
    Emit ('<line x1="') ; EmitR (FigW - MRight - 150.0) ;
    Emit ('" y1="') ; EmitR (ly - 4.0) ;
    Emit ('" x2="') ; EmitR (FigW - MRight - 126.0) ;
    Emit ('" y2="') ; EmitR (ly - 4.0) ;
    Emit ('" stroke="') ; Emit (col) ; Emit ('" stroke-width="2"/>') ;
    Emit ('<text x="') ; EmitR (FigW - MRight - 120.0) ;
    Emit ('" y="') ; EmitR (ly) ;
    Emit ('" font-size="11" fill="#222">') ;
    Emit (serLbl[s]) ;
    Emit ('</text>') ;
    ly := ly + 16.0
  END ;

  (* labels *)
  Emit ('<text x="360" y="24" font-size="14" fill="#111" text-anchor="middle">') ;
  Emit (title) ;
  Emit ('</text>') ;
  Emit ('<text x="360" y="') ; EmitR (FigH - 14.0) ;
  Emit ('" font-size="12" fill="#222" text-anchor="middle">') ;
  Emit (xlabel) ;
  Emit ('</text>') ;
  Emit ('<text x="18" y="230" font-size="12" fill="#222" text-anchor="middle" ') ;
  Emit ('transform="rotate(-90 18 230)">') ;
  Emit (ylabel) ;
  Emit ('</text>') ;
  Emit ('</svg>') ;
  Flush (fname)
END Render ;

(* ---------- public: heatmap ---------- *)

PROCEDURE RenderHeat (fname, title: ARRAY OF CHAR; m: Matrix;
                      cmap: Cmap; symmetric: BOOLEAN) ;
VAR
  r, c, nr, nc, i : CARDINAL ;
  mn, mx, cw, ch, t, v : REAL ;
  col : ARRAY [0..15] OF CHAR ;
BEGIN
  nr := Rows (m) ;
  nc := Cols (m) ;
  MinMax (m, mn, mx) ;
  IF symmetric THEN
    IF -mn > mx THEN mx := -mn ELSE mn := -mx END
  END ;
  IF mx = mn THEN mx := mn + 1.0 END ;
  cw := (FigW - MLeft - MRight - 60.0) / VAL (REAL, nc) ;
  ch := (FigH - MTop - MBottom) / VAL (REAL, nr) ;

  olen := 0 ;
  Emit ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 440" ') ;
  Emit ('font-family="DejaVu Sans, Helvetica, sans-serif">') ;
  Emit ('<rect width="720" height="440" fill="white"/>') ;

  FOR r := 0 TO nr - 1 DO
    FOR c := 0 TO nc - 1 DO
      v := Get (m, r, c) ;
      IF NOT (v = v) THEN
        StrCopy ('#ffffff', col)
      ELSE
        CmapColor (cmap, (v - mn) / (mx - mn), col)
      END ;
      Emit ('<rect x="') ; EmitR (MLeft + VAL (REAL, c) * cw) ;
      Emit ('" y="') ; EmitR (MTop + VAL (REAL, r) * ch) ;
      Emit ('" width="') ; EmitR (cw + 0.5) ;
      Emit ('" height="') ; EmitR (ch + 0.5) ;
      Emit ('" fill="') ; Emit (col) ; Emit ('"/>')
    END
  END ;

  (* colorbar *)
  FOR i := 0 TO 99 DO
    t := VAL (REAL, i) / 99.0 ;
    CmapColor (cmap, 1.0 - t, col) ;
    Emit ('<rect x="') ; EmitR (FigW - MRight - 38.0) ;
    Emit ('" y="') ;
    EmitR (MTop + t * (FigH - MTop - MBottom - 3.4)) ;
    Emit ('" width="16" height="') ;
    EmitR ((FigH - MTop - MBottom) / 100.0 + 0.5) ;
    Emit ('" fill="') ; Emit (col) ; Emit ('"/>')
  END ;
  Emit ('<text x="') ; EmitR (FigW - MRight - 30.0) ;
  Emit ('" y="') ; EmitR (MTop - 6.0) ;
  Emit ('" font-size="10" fill="#333" text-anchor="middle">') ;
  EmitR (mx) ;
  Emit ('</text>') ;
  Emit ('<text x="') ; EmitR (FigW - MRight - 30.0) ;
  Emit ('" y="') ; EmitR (FigH - MBottom + 14.0) ;
  Emit ('" font-size="10" fill="#333" text-anchor="middle">') ;
  EmitR (mn) ;
  Emit ('</text>') ;

  Emit ('<text x="360" y="24" font-size="14" fill="#111" text-anchor="middle">') ;
  Emit (title) ;
  Emit ('</text>') ;
  Emit ('</svg>') ;
  Flush (fname)
END RenderHeat ;

BEGIN
  nSer := 0 ;
  StrCopy ('0123456789abcdef', hexDigits)
END Plot.
