{$mode objfpc}{$H+}
{ p1 -- parse ONE file and print its errors the way m9c does, so the
  two parsers can be held to the SAME diagnostics.

  The M9 parser counted its errors and said nothing else until
  2026-08-30; the oracle has carried messages since the day it was
  written.  Now that both word them, a gate that only compared
  printed TREES (parsediff, over files that parse clean) would never
  see the two drift apart on the files that matter -- the broken
  ones.  runtime/test/parsediff.sh puts every parseprobes/ file to
  this and to m9c and requires the output to be identical.

  Format is m9c's: FILE:LINE:COL: parse: MESSAGE, then the count.
  `fpc -O2 p1.pas && ./p1 FILE.m9` }
program p1;
uses SysUtils, Classes, M9AST, M9Parse;

function LoadFile (const fn: string): string;
var f: TStringList;
begin
  f := TStringList.Create;
  f.LoadFromFile (fn);
  Result := f.Text;
  f.Free;
end;

var
  p : TParser;
  root : TNode;
  i, n, colon : Integer;
  s, lc, msg : string;
begin
  if ParamCount <> 1 then
  begin
    WriteLn ('usage: p1 FILE.m9');
    Halt (2);
  end;
  p := TParser.Create (LoadFile (ParamStr (1)));
  root := p.ParseFile;
  n := p.Errors.Count;
  { the oracle stores 'line:col message'; m9c prints
    'FILE:line:col: parse: message', and the split is at the FIRST
    space, because a message may contain any number of them }
  for i := 0 to n - 1 do
  begin
    if i >= 8 then Break;          { m9c prints the first eight }
    s := p.Errors[i];
    colon := Pos (' ', s);
    lc := Copy (s, 1, colon - 1);
    msg := Copy (s, colon + 1, Length (s));
    WriteLn (Format ('%s:%s: parse: %s', [ParamStr (1), lc, msg]));
  end;
  if n > 0 then
    WriteLn (Format ('m9c: %d parse errors in %s', [n, ParamStr (1)]));
  root.Free;
  p.Free;
  if n > 0 then Halt (1);
end.
