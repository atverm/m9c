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
    nkArgList
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

implementation

constructor TNode.Create (k: TNodeKind);
begin
  kind := k;
end;

procedure TNode.Add (n: TNode);
begin
  SetLength (kids, Length (kids) + 1);
  kids[High (kids)] := n;
end;

end.
