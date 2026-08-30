program gendump;
{ P5 stage-2 oracle side: emit the generated C for one module to
  stdout, header then source, separated by a marker line.  The
  M9-compiled generator (runtime/test/gendump_m9) must produce
  identical bytes.  Usage: gendump MODULE [DEP ...]              }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9AST, M9Parse, M9Gen;

function LoadFile (const fn: string): string;
var sl : TStringList;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  Result := sl.Text;
  sl.Free;
end;

var
  p, dp : TParser;
  root, droot : TNode;
  g : TGen;
  i, k : Integer;
  m : string;
begin
  if ParamCount < 1 then
  begin
    WriteLn ('usage: gendump MODULE [DEP ...]');
    Halt (2);
  end;
  m := ParamStr (1);
  p := TParser.Create (LoadFile ('../../corpus/' + m + '.m9'));
  root := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    for i := 0 to p.Errors.Count - 1 do WriteLn (StdErr, p.Errors[i]);
    Halt (1);
  end;

  g := TGen.Create;
  for k := 2 to ParamCount do
  begin
    dp := TParser.Create (LoadFile ('../../corpus/' + ParamStr (k) + '.m9'));
    droot := dp.ParseFile;
    for i := 0 to High (droot.kids) do
      g.LoadExtern (droot.kids[i]);
    dp.Free;
  end;
  for i := 0 to High (root.kids) do
    g.LoadUnit (root.kids[i]);
  g.Emit (m);

  Write (g.HText);
  WriteLn ('==== M9GEN SPLIT ====');
  Write (g.CText);
  if g.Errors.Count > 0 then
  begin
    for i := 0 to g.Errors.Count - 1 do WriteLn (StdErr, g.Errors[i]);
    Halt (1);
  end;
  g.Free;
  p.Free;
end.
