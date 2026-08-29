program lexbench;
{$mode objfpc}{$H+}
{ Throughput: corpus concatenated to ~8MB in memory, lexed twice.
  Report the second run (first run warms; page cache lies -- the
  7402ms -> 114ms "speedup" of 2026-08-20 was cache warming). }
uses SysUtils, Classes, M9Lex;

function Load (const fn: string): string;
var
  sl : TStringList;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  Result := sl.Text;
  sl.Free;
end;

function Run (const src: string): string;
var
  lx : TLexer;
  t : TToken;
  n : Integer;
  t0, ms : QWord;
begin
  lx := TLexer.Create (src);
  n := 0;
  t0 := GetTickCount64;
  repeat t := lx.Next; Inc (n) until t.kind = tkEOF;
  ms := GetTickCount64 - t0;
  lx.Free;
  if ms = 0 then ms := 1;
  Result := Format ('%d tokens, %d KB, %d ms, %.0f ktok/s',
    [n, Length (src) div 1024, ms, n / ms]);
end;

var
  unit1, big : string;
begin
  unit1 := Load ('../../corpus/ZarrStore.m9') + Load ('../../corpus/Json.m9');
  big := '';
  while Length (big) < 8 * 1024 * 1024 do
    big := big + unit1;
  WriteLn ('warm-up: ', Run (big));
  WriteLn ('measure: ', Run (big));
end.
