program parsedump;
{ P5 stage-1 oracle side: print(parse(FILE)) to stdout.  The
  M9-compiled parser+printer must produce identical bytes. }
{$mode objfpc}{$H+}
uses SysUtils, Classes, M9AST, M9Parse, M9Print;

var
  sl : TStringList;
  p : TParser;
begin
  if ParamCount < 1 then begin WriteLn ('usage: parsedump FILE'); Halt (2); end;
  sl := TStringList.Create;
  sl.LoadFromFile (ParamStr (1));
  p := TParser.Create (sl.Text);
  Write (PrintTree (p.ParseFile));
  if p.Errors.Count > 0 then Halt (1);
  p.Free;
  sl.Free;
end.
