program lextest;
{$mode objfpc}{$H+}
{ Lexes every .m9 under corpus/ and museum/ (run from host/fpc).
  Exit code 1 if any of those produce an error token -- museum pieces
  are semantic failures and must lex clean.  The adversarial section
  exists to produce errors; those are printed, not gated. }
uses SysUtils, Classes, M9Lex;

function LexFile (const fn: string): Integer;
var
  sl : TStringList;
  lx : TLexer;
  t : TToken;
  n : Integer;
begin
  sl := TStringList.Create;
  sl.LoadFromFile (fn);
  lx := TLexer.Create (sl.Text);
  n := 0; Result := 0;
  repeat
    t := lx.Next;
    Inc (n);
    if t.kind = tkError then
    begin
      Inc (Result);
      WriteLn (Format ('  ERROR %d:%d %s', [t.line, t.col, t.text]));
    end;
  until t.kind = tkEOF;
  WriteLn (Format ('%-40s tokens=%d errors=%d', [fn, n, Result]));
  lx.Free; sl.Free;
end;

procedure LexDir (const dir: string; var errs: Integer);
{ byte-order sorted: ext4 and NTFS disagree on enumeration order,
  and the golden diff in CI needs one truth }
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
    Inc (errs);
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
    errs := errs + LexFile (dir + '/' + names[i]);
end;

var
  errs : Integer;
  s : string;
  lx : TLexer;
  t : TToken;
begin
  errs := 0;
  LexDir ('../../corpus', errs);
  LexDir ('../../bench', errs);      { benchmark programs are M9 too }
  LexDir ('../../museum', errs);

  WriteLn;
  WriteLn ('=== adversarial (errors below are expected, not gated) ===');
  s := 'a := 1..5; x := 2.5e-3; (* nested (* deep *) ok *) y := 0x1F;' +
       ' nul := 0C; nl := 0AC; ay := 41C; esc := 10C;' +
       { each of the next six must produce exactly one error token }
       ' e1 := 1E5; e2 := 1e5; e3 := 1A; e4 := 0ac;' +
       ' e5 := 110000C; e6 := 0D800C;' +
       { D800C without the leading digit is an identifier, by design }
       ' id := D800C;' +
       ' bad_name := "unterminated';
  lx := TLexer.Create (s);
  repeat
    t := lx.Next;
    WriteLn (Format ('%4d:%-3d %-14s %s',
      [t.line, t.col, KindName (t.kind), t.text]));
  until t.kind = tkEOF;
  lx.Free;

  WriteLn;
  if errs > 0 then
  begin
    WriteLn ('FAIL: ', errs, ' lex errors in corpus/museum');
    ExitCode := 1;
  end
  else
    WriteLn ('PASS: corpus and museum lex clean');
end.
