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
    nkLinkList                    { LINK "w1", "w2" on a FOR "C" unit:
                                    the Definition's LAST kid; kids are
                                    nkString, a the word.
                                    Ast.NLinkList, 2026-10-09 }
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
    constructor Create (k: TNodeKind);
    procedure Add (n: TNode);          { nil is a legal child }
  end;

function Utf8Next (const s: string; var i: Integer): Cardinal;
function Utf8Len (const s: string): Integer;
function Utf8Enc (c: Cardinal): string;
function LabelName (lv: TNode): string;

implementation

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

end.
