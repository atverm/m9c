program semdump;
{ P5 stage-2 oracle side for the CHECKER: the diagnostics for one
  file, verbatim, one per line, in the order the checker produced
  them.  The M9-compiled checker must emit identical bytes.

  A checker's output IS its diagnostics -- their text, their line and
  column, and their order -- so that is the whole comparison, the way
  byte-identical C was the whole comparison for the generator.

  Usage: semdump FILE.m9 [DEP.m9 ...]
  Dependencies are loaded first so cross-module names resolve, which
  is what semtest does for the corpus.                              }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9AST, M9Parse, M9Sem;

function LoadFile (const fn: string): string;
var sl : TStringList;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  Result := sl.Text;
  sl.Free;
end;

function ParseOne (const fn: string): TNode;
var p : TParser;
begin
  p := TParser.Create (LoadFile (fn));
  Result := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    WriteLn (StdErr, fn, ': parse errors');
    Halt (2);
  end;
end;

var
  sem : TSem;
  ast : TNode;
  i, k : Integer;
begin
  if ParamCount < 1 then
  begin
    WriteLn (StdErr, 'usage: semdump FILE.m9 [DEP.m9 ...]');
    Halt (2);
  end;
  sem := TSem.Create;
  for k := 2 to ParamCount do
    sem.LoadFile (ParseOne (ParamStr (k)));
  ast := ParseOne (ParamStr (1));
  sem.LoadFile (ast);
  sem.CheckFile (ast);
  for i := 0 to sem.Errors.Count - 1 do
    WriteLn (sem.Errors[i]);
  { the ledger is part of what the checker says, so it is compared
    too -- it is measured output, not a debug aside }
  for i := 0 to sem.Ledger.Count - 1 do
    WriteLn ('ledger: ', sem.Ledger[i]);
  sem.Free;
end.
