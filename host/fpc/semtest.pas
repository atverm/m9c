program semtest;
{ P2 exit harness (ROADMAP):
    1. every corpus/ file passes the semantic checker with ZERO
       diagnostics;
    2. every museum/ file is REJECTED, and at least one diagnostic
       contains the file's (* EXPECT-ERROR: ... *) text verbatim.
  Museum files are checked against the corpus registry, so their
  imports (cblosc et al.) resolve to the real declarations.
  Exit code 1 on any failure.                                        }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Lex, M9AST, M9Parse, M9Print, M9Sem;

var
  gFail : Boolean = False;

function LoadFile (const fn: string): string;
var
  sl : TStringList;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  Result := sl.Text;
  sl.Free;
end;

function SortedM9 (const dir: string): TStringArray;
var
  sr : TSearchRec;
  n, i, j : Integer;
  t : string;
begin
  SetLength (Result, 0);
  n := 0;
  if FindFirst (dir + '/*.m9', faAnyFile, sr) = 0 then
  begin
    repeat
      SetLength (Result, n + 1);
      Result[n] := dir + '/' + sr.Name;   { full path: two source
                                             directories now }
      Inc (n);
    until FindNext (sr) <> 0;
    FindClose (sr);
  end;
  for i := 1 to n - 1 do
  begin
    t := Result[i];
    j := i;
    while (j > 0) and (CompareStr (Result[j-1], t) > 0) do
    begin
      Result[j] := Result[j-1];
      Dec (j);
    end;
    Result[j] := t;
  end;
end;

function ExpectText (const src: string): string;
var
  a, b : Integer;
begin
  Result := '';
  a := Pos ('EXPECT-ERROR:', src);
  if a = 0 then Exit;
  a := a + Length ('EXPECT-ERROR:');
  b := Pos ('*)', src);
  if b <= a then Exit;
  Result := Trim (Copy (src, a, b - a));
end;

function ParseOne (const fn: string): TNode;
var
  p : TParser;
  i : Integer;
begin
  p := TParser.Create (LoadFile (fn));
  Result := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    WriteLn (fn, ': PARSE errors (semtest expects a parsing corpus):');
    for i := 0 to p.Errors.Count - 1 do
      WriteLn ('  ', p.Errors[i]);
    gFail := True;
  end;
  p.Free;
end;

var
  sem : TSem;
  corpusNames, museumNames : TStringArray;
  corpusAsts : array of TNode;
  i, j : Integer;
  ast : TNode;
  fn, expect : string;
  before : Integer;
  hit : Boolean;
begin
  { benchmark programs are M9 and get the same checking }
  corpusNames := Concat (SortedM9 ('../../corpus'), SortedM9 ('../../bench'));
  museumNames := SortedM9 ('../../museum');
  if (Length (corpusNames) = 0) or (Length (museumNames) = 0) then
  begin
    WriteLn ('MISSING corpus/ or museum/');
    ExitCode := 1;
    Exit;
  end;

  sem := TSem.Create;

  { registry pass over the whole corpus first }
  SetLength (corpusAsts, Length (corpusNames));
  for i := 0 to High (corpusNames) do
  begin
    corpusAsts[i] := ParseOne (corpusNames[i]);
    sem.LoadFile (corpusAsts[i]);
  end;

  { corpus must be clean }
  for i := 0 to High (corpusNames) do
  begin
    before := sem.Errors.Count;
    sem.CheckFile (corpusAsts[i]);
    if sem.Errors.Count > before then
    begin
      WriteLn (Format ('%-40s SEM FAIL (%d diagnostics)',
        [corpusNames[i], sem.Errors.Count - before]));
      for j := before to sem.Errors.Count - 1 do
        WriteLn ('  ', sem.Errors[j]);
      gFail := True;
    end
    else
      WriteLn (Format ('%-40s clean',
        [corpusNames[i]]));
  end;

  { museum must be rejected with the intended message }
  for i := 0 to High (museumNames) do
  begin
    fn := museumNames[i];
    expect := ExpectText (LoadFile (fn));
    ast := ParseOne (fn);
    sem.LoadFile (ast);
    before := sem.Errors.Count;
    sem.CheckFile (ast);
    if sem.Errors.Count = before then
    begin
      WriteLn (Format ('%-40s NOT REJECTED (museum piece accepted)',
        [fn]));
      gFail := True;
      Continue;
    end;
    hit := False;
    for j := before to sem.Errors.Count - 1 do
      if Pos (expect, sem.Errors[j]) > 0 then hit := True;
    if hit then
      WriteLn (Format ('%-40s rejected as intended', [fn]))
    else
    begin
      WriteLn (Format ('%-40s REJECTED WITH WRONG MESSAGE', [fn]));
      WriteLn ('  expected to contain: ', expect);
      for j := before to sem.Errors.Count - 1 do
        WriteLn ('  got: ', sem.Errors[j]);
      gFail := True;
    end;
  end;

  WriteLn;
  if gFail then
  begin
    WriteLn ('FAIL');
    ExitCode := 1;
  end
  else
    WriteLn ('PASS: corpus clean, museum rejected with intended messages');
end.
