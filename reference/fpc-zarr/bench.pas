program bench;
{$mode objfpc}{$H+}
uses SysUtils, Math, ZarrReader;
var
  S: TZarrStore; A: TZarrArray;
  t0: QWord; Sum: Double; N: Int64;
  r, c, cr, cc: Int64; v: Double;
  Chunk: TBytes; P: PDouble; i, ChunkElems: Int64;
begin
  S := TZarrStore.Create('/home/claude/bench.zarr');
  A := S.OpenArray('co2');

  { --- A: element-wise via GetDouble (safe API, per-element checks) --- }
  t0 := GetTickCount64;
  Sum := 0; N := 0;
  for r := 0 to 3999 do
    for c := 0 to 3999 do
    begin
      v := A.GetDouble([r, c]);
      if not IsNan(v) then begin Sum := Sum + v; Inc(N); end;
    end;
  WriteLn(Format('element-wise GetDouble: %5d ms  sum=%.6f n=%d',
    [GetTickCount64 - t0, Sum, N]));

  { --- B: chunk-wise zero-copy pointer loop --- }
  t0 := GetTickCount64;
  Sum := 0; N := 0;
  ChunkElems := 500 * 500;
  for cr := 0 to 7 do
    for cc := 0 to 7 do
    begin
      Chunk := A.ReadChunk([cr, cc]);
      P := PDouble(@Chunk[0]);
      for i := 0 to ChunkElems - 1 do
        if not IsNan(P[i]) then begin Sum := Sum + P[i]; Inc(N); end;
    end;
  WriteLn(Format('chunk-wise zero-copy  : %5d ms  sum=%.6f n=%d',
    [GetTickCount64 - t0, Sum, N]));

  A.Free; S.Free;
end.
