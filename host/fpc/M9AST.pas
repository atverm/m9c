unit M9AST;
{ M9 abstract syntax: one homogeneous node type, kinds mirroring the
  productions of report par 10.  Fixed child slots may be nil (they
  print as absence); a/b carry ident and literal text VERBATIM so the
  printer can reproduce the exact token (0x1F stays 0x1F).           }
{$mode objfpc}{$H+}
interface

type
  TNodeKind = (
    nkFile,
    { units: a=name; nkDefinition b=FOR-string, f1=UNSAFE f2=STATEFUL;
      nkImplementation f1=UNSAFE; kids: imports, decls, [nkModBody] }
    nkDefinition, nkImplementation, nkProgram,
    nkModBody,                    { kids[0]=stmtseq }
    nkFromImport,                 { a=module; kids: nkIdent }
    nkImportList,                 { kids: nkIdent }
    nkConstSection, nkTypeSection, nkVarSection, nkExcSection,
    nkConstDecl,                  { a=name; kids[0]=expr }
    nkTypeDecl,                   { a=name; kids[0]=type|nil (opaque) }
    nkVarDecl,                    { kids[0]=identlist kids[1]=type }
    nkExcDecl,                    { a=name; kids[0]=fieldseq|nil }
    { a=name b=foreign name ('' if native);
      kids: 0=paramlist 1=rettype|nil 2=raises|nil 3=attrib|nil
            4=procbody|nil }
    nkProcDecl,
    nkParamList,
    nkParam,                      { f1=VAR f2=OWN; kids: identlist, type }
    nkRaises,                     { kids: qualidents }
    nkAttrib,                     { a=ident }
    nkProcBody,                   { kids: decls..., last=nkBlock }
    nkBlock,                      { kids[0]=stmtseq, nkHandler*, [nkFinally] }
    nkHandler,                    { kids: qualident, arglist|nil, stmtseq }
    nkFinally,                    { kids[0]=stmtseq }
    nkIdentList, nkIdent,         { nkIdent: a=name }
    nkQualident,                  { a=first, b=second ('' if single) }
    { types }
    nkArrayType,                  { kids: constexpr, type }
    nkGridType,                   { kids: rank constexpr, type }
    nkSliceType,                  { kids: type, attrib|nil }
    nkRecordType,                 { kids: base qualident|nil, fieldseq }
    nkCaseRecordType,             { kids: nkVariant }
    nkVariant,                    { a=name; kids[0]=fieldseq|nil }
    nkMonitorType,                { kids[0]=fieldseq }
    nkFieldSeq,                   { f1=trailing ';'; kids: nkFieldGroup }
    nkFieldGroup,                 { kids: identlist, type }
    nkPtrType,                    { kids: type, IN-designator|nil }
    nkOptType, nkSharedType,      { kids[0]=type }
    { statements }
    nkStmtSeq,                    { f1=trailing ';'; kids: stmts }
    nkAssign,                     { kids: designator, expr }
    nkCallStmt,                   { f1=parens present; kids: designator,
                                    arglist|nil }
    nkIf,                         { kids: cond, seq, nkElsif*, [nkElse] }
    nkElsif, nkWhile,             { kids: cond, seq }
    nkElse,                       { kids[0]=seq }
    nkFor,                        { a=ident; kids: from,to,by|nil,seq }
    nkLoop,                       { kids[0]=seq }
    nkExit,
    nkCase,                       { kids: expr, nkCaseArm*, [nkElse] }
    nkCaseArm,                    { kids: labellist, seq }
    nkLabelList,
    nkLabelRange,                 { kids: expr, expr|nil }
    nkLabelPattern,               { a=ident; kids[0]=identlist }
    nkReturn,                     { kids[0]=expr|nil }
    nkRaiseStmt,                  { kids: qualident, arglist|nil }
    nkDispose,                    { kids[0]=designator }
    nkThread, nkTransfer,         { kids: expr, expr }
    nkWait, nkSignal,             { kids[0]=expr }
    { expressions }
    nkBin,                        { a=operator text; kids: left, right }
    nkUn,                         { a='+'|'-'|'NOT'; kids[0] }
    nkIs,                         { kids: expr, nkIsSome|nkQualident }
    nkIsSome,                     { a=bound ident }
    nkParen,                      { kids[0] }
    nkInt, nkReal, nkChar,        { a=verbatim text }
    nkString,                     { a=content, b=quote char }
    nkTrue, nkFalse, nkNoneLit,
    nkSomeExpr,                   { kids[0] }
    nkSharedExpr,                 { kids[0]: owned ptr -> first handle }
    nkNewExpr,                    { kids: pool designator|nil, qualident,
                                    count expr|nil }
    nkSliceOf3,                   { kids: slice, start, len }
    nkCallExpr,                   { kids: designator, arglist }
    nkDesignator,                 { a=base ident; kids: selectors }
    nkSelField,                   { a=field }
    nkSelIndex,                   { kids[0]=index expr }
    nkArgList,
    nkEnumType,                   { kids: nkIdent per member, in order }
    nkProcType,                   { PROCEDURE (...) [: T] [RAISES] as a
                                    type; kids as a ProcDecl's head:
                                    paramlist, result|nil, raises|nil }
    nkAggregate,                  { [ e1, ..., en ] as the value of a
                                    CONST: the kids are the elements.
                                    Only a ConstDecl's kid is ever one.
                                    Ast.NAggregate, 2026-10-01 }
    nkGridOf,                     { GRID (s, n0, ..., nR): kids[0] the
                                    slice, the rest the extents.
                                    Ast.NGridOf, 2026-10-08 }
    nkLinkList,                   { LINK "w1", "w2" on a FOR "C" unit:
                                    the Definition's LAST kid; kids are
                                    nkString, a the word.
                                    Ast.NLinkList, 2026-10-09 }
    nkCallSel                     { F (x).f, F (x)[i]: kids[0] the
                                    nkCallExpr, the rest selectors.
                                    Ast.NCallSel, 2026-10-09 }
  );

  TNode = class
  public
    kind      : TNodeKind;
    a, b      : string;
    f1, f2, f3, f4: Boolean;  { f3: the RO mode on a binding;
                                f4: KEPT, which composes with any mode
                                rather than replacing one }
    line, col : Integer;
    kids      : array of TNode;
    tys       : string;    { the typed tree's stage 3: the canonical
                             type the checker gave this expression
                             (SetTyStr/TyStrAt); '' unknown }
    ty        : TNode;     { the TYPED TREE (2026-10-09), through
                             SetType/TypeAt below: corpus/Ast.m9 keys
                             a table by node id, because the M9
                             checker reads the tree through borrowed
                             pointers; a class field is the same
                             thing here }
    constructor Create (k: TNodeKind);
    procedure Add (n: TNode);          { nil is a legal child }
  end;

