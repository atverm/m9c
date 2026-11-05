program gentest;
{ gentest is the P4 harness, first milestone: DynStr.m9 -> C11 -> gcc
  -> driver.
  This program only generates; runtime/test/build.sh compiles the
  output against m9rt and runs the driver.  It exits 1 on gen errors. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9AST, M9Parse, M9Sem, M9Gen;

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
  sem : TSem;
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

  { Run the checker first, as m9c runs it.  It records the types the
    generator reads (the typed tree, 2026-10-09).  Its diagnostics are
    not this tool's business: semdiff holds them. }
  sem := TSem.Create;
  g := TGen.Create;
  for k := 0 to High (deps) do
  begin
    dp := TParser.Create (LoadFile ('../../corpus/' + deps[k] + '.m9'));
    droot := dp.ParseFile;
    sem.LoadFile (droot);
    for i := 0 to High (droot.kids) do
      g.LoadExtern (droot.kids[i]);
    dp.Free;
  end;
  sem.LoadFile (root);
  sem.CheckFile (root);
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
  GenModule ('Faults', []);
  GenModule ('Mat', ['Math', 'Faults']);
  GenModule ('Stats', ['Math', 'Bits', 'Faults', 'Sort']);
  GenModule ('System', ['Io', 'DynStr', 'Text']);
  GenModule ('Json', ['DynStr', 'Text']);
  GenModule ('JsonUtf', ['DynStr', 'Text']);
  GenModule ('Chars', ['Bits', 'Faults', 'Text']);
  GenModule ('DynUtf', []);
  GenModule ('Tsk', ['Faults', 'System']);
  GenModule ('Chan', []);
  GenModule ('Sup', ['Faults', 'Time', 'Io', 'Fmt']);
  GenModule ('Http', ['DynStr', 'Io', 'Text']);
  GenModule ('HttpServer', ['DynStr', 'Http', 'Io', 'Logger', 'Zip', 'Text']);
  GenModule ('OpenApi', ['HttpServer', 'DynStr', 'Text']);
  GenModule ('ApiSpec', ['DynStr', 'Text']);
  GenModule ('Arrow', ['DynStr', 'Faults', 'Text']);
  GenModule ('ZarrStore', ['DynStr', 'Json', 'Http', 'Io', 'Text']);
  GenModule ('Sparql', ['DynStr', 'Io', 'Http', 'Json', 'Text']);
  GenModule ('Rdf', ['DynStr', 'Fmt', 'Json', 'Text', 'Xml']);
  GenModule ('Regex', ['DynStr', 'Text']);
  GenModule ('Map', ['DynStr', 'Faults', 'Fmt', 'Math', 'Plot', 'Stats', 'Text']);
  GenModule ('Xml', ['DynStr', 'Fmt', 'Text']);
  GenModule ('Hash', ['Bits', 'Faults', 'Text']);
  GenModule ('Smtp', ['Time', 'DynStr', 'Fmt', 'Text']);
  GenModule ('Rsa', ['Hash', 'Text']);
  GenModule ('Zarr', ['DynStr', 'Json', 'Io', 'Math', 'Text']);
  GenModule ('Plot', ['DynStr', 'Mat', 'Math', 'Faults', 'Fmt', 'Text', 'Time']);
  GenModule ('Lex', ['DynStr', 'Text']);
  GenModule ('M9f', ['DynStr', 'Lex', 'Text']);
  GenModule ('Ast', ['Text']);
  GenModule ('Print', ['Ast', 'DynStr', 'Text']);
  GenModule ('Parse', ['Ast', 'Lex', 'Text']);
  GenModule ('Dict', ['Text']);
  GenModule ('Fmt', []);
  GenModule ('Io', ['DynStr']);
  GenModule ('Time', ['DynStr', 'Fmt', 'Text']);
  GenModule ('Pg', ['DynStr', 'Fmt', 'Time', 'Text']);
  GenModule ('Text', ['DynStr']);
  GenModule ('Math', []);
  GenModule ('Bits', []);
  GenModule ('Sort', ['Math', 'Text']);
  GenModule ('Seq', ['Sort', 'Text']);
  GenModule ('Check', ['Io', 'Fmt', 'Math', 'Text']);
  GenModule ('Arrays', ['Faults', 'Math']);
  GenModule ('Numeric', ['Faults', 'Math']);
  GenModule ('Csv', ['DynStr', 'Io', 'Time', 'Text']);
  GenModule ('Delim', ['DynStr', 'Io', 'Text']);
  GenModule ('Zip', ['DynStr', 'Io', 'Bits', 'Text']);
  GenModule ('Png', ['Faults', 'Zip', 'Math', 'DynStr', 'Text']);
  GenModule ('Frame', ['Csv', 'Io', 'Math', 'DynStr', 'Fmt', 'Time', 'NetCDF', 'Faults', 'Sort', 'Stats', 'Text']);
  GenModule ('Parquet', ['Frame', 'Io', 'DynStr', 'Csv', 'Math', 'Fmt', 'Time', 'NetCDF', 'Faults', 'Zip', 'Bits', 'Text']);
  GenModule ('NbCells', ['Parquet', 'Frame', 'Io', 'DynStr', 'Csv', 'Math', 'Fmt', 'Time', 'NetCDF', 'Faults', 'Zip', 'Bits', 'Text']);
  GenModule ('NbShow', ['Frame', 'Io', 'DynStr', 'Fmt', 'Text', 'Time']);
  GenModule ('NetCDF', ['DynStr', 'Faults', 'Text']);
  GenModule ('Grib', ['DynStr', 'Faults']);
  GenModule ('Syslog', []);
  GenModule ('Logger', ['DynStr', 'Fmt', 'Io', 'Syslog', 'Time', 'Text']);
  GenModule ('Hello', ['Io', 'DynStr']);
  GenModule ('Concat', ['Io', 'DynStr', 'Text']);
  GenModule ('Narrow', ['Io']);
  GenModule ('ProcUse', ['Io', 'Text']);
  GenModule ('AggUse', ['Io', 'Text']);
  GenModule ('ExportDef', ['Io', 'Fmt']);
  GenModule ('ExportUse', ['ExportDef', 'Io', 'Fmt']);
  GenModule ('ShareUse', ['Io']);
  GenModule ('Sem', ['Ast', 'DynStr', 'Print', 'Text']);
  GenModule ('Doc', ['Ast', 'DynStr', 'Text', 'Print', 'Lex']);
  GenModule ('Review', ['Ast', 'DynStr', 'Text']);
  GenModule ('M9c', ['Io', 'Ast', 'Parse', 'Gen', 'Sem', 'DynStr', 'Doc', 'Review', 'Lex', 'M9f', 'System', 'Text']);
  GenModule ('Gen', ['Ast', 'DynStr', 'Text']);
  GenModule ('Diag', ['DynStr', 'Io', 'Lex', 'Text']);
end.
