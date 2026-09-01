program testzarr;

{$mode objfpc}{$H+}

uses
  SysUtils, Math, fpjson, ZarrReader;

var
  Store: TZarrStore;
  CO2, Flags: TZarrArray;
  Attrs: TJSONObject;
  r, c: Int64;
  v, Sum: Double;
  N: Int64;
begin
  Store := TZarrStore.Create('/home/claude/test.zarr');
  try
    CO2 := Store.OpenArray('co2');
    WriteLn(Format('co2: shape (%d,%d)  chunks (%d,%d)  dtype f%d',
      [CO2.Meta.Shape[0], CO2.Meta.Shape[1],
       CO2.Meta.Chunks[0], CO2.Meta.Chunks[1], CO2.Meta.ItemSize]));

    Attrs := Store.ArrayAttrs('co2');
    if Attrs <> nil then
      WriteLn('units attr: ', Attrs.Get('units', '?'));

    WriteLn('co2[0,0]   = ', CO2.GetDouble([0, 0]):0:13);
    WriteLn('co2[99,49] = ', CO2.GetDouble([99, 49]):0:13);
    WriteLn('co2[42,17] = ', CO2.GetDouble([42, 17]):0:13);
    WriteLn('co2[10,5]  = ', CO2.GetDouble([10, 5]):0:13, '  (expect NaN)');

    // nan-aware mean over the full array, walking element-wise.
    // The single-chunk cache makes this row-major scan cheap.
    Sum := 0; N := 0;
    for r := 0 to CO2.Meta.Shape[0] - 1 do
      for c := 0 to CO2.Meta.Shape[1] - 1 do
      begin
        v := CO2.GetDouble([r, c]);
        if not IsNan(v) then begin Sum := Sum + v; Inc(N); end;
      end;
    WriteLn('nanmean    = ', (Sum / N):0:13, '   (n=', N, ')');

    Flags := Store.OpenArray('flags');
    WriteLn('flags[13,7] = ', Flags.GetInt([13, 7]));
    Flags.Free;
    CO2.Free;
  finally
    Store.Free;
  end;
end.
