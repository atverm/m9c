program lexdump;
{ P5 stage-1 oracle side: dump the FPC lexer's token stream for one
  file, one token per line: 'line:col Kind text'.  The M9-compiled
  lexer must produce the identical bytes (lexdiff in runtime/test). }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9Lex;

var
  sl : TStringList;
  lx : TLexer;
  t : TToken;
begin
  if ParamCount < 1 then begin WriteLn ('usage: lexdump FILE'); Halt (2); end;
  sl := TStringList.Create;
  sl.LoadFromFile (ParamStr (1));
  lx := TLexer.Create (sl.Text);
  repeat
    t := lx.Next;
    WriteLn (Format ('%d:%d %s %s', [t.line, t.col, KindName (t.kind), t.text]));
  until t.kind = tkEOF;
  lx.Free;
  sl.Free;
end.
