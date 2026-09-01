program bintrees;
{ binary-trees in Object Pascal, the same algorithm as BinTrees.m9.

  The allocation story is the whole benchmark, and Pascal's is New and
  Dispose: one heap allocation per node and one free per node, which
  is the shape M9's POOL exists to replace and the shape Rust's Box
  column also has.  There is no arena here because the language has no
  such thing -- writing one by hand would be measuring a program I
  wrote for the occasion rather than what an Object Pascal programmer
  would actually write.

  Checks on by default, off with -dUNCHECKED, as in fannkuch.pas. }
{$mode objfpc}{$H+}
{$IFDEF UNCHECKED}{$R-}{$Q-}{$ELSE}{$R+}{$Q+}{$ENDIF}

uses SysUtils;

type
  PNode = ^TNode;
  TNode = record
    left, right : PNode;
  end;

const
  MinDepth = 4;

function Make (depth: Int64): PNode;
begin
  New (Result);
  if depth > 0 then
  begin
    Result^.left  := Make (depth - 1);
    Result^.right := Make (depth - 1);
  end
  else
  begin
    Result^.left  := nil;
    Result^.right := nil;
  end;
end;

function Check (n: PNode): Int64;
begin
  Result := 1;
  if n^.left <> nil then Result := Result + Check (n^.left);
  if n^.right <> nil then Result := Result + Check (n^.right);
end;

{ Dispose is the other half of New, and leaving it out would be
  benchmarking a leak against two languages that free }
procedure Drop (n: PNode);
begin
  if n^.left <> nil then Drop (n^.left);
  if n^.right <> nil then Drop (n^.right);
  Dispose (n);
end;

function Generation (depth, iters: Int64): Int64;
var
  i : Int64;
  t : PNode;
begin
  Result := 0;
  for i := 1 to iters do
  begin
    t := Make (depth);
    Result := Result + Check (t);
    Drop (t);
  end;
end;

function Stretch (depth: Int64): Int64;
var t : PNode;
begin
  t := Make (depth);
  Result := Check (t);
  Drop (t);
end;

var
  maxDepth, depth, iters, i : Int64;
  longLived : PNode;

begin
  maxDepth := 18;
  if ParamCount >= 1 then maxDepth := StrToInt64 (ParamStr (1));
  if maxDepth < MinDepth + 2 then maxDepth := MinDepth + 2;

  WriteLn ('stretch tree of depth ', maxDepth + 1, '  check: ',
           Stretch (maxDepth + 1));

  longLived := Make (maxDepth);

  depth := MinDepth;
  while depth <= maxDepth do
  begin
    iters := 1;
    for i := 1 to maxDepth - depth + MinDepth do iters := iters * 2;
    WriteLn (iters, ' trees of depth ', depth, '  check: ',
             Generation (depth, iters));
    depth := depth + 2;
  end;

  WriteLn ('long lived tree of depth ', maxDepth, '  check: ',
           Check (longLived));
  Drop (longLived);
end.
