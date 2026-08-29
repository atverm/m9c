program parsetest;
{ P1 exit harness (ROADMAP):
    1. every corpus/ and museum/ file parses with zero errors;
    2. fixpoint: print(parse(print(parse(src)))) = print(parse(src))
       byte for byte;
    3. re-lexing the printed text yields the source token sequence
       (kind and text) exactly.
  Exit code 1 on any failure.  Failing printed text is dumped next to
  the binary as parsefail-<name>.txt for inspection.                 }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Lex, M9AST, M9Parse, M9Print;

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

procedure SaveText (const fn, s: string);
var
  f : TextFile;
begin
  AssignFile (f, fn);
  Rewrite (f);
  Write (f, s);
  CloseFile (f);
end;

type
  TTokSig = array of record
    kind : TTokKind;
    text : string;
  end;

function Tokens (const src: string): TTokSig;
var
  lx : TLexer;
  t : TToken;
  n : Integer;
begin
  SetLength (Result, 0);
  n := 0;
  lx := TLexer.Create (src);
  repeat
    t := lx.Next;
    if t.kind = tkEOF then Break;
    SetLength (Result, n + 1);
    Result[n].kind := t.kind;
    Result[n].text := t.text;
    Inc (n);
  until False;
  lx.Free;
end;

procedure CheckFile (const fn: string);
var
  src, out1, out2, base : string;
  p1, p2 : TParser;
  a1, a2 : TNode;
  t0, t1 : TTokSig;
  i, bad : Integer;
begin
  base := ExtractFileName (fn);
  src := LoadFile (fn);

  p1 := TParser.Create (src);
  a1 := p1.ParseFile;
  if p1.Errors.Count > 0 then
  begin
    WriteLn (Format ('%-40s PARSE FAIL (%d errors)',
      [fn, p1.Errors.Count]));
    for i := 0 to p1.Errors.Count - 1 do
      WriteLn ('  ', p1.Errors[i]);
    gFail := True;
    p1.Free;
    Exit;
  end;
  out1 := PrintTree (a1);

  p2 := TParser.Create (out1);
  a2 := p2.ParseFile;
  if p2.Errors.Count > 0 then
  begin
    WriteLn (Format ('%-40s REPARSE FAIL (%d errors)',
      [fn, p2.Errors.Count]));
    for i := 0 to p2.Errors.Count - 1 do
      WriteLn ('  ', p2.Errors[i]);
    SaveText ('parsefail-' + base + '.txt', out1);
    gFail := True;
    p1.Free; p2.Free;
    Exit;
  end;
  out2 := PrintTree (a2);

  if out1 <> out2 then
  begin
    WriteLn (Format ('%-40s FIXPOINT FAIL', [fn]));
    SaveText ('parsefail-' + base + '.1.txt', out1);
    SaveText ('parsefail-' + base + '.2.txt', out2);
    gFail := True;
    p1.Free; p2.Free;
    Exit;
  end;

  t0 := Tokens (src);
  t1 := Tokens (out1);
  bad := -1;
  for i := 0 to Length (t0) - 1 do
  begin
    if (i >= Length (t1)) or (t0[i].kind <> t1[i].kind) or
       (t0[i].text <> t1[i].text) then
    begin
      bad := i;
      Break;
    end;
  end;
  if (bad < 0) and (Length (t1) > Length (t0)) then
    bad := Length (t0);
  if bad >= 0 then
  begin
    WriteLn (Format ('%-40s TOKEN FAIL at #%d', [fn, bad]));
    if bad < Length (t0) then
      WriteLn ('  source : ', KindName (t0[bad].kind), ' ''',
        t0[bad].text, '''')
    else
      WriteLn ('  source : <end>');
    if bad < Length (t1) then
      WriteLn ('  printed: ', KindName (t1[bad].kind), ' ''',
        t1[bad].text, '''')
    else
      WriteLn ('  printed: <end>');
    SaveText ('parsefail-' + base + '.txt', out1);
    gFail := True;
    p1.Free; p2.Free;
    Exit;
  end;

  WriteLn (Format ('%-40s ok  tokens=%d bytes=%d',
    [fn, Length (t0), Length (out1)]));
  p1.Free;
  p2.Free;
end;

procedure CheckDir (const dir: string);
var
  sr : TSearchRec;
  names : array of string;
  n, i, j : Integer;
  t : string;
begin
  SetLength (names, 0);
  n := 0;
  if FindFirst (dir + '/*.m9', faAnyFile, sr) = 0 then
  begin
    repeat
      SetLength (names, n + 1);
      names[n] := sr.Name;
      Inc (n);
    until FindNext (sr) <> 0;
    FindClose (sr);
  end;
  if n = 0 then
  begin
    WriteLn ('MISSING OR EMPTY DIR: ', dir);
    gFail := True;
    Exit;
  end;
  for i := 1 to n - 1 do
  begin
    t := names[i];
    j := i;
    while (j > 0) and (CompareStr (names[j-1], t) > 0) do
    begin
      names[j] := names[j-1];
      Dec (j);
    end;
    names[j] := t;
  end;
  for i := 0 to n - 1 do
    CheckFile (dir + '/' + names[i]);
end;

begin
  CheckDir ('../../corpus');
  CheckDir ('../../bench');          { benchmark programs are M9 too }
  CheckDir ('../../museum');
  WriteLn;
  if gFail then
  begin
    WriteLn ('FAIL');
    ExitCode := 1;
  end
  else
    WriteLn ('PASS: parse, fixpoint, and token equality across corpus+museum');
end.
