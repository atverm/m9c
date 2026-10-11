program semprobe;
{ Negative probes: each program in probes/ must produce the
  diagnostic its first line names.  A checker that accepts a clean
  corpus proves nothing until its rejections are demonstrated too.

  The programs live in FILES rather than in this source, because the
  M9 checker has to be held to the same ones: runtime/test/probediff.sh
  puts every file to both checkers and requires the diagnostics to be
  identical, line for line.  One source of truth, two consumers.

  The first line of each file is either

    (* EXPECT: substring *)     an error that must be reported
    (* LEDGER: substring *)     a par 4.1 retention, measured not
                                rejected

  and the rest of the file is the program.

  A probe writes its LEGAL forms first and its refusal after them, so
  nothing may be refused on a line BEFORE the first line the
  expectation is reported at: an earlier diagnostic is a legal form
  refused.  Until 2026-10-11 any diagnostic containing the text was
  enough, and a checker refusing every legal form passed. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Parse, M9AST, M9Sem;

var
  fails, ran : Integer;

function LoadFile (const fn: string): string;
var sl : TStringList;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  Result := sl.Text;
  sl.Free;
end;

{ the expectation is the first line: (* KIND: text *) }
procedure Expectation (const src: string; out kind, want: string);
var
  nl, colon : Integer;
  first : string;
begin
  kind := '';
  want := '';
  nl := Pos (#10, src);
  if nl = 0 then Exit;
  first := Trim (Copy (src, 1, nl - 1));
  if (Copy (first, 1, 2) <> '(*') or
     (Copy (first, Length (first) - 1, 2) <> '*)') then Exit;
  first := Trim (Copy (first, 3, Length (first) - 4));
  colon := Pos (':', first);
  if colon = 0 then Exit;
  kind := Trim (Copy (first, 1, colon - 1));
  want := Trim (Copy (first, colon + 1, MaxInt));
end;

procedure Probe (const fn: string);
var
  p : TParser;
  ast : TNode;
  sem : TSem;
  i, ln, hitLine, firstLine : Integer;
  hit : Boolean;
  src, kind, want, title, firstDiag : string;
  list : TStringList;
begin
  title := ChangeFileExt (ExtractFileName (fn), '');
  src := LoadFile (fn);
  Expectation (src, kind, want);
  if kind = '' then
  begin
    WriteLn (title, ': NO EXPECTATION on the first line');
    Inc (fails);
    Exit;
  end;
  Inc (ran);

  p := TParser.Create (src);
  ast := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    WriteLn (title, ': UNEXPECTED PARSE ERRORS');
    for i := 0 to p.Errors.Count - 1 do WriteLn ('  ', p.Errors[i]);
    Inc (fails);
    Exit;
  end;
  sem := TSem.Create;
  sem.LoadFile (ast);
  sem.CheckFile (ast);
  if kind = 'LEDGER' then list := sem.Ledger else list := sem.Errors;
  hit := False;
  hitLine := MaxInt;
  firstLine := MaxInt;
  firstDiag := '';
  for i := 0 to list.Count - 1 do
  begin
    ln := StrToIntDef (Copy (list[i], 1, Pos (':', list[i]) - 1), MaxInt);
    if Pos (want, list[i]) > 0 then
    begin
      hit := True;
      if ln < hitLine then hitLine := ln;
    end;
    if ln < firstLine then
    begin
      firstLine := ln;
      firstDiag := list[i];
    end;
  end;
  if hit and (kind = 'EXPECT') and (firstLine < hitLine) then
  begin
    WriteLn (title, ': REFUSED A LEGAL FORM before the expected refusal: ', firstDiag);
    Inc (fails);
  end
  else if hit then
    WriteLn (title, ': fires as intended')
  else
  begin
    WriteLn (title, ': DID NOT FIRE (expected "', want, '")');
    for i := 0 to list.Count - 1 do
      WriteLn ('  got: ', list[i]);
    Inc (fails);
  end;
  sem.Free;
  p.Free;
end;

var
  rec : TSearchRec;
  names : TStringList;
  i : Integer;
  dir : string;
begin
  fails := 0;
  ran := 0;
  dir := '../../probes/';
  names := TStringList.Create;
  names.Sorted := True;
  if FindFirst (dir + '*.m9', faAnyFile, rec) = 0 then
  begin
    repeat
      names.Add (dir + rec.Name);
    until FindNext (rec) <> 0;
    FindClose (rec);
  end;
  if names.Count = 0 then
  begin
    WriteLn ('semprobe: no probes found in ', dir);
    Halt (1);
  end;
  for i := 0 to names.Count - 1 do Probe (names[i]);
  names.Free;

  WriteLn;
  if fails > 0 then
  begin
    WriteLn ('FAIL: ', fails, ' of ', ran);
    ExitCode := 1;
  end
  else
    WriteLn ('PASS: all ', ran, ' probes fire');
end.
