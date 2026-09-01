program fannkuch;
{ fannkuch-redux in Object Pascal, the same algorithm as Fannkuch.m9.

  This is the FPC column that matters, because fannkuch is nothing but
  subscripting and integer addition -- exactly the two things R+ and
  Q+ price.  Built both ways from one source:

    fpc -O2                fannkuch.pas   -- checked, as written
    fpc -O2 -dUNCHECKED    fannkuch.pas   -- FPC's own default

  The gap between those two columns is what an Object Pascal program
  pays for the checks M9 has no switch to remove -- the same question
  the Rust -C overflow-checks pair asks, put to the language M9 is
  descended from. }
{$mode objfpc}{$H+}
{$IFDEF UNCHECKED}{$R-}{$Q-}{$ELSE}{$R+}{$Q+}{$ENDIF}

uses SysUtils;

const
  MaxN = 16;

function Run (n: Int64; out checksum: Int64): Int64;
var
  perm, perm1, count : array [0 .. MaxN - 1] of Int64;
  i, j, r, k, t, p0, flips, maxFlips, permCount : Int64;
begin
  for i := 0 to n - 1 do perm1[i] := i;
  r := n;
  maxFlips := 0;
  permCount := 0;
  checksum := 0;
  while True do
  begin
    while r <> 1 do
    begin
      count[r - 1] := r;
      r := r - 1;
    end;
    for i := 0 to n - 1 do perm[i] := perm1[i];
    flips := 0;
    k := perm[0];
    while k <> 0 do
    begin
      i := 0;
      j := k;
      while i < j do
      begin
        t := perm[i];
        perm[i] := perm[j];
        perm[j] := t;
        i := i + 1;
        j := j - 1;
      end;
      flips := flips + 1;
      k := perm[0];
    end;
    if flips > maxFlips then maxFlips := flips;
    if permCount mod 2 = 0 then
      checksum := checksum + flips
    else
      checksum := checksum - flips;
    permCount := permCount + 1;
    while True do
    begin
      if r = n then
      begin
        Result := maxFlips;
        Exit;
      end;
      p0 := perm1[0];
      for i := 0 to r - 1 do perm1[i] := perm1[i + 1];
      perm1[r] := p0;
      count[r] := count[r] - 1;
      if count[r] > 0 then Break;
      r := r + 1;
    end;
  end;
end;

var
  n, checksum, maxFlips : Int64;

begin
  n := 10;
  if ParamCount >= 1 then n := StrToInt64 (ParamStr (1));
  if n < 1 then n := 1;
  if n > MaxN then n := MaxN;
  checksum := 0;
  maxFlips := Run (n, checksum);
  WriteLn (checksum);
  WriteLn ('Pfannkuchen(', n, ') = ', maxFlips);
end.
