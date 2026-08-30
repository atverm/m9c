unit M9Print;
{ Canonical form.  One layout, deterministic; the roundtrip harness
  requires print(parse(print(parse(src)))) = print(parse(src)) byte
  for byte, and re-lexing the printed text must reproduce the source
  token sequence exactly (comments are not tokens).                  }
{$mode objfpc}{$H+}
interface

uses SysUtils, M9AST;

function PrintTree (root: TNode): string;

{ canonical fragments, used by the semantic checker to compare
  definition and implementation signatures as text }
function TypeText (n: TNode): string;
function ParamsText (n: TNode): string;
function ExprText (n: TNode): string;

implementation

const
  LF = #10;

function Sp (levels: Integer): string;
begin
  Result := StringOfChar (' ', levels * 2);
end;

function E (n: TNode): string; forward;
function TypeStr (n: TNode; ind: Integer): string; forward;
function SeqStr (n: TNode; ind: Integer): string; forward;
function DeclLines (n: TNode; ind: Integer): string; forward;

function QuoteStr (const s: string): string;
begin
  if Pos ('''', s) > 0 then
    Result := '"' + s + '"'
  else
    Result := '''' + s + '''';
end;

function QualStr (n: TNode): string;
begin
  Result := n.a;
  if n.b <> '' then Result := Result + '.' + n.b;
end;

function IdentsStr (n: TNode): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High (n.kids) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + n.kids[i].a;
  end;
end;

function ArgsStr (n: TNode): string;
var
  i : Integer;
begin
  Result := '';
  if n = nil then Exit;
  for i := 0 to High (n.kids) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + E (n.kids[i]);
  end;
end;

function DesigStr (n: TNode): string;
var
  i, j : Integer;
begin
  Result := n.a;
  for i := 0 to High (n.kids) do
    case n.kids[i].kind of
      nkSelField : Result := Result + '.' + n.kids[i].a;
      nkSelIndex :
        begin
          Result := Result + '[';
          for j := 0 to High (n.kids[i].kids) do
          begin
            if j > 0 then Result := Result + ', ';
            Result := Result + E (n.kids[i].kids[j]);
          end;
          Result := Result + ']';
        end;
    end;
end;

function E (n: TNode): string;
var
  i : Integer;
begin
  if n = nil then Exit ('');
  case n.kind of
    nkBin       : Result := E (n.kids[0]) + ' ' + n.a + ' ' + E (n.kids[1]);
    nkUn        : if n.a = 'NOT' then Result := 'NOT ' + E (n.kids[0])
                  else Result := n.a + E (n.kids[0]);
    nkIs        : begin
                    Result := E (n.kids[0]) + ' IS ';
                    if n.kids[1].kind = nkIsSome then
                      Result := Result + 'SOME ' + n.kids[1].a
                    else
                      Result := Result + QualStr (n.kids[1]);
                  end;
    nkParen     : Result := '(' + E (n.kids[0]) + ')';
    nkInt, nkReal, nkChar : Result := n.a;
    nkString    : Result := QuoteStr (n.a);
    nkTrue      : Result := 'TRUE';
    nkFalse     : Result := 'FALSE';
    nkNoneLit   : Result := 'NONE';
    nkSomeExpr  : Result := 'SOME (' + E (n.kids[0]) + ')';
    nkSharedExpr: Result := 'SHARED (' + E (n.kids[0]) + ')';
    nkNewExpr   : begin
                    Result := 'NEW (';
                    if n.kids[0] <> nil then
                      Result := Result + DesigStr (n.kids[0]) + ', ';
                    Result := Result + QualStr (n.kids[1]);
                    for i := 2 to High (n.kids) do
                      if n.kids[i] <> nil then
                        Result := Result + ', ' + E (n.kids[i]);
                    Result := Result + ')';
                  end;
    nkSliceOf3  : Result := 'SLICE (' + E (n.kids[0]) + ', ' +
                    E (n.kids[1]) + ', ' + E (n.kids[2]) + ')';
    nkCallExpr  : Result := DesigStr (n.kids[0]) + ' (' +
                    ArgsStr (n.kids[1]) + ')';
    nkDesignator: Result := DesigStr (n);
    nkQualident : Result := QualStr (n);
    nkIdent     : Result := n.a;
  else
    Result := '?expr?';
  end;
end;

function GroupInline (g: TNode): string;
begin
  Result := '';
  if g.f3 then Result := 'RO ';
  Result := Result + IdentsStr (g.kids[0]) + ': ' + TypeStr (g.kids[1], 0);
end;

function FieldsInline (fs: TNode): string;
var
  i : Integer;
begin
  Result := '';
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
  begin
    if i > 0 then Result := Result + ' ; ';
    Result := Result + GroupInline (fs.kids[i]);
  end;
  if fs.f1 then Result := Result + ' ;';
end;

function FieldsLines (fs: TNode; ind: Integer): string;
var
  i : Integer;
  s : string;
begin
  Result := '';
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
  begin
    s := Sp (ind);
    if fs.kids[i].f3 then s := s + 'RO ';
    s := s + IdentsStr (fs.kids[i].kids[0]) + ' : ' +
         TypeStr (fs.kids[i].kids[1], ind);
    if (i < High (fs.kids)) or fs.f1 then s := s + ' ;';
    Result := Result + s + LF;
  end;
end;

function TypeStr (n: TNode; ind: Integer): string;
var
  i : Integer;
begin
  if n = nil then Exit ('');
  case n.kind of
    nkQualident : Result := QualStr (n);
    nkGridType  : Result := 'GRID ' + E (n.kids[0]) + ' OF ' +
                    TypeStr (n.kids[1], ind);
    nkArrayType : Result := 'ARRAY ' + E (n.kids[0]) + ' OF ' +
                    TypeStr (n.kids[1], ind);
    nkSliceType : Result := 'SLICE OF ' + TypeStr (n.kids[0], ind);
    nkPtrType   : begin
                    Result := 'PTR ' + TypeStr (n.kids[0], ind);
                    if n.kids[1] <> nil then
                      Result := Result + ' IN ' + DesigStr (n.kids[1]);
                  end;
    nkOptType   : Result := 'OPT ' + TypeStr (n.kids[0], ind);
    nkSharedType: Result := 'SHARED PTR ' + TypeStr (n.kids[0], ind);
    nkRecordType: begin
                    Result := 'RECORD';
                    if n.kids[0] <> nil then
                      Result := Result + ' (' + QualStr (n.kids[0]) + ')';
                    Result := Result + LF +
                      FieldsLines (n.kids[1], ind + 1) + Sp (ind) + 'END';
                  end;
    nkCaseRecordType :
      begin
        Result := 'CASE RECORD' + LF;
        for i := 0 to High (n.kids) do
        begin
          Result := Result + Sp (ind) + '| ' + n.kids[i].a;
          if n.kids[i].kids[0] <> nil then
            Result := Result + ' : ' + FieldsInline (n.kids[i].kids[0]);
          Result := Result + LF;
        end;
        Result := Result + Sp (ind) + 'END';
      end;
    nkMonitorType :
      Result := 'MONITOR RECORD' + LF +
        FieldsLines (n.kids[0], ind + 1) + Sp (ind) + 'END';
  else
    Result := '?type?';
  end;
end;

function LabelStr (n: TNode): string;
begin
  if n.kind = nkLabelPattern then
    Result := n.a + ' (' + IdentsStr (n.kids[0]) + ')'
  else
  begin
    Result := E (n.kids[0]);
    if n.kids[1] <> nil then Result := Result + ' .. ' + E (n.kids[1]);
  end;
end;

function BlockLines (blk: TNode; ind: Integer;
                     withEnd: Boolean = True): string; forward;

function StmtStr (n: TNode; ind: Integer): string;
var
  i, j : Integer;
  s : string;
begin
  case n.kind of
    nkAssign   : Result := Sp (ind) + DesigStr (n.kids[0]) + ' := ' +
                   E (n.kids[1]);
    nkCallStmt : begin
                   Result := Sp (ind) + DesigStr (n.kids[0]);
                   if n.f1 then
                     Result := Result + ' (' + ArgsStr (n.kids[1]) + ')';
                 end;
    nkIf :
      begin
        Result := Sp (ind) + 'IF ' + E (n.kids[0]) + ' THEN' + LF +
                  SeqStr (n.kids[1], ind + 1);
        for i := 2 to High (n.kids) do
          case n.kids[i].kind of
            nkElsif :
              Result := Result + Sp (ind) + 'ELSIF ' +
                E (n.kids[i].kids[0]) + ' THEN' + LF +
                SeqStr (n.kids[i].kids[1], ind + 1);
            nkElse :
              Result := Result + Sp (ind) + 'ELSE' + LF +
                SeqStr (n.kids[i].kids[0], ind + 1);
          end;
        Result := Result + Sp (ind) + 'END';
      end;
    nkWhile :
      Result := Sp (ind) + 'WHILE ' + E (n.kids[0]) + ' DO' + LF +
        SeqStr (n.kids[1], ind + 1) + Sp (ind) + 'END';
    nkFor :
      begin
        Result := Sp (ind) + 'FOR ' + n.a + ' := ' + E (n.kids[0]) +
          ' TO ' + E (n.kids[1]);
        if n.kids[2] <> nil then
          Result := Result + ' BY ' + E (n.kids[2]);
        Result := Result + ' DO' + LF + SeqStr (n.kids[3], ind + 1) +
          Sp (ind) + 'END';
      end;
    nkLoop :
      Result := Sp (ind) + 'LOOP' + LF + SeqStr (n.kids[0], ind + 1) +
        Sp (ind) + 'END';
    nkExit : Result := Sp (ind) + 'EXIT';
    nkCase :
      begin
        Result := Sp (ind) + 'CASE ' + E (n.kids[0]) + ' OF' + LF;
        for i := 1 to High (n.kids) do
          case n.kids[i].kind of
            nkCaseArm :
              begin
                s := '';
                for j := 0 to High (n.kids[i].kids[0].kids) do
                begin
                  if j > 0 then s := s + ', ';
                  s := s + LabelStr (n.kids[i].kids[0].kids[j]);
                end;
                Result := Result + Sp (ind) + '| ' + s + ' :' + LF +
                  SeqStr (n.kids[i].kids[1], ind + 2);
              end;
            nkElse :
              Result := Result + Sp (ind) + 'ELSE' + LF +
                SeqStr (n.kids[i].kids[0], ind + 2);
          end;
        Result := Result + Sp (ind) + 'END';
      end;
    nkReturn :
      begin
        Result := Sp (ind) + 'RETURN';
        if n.kids[0] <> nil then Result := Result + ' ' + E (n.kids[0]);
      end;
    nkRaiseStmt :
      begin
        Result := Sp (ind) + 'RAISE ' + QualStr (n.kids[0]);
        if n.kids[1] <> nil then
          Result := Result + ' (' + ArgsStr (n.kids[1]) + ')';
      end;
    nkDispose :
      Result := Sp (ind) + 'DISPOSE (' + DesigStr (n.kids[0]) + ')';
    nkThread :
      Result := Sp (ind) + 'THREAD (' + E (n.kids[0]) + ', ' +
        E (n.kids[1]) + ')';
    nkTransfer :
      Result := Sp (ind) + 'TRANSFER (' + E (n.kids[0]) + ', ' +
        E (n.kids[1]) + ')';
    nkWait   : Result := Sp (ind) + 'WAIT (' + E (n.kids[0]) + ')';
    nkSignal : Result := Sp (ind) + 'SIGNAL (' + E (n.kids[0]) + ')';
    nkBlock  : Result := BlockLines (n, ind);
    nkStmtSeq: Result := Sp (ind);        { error placeholder: nothing }
  else
    Result := Sp (ind) + '?stmt?';
  end;
end;

function SeqStr (n: TNode; ind: Integer): string;
var
  i : Integer;
  s : string;
begin
  Result := '';
  if n = nil then Exit;
  for i := 0 to High (n.kids) do
  begin
    s := StmtStr (n.kids[i], ind);
    if (i < High (n.kids)) or n.f1 then s := s + ' ;';
    Result := Result + s + LF;
  end;
end;

function BlockLines (blk: TNode; ind: Integer;
                     withEnd: Boolean = True): string;
var
  i, j : Integer;
  h : TNode;
begin
  Result := Sp (ind) + 'BEGIN' + LF + SeqStr (blk.kids[0], ind + 1);
  i := 1;
  if (i <= High (blk.kids)) and (blk.kids[i].kind = nkHandler) then
  begin
    Result := Result + Sp (ind) + 'EXCEPT' + LF;
    while (i <= High (blk.kids)) and (blk.kids[i].kind = nkHandler) do
    begin
      h := blk.kids[i];
      Result := Result + Sp (ind) + '| ' + QualStr (h.kids[0]);
      if h.kids[1] <> nil then
      begin
        Result := Result + ' (';
        for j := 0 to High (h.kids[1].kids) do
        begin
          if j > 0 then Result := Result + ', ';
          Result := Result + E (h.kids[1].kids[j]);
        end;
        Result := Result + ')';
      end;
      Result := Result + ' :' + LF + SeqStr (h.kids[2], ind + 2);
      Inc (i);
    end;
  end;
  if (i <= High (blk.kids)) and (blk.kids[i].kind = nkFinally) then
  begin
    Result := Result + Sp (ind) + 'FINALLY' + LF +
      SeqStr (blk.kids[i].kids[0], ind + 1);
    Inc (i);
  end;
  if withEnd then Result := Result + Sp (ind) + 'END';
end;

function ParamsStr (pl: TNode): string;
var
  i : Integer;
  p : TNode;
  s : string;
begin
  Result := '';
  for i := 0 to High (pl.kids) do
  begin
    p := pl.kids[i];
    if i > 0 then Result := Result + ' ; ';
    s := '';
    if p.f1 then s := 'VAR ';
    if p.f2 then s := 'OWN ';
    if p.f3 then s := 'RO ';
    Result := Result + s + IdentsStr (p.kids[0]) + ': ' +
      TypeStr (p.kids[1], 0);
  end;
end;

function ProcLines (n: TNode; ind: Integer): string;
var
  hdr : string;
  i : Integer;
  body : TNode;
begin
  hdr := Sp (ind) + 'PROCEDURE ' + n.a;
  if n.b <> '' then hdr := hdr + ' = ' + QuoteStr (n.b);
  hdr := hdr + ' (' + ParamsStr (n.kids[0]) + ')';
  if n.kids[1] <> nil then
    if n.f3 then hdr := hdr + ' : RO ' + TypeStr (n.kids[1], ind)
    else hdr := hdr + ' : ' + TypeStr (n.kids[1], ind);
  if n.kids[2] <> nil then
  begin
    hdr := hdr + LF + Sp (ind + 1) + 'RAISES ';
    for i := 0 to High (n.kids[2].kids) do
    begin
      if i > 0 then hdr := hdr + ', ';
      hdr := hdr + QualStr (n.kids[2].kids[i]);
    end;
  end;
  if n.kids[3] <> nil then
    hdr := hdr + ' [' + n.kids[3].a + ']';
  body := n.kids[4];
  if body = nil then
  begin
    Result := hdr + ' ;' + LF;
    Exit;
  end;
  Result := hdr + ' =' + LF;
  { local declarations, then the block, then END name ; }
  for i := 0 to High (body.kids) - 1 do
    Result := Result + DeclLines (body.kids[i], ind);
  Result := Result + BlockLines (body.kids[High (body.kids)], ind);
  Result := Result + ' ' + n.a + ' ;' + LF;
end;

function DeclLines (n: TNode; ind: Integer): string;
var
  i : Integer;
  d : TNode;
begin
  Result := '';
  case n.kind of
    nkConstSection :
      begin
        Result := Sp (ind) + 'CONST' + LF;
        for i := 0 to High (n.kids) do
          Result := Result + Sp (ind + 1) + n.kids[i].a + ' = ' +
            E (n.kids[i].kids[0]) + ' ;' + LF;
      end;
    nkTypeSection :
      begin
        Result := Sp (ind) + 'TYPE' + LF;
        for i := 0 to High (n.kids) do
        begin
          d := n.kids[i];
          if d.kids[0] = nil then
            Result := Result + Sp (ind + 1) + d.a + ' ;' + LF
          else
            Result := Result + Sp (ind + 1) + d.a + ' = ' +
              TypeStr (d.kids[0], ind + 1) + ' ;' + LF;
        end;
      end;
    nkVarSection :
      begin
        Result := Sp (ind) + 'VAR' + LF;
        for i := 0 to High (n.kids) do
        begin
          Result := Result + Sp (ind + 1);
          if n.kids[i].f3 then Result := Result + 'RO ';
          Result := Result +
            IdentsStr (n.kids[i].kids[0]) + ' : ' +
            TypeStr (n.kids[i].kids[1], ind + 1) + ' ;' + LF;
        end;
      end;
    nkExcSection :
      begin
        Result := Sp (ind) + 'EXCEPTION' + LF;
        for i := 0 to High (n.kids) do
        begin
          d := n.kids[i];
          Result := Result + Sp (ind + 1) + d.a;
          if d.kids[0] <> nil then
            Result := Result + ' (' + FieldsInline (d.kids[0]) + ')';
          Result := Result + ' ;' + LF;
        end;
      end;
    nkProcDecl :
      Result := ProcLines (n, ind);
  end;
end;

function UnitLines (u: TNode): string;
var
  i : Integer;
  hdr : string;
  hasBody : Boolean;
begin
  case u.kind of
    nkDefinition :
      begin
        hdr := '';
        if u.f1 then hdr := hdr + 'UNSAFE ';
        if u.f2 then hdr := hdr + 'STATEFUL ';
        hdr := hdr + 'DEFINITION MODULE ';
        if u.b <> '' then hdr := hdr + 'FOR ' + QuoteStr (u.b) + ' ';
        hdr := hdr + u.a + ' ;';
      end;
    nkImplementation :
      begin
        hdr := '';
        if u.f1 then hdr := hdr + 'UNSAFE ';
        hdr := hdr + 'IMPLEMENTATION MODULE ' + u.a + ' ;';
      end;
  else
    hdr := 'MODULE ' + u.a + ' ;';
  end;
  Result := hdr + LF + LF;
  hasBody := False;
  for i := 0 to High (u.kids) do
  begin
    case u.kids[i].kind of
      nkFromImport :
        Result := Result + 'FROM ' + u.kids[i].a + ' IMPORT ' +
          IdentsStr (u.kids[i].kids[0]) + ' ;' + LF + LF;
      nkImportList :
        Result := Result + 'IMPORT ' +
          IdentsStr (u.kids[i].kids[0]) + ' ;' + LF + LF;
      nkModBody :
        begin
          { the block's END is the MODULE's END: one keyword, not two }
          Result := Result + BlockLines (u.kids[i].kids[0], 0, False);
          hasBody := True;
        end;
    else
      Result := Result + DeclLines (u.kids[i], 0) + LF;
    end;
  end;
  if hasBody then
    Result := Result + 'END ' + u.a + '.' + LF
  else
    Result := Result + 'END ' + u.a + '.' + LF;
end;

function PrintTree (root: TNode): string;
var
  i : Integer;
begin
  Result := '';
  for i := 0 to High (root.kids) do
  begin
    if i > 0 then Result := Result + LF + LF;
    Result := Result + UnitLines (root.kids[i]);
  end;
end;

function TypeText (n: TNode): string;
begin
  if n = nil then Result := '' else Result := TypeStr (n, 0);
end;

function ParamsText (n: TNode): string;
begin
  if n = nil then Result := '' else Result := ParamsStr (n);
end;

function ExprText (n: TNode): string;
begin
  if n = nil then Result := '' else Result := E (n);
end;

end.
