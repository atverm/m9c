program gentest;
{ P4 harness, first milestone: DynStr.m9 -> C11 -> gcc -> driver.
  This program only generates; runtime/test/build.sh compiles the
  output against m9rt and runs the driver.  Exit 1 on gen errors. }
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

procedure SaveText (const fn, s: string);
var sl : TStringList;
begin
  sl := TStringList.Create;
  sl.Text := s;
  sl.SaveToFile (fn);
  sl.Free;
end;

procedure GenModule (const m: string; const deps: array of string);
var
  p, dp : TParser;
  root, droot : TNode;
  g : TGen;
  i, k : Integer;
begin
  p := TParser.Create (LoadFile ('../../corpus/' + m + '.m9'));
  root := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    for i := 0 to p.Errors.Count - 1 do WriteLn (p.Errors[i]);
    ExitCode := 1;
    Exit;
  end;

  g := TGen.Create;
  for k := 0 to High (deps) do
  begin
    dp := TParser.Create (LoadFile ('../../corpus/' + deps[k] + '.m9'));
    droot := dp.ParseFile;
    for i := 0 to High (droot.kids) do
      g.LoadExtern (droot.kids[i]);
    dp.Free;
  end;
  for i := 0 to High (root.kids) do
    g.LoadUnit (root.kids[i]);
  g.Emit (m);

  if g.Errors.Count > 0 then
  begin
    WriteLn (m, ': GEN ERRORS (', g.Errors.Count, '):');
    for i := 0 to g.Errors.Count - 1 do WriteLn ('  ', g.Errors[i]);
    ExitCode := 1;
  end
  else
  begin
    ForceDirectories ('../../runtime/gen');
    SaveText ('../../runtime/gen/' + m + '.h', g.HText);
    SaveText ('../../runtime/gen/' + m + '.c', g.CText);
    WriteLn ('generated runtime/gen/', m, '.{h,c}');
  end;
  g.Free;
  p.Free;
end;

begin
  GenModule ('DynStr', []);
  GenModule ('Mat', ['Math']);
  GenModule ('Stats', ['Math']);
  GenModule ('Json', ['DynStr']);
  GenModule ('Http', ['DynStr']);
  GenModule ('HttpServer', ['DynStr', 'Http']);
  GenModule ('OpenApi', ['HttpServer', 'DynStr']);
  GenModule ('ZarrStore', ['DynStr', 'Json', 'Http']);
  GenModule ('Plot', ['DynStr', 'Mat']);
  GenModule ('Lex', ['DynStr']);
  GenModule ('Ast', []);
  GenModule ('Print', ['Ast', 'DynStr']);
  GenModule ('Parse', ['Ast', 'Lex', 'DynStr']);
  GenModule ('Dict', []);
  GenModule ('Fmt', ['DynStr']);
  GenModule ('Io', ['DynStr']);
  GenModule ('Time', ['DynStr', 'Fmt']);
  GenModule ('Text', ['DynStr']);
  GenModule ('Math', []);
  GenModule ('Csv', ['DynStr', 'Io', 'Time']);
  GenModule ('Frame', ['Csv', 'Io', 'Math', 'DynStr', 'Fmt', 'Time', 'NetCDF']);
  GenModule ('Parquet', ['Frame', 'Io', 'DynStr', 'Csv', 'Math', 'Fmt', 'Time', 'NetCDF']);
  GenModule ('NetCDF', ['DynStr']);
  GenModule ('Grib', ['DynStr']);
  GenModule ('Syslog', ['DynStr']);
  GenModule ('Logger', ['DynStr', 'Fmt', 'Io', 'Syslog', 'Time']);
  GenModule ('Hello', ['Io', 'DynStr']);
  GenModule ('Concat', ['Io', 'DynStr']);
  GenModule ('Sem', ['Ast', 'DynStr', 'Fmt', 'Print', 'Text']);
  GenModule ('Doc', ['Ast', 'DynStr', 'Text', 'Print', 'Lex']);
  GenModule ('M9c', ['Io', 'Ast', 'Parse', 'Gen', 'Sem', 'DynStr', 'Doc', 'Lex']);
  GenModule ('Gen', ['Ast', 'DynStr']);
end.
