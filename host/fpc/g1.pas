{$mode objfpc}{$H+}
{ g1 -- run the generator over ONE file, wherever it lives, and print
  its errors with line numbers.  gentest.pas only walks corpus/, and
  m9c reports a COUNT rather than the messages (Parse.m9 counts;
  messages are stage-2 work), so porting a module outside the corpus
  had no way to see what the generator refused.  Scratch tool, not a
  gate: `fpc -O2 g1.pas && ./g1 FILE.m9 DEP DEP ...` }
program g1;
uses SysUtils, Classes, M9AST, M9Parse, M9Gen;

function LoadFile (const fn: string): string;
var f: TStringList;
begin
  f := TStringList.Create;
  f.LoadFromFile (fn);
  Result := f.Text;
  f.Free;
end;

var
  o : TStringList;
  DepDir : string;
  p, dp : TParser;
  root, droot : TNode;
  g : TGen;
  i, k : Integer;
begin
  { deps are looked for beside the file, then in corpus/ }
  if ParamCount < 1 then
  begin
    WriteLn ('usage: g1 FILE.m9 [DEPMODULE ...]');
    Halt (2);
  end;
  DepDir := ExtractFilePath (ParamStr (1));
  if DepDir = '' then DepDir := './';
  p := TParser.Create (LoadFile (ParamStr (1)));
  root := p.ParseFile;
  if p.Errors.Count > 0 then
  begin
    for i := 0 to p.Errors.Count - 1 do WriteLn (p.Errors[i]);
    Halt (1);
  end;
  g := TGen.Create;
  for k := 2 to ParamCount do
  begin
    if FileExists (DepDir + ParamStr (k) + '.m9') then
      dp := TParser.Create (LoadFile (DepDir + ParamStr (k) + '.m9'))
    else
      dp := TParser.Create (LoadFile ('../../corpus/' + ParamStr (k) + '.m9'));
    droot := dp.ParseFile;
    for i := 0 to High (droot.kids) do g.LoadExtern (droot.kids[i]);
  end;
  for i := 0 to High (root.kids) do g.LoadUnit (root.kids[i]);
  { the module's OWN name, so the include guard is an identifier and
    the emitted C compiles as-is -- it used to be the output path,
    which put slashes in a #ifndef }
  g.Emit (ChangeFileExt (ExtractFileName (ParamStr (1)), ''));
  { the emitted C, so a construct can be INSPECTED and not merely
    reported clean -- added while implementing par 6, where "no
    generator errors" says nothing about whether the C is right }
  if g.Errors.Count = 0 then
  begin
    o := TStringList.Create;
    o.Text := g.HText; o.SaveToFile ('/tmp/g1out.h');
    o.Text := g.CText; o.SaveToFile ('/tmp/g1out.c');
    o.Free;
  end;
  if g.Errors.Count = 0 then
    WriteLn ('no generator errors (C in /tmp/g1out.h and .c)')
  else
    for i := 0 to g.Errors.Count - 1 do WriteLn (g.Errors[i]);
end.
