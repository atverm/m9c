program ownledger;
{ P3 measurement harness: prints the contortion ledger over corpus/
  and the kill-gate statistic.  ROADMAP, binding: if >~20% of corpus
  procedures need contortions, par 4.1 is wrong -- revise toward
  region annotations.  Decided by this number, not by mood.
  A CI GATE since the ledger silently shrank once: semtest gates
  ownership ERRORS, this measures the PRICE of the borrow discipline
  and FAILS THE BUILD over the gate, because a pre-registered rule
  that only prints a verdict is not a rule.  Watch the count as well
  as the rate: an RO sweep once dropped five procedures out of the
  ledger unnoticed, understating 4.0% as 2.4%.
  Known under-measurement, stated honestly: only DIRECT stores of a
  borrowed parameter are counted; a borrow laundered through a call
  result, a variant constructor, or a VAR-record intermediary is
  not seen (Json's tree-building src slices travel that way).       }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Lex, M9AST, M9Parse, M9Print, M9Sem;

function LoadFile (const fn: string): string;
var sl : TStringList;
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
      Result[n] := sr.Name;
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

function CountBodies (root: TNode): Integer;
var u, d : Integer;
begin
  Result := 0;
  for u := 0 to High (root.kids) do
    for d := 0 to High (root.kids[u].kids) do
      if (root.kids[u].kids[d] <> nil) and
         (root.kids[u].kids[d].kind = nkProcDecl) and
         (root.kids[u].kids[d].kids[4] <> nil) then
        Inc (Result);
end;

{ ledger lines are 'line:col ctx: msg' -- ctx is field 2 }
function CtxOf (const s: string): string;
var a, b : Integer;
begin
  a := Pos (' ', s);
  b := Pos (': ', s);
  if (a > 0) and (b > a) then
    Result := Copy (s, a + 1, b - a - 1)
  else
    Result := s;
end;

var
  sem : TSem;
  names : TStringArray;
  asts : array of TNode;
  ctxs : TStringList;
  i, j, bodies : Integer;
  p : TParser;
  pct : Double;
begin
  names := SortedM9 ('../../corpus');
  if Length (names) = 0 then
  begin
    WriteLn ('MISSING corpus/');
    ExitCode := 1;
    Exit;
  end;
  sem := TSem.Create;
  SetLength (asts, Length (names));
  bodies := 0;
  for i := 0 to High (names) do
  begin
    p := TParser.Create (LoadFile ('../../corpus/' + names[i]));
    asts[i] := p.ParseFile;
    if p.Errors.Count > 0 then
    begin
      WriteLn (names[i], ': PARSE errors; ledger needs a parsing corpus');
      ExitCode := 1;
      Exit;
    end;
    p.Free;
    sem.LoadFile (asts[i]);
    bodies := bodies + CountBodies (asts[i]);
  end;
  for i := 0 to High (names) do
    sem.CheckFile (asts[i]);

  if sem.Errors.Count > 0 then
  begin
    WriteLn ('ownership/semantic ERRORS (semtest gates these):');
    for i := 0 to sem.Errors.Count - 1 do
      WriteLn ('  ', sem.Errors[i]);
  end;

  WriteLn ('contortion ledger (', sem.Ledger.Count, ' entries):');
  for i := 0 to sem.Ledger.Count - 1 do
    WriteLn ('  ', sem.Ledger[i]);

  ctxs := TStringList.Create;
  ctxs.Duplicates := dupIgnore;
  ctxs.Sorted := True;
  for i := 0 to sem.Ledger.Count - 1 do
    ctxs.Add (CtxOf (sem.Ledger[i]));

  WriteLn;
  WriteLn (Format ('procedures with bodies : %d', [bodies]));
  WriteLn (Format ('procedures in ledger   : %d', [ctxs.Count]));
  for j := 0 to ctxs.Count - 1 do
    WriteLn ('  ', ctxs[j]);
  if bodies > 0 then
  begin
    pct := 100.0 * ctxs.Count / bodies;
    WriteLn (Format ('contortion rate        : %.1f%%  (kill-gate: 20%%)',
      [pct]));
    if pct > 20.0 then
    begin
      WriteLn ('VERDICT: over the gate -- par 4.1 must be revised ' +
        '(region annotations), per the pre-registered rule');
      { the pre-registered rule is a RULE: over the gate fails the
        build rather than printing a verdict nobody reads }
      ExitCode := 1;
    end
    else
      WriteLn ('VERDICT: under the gate -- par 4.1 stands, for now');
  end;
  ctxs.Free;

  { RO evidence (par 4.1 candidate mode): M9's only non-copying
    parameter mode is VAR, which also grants the right to write.  A
    VAR parameter never written through and never lent onward is a
    read-only borrow wearing a mutator's mark -- and a place where
    the checker cannot tell a reader from a writer. }
  WriteLn;
  WriteLn ('RO candidates (VAR params never written through):');
  for i := 0 to sem.RoCand.Count - 1 do
    WriteLn ('  ', sem.RoCand[i]);
  WriteLn (Format ('RO candidates          : %d', [sem.RoCand.Count]));
end.
