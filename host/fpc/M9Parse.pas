unit M9Parse;
{ Recursive descent over report par 10, one procedure per production
  where the production earns one.  Errors are values: every problem
  lands in Errors as 'line:col message', the parser resyncs on ';'
  and END and keeps going, and a tree always comes back.             }
{$mode objfpc}{$H+}
interface

uses SysUtils, Classes, M9Lex, M9AST;

type
  TTokSet = set of TTokKind;

  TParser = class
  private
    lx  : TLexer;
    cur : TToken;
    peeked   : Boolean;
    peekTok  : TToken;
    procedure Bump;
    function Nxt: TToken;
    procedure Err (const msg: string);
    procedure ErrAt (const msg: string; ln, cl: Integer);
    function Expect (k: TTokKind; const what: string): Boolean;
    function TakeIdent (const what: string): string;
    function NewNode (k: TNodeKind): TNode;
    { units and declarations }
    function PUnit: TNode;
    procedure PImports (parent: TNode);
    procedure PDecls (parent: TNode);
    function PDeclaration: TNode;
    function PProcDecl: TNode;
    function PParamList: TNode;
    function PAttribOpt: TNode;
    function PRaises: TNode;
    function PProcBody (const name: string): TNode;
    function PBlock: TNode;
    function PHandler: TNode;
    { types }
    function PType: TNode;
    function PFieldSeq (stops: TTokSet): TNode;
    function PVariant: TNode;
    { statements }
    function PStmtSeq (stops: TTokSet): TNode;
    function PStatement: TNode;
    function PCaseArm: TNode;
    function PCaseLabel: TNode;
    { expressions }
    function PExpr: TNode;
    function PDisj: TNode;
    function PConj: TNode;
    function PRel: TNode;
    function PSimple: TNode;
    function PTerm: TNode;
    function PFactor: TNode;
    function PNew: TNode;
    function PDesignator: TNode;
    function PQualident: TNode;
    function PIdentList: TNode;
    function PArgList: TNode;
    function DesigToQual (d: TNode): TNode;
  public
    Errors : TStringList;
    constructor Create (const src: string);
    destructor Destroy; override;
    function ParseFile: TNode;
  end;

implementation

const
  DeclStarts = [tkCONST, tkTYPE, tkVAR, tkEXCEPTION, tkPROCEDURE];
  RelOps     = [tkEq, tkNeq, tkLt, tkLe, tkGt, tkGe];
  AddOps     = [tkPlus, tkMinus, tkPlusWrap, tkMinusWrap];
  MulOps     = [tkStar, tkSlash, tkStarWrap, tkDIV, tkMOD];

function OpText (k: TTokKind): string;
begin
  case k of
    tkEq: Result := '=';   tkNeq: Result := '#';
    tkLt: Result := '<';   tkLe: Result := '<=';
    tkGt: Result := '>';   tkGe: Result := '>=';
    tkPlus: Result := '+'; tkMinus: Result := '-';
    tkPlusWrap: Result := '+%'; tkMinusWrap: Result := '-%';
    tkStar: Result := '*'; tkSlash: Result := '/';
    tkStarWrap: Result := '*%';
    tkDIV: Result := 'DIV'; tkMOD: Result := 'MOD';
    tkOR: Result := 'OR'; tkAND: Result := 'AND';
  else
    Result := '?';
  end;
end;

constructor TParser.Create (const src: string);
begin
  lx := TLexer.Create (src);
  Errors := TStringList.Create;
  peeked := False;
  Bump;
end;

destructor TParser.Destroy;
begin
  lx.Free;
  Errors.Free;
  inherited;
end;

procedure TParser.Bump;
begin
  repeat
    if peeked then
    begin
      cur := peekTok;
      peeked := False;
    end
    else
      cur := lx.Next;
    if cur.kind = tkError then
      ErrAt ('lex: ' + cur.text, cur.line, cur.col);
  until cur.kind <> tkError;
end;

function TParser.Nxt: TToken;
begin
  if not peeked then
  begin
    repeat
      peekTok := lx.Next;
      if peekTok.kind = tkError then
        ErrAt ('lex: ' + peekTok.text, peekTok.line, peekTok.col);
    until peekTok.kind <> tkError;
    peeked := True;
  end;
  Result := peekTok;
end;

procedure TParser.Err (const msg: string);
begin
  ErrAt (msg, cur.line, cur.col);
end;