{ THE TYPED TREE (2026-10-09, the review's decision): the checker
  records the type it resolved at a node -- on a designator's selector,
  the component the selector reaches, qualified in its declaring module
  -- and the generator reads it instead of working the type out again;
  nil where no checker has run or it did not know }
procedure SetType (n, t: TNode);
function TypeAt (n: TNode): TNode;
{ stage 3: an EXPRESSION's type, as the checker's canonical string
  ('I64', 'PTR Mod.T', '<str1>', ...); '' where none was recorded }
procedure SetTyStr (n: TNode; const t: string);
function TyStrAt (n: TNode): string;

function Utf8Next (const s: string; var i: Integer): Cardinal;
function Utf8Len (const s: string): Integer;
function Utf8Enc (c: Cardinal): string;
function LabelName (lv: TNode): string;
{ A constant's VALUE, one evaluator for every place C needs one -- a
  CASE label, an array bound (the typed tree's stage 2, 2026-10-09):
  an integer literal or an expression of them (FoldInt), a CHAR
  literal, a one-character string.  ch says the value is a character.
  False for anything else.  (corpus/Ast.m9 ScalarConst/CharCode) }
function ScalarConst (e: TNode; var v: Int64; var ch: Boolean): Boolean;
function CharCode (const lit: string): Int64;
function FoldInt (e: TNode; var v: Int64): Boolean;

implementation

function CharCode (const lit: string): Int64;
var
  i : Integer;
  c : Char;
begin
  { hex digits + trailing C: 0AC = U+000A }
  Result := 0;
  for i := 1 to Length (lit) - 1 do
  begin
    c := lit[i];
    if (c >= '0') and (c <= '9') then Result := Result * 16 + (Ord (c) - 48)
    else Result := Result * 16 + (Ord (c) - 55);
    if Result > $10FFFF then Exit (-1);
  end;
end;

function ScalarConst (e: TNode; var v: Int64; var ch: Boolean): Boolean;
var i : Integer;
begin
  ch := False;
  if e <> nil then
  begin
    if e.kind = nkChar then
    begin
      v := CharCode (e.a);
      ch := True;
      Exit (v >= 0);
    end;
    if e.kind = nkString then
    begin
      if Utf8Len (e.a) <> 1 then Exit (False);
      i := 1;
      v := Utf8Next (e.a, i);
      ch := True;
      Exit (True);
    end;
    if (e.kind = nkParen) and (Length (e.kids) = 1) then
      Exit (ScalarConst (e.kids[0], v, ch));
  end;
  Result := FoldInt (e, v);
end;

procedure SetType (n, t: TNode);
begin
  if n <> nil then n.ty := t;
end;

function TypeAt (n: TNode): TNode;
begin
  if n = nil then Exit (nil);
  Result := n.ty;
end;

procedure SetTyStr (n: TNode; const t: string);
begin
  if n <> nil then n.tys := t;
end;

function TyStrAt (n: TNode): string;
begin
  if n = nil then Exit ('');
  Result := n.tys;
end;

{ A string literal's text is UTF-8 octets on this side (FPC reads the
  file as bytes; m9c reads it as scalars since 2026-10-09): these two
  read it as the scalars the M9 side holds.  Lenient: a malformed
  sequence counts byte by byte, as the lexer never refuses one. }
function Utf8Next (const s: string; var i: Integer): Cardinal;
var b : Byte; n, k : Integer;
begin
  b := Ord (s[i]);
  if b < $80 then begin Result := b; Inc (i); Exit; end;
  if (b and $E0) = $C0 then begin Result := b and $1F; n := 1; end
  else if (b and $F0) = $E0 then begin Result := b and $0F; n := 2; end
  else if (b and $F8) = $F0 then begin Result := b and $07; n := 3; end
  else begin Result := b; Inc (i); Exit; end;
  if i + n > Length (s) then begin Result := b; Inc (i); Exit; end;
  for k := 1 to n do
    if (Ord (s[i + k]) and $C0) <> $80 then begin Result := b; Inc (i); Exit; end;
  for k := 1 to n do Result := (Result shl 6) or (Ord (s[i + k]) and $3F);
  Inc (i, n + 1);
end;

function Utf8Len (const s: string): Integer;
var i : Integer;
begin
  Result := 0;
  i := 1;
  while i <= Length (s) do begin Utf8Next (s, i); Inc (Result); end;
end;

{ a scalar as its UTF-8 bytes (the inverse of Utf8Next) }
function Utf8Enc (c: Cardinal): string;
begin
  if c < $80 then Result := Chr (c)
  else if c < $800 then Result := Chr ($C0 or (c shr 6)) + Chr ($80 or (c and $3F))
  else if c < $10000 then Result := Chr ($E0 or (c shr 12)) + Chr ($80 or ((c shr 6) and $3F)) + Chr ($80 or (c and $3F))
  else Result := Chr ($F0 or (c shr 18)) + Chr ($80 or ((c shr 12) and $3F)) + Chr ($80 or ((c shr 6) and $3F)) + Chr ($80 or (c and $3F));
end;

constructor TNode.Create (k: TNodeKind);
begin
  kind := k;
end;

procedure TNode.Add (n: TNode);
begin
  SetLength (kids, Length (kids) + 1);
  kids[High (kids)] := n;
end;

{ the member a CASE label names: `Fs', `Kind.Fs', `Mod.Kind.Fs' --
  the last field of a designator of field selectors only; '' else
  (mirrors Sem/Gen.LabelName; cp-kernel's issue 13, 2026-10-09) }
function LabelName (lv: TNode): string;
var i : Integer;
begin
  Result := '';
  if (lv = nil) or (lv.kind <> nkDesignator) then Exit;
  if Length (lv.kids) = 0 then Exit (lv.a);
  for i := 0 to High (lv.kids) do
    if (lv.kids[i] = nil) or (lv.kids[i].kind <> nkSelField) then Exit;
  Result := lv.kids[High (lv.kids)].a;
end;

{ the value of an integer CONSTANT EXPRESSION, with the runtime's
  arithmetic: checked, DIV and MOD truncating (mirrors Ast.FoldInt) }
function FoldLit (const s: string; var v: Int64): Boolean;
var i, d, base, from : Integer; hi : Int64;
begin
  Result := False;
  base := 10; from := 1;
  if (Length (s) > 2) and (s[1] = '0') and (s[2] in ['x', 'X']) then begin base := 16; from := 3; end;
  if Length (s) < from then Exit;
  v := 0;
  for i := from to Length (s) do
  begin
    case s[i] of
      '0'..'9': d := Ord (s[i]) - 48;
      'a'..'f': if base = 16 then d := Ord (s[i]) - 87 else Exit;
      'A'..'F': if base = 16 then d := Ord (s[i]) - 55 else Exit;
    else Exit;
    end;
    hi := (High (Int64) - d) div base;
    if v > hi then Exit;
    v := v * base + d;
  end;
  Result := True;
end;

function FoldInt (e: TNode; var v: Int64): Boolean;
var a, b : Int64;
begin
  Result := False;
  if e = nil then Exit;
  if e.kind = nkInt then Exit (FoldLit (e.a, v));
  if Length (e.kids) < 1 then Exit;
  if e.kind = nkParen then Exit (FoldInt (e.kids[0], v));
  if (e.kind = nkUn) and (e.a = '-') then
  begin
    if not FoldInt (e.kids[0], a) then Exit;
    if a = Low (Int64) then Exit;
    v := -a;
    Exit (True);
  end;
  if (e.kind = nkBin) and (Length (e.kids) = 2) then
  begin
    if not FoldInt (e.kids[0], a) then Exit;
    if not FoldInt (e.kids[1], b) then Exit;
    if e.a = '+' then
    begin
      if ((b > 0) and (a > High (Int64) - b)) or ((b < 0) and (a < Low (Int64) - b)) then Exit;
      v := a + b; Exit (True);
    end;
    if e.a = '-' then
    begin
      if ((b < 0) and (a > High (Int64) + b)) or ((b > 0) and (a < Low (Int64) + b)) then Exit;
      v := a - b; Exit (True);
    end;
    if e.a = '*' then
    begin
      if (a <> 0) and (b <> 0) then
      begin
        if (a = Low (Int64)) or (b = Low (Int64)) then
        begin
          if (a <> 1) and (b <> 1) then Exit;
        end
        else if (a <> -1) and (b <> -1) then
          if (Abs (a) > High (Int64) div Abs (b)) then Exit;
      end;
      v := a * b; Exit (True);
    end;
    if (e.a = 'DIV') or (e.a = 'MOD') then
    begin
      if b = 0 then Exit;
      if (b = -1) and (a = Low (Int64)) then Exit;
      if e.a = 'DIV' then v := a div b else v := a mod b;
      Exit (True);
    end;
  end;
end;

end.
