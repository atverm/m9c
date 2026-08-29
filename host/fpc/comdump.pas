program comdump;
{ The comment side channel, oracle side: dump every comment the FPC
  lexer skipped over one file, one per line:

      line:col-endLine text

  with newlines shown as \n and backslashes doubled, so a multi-line
  comment stays one line and the escaping is reversible.  The
  M9-compiled lexer must produce the identical bytes (comdiff in
  runtime/test).

  Comments are NOT tokens -- lexdump's stream does not contain one and
  must not start to, or "token streams byte-identical to the oracle"
  stops being literally true.  Hence a second dump rather than a
  wider one. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Lex;

function Esc (const s: string): string;
var
  i : Integer;
begin
  Result := '';
  for i := 1 to Length (s) do
    case s[i] of
      #10 : Result := Result + '\n';
      #13 : Result := Result + '\r';
      '\' : Result := Result + '\\';
    else
      Result := Result + s[i];
    end;
end;

var
  sl : TStringList;
  lx : TLexer;
  t : TToken;
  i : Integer;
  c : TComment;
begin
  if ParamCount < 1 then begin WriteLn ('usage: comdump FILE'); Halt (2); end;
  sl := TStringList.Create;
  sl.LoadFromFile (ParamStr (1));
  lx := TLexer.Create (sl.Text);
  lx.Collect (True);
  repeat
    t := lx.Next;
  until t.kind = tkEOF;
  for i := 0 to lx.ComCount - 1 do
  begin
    c := lx.ComAt (i);
    WriteLn (Format ('%d:%d-%d %s', [c.line, c.col, c.endLine, Esc (c.text)]));
  end;
  WriteLn (Format ('comments=%d', [lx.ComCount]));
  lx.Free;
  sl.Free;
end.
