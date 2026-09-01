program prof;
{$mode objfpc}{$H+}
uses SysUtils, Math, ZarrReader;
var
  S: TZarrStore; A: TZarrArray;
  t0: QWord; r, c: Int64; v, Sum: Double;
  Chunk: TBytes; i: Int64;
begin
  S := TZarrStore.Create('/home/claude/bench.zarr');
  A := S.OpenArray('co2');

  // 1M calls, all inside ONE chunk => pure API overhead, cache always hits
  Chunk := A.ReadChunk([0,0]);  // warm
  t0 := GetTickCount64;
  Sum := 0;
  for r := 0 to 999 do
    for c := 0 to 999 do
      if (r < 500) and (c < 500) then
      begin
        v := A.GetDouble([r, c]);
        if not IsNan(v) then Sum := Sum + v;
      end;
  WriteLn('250k GetDouble same-chunk: ', GetTickCount64 - t0, ' ms');

  // same count, raw pointer on the already-read chunk
  t0 := GetTickCount64;
  Sum := 0;
  for i := 0 to 249999 do
    if not IsNan(PDouble(@Chunk[0])[i]) then Sum := Sum + PDouble(@Chunk[0])[i];
  WriteLn('250k raw pointer         : ', GetTickCount64 - t0, ' ms');
  A.Free; S.Free;
end.
