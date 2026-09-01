program mandel;
{ mandelbrot in Object Pascal, the same algorithm as Mandel.m9.

  FPC is in this comparison because M9 is in the Wirth line and
  because the zarr reader whose bugs became the museum was written in
  this compiler: it is the language M9 is a reaction to, so a column
  where it is level with M9 says the reaction cost nothing, and a
  column where it is not says what.

  Checks are ON by default here -- R+ bounds, Q+ overflow -- because
  that is the honest comparison against a language whose checks
  cannot be switched off.  Compiled with -dUNCHECKED it is the same
  file with them off, which is what FPC's own default gives you, and
  the pair prices what that default is hiding. }
{$mode objfpc}{$H+}
{$IFDEF UNCHECKED}{$R-}{$Q-}{$ELSE}{$R+}{$Q+}{$ENDIF}

uses SysUtils;

const
  MaxIter = 50;
  { TYPED constants, and this is not a style choice.  An untyped real
    constant in FPC is Extended, and SizeOf(Extended) is 10 on
    x86_64: mixing one into a Double expression evaluates the whole
    expression in x87 80-bit and rounds once at the end, which is a
    DIFFERENT number.  Measured here, not assumed --

      2.0 * zr * zi + 0.1   untyped   -0.32000000000000003997
                            typed     -0.32000000000000006217  = C

    -- and it made this program disagree with the other five on two
    pixels out of 40000 the first time it ran.  That is the museum's
    founding bug (longreal-stride: gm2's LONGREAL was x87 long
    double over 8-byte wire data) appearing unprompted in a
    benchmark, in a different compiler, thirty years later.  M9 has
    F64 and no wider type to promote into, which is the whole point
    of exact-width types. }
  Limit  : Double = 4.0;
  Two    : Double = 2.0;
  ThreeHalves : Double = 1.5;
  One    : Double = 1.0;

var
  n, x, y, k, bits, bit, iter : Int64;
  cr, ci, zr, zi, t, inv : Double;
  row : array of Byte;
  hdr : AnsiString;
  f : File;

begin
  if ParamCount < 2 then
  begin
    WriteLn (StdErr, 'usage: mandel N OUTFILE');
    Halt (1);
  end;
  n := StrToInt64 (ParamStr (1));
  if n < 8 then n := 8;
  n := n - n mod 8;

  Assign (f, ParamStr (2));
  Rewrite (f, 1);
  { the header goes out as bytes, like the bitmap, so the file is
    byte-identical to the other five }
  hdr := 'P4' + #10 + IntToStr (n) + ' ' + IntToStr (n) + #10;
  BlockWrite (f, hdr[1], Length (hdr));

  SetLength (row, n div 8);
  inv := Two / n;

  for y := 0 to n - 1 do
  begin
    ci := y * inv - One;
    x := 0;
    while x < n do
    begin
      bits := 0;
      for k := 0 to 7 do
      begin
        cr := (x + k) * inv - ThreeHalves;
        zr := 0.0;
        zi := 0.0;
        bit := 1;
        for iter := 0 to MaxIter - 1 do
        begin
          t := zr * zr - zi * zi + cr;
          zi := Two * zr * zi + ci;
          zr := t;
          if zr * zr + zi * zi > Limit then
          begin
            bit := 0;
            Break;
          end;
        end;
        bits := bits * 2 + bit;
      end;
      row[x div 8] := Byte (bits);
      x := x + 8;
    end;
    BlockWrite (f, row[0], n div 8);
  end;
  Close (f);
end.