procedure TParser.ErrAt (const msg: string; ln, cl: Integer);
begin
  Errors.Add (Format ('%d:%d %s', [ln, cl, msg]));
end;

function TParser.Expect (k: TTokKind; const what: string): Boolean;
begin
  Result := cur.kind = k;
  if Result then
    Bump
  else
    Err (what + ' expected, found ' + KindName (cur.kind) +
         ' ''' + cur.text + '''');
end;

function TParser.TakeIdent (const what: string): string;
begin
  if cur.kind = tkIdent then
  begin
    Result := cur.text;
    Bump;
  end
  else
  begin
    Result := '';
    Err (what + ' (identifier) expected, found ' + KindName (cur.kind));
  end;
end;

function TParser.NewNode (k: TNodeKind): TNode;
begin
  Result := TNode.Create (k);
  Result.line := cur.line;
  Result.col := cur.col;
end;

{ ---- file and units ---- }

function TParser.ParseFile: TNode;
var
  before : Integer;
begin
  Result := NewNode (nkFile);
  while cur.kind <> tkEOF do
  begin
    before := Errors.Count;
    Result.Add (PUnit);
    { guaranteed progress: PUnit always consumes or errs; if it
      neither consumed nor moved, drop one token }
    if (cur.kind <> tkEOF) and (Errors.Count > before + 50) then
      Break;                       { runaway guard }
  end;
end;

function TParser.PUnit: TNode;
var
  uns, stf : Boolean;
  body : TNode;
begin
  uns := False; stf := False;
  if cur.kind = tkUNSAFE then begin uns := True; Bump; end;
  if cur.kind = tkSTATEFUL then begin stf := True; Bump; end;

  if cur.kind = tkDEFINITION then
  begin
    Result := NewNode (nkDefinition);
    Result.f1 := uns; Result.f2 := stf;
    Bump;
    Expect (tkMODULE, 'MODULE');
    if cur.kind = tkFOR then
    begin
      Bump;
      if cur.kind = tkStrLit then begin Result.b := cur.text; Bump; end
      else Err ('foreign language string expected after FOR');
    end;
    Result.a := TakeIdent ('module name');
    Expect (tkSemi, ';');
    PImports (Result);
    PDecls (Result);
    Expect (tkEND, 'END');
    if TakeIdent ('module name after END') <> Result.a then
      Err ('END name does not match MODULE ' + Result.a);
    Expect (tkDot, '.');
    Exit;
  end;

  if cur.kind = tkIMPLEMENTATION then
  begin
    Result := NewNode (nkImplementation);
    Result.f1 := uns;
    if stf then Err ('STATEFUL belongs on the definition');
    Bump;
    Expect (tkMODULE, 'MODULE');
    Result.a := TakeIdent ('module name');
    Expect (tkSemi, ';');
    PImports (Result);
    PDecls (Result);
    if cur.kind = tkBEGIN then
    begin
      { a BLOCK, not a bare sequence: the module body is the root
        frame, the one with no caller to declare RAISES to, so it is
        exactly where a program must be able to SAY what it does
        about failure.  PBlock consumes BEGIN .. END. }
      body := NewNode (nkModBody);
      body.Add (PBlock);
      Result.Add (body);
    end
    else
      Expect (tkEND, 'END');
    if TakeIdent ('module name after END') <> Result.a then
      Err ('END name does not match MODULE ' + Result.a);
    Expect (tkDot, '.');
    Exit;
  end;

  if cur.kind = tkMODULE then
  begin
    Result := NewNode (nkProgram);
    if uns then Err ('UNSAFE program modules are not a thing');
    if stf then Err ('STATEFUL belongs on definitions');
    Bump;
    Result.a := TakeIdent ('module name');
    Expect (tkSemi, ';');
    PImports (Result);
    PDecls (Result);
    if cur.kind = tkBEGIN then
    begin
      { a BLOCK, not a bare sequence: the module body is the root
        frame, the one with no caller to declare RAISES to, so it is
        exactly where a program must be able to SAY what it does
        about failure.  PBlock consumes BEGIN .. END. }
      body := NewNode (nkModBody);
      body.Add (PBlock);
      Result.Add (body);
    end
    else
      Expect (tkEND, 'END');
    if TakeIdent ('module name after END') <> Result.a then
      Err ('END name does not match MODULE ' + Result.a);
    Expect (tkDot, '.');
    Exit;
  end;

  Err ('DEFINITION, IMPLEMENTATION, or MODULE expected, found ' +
       KindName (cur.kind));
  Result := NewNode (nkProgram);
  Result.a := '?';
  Bump;
end;

procedure TParser.PImports (parent: TNode);
var
  n : TNode;
begin
  while cur.kind in [tkFROM, tkIMPORT] do
  begin
    if cur.kind = tkFROM then
    begin
      n := NewNode (nkFromImport);
      Bump;
      n.a := TakeIdent ('module name');
      Expect (tkIMPORT, 'IMPORT');
    end
    else
    begin
      n := NewNode (nkImportList);
      Bump;
    end;
    n.Add (PIdentList);
    Expect (tkSemi, ';');
    parent.Add (n);
  end;
end;

procedure TParser.PDecls (parent: TNode);
begin
  while cur.kind in DeclStarts do
    parent.Add (PDeclaration);
end;

function TParser.PDeclaration: TNode;
var
  d : TNode;
begin
  case cur.kind of
    tkCONST :
      begin
        Result := NewNode (nkConstSection);
        Bump;
        while cur.kind = tkIdent do
        begin
          d := NewNode (nkConstDecl);
          d.a := TakeIdent ('constant name');
          Expect (tkEq, '=');
          d.Add (PExpr);
          Expect (tkSemi, ';');
          Result.Add (d);
        end;
      end;
    tkTYPE :
      begin
        Result := NewNode (nkTypeSection);
        Bump;
        while cur.kind = tkIdent do
        begin
          d := NewNode (nkTypeDecl);
          d.a := TakeIdent ('type name');
          if cur.kind = tkEq then
          begin
            Bump;
            d.Add (PType ());
          end
          else
            d.Add (nil);                 { opaque }
          Expect (tkSemi, ';');
          Result.Add (d);
        end;
      end;
    tkVAR :
      begin
        Result := NewNode (nkVarSection);
        Bump;
        while cur.kind in [tkIdent, tkRO] do
        begin
          d := NewNode (nkVarDecl);
          if cur.kind = tkRO then begin d.f3 := True; Bump; end;
          d.Add (PIdentList);
          Expect (tkColon, ':');
          d.Add (PType ());
          Expect (tkSemi, ';');
          Result.Add (d);
        end;
      end;
    tkEXCEPTION :
      begin
        Result := NewNode (nkExcSection);
        Bump;
        while cur.kind = tkIdent do
        begin
          d := NewNode (nkExcDecl);
          d.a := TakeIdent ('exception name');
          if cur.kind = tkLParen then
          begin
            Bump;
            d.Add (PFieldSeq ([tkRParen]));
            Expect (tkRParen, ')');
          end
          else
            d.Add (nil);
          Expect (tkSemi, ';');
          Result.Add (d);
        end;
      end;
    tkPROCEDURE :
      Result := PProcDecl;
  else
    begin
      Err ('declaration expected');
      Result := NewNode (nkConstSection);
      Bump;
    end;
  end;
end;

function TParser.PProcDecl: TNode;
begin
  Result := NewNode (nkProcDecl);
  Expect (tkPROCEDURE, 'PROCEDURE');
  Result.a := TakeIdent ('procedure name');
  if cur.kind = tkEq then                       { foreign binding }
  begin
    Bump;
    if cur.kind = tkStrLit then begin Result.b := cur.text; Bump; end
    else Err ('foreign name string expected after =');
  end;
  Expect (tkLParen, '(');
  Result.Add (PParamList);                      { kid 0 }
  Expect (tkRParen, ')');
  if cur.kind = tkColon then                    { kid 1: return type }
  begin
    Bump;
    { RO precedes what it qualifies, here as everywhere }
    if cur.kind = tkRO then begin Result.f3 := True; Bump; end;
    Result.Add (PType ());
  end
  else
    Result.Add (nil);
  if cur.kind = tkRAISES then Result.Add (PRaises)   { kid 2 }
  else Result.Add (nil);
  Result.Add (PAttribOpt);                      { kid 3 }
  if cur.kind = tkEq then                       { kid 4: body }
  begin
    Bump;
    Result.Add (PProcBody (Result.a));
  end
  else
    Result.Add (nil);
  Expect (tkSemi, ';');
end;

function TParser.PParamList: TNode;
var
  p : TNode;
begin
  Result := NewNode (nkParamList);
  if cur.kind = tkRParen then Exit;
  repeat
    p := NewNode (nkParam);
    if cur.kind = tkVAR then begin p.f1 := True; Bump; end
    else if cur.kind = tkOWN then begin p.f2 := True; Bump; end
    else if cur.kind = tkRO then begin p.f3 := True; Bump; end;
    p.Add (PIdentList);
    Expect (tkColon, ':');
    p.Add (PType ());
    Result.Add (p);
    if cur.kind = tkSemi then Bump else Break;
  until cur.kind in [tkRParen, tkEOF];
end;

function TParser.PAttribOpt: TNode;
begin
  Result := nil;
  if cur.kind = tkLBrack then
  begin
    Result := NewNode (nkAttrib);
    Bump;
    Result.a := TakeIdent ('attribute name');
    Expect (tkRBrack, ']');
  end;
end;

function TParser.PRaises: TNode;
begin
  Result := NewNode (nkRaises);
  Expect (tkRAISES, 'RAISES');
  Result.Add (PQualident);
  while cur.kind = tkComma do
  begin
    Bump;
    Result.Add (PQualident);
  end;
end;

function TParser.PProcBody (const name: string): TNode;
begin
  Result := NewNode (nkProcBody);
  while cur.kind in DeclStarts do
    Result.Add (PDeclaration);
  Result.Add (PBlock);
  if cur.kind = tkIdent then
  begin
    if cur.text <> name then
      Err ('END ' + cur.text + ' does not match PROCEDURE ' + name);
    Bump;
  end
  else
    Err ('procedure name expected after END');
end;

function TParser.PBlock: TNode;
var
  fin : TNode;
begin
  Result := NewNode (nkBlock);
  Expect (tkBEGIN, 'BEGIN');
  Result.Add (PStmtSeq ([tkEXCEPT, tkFINALLY, tkEND]));
  if cur.kind = tkEXCEPT then
  begin
    Bump;
    if cur.kind <> tkBar then Err ('handler | expected after EXCEPT');
    while cur.kind = tkBar do
      Result.Add (PHandler);
  end;
  if cur.kind = tkFINALLY then
  begin
    Bump;
    fin := NewNode (nkFinally);
    fin.Add (PStmtSeq ([tkEND]));
    Result.Add (fin);
  end;
  Expect (tkEND, 'END');
end;

function TParser.PHandler: TNode;
var
  args, h : TNode;
begin
  Result := NewNode (nkHandler);
  Expect (tkBar, '|');
  Result.Add (PQualident);
  args := nil;
  if cur.kind = tkLParen then
  begin
    Bump;
    args := NewNode (nkArgList);
    repeat
      case cur.kind of
        tkIdent   : begin h := NewNode (nkIdent);   h.a := cur.text; Bump; end;
        tkIntLit  : begin h := NewNode (nkInt);     h.a := cur.text; Bump; end;
        tkRealLit : begin h := NewNode (nkReal);    h.a := cur.text; Bump; end;
        tkCharLit : begin h := NewNode (nkChar);    h.a := cur.text; Bump; end;
        tkStrLit  : begin h := NewNode (nkString);  h.a := cur.text; Bump; end;
      else
        begin
          Err ('handler argument expected');
          h := NewNode (nkIdent);
          h.a := '?';
          Bump;
        end;
      end;
      args.Add (h);
      if cur.kind = tkComma then Bump else Break;
    until False;
    Expect (tkRParen, ')');
  end;
  Result.Add (args);
  Expect (tkColon, ':');
  Result.Add (PStmtSeq ([tkBar, tkFINALLY, tkEND]));
end;

{ ---- types ---- }

function TParser.PType: TNode;
var
  n : TNode;
begin
  case cur.kind of
    tkIdent :
      Result := PQualident;
    tkPOOL :
      begin
        Result := NewNode (nkQualident);
        Result.a := 'POOL';
        Bump;
      end;
    tkARRAY :
      begin
        Result := NewNode (nkArrayType);
        Bump;
        Result.Add (PExpr);
        Expect (tkOF, 'OF');
        Result.Add (PType ());
      end;
    tkGRID :
      begin
        { GRID r OF T -- the rank is in the type, the extents are in
          the value.  The rank is a constant because the checker
          checks subscript arity against it, which is the whole
          reason the type carries one: Mat.Get (m, 0, 3) on a
          three-column matrix answered element (1,0) and raised
          nothing (docs/nd-arrays.md). }
        Result := NewNode (nkGridType);
        Bump;
        Result.Add (PExpr);
        Expect (tkOF, 'OF');
        Result.Add (PType ());
      end;
    tkSLICE :
      begin
        Result := NewNode (nkSliceType);
        Bump;
        Expect (tkOF, 'OF');
        Result.Add (PType ());
        { the attribute form is gone: RO is a mode now, and one
          canonical spelling is what makes the printer's fixpoint
          mean anything.  The kid stays for AST shape. }
        Result.Add (nil);
      end;
    tkRECORD :
      begin
        Result := NewNode (nkRecordType);
        Bump;
        if cur.kind = tkLParen then
        begin
          Bump;
          Result.Add (PQualident);
          Expect (tkRParen, ')');
        end
        else
          Result.Add (nil);
        Result.Add (PFieldSeq ([tkEND]));
        Expect (tkEND, 'END');
      end;
    tkCASE :
      begin
        Result := NewNode (nkCaseRecordType);
        Bump;
        Expect (tkRECORD, 'RECORD');
        if cur.kind <> tkBar then Err ('variant | expected');
        while cur.kind = tkBar do
          Result.Add (PVariant);
        Expect (tkEND, 'END');
      end;
    tkMONITOR :
      begin
        Result := NewNode (nkMonitorType);
        Bump;
        Expect (tkRECORD, 'RECORD');
        Result.Add (PFieldSeq ([tkEND]));
        Expect (tkEND, 'END');
      end;
    tkPTR :
      begin
        Result := NewNode (nkPtrType);
        Bump;
        Result.Add (PType ());
        if cur.kind = tkIN then
        begin
          Bump;
          Result.Add (PDesignator);
        end
        else
          Result.Add (nil);
      end;
    tkOPT :
      begin
        Result := NewNode (nkOptType);
        Bump;
        Result.Add (PType ());
      end;
    tkSHARED :
      begin
        Result := NewNode (nkSharedType);
        Bump;
        Expect (tkPTR, 'PTR');
        Result.Add (PType ());
      end;
  else
    begin
      Err ('type expected, found ' + KindName (cur.kind));
      n := NewNode (nkQualident);
      n.a := '?';
      Result := n;
      Bump;
    end;
  end;
end;

function TParser.PFieldSeq (stops: TTokSet): TNode;
var
  g : TNode;
begin
  Result := NewNode (nkFieldSeq);
  if (cur.kind in stops) or (cur.kind = tkEOF) then Exit;
  repeat
    g := NewNode (nkFieldGroup);
    if cur.kind = tkRO then begin g.f3 := True; Bump; end;
    g.Add (PIdentList);
    Expect (tkColon, ':');
    g.Add (PType ());
    Result.Add (g);
    if cur.kind = tkSemi then
    begin
      Bump;
      if (cur.kind in stops) or (cur.kind = tkEOF) then
      begin
        Result.f1 := True;
        Break;
      end;
    end
    else
      Break;
  until False;
  if not ((cur.kind in stops) or (cur.kind = tkEOF)) then
    Err ('field list does not end where it should');
end;

function TParser.PVariant: TNode;
begin
  Result := NewNode (nkVariant);
  Expect (tkBar, '|');
  Result.a := TakeIdent ('variant name');
  if cur.kind = tkColon then
  begin
    Bump;
    Result.Add (PFieldSeq ([tkBar, tkEND]));
  end
  else
    Result.Add (nil);
end;

{ ---- statements ---- }

function TParser.PStmtSeq (stops: TTokSet): TNode;
begin
  Result := NewNode (nkStmtSeq);
  while not ((cur.kind in stops) or (cur.kind = tkEOF)) do
  begin
    Result.Add (PStatement);
    if cur.kind = tkSemi then
    begin
      Bump;
      if (cur.kind in stops) or (cur.kind = tkEOF) then
      begin
        Result.f1 := True;
        Break;
      end;
    end
    else
    begin
      if not ((cur.kind in stops) or (cur.kind = tkEOF)) then
      begin
        Err ('; or end of statement list expected, found ' +
             KindName (cur.kind));
        { resync: eat until something that can restart or close }
        while not ((cur.kind in stops) or (cur.kind = tkSemi) or
                   (cur.kind = tkEOF)) do
          Bump;
        if cur.kind = tkSemi then Bump else Break;
      end
      else
        Break;
    end;
  end;
end;

function TParser.PStatement: TNode;
var
  des, n : TNode;
begin
  case cur.kind of
    tkIdent :
      begin
        des := PDesignator;
        if cur.kind = tkAssign then
        begin
          Result := NewNode (nkAssign);
          Bump;
          Result.Add (des);
          Result.Add (PExpr);
        end
        else
        begin
          Result := NewNode (nkCallStmt);
          Result.Add (des);
          if cur.kind = tkLParen then
          begin
            Result.f1 := True;
            Bump;
            if cur.kind = tkRParen then Result.Add (NewNode (nkArgList))
            else Result.Add (PArgList);
            Expect (tkRParen, ')');
          end
          else
            Result.Add (nil);
        end;
      end;
    tkIF :
      begin
        Result := NewNode (nkIf);
        Bump;
        Result.Add (PExpr);
        Expect (tkTHEN, 'THEN');
        Result.Add (PStmtSeq ([tkELSIF, tkELSE, tkEND]));
        while cur.kind = tkELSIF do
        begin
          n := NewNode (nkElsif);
          Bump;
          n.Add (PExpr);
          Expect (tkTHEN, 'THEN');
          n.Add (PStmtSeq ([tkELSIF, tkELSE, tkEND]));
          Result.Add (n);
        end;
        if cur.kind = tkELSE then
        begin
          n := NewNode (nkElse);
          Bump;
          n.Add (PStmtSeq ([tkEND]));
          Result.Add (n);
        end;
        Expect (tkEND, 'END');
      end;
    tkWHILE :
      begin
        Result := NewNode (nkWhile);
        Bump;
        Result.Add (PExpr);
        Expect (tkDO, 'DO');
        Result.Add (PStmtSeq ([tkEND]));
        Expect (tkEND, 'END');
      end;
    tkFOR :
      begin
        Result := NewNode (nkFor);
        Bump;
        Result.a := TakeIdent ('loop variable');
        Expect (tkAssign, ':=');
        Result.Add (PExpr);
        Expect (tkTO, 'TO');
        Result.Add (PExpr);
        if cur.kind = tkBY then
        begin
          Bump;
          Result.Add (PExpr);
        end
        else
          Result.Add (nil);
        Expect (tkDO, 'DO');
        Result.Add (PStmtSeq ([tkEND]));
        Expect (tkEND, 'END');
      end;
    tkLOOP :
      begin
        Result := NewNode (nkLoop);
        Bump;
        Result.Add (PStmtSeq ([tkEND]));
        Expect (tkEND, 'END');
      end;
    tkEXIT :
      begin
        Result := NewNode (nkExit);
        Bump;
      end;
    tkCASE :
      begin
        Result := NewNode (nkCase);
        Bump;
        Result.Add (PExpr);
        Expect (tkOF, 'OF');
        if cur.kind <> tkBar then Err ('case arm | expected');
        while cur.kind = tkBar do
          Result.Add (PCaseArm);
        if cur.kind = tkELSE then
        begin
          n := NewNode (nkElse);
          Bump;
          n.Add (PStmtSeq ([tkEND]));
          Result.Add (n);
        end;
        Expect (tkEND, 'END');
      end;
    tkRETURN :
      begin
        Result := NewNode (nkReturn);
        Bump;
        if cur.kind in [tkSemi, tkEND, tkELSE, tkELSIF, tkEXCEPT,
                        tkFINALLY, tkBar, tkEOF] then
          Result.Add (nil)
        else
          Result.Add (PExpr);
      end;
    tkRAISE :
      begin
        Result := NewNode (nkRaiseStmt);
        Bump;
        Result.Add (PQualident);
        if cur.kind = tkLParen then
        begin
          Bump;
          Result.Add (PArgList);
          Expect (tkRParen, ')');
        end
        else
          Result.Add (nil);
      end;
    tkDISPOSE :
      begin
        Result := NewNode (nkDispose);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PDesignator);
        Expect (tkRParen, ')');
      end;
    tkBEGIN :
      Result := PBlock;
    tkTHREAD, tkTRANSFER :
      begin
        if cur.kind = tkTHREAD then Result := NewNode (nkThread)
        else Result := NewNode (nkTransfer);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PExpr);
        Expect (tkComma, ',');
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
    tkWAIT, tkSIGNAL :
      begin
        if cur.kind = tkWAIT then Result := NewNode (nkWait)
        else Result := NewNode (nkSignal);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
  else
    begin
      Err ('statement expected, found ' + KindName (cur.kind));
      Result := NewNode (nkStmtSeq);      { empty placeholder }
      Bump;
    end;
  end;
end;

function TParser.PCaseArm: TNode;
var
  labels : TNode;
begin
  Result := NewNode (nkCaseArm);
  Expect (tkBar, '|');
  labels := NewNode (nkLabelList);
  labels.Add (PCaseLabel);
  while cur.kind = tkComma do
  begin
    Bump;
    labels.Add (PCaseLabel);
  end;
  Result.Add (labels);
  Expect (tkColon, ':');
  Result.Add (PStmtSeq ([tkBar, tkELSE, tkEND]));
end;

function TParser.PCaseLabel: TNode;
begin
  if (cur.kind = tkIdent) and (Nxt.kind = tkLParen) then
  begin
    Result := NewNode (nkLabelPattern);
    Result.a := TakeIdent ('variant name');
    Expect (tkLParen, '(');
    Result.Add (PIdentList);
    Expect (tkRParen, ')');
  end
  else
  begin
    Result := NewNode (nkLabelRange);
    Result.Add (PExpr);
    if cur.kind = tkDotDot then
    begin
      Bump;
      Result.Add (PExpr);
    end
    else
      Result.Add (nil);
  end;
end;

{ ---- expressions ---- }

function TParser.PExpr: TNode;
var
  e, t : TNode;
begin
  e := PDisj;
  if cur.kind = tkIS then
  begin
    Result := NewNode (nkIs);
    Bump;
    Result.Add (e);
    if cur.kind = tkSOME then
    begin
      t := NewNode (nkIsSome);
      Bump;
      t.a := TakeIdent ('binding name');
      Result.Add (t);
    end
    else
      Result.Add (PQualident);
  end
  else
    Result := e;
end;

function TParser.PDisj: TNode;
var
  n : TNode;
begin
  Result := PConj;
  while cur.kind = tkOR do
  begin
    n := NewNode (nkBin);
    n.a := 'OR';
    Bump;
    n.Add (Result);
    n.Add (PConj);
    Result := n;
  end;
end;

function TParser.PConj: TNode;
var
  n : TNode;
begin
  Result := PRel;
  while cur.kind = tkAND do
  begin
    n := NewNode (nkBin);
    n.a := 'AND';
    Bump;
    n.Add (Result);
    n.Add (PRel);
    Result := n;
  end;
end;

function TParser.PRel: TNode;
var
  n : TNode;
begin
  Result := PSimple;
  if cur.kind in RelOps then
  begin
    n := NewNode (nkBin);
    n.a := OpText (cur.kind);
    Bump;
    n.Add (Result);
    n.Add (PSimple);
    Result := n;
  end;
end;

function TParser.PSimple: TNode;
var
  n : TNode;
  signed : TNode;
begin
  signed := nil;
  if cur.kind in [tkPlus, tkMinus] then
  begin
    signed := NewNode (nkUn);
    signed.a := OpText (cur.kind);
    Bump;
  end;
  Result := PTerm;
  if signed <> nil then
  begin
    signed.Add (Result);
    Result := signed;
  end;
  while cur.kind in AddOps do
  begin
    n := NewNode (nkBin);
    n.a := OpText (cur.kind);
    Bump;
    n.Add (Result);
    n.Add (PTerm);
    Result := n;
  end;
end;

function TParser.PTerm: TNode;
var
  n : TNode;
begin
  Result := PFactor;
  while cur.kind in MulOps do
  begin
    n := NewNode (nkBin);
    n.a := OpText (cur.kind);
    Bump;
    n.Add (Result);
    n.Add (PFactor);
    Result := n;
  end;
end;

function TParser.PFactor: TNode;
var
  des : TNode;
begin
  case cur.kind of
    tkIntLit :
      begin Result := NewNode (nkInt); Result.a := cur.text; Bump; end;
    tkRealLit :
      begin Result := NewNode (nkReal); Result.a := cur.text; Bump; end;
    tkCharLit :
      begin Result := NewNode (nkChar); Result.a := cur.text; Bump; end;
    tkStrLit :
      begin Result := NewNode (nkString); Result.a := cur.text; Bump; end;
    tkTRUE :
      begin Result := NewNode (nkTrue); Bump; end;
    tkFALSE :
      begin Result := NewNode (nkFalse); Bump; end;
    tkNONE :
      begin Result := NewNode (nkNoneLit); Bump; end;
    tkSOME :
      begin
        Result := NewNode (nkSomeExpr);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
    tkSHARED :
      begin
        Result := NewNode (nkSharedExpr);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
    tkNEW :
      Result := PNew;
    tkSLICE :
      begin
        Result := NewNode (nkSliceOf3);
        Bump;
        Expect (tkLParen, '(');
        Result.Add (PExpr);
        Expect (tkComma, ',');
        Result.Add (PExpr);
        Expect (tkComma, ',');
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
    tkNOT :
      begin
        Result := NewNode (nkUn);
        Result.a := 'NOT';
        Bump;
        Result.Add (PFactor ());
      end;
    tkLParen :
      begin
        Result := NewNode (nkParen);
        Bump;
        Result.Add (PExpr);
        Expect (tkRParen, ')');
      end;
    tkIdent :
      begin
        des := PDesignator;
        if cur.kind = tkLParen then
        begin
          Result := NewNode (nkCallExpr);
          Result.Add (des);
          Bump;
          if cur.kind = tkRParen then Result.Add (NewNode (nkArgList))
          else Result.Add (PArgList);
          Expect (tkRParen, ')');
        end
        else
          Result := des;
      end;
  else
    begin
      Err ('expression expected, found ' + KindName (cur.kind));
      Result := NewNode (nkInt);
      Result.a := '0';
      Bump;
    end;
  end;
end;

function TParser.PNew: TNode;
var
  d1, d2 : TNode;
begin
  Result := NewNode (nkNewExpr);
  Expect (tkNEW, 'NEW');
  Expect (tkLParen, '(');
  d1 := PDesignator;
  if cur.kind = tkComma then
  begin
    Bump;
    d2 := PDesignator;
    Result.Add (d1);                       { pool }
    Result.Add (DesigToQual (d2));         { type }
    if cur.kind = tkComma then
    begin
      Bump;
      Result.Add (PExpr);                  { count, or the first extent }
      { further extents make it a GRID: NEW (p, F64, nx, ny, nz).  The
        arity states the rank, so the rank cannot disagree with the
        number of extents the caller gave. }
      while cur.kind = tkComma do
      begin
        Bump;
        Result.Add (PExpr);
      end;
    end
    else
      Result.Add (nil);
  end
  else
  begin
    Result.Add (nil);
    Result.Add (DesigToQual (d1));
    Result.Add (nil);
  end;
  Expect (tkRParen, ')');
end;

function TParser.DesigToQual (d: TNode): TNode;
begin
  Result := NewNode (nkQualident);
  Result.a := d.a;
  if Length (d.kids) = 0 then Exit;
  if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
    Result.b := d.kids[0].a
  else
    ErrAt ('type name expected in NEW', cur.line, cur.col);
end;

function TParser.PDesignator: TNode;
var
  sel : TNode;
begin
  Result := NewNode (nkDesignator);
  Result.a := TakeIdent ('name');
  while cur.kind in [tkDot, tkLBrack] do
  begin
    if cur.kind = tkDot then
    begin
      Bump;
      sel := NewNode (nkSelField);
      sel.a := TakeIdent ('field name');
      Result.Add (sel);
    end
    else
    begin
      { one subscript per axis: a[i] on a slice or array, a[i,j,k] on
        a GRID.  The arity is checked against the rank, so a missing
        subscript is a compile error and not an index into the next
        row. }
      Bump;
      sel := NewNode (nkSelIndex);
      sel.Add (PExpr);
      while cur.kind = tkComma do
      begin
        Bump;
        sel.Add (PExpr);
      end;
      Expect (tkRBrack, ']');
      Result.Add (sel);
    end;
  end;
end;

function TParser.PQualident: TNode;
begin
  Result := NewNode (nkQualident);
  Result.a := TakeIdent ('name');
  if cur.kind = tkDot then
  begin
    Bump;
    Result.b := TakeIdent ('name after .');
  end;
end;

function TParser.PIdentList: TNode;
var
  n : TNode;
begin
  Result := NewNode (nkIdentList);
  n := NewNode (nkIdent);
  n.a := TakeIdent ('name');
  Result.Add (n);
  while cur.kind = tkComma do
  begin
    Bump;
    n := NewNode (nkIdent);
    n.a := TakeIdent ('name');
    Result.Add (n);
  end;
end;

function TParser.PArgList: TNode;
begin
  Result := NewNode (nkArgList);
  Result.Add (PExpr);
  while cur.kind = tkComma do
  begin
    Bump;
    Result.Add (PExpr);
  end;
end;

end.
