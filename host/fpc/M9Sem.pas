unit M9Sem;
{ P2 semantic core, pass 3.
  Pass-1/2 checks kept: foreign signatures C.*-only with mandatory
  [SERIAL]/[REENTRANT]; def/impl signature conformance and
  completeness; STATEFUL required for module vars; CASE totality
  over CASE RECORD; RAISES accounting with full call resolution;
  OPT and CASE RECORD selector misuse; ADR only in UNSAFE units;
  THREAD roots may not reach a [SERIAL] foreign proc.
  Pass-3 additions -- expression/assignment typing over canonical
  type strings ('I64', 'PTR Json.Node', 'SLICE OF CHAR', ...):
    - records/monitors/opaque types are NOMINAL (Mod.Name); aliases
      chase to structure; IN-pool and [RO] are not part of the
      type identity (they are P3 ownership facts);
    - literals are adaptive: <int> fits any integer or BYTE, <real>
      fits F32/F64, a 1-char string fits CHAR or SLICE OF CHAR,
      NONE fits any OPT -- everything else converts explicitly,
      including widths (the LONGREAL lesson, par 2.1);
    - assignment, RETURN, and argument compatibility; call arity;
      VAR/OWN arguments must be designators; a discarded function
      result is an error (errors are values, so are results);
    - conditions are BOOL; BYTE has no arithmetic; '/' is float
      division, DIV/MOD and +% -% *% are integer; CASE labels must
      match the selector; ARRAY N OF T is accepted where SLICE OF T
      is expected; SHARED PTR T lends where PTR T is borrowed.
  Diagnostics: 'line:col ctx: message'.  Errors are values; checking
  continues.  Unknown types ('') never diagnose: softness is the
  contract.  Remaining softness (pass 4): C.* conversions treated as
  raise-free, F32(F64) narrowing unchecked, handler matching by
  name not payload, MONITOR outside-access, flow-sensitive OPT.     }
{$mode objfpc}{$H+}
interface

uses SysUtils, Classes, M9AST, M9Print;

type
  TNodeArr = array of TNode;

  TProcInfo = record
    name, foreign, attrib : string;
    modName : string;
    raises : array of string;
    sig    : string;
    node   : TNode;
    body   : TNode;                 { the implementation's node, when
                                      one was loaded (AnswersFrame) }
    fromDef, hasBody : Boolean;
  end;

  TVariantInfo = record
    typeName : string;
    variants : array of string;
    fields   : array of TNode;         { fieldseq per variant, or nil }
  end;

  TModuleInfo = class
  public
    name : string;
    foreignLang : string;
    stateful, hasDef, hasImpl : Boolean;
    procs : array of TProcInfo;
    { set for the duration of one PURE procedure's body (par 3.2) }
    vts : array of TVariantInfo;
    tdNames : array of string;         { type decls with bodies }
    tdNodes : array of TNode;
    opaque : array of string;          { opaque decls in the def }
    cnNames : array of string;         { exported CONSTs ... }
    cnTypes : array of string;         { ... and their LitType }
    exNames : array of string;         { EXCEPTION declarations }
    exDecls : array of TNode;          { ... and their nodes, for a handler's binder types }
    vrNames : array of string;         { the definition's VARs (decision 28) ... }
    vrTypes : array of TNode;          { ... their types, QualifiedIn this module ... }
    vrRo : array of Boolean;           { ... and VAR RO }
    function HasExc (const n: string): Boolean;
    function FindProc (const n: string): Integer;
    procedure AddProc (const p: TProcInfo);
    function FindType (const n: string): TNode;
  end;

  TSem = class
  private
    mods : array of TModuleInfo;
    curMod : string;
    curUnsafe : Boolean;
    curPure : Boolean;                 { inside a [PURE] body (par 3.2) }
    curInBody : Boolean;               { the module init body, whose
                                         frame and module vars co-live,
                                         so a concat stored in a module
                                         var there does not outlive it }
    boundMon : string;                 { the bound monitor parameter,
                                         '' if this procedure is not
                                         bound to one (par 6) }
    fromMap : TStringList;
    varParams, varWritten : TStringList;   { RO measurement }
    keptParams : TStringList;    { params declared KEPT (par 4.1),
                                    as name=line:col of the declaring
                                    identifier }
    keptUsed : TStringList;      { KEPT params the analysis saw
                                    retained -- the complement is the
                                    overstatement ledger class }
    localConsts : TStringList;             { a procedure's own CONSTs }
    canonCtx : string;                 { module whose bare type names
                                         are being canonicalized;
                                         '' = the current module }
    constMap : TStringList;            { module-level CONST name=type }
    roScope : TStringList;             { scope indices of `VAR RO' variables }
    roFrom : TStringList;              { scope index=what|line: read-only storage a name was given }
    roFresh : TStringList;             { RoFreshWalk: `name.field' paths of a marked copy given fresh storage }
    resolvedIn : string;               { the module ResolveType's last lookup ended in, '' when none }
    ixD : TNode;                       { EXCEPTION IndexError (index, length : I64), built once }
    loopsOpen, finSinceLoop : Integer; { LOOPs around the walk; FINALLY blocks since the innermost }
    forNames : array of string;        { the FORs being walked, innermost last (issue 3) }
    forLines : array of Integer;
    mro : TStringList;                 { ModRoSeed: module variable=what|line, per unit }
    nAgg : Integer;                    { aggregate CONSTs in this unit:
                                         the walk that guards them is
                                         skipped at zero }
    tyI64 : TNode;                     { synthetic 'I64' for FOR vars }
    strNode : TNode;                   { the SLICE OF CHAR that STR names }
    tyCHAR : TNode;                    { its element }
    ansMemo : TStringList;             { AnswersFrame: Module.Proc=yes|no|busy }
    function FindMod (const n: string): TModuleInfo;
    function ProcNamed (const modn, callee: string; out pr: TProcInfo): Boolean;
    function NewIsFrameIn (e: TNode; const modn: string): Boolean;
    function AssignEvidence (k: TNode; const name, modn: string;
      isStr: Boolean; body: TNode; depth: Integer): Boolean;
    function ExprEvidence (k: TNode; const modn: string; isStr: Boolean;
      body: TNode; depth: Integer): Boolean;
    function FrameEvidence (k: TNode; const modn: string; isStr: Boolean;
      body: TNode; scratchCounts: Boolean): Boolean;
    function AnswersFrame (const qual: string; const pr: TProcInfo): Boolean;
    function CallAnswersFrame (dn: TNode): string;
    procedure ErrN (n: TNode; const ctx, msg: string);
    function SigOf (p: TNode): string;
    function RaisesOf (p: TNode): TStringArray;
    function ExcKnown (const qual, nm: string): Boolean;
    function ExcDeclOf (const qual, nm: string; out owner: string): TNode;
    function IxDecl: TNode;
    function ExcFieldType (decl: TNode; const owner: string; k: Integer): TNode;
    procedure CheckExcName (n: TNode; const ctx: string);
    function TypeKnown (const qual, nm: string): Boolean;
    procedure CheckTypeNode (t: TNode; const ctx: string);
    procedure CheckFieldTypes (fs: TNode; const ctx: string);
    procedure CheckVarTypes (holder: TNode; const ctx: string);
    procedure CheckDeclTypes (u: TNode);
    procedure CollectUnit (u: TNode);
    procedure CheckForeignDef (u: TNode);
    procedure CheckConformance (u: TNode);
    procedure CheckAggregate (cd: TNode; const ctx: string;
                              where: Integer);
    function RecordNamed (const name: string; out om, canon: string): TNode;
    function RecordConstType (e: TNode): string;
    function IsRecordCall (e: TNode): Boolean;
    function ConstFieldType (const rec, f: string): string;
    procedure CheckRecordConst (el: TNode; const ctx, what: string);
    procedure CheckBody (body: TNode; const ctx: string;
                         const declared: array of string;
                         scope: TStringList; const retTy: string);
    function LookupProcInfo (const callee: string;
                             out pr: TProcInfo): Boolean;
    function IsVariantCtor (const callee: string): Boolean;
    function VariantOfType (const canon: string;
                            out vi: TVariantInfo): Boolean;
    function VariantOwner (const vname: string;
                           out vi: TVariantInfo): Boolean;
    function FindVariant (const tn, vn: string; out ownerMod: string;
                          out fields: TNode): Boolean;
    function VariantIn (const mn, tn, vn: string; out ownerMod: string;
      out fields: TNode): Boolean;
    function ResolveType (t: TNode): TNode;
    function InMod (t: TNode; const m: string): TNode;
    procedure NoteMod (t: TNode; var m: string);
    function LookupTypeName (const modName, typeName: string): TNode;
    function CanonQual (const modName, typeName: string;
                        depth: Integer): string;
    function AllPayloadless (n: TNode): Boolean;
    function IsTagged (const canon: string): Boolean;
    function EnumConvType (const name: string): string;
    function CanonT (t: TNode; depth: Integer): string;
    function ProcSig (pl, rt: TNode; ro: Boolean; rs: TNode;
                      depth: Integer): string;
    function IsBareProc (t: TNode): Boolean;
    function OptOverValue (t: TNode): Boolean;
    function IsReadonlyT (declN, res: TNode): Boolean;
  public
    Errors : TStringList;
    RoCand : TStringList;              { VAR params never written }
    RoProcs : Integer;
    { P3 contortion ledger: places where corpus code retains a
      borrow.  Measured, not asserted -- the kill-gate reads this. }
    Ledger : TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure LoadFile (root: TNode);
    procedure CheckFile (root: TNode);
  end;

implementation

const
  Unchecked : array [0..2] of string = ('Overflow', 'IndexError',
    'OutOfMemory');
  { checked conversions: may raise ValueRange }
  ConvVR : array [0..9] of string = ('I8', 'I16', 'I32', 'I64',
    'U8', 'U16', 'U32', 'U64', 'BYTE', 'CHR');

const
  BuiltinTypes : array [0..12] of string = ('I8', 'I16', 'I32', 'I64',
    'U8', 'U16', 'U32', 'U64', 'F32', 'F64', 'BYTE', 'BOOL', 'CHAR');

function InList (const s: string; const a: array of string): Boolean;
var i : Integer;
begin
  for i := 0 to High (a) do
    if a[i] = s then Exit (True);
  Result := False;
end;

{ the dotted callee name of a call's designator -- the nested
  DesigName of CheckBody, for the helpers outside it (RoAnswerOf,
  MroAnswer); a leading index or deref stops it the same way }
function CallName (d: TNode): string;
var i : Integer;
begin
  Result := d.a;
  for i := 0 to High (d.kids) do
    if d.kids[i].kind = nkSelField then
      Result := Result + '.' + d.kids[i].a
    else
      Break;
end;

function StartsWithS (const s, p: string): Boolean;
begin
  Result := (Length (s) >= Length (p)) and (Copy (s, 1, Length (p)) = p);
end;

function IsIntStr (const s: string): Boolean;
begin
  Result := (s = 'I8') or (s = 'I16') or (s = 'I32') or (s = 'I64') or
            (s = 'U8') or (s = 'U16') or (s = 'U32') or (s = 'U64');
end;

function IsFloatStr (const s: string): Boolean;
begin
  Result := (s = 'F32') or (s = 'F64');
end;

function ElemOfArray (const s: string): string;
var p : Integer;
begin
  p := Pos (' OF ', s);
  if p > 0 then Result := Copy (s, p + 4, MaxInt) else Result := '';
end;

{ 'GRID 3 OF F64': the rank is part of the type so that subscript
  arity is a compile-time question.  0 means "not a grid". }
function GridRank (const s: string): Integer;
var p : Integer;
begin
  Result := 0;
  if Copy (s, 1, 5) <> 'GRID ' then Exit;
  p := Pos (' OF ', s);
  if p <= 5 then Exit;
  Result := StrToIntDef (Copy (s, 6, p - 6), 0);
end;

{ the type of a view that keeps k axes.  A rank-1 view is a GRID 1
  and NOT a slice: a slice is {pointer, length} with no stride, and
  the most useful rank-1 view there is -- the vertical column at
  (i,j) -- is strided.  Implementation corrected the design note
  here, which is the rule (docs/nd-arrays.md said SLICE). }
function GridOf (rank: Integer; const elem: string): string;
begin
  if elem = '' then Exit ('');
  Result := 'GRID ' + IntToStr (rank) + ' OF ' + elem;
end;

{ human name for a canonical type in diagnostics }
function TyName (const s: string): string;
begin
  if s = '<int>' then Exit ('an integer literal');
  if s = '<real>' then Exit ('a real literal');
  if s = '<str1>' then Exit ('a CHAR/string literal');
  if s = '<none>' then Exit ('NONE');
  if s = '<void>' then Exit ('no value');
  if s = '<all>' then Exit ('ALL');
  if s = '' then Exit ('an unknown type');
  Result := s;
end;

{ assignment compatibility: may a src value land where dst is
  expected?  '' (unknown) is compatible with everything: softness
  is the contract.  Literals adapt; nothing else converts.          }
{ the range of an integer width a literal is stored into; False for a
  type that is not a narrow integer -- I64 holds every literal the
  lexer accepts, and U64's upper half cannot be spelled as one }
function LitRange (const t: string; out lo, hi: Int64): Boolean;
begin
  lo := 0; hi := 0;
  Result := True;
  if t = 'I8' then begin lo := -128; hi := 127; Exit; end;
  if t = 'I16' then begin lo := -32768; hi := 32767; Exit; end;
  if t = 'I32' then begin lo := -2147483648; hi := 2147483647; Exit; end;
  if (t = 'U8') or (t = 'BYTE') then begin lo := 0; hi := 255; Exit; end;
  if t = 'U16' then begin lo := 0; hi := 65535; Exit; end;
  if t = 'U32' then begin lo := 0; hi := 4294967295; Exit; end;
  if t = 'U64' then begin lo := 0; hi := 9223372036854775807; Exit; end;
  Result := False;
end;

{ a decimal literal node's value, negated when asked; False for a hex
  literal (a bit pattern, left to the width it names) or one too long
  to hold }
function LitVal (lit: TNode; neg: Boolean; out v: Int64): Boolean;
var
  i : Integer;
begin
  v := 0;
  if lit.kind <> nkInt then Exit (False);
  if (Length (lit.a) = 0) or (Length (lit.a) > 18) then Exit (False);
  for i := 1 to Length (lit.a) do
    if (lit.a[i] < '0') or (lit.a[i] > '9') then Exit (False);
  v := StrToInt64 (lit.a);
  if neg then v := -v;
  Result := True;
end;

{ an integer literal stored where a narrow width is expected must fit
  it.  `s := 40000` for an I16 passed this checker and the C
  conversion stored -25536 until 2026-09-27 -- the same silence as
  the narrow arithmetic fixed the same day
  (docs/agent-review-2026-09-27.md F1).  Mirrors Sem.LitOut. }
function LitOut (n: TNode; const t: string; out v: Int64): Boolean;
var
  lo, hi : Int64;
begin
  v := 0;
  if not LitRange (t, lo, hi) then Exit (False);
  if (n.kind = nkUn) and (n.a = '-') then
  begin
    if (Length (n.kids) > 0) and (n.kids[0] <> nil) then
    begin
      if not LitVal (n.kids[0], True, v) then Exit (False);
      Exit ((v < lo) or (v > hi));
    end;
    Exit (False);
  end;
  if not LitVal (n, False, v) then Exit (False);
  Result := (v < lo) or (v > hi);
end;

{ par 3 rule 4: a function answers on every path.  Can control pass
  this statement?  Structural and conservative -- a WHILE or FOR can
  be passed, a LOOP only by an EXIT of its own, an IF when a branch
  can be or there is no ELSE, a CASE when an arm can be, a block when
  its statements or a handler can be, and a call is never an ending.
  Mirrors Sem.EndsStmt / EndsSeq / HasExit, where the rule and its
  measurement are written down. }
function EndsSeq (k: TNode): Boolean; forward;

function HasExit (k: TNode): Boolean;
var i : Integer;
begin
  if k = nil then Exit (False);
  if k.kind = nkExit then Exit (True);
  if k.kind in [nkLoop, nkWhile, nkFor] then Exit (False);   { the innermost loop owns an EXIT (mirrors Sem) }
  for i := 0 to High (k.kids) do
    if HasExit (k.kids[i]) then Exit (True);
  Result := False;
end;

function EndsStmt (n: TNode): Boolean;
var
  i : Integer;
  e : TNode;
  hasElse : Boolean;
begin
  case n.kind of
    nkReturn, nkRaiseStmt :
      Exit (True);
    nkIf :
      begin
        if not EndsSeq (n.kids[1]) then Exit (False);
        hasElse := False;
        for i := 2 to High (n.kids) do
        begin
          e := n.kids[i];
          if e = nil then Continue;
          if e.kind = nkElsif then
          begin
            if not EndsSeq (e.kids[1]) then Exit (False);
          end
          else if e.kind = nkElse then
          begin
            hasElse := True;
            if not EndsSeq (e.kids[0]) then Exit (False);
          end;
        end;
        Exit (hasElse);
      end;
    nkCase :
      begin
        for i := 1 to High (n.kids) do
        begin
          e := n.kids[i];
          if e = nil then Continue;
          if e.kind = nkCaseArm then
          begin
            if not EndsSeq (e.kids[1]) then Exit (False);
          end
          else if e.kind = nkElse then
          begin
            if not EndsSeq (e.kids[0]) then Exit (False);
          end;
        end;
        Exit (Length (n.kids) > 1);
      end;
    nkLoop :
      Exit (not HasExit (n.kids[0]));
    nkBlock :
      begin
        if not EndsSeq (n.kids[0]) then Exit (False);
        for i := 1 to High (n.kids) do
        begin
          e := n.kids[i];
          if (e <> nil) and (e.kind = nkHandler) then
            if not EndsSeq (e.kids[2]) then Exit (False);
        end;
        Exit (True);
      end;
  else
    Exit (False);
  end;
end;

function EndsSeq (k: TNode): Boolean;
var i : Integer;
begin
  if k = nil then Exit (False);
  for i := 0 to High (k.kids) do
    if (k.kids[i] <> nil) and EndsStmt (k.kids[i]) then Exit (True);
  Result := False;
end;

{ ---- a procedure fits a procedure type that lets it raise MORE than
  it does (par 2.2.3, relaxed 2026-10-02).  corpus/Sem.m9's ProcFits
  says why; these are the same three, on 1-based strings. ---- }

{ how many characters of a procedure type's canonical text come before
  its own RAISES clause: all of them when it has none, -1 when s is
  not a procedure type }
function ProcHead (const s: string): Integer;
var i, depth, shut : Integer;
begin
  if not StartsWithS (s, 'PROCEDURE (') then Exit (-1);
  depth := 0;
  shut := -1;
  i := 11;
  while (i <= Length (s)) and (shut < 0) do
  begin
    if s[i] = '(' then Inc (depth)
    else if s[i] = ')' then
    begin
      Dec (depth);
      if depth = 0 then shut := i;
    end;
    Inc (i);
  end;
  if shut < 0 then Exit (-1);
  i := shut;
  while i + 7 <= Length (s) do
  begin
    if Copy (s, i, 8) = ' RAISES ' then Exit (i - 1);
    Inc (i);
  end;
  Result := Length (s);
end;

{ two lists as they stand after RAISES, 'A, B': is every name of src
  one of dst's? }
function RaisesWithin (const src, dst: string): Boolean;
var
  a, b, ea, eb : Integer;
  found : Boolean;
begin
  a := 1;
  while a <= Length (src) do
  begin
    ea := a;
    while (ea <= Length (src)) and (src[ea] <> ',') do Inc (ea);
    found := False;
    b := 1;
    while (b <= Length (dst)) and not found do
    begin
      eb := b;
      while (eb <= Length (dst)) and (dst[eb] <> ',') do Inc (eb);
      found := Copy (src, a, ea - a) = Copy (dst, b, eb - b);
      b := eb + 2;
    end;
    if not found then Exit (False);
    a := ea + 2;
  end;
  Result := True;
end;

function ProcFits (const dst, src: string): Boolean;
var hd, hs : Integer;
begin
  hd := ProcHead (dst);
  hs := ProcHead (src);
  if (hd < 0) or (hs < 0) then Exit (False);
  if Copy (dst, 1, hd) <> Copy (src, 1, hs) then Exit (False);
  if hs = Length (src) then Exit (True);         { src raises nothing }
  if hd = Length (dst) then Exit (False);        { and dst allows nothing }
  Result := RaisesWithin (Copy (src, hs + 9, MaxInt), Copy (dst, hd + 9, MaxInt));
end;

function Compat (const dst, src: string): Boolean;
begin
  if (dst = '<void>') or (src = '<void>') then Exit (False);
  if (dst = '') or (src = '') then Exit (True);
  if dst = src then Exit (True);
  if src = '<int>' then
    Exit (IsIntStr (dst) or (dst = 'BYTE'));
  if dst = '<int>' then
    Exit (IsIntStr (src) or (src = 'BYTE'));
  if src = '<real>' then Exit (IsFloatStr (dst));
  if dst = '<real>' then Exit (IsFloatStr (src));
  if src = '<str1>' then
    Exit ((dst = 'CHAR') or (dst = 'SLICE OF CHAR'));
  if dst = '<str1>' then
    Exit ((src = 'CHAR') or (src = 'SLICE OF CHAR'));
  if src = '<none>' then Exit (StartsWithS (dst, 'OPT '));
  if dst = '<none>' then Exit (StartsWithS (src, 'OPT '));
  { ADR's answer fits a C pointer parameter of either constness }
  if src = 'C.Ptr' then Exit ((dst = 'C.ConstPtr') or (dst = 'C.MutPtr'));
  { ARRAY N OF T is the view of all N elements (par 2.2) }
  if StartsWithS (dst, 'SLICE OF ') and StartsWithS (src, 'ARRAY ') then
    Exit (ElemOfArray (src) = Copy (dst, 10, MaxInt));
  { a shared handle lends like a plain borrow (par 4.1) }
  if StartsWithS (dst, 'PTR ') and (src = 'SHARED ' + dst) then
    Exit (True);
  { a procedure that raises no more than the type allows, bare or as
    the OPT a variable of procedure type must be }
  if ProcFits (dst, src) then Exit (True);
  if StartsWithS (dst, 'OPT ') and StartsWithS (src, 'OPT ') then
    Exit (ProcFits (Copy (dst, 5, MaxInt), Copy (src, 5, MaxInt)));
  Result := False;
end;

{ the type one element of an aggregate has (par 2.2.4): a literal, or
  a negated numeric literal.  An integer is an I64, a real an F64, a
  string a STR whatever its length -- a table has one element type
  and nothing in it adapts.  '' for anything else. }
{ the checker a record aggregate in a CONST is asked of: AggElemType
  and LitType are plain functions and a record's type is the module
  tables' (Sem.RecordConstType) }
var recSem : TSem = nil;

function AggElemType (e: TNode): string;
begin
  Result := '';
  if e = nil then Exit;
  if e.kind = nkCallExpr then
  begin
    if recSem <> nil then Result := recSem.RecordConstType (e);
    Exit;
  end;
  case e.kind of
    nkInt  : Result := 'I64';
    nkReal : Result := 'F64';
    nkChar : Result := 'CHAR';
    nkString : Result := 'SLICE OF CHAR';
    nkTrue, nkFalse : Result := 'BOOL';
    nkUn :
      if (e.a = '-') and (e.kids[0] <> nil) then
      begin
        if e.kids[0].kind = nkInt then Result := 'I64'
        else if e.kids[0].kind = nkReal then Result := 'F64';
      end;
  end;
end;

{ [ e1, ..., en ] is an ARRAY n OF T, T being what every element is;
  unknown ('') when the elements do not agree, which CheckAggregate
  says by name }
function AggType (e: TNode): string;
var
  i : Integer;
  t : string;
begin
  Result := '';
  if Length (e.kids) = 0 then Exit;
  t := AggElemType (e.kids[0]);
  if t = '' then Exit;
  for i := 1 to High (e.kids) do
    if AggElemType (e.kids[i]) <> t then Exit;
  Result := 'ARRAY ' + IntToStr (Length (e.kids)) + ' OF ' + t;
end;

{ type of a module-level CONST expression: literals and literal
  arithmetic, an aggregate of literals; anything fancier stays
  unknown }
function IsStrLit (const t: string): Boolean;
begin
  Result := (t = '<str1>') or (t = 'SLICE OF CHAR') or (t = 'CHAR');
end;

function LitType (e: TNode): string;
var l, r : string;
begin
  Result := '';
  if e = nil then Exit;
  if e.kind = nkCallExpr then
  begin
    if recSem <> nil then Result := recSem.RecordConstType (e);
    Exit;
  end;
  case e.kind of
    nkAggregate : Result := AggType (e);
    nkInt  : Result := '<int>';
    nkReal : Result := '<real>';
    nkChar : Result := 'CHAR';
    nkString :
      if Utf8Len (e.a) = 1 then Result := '<str1>'
      else Result := 'SLICE OF CHAR';
    nkTrue, nkFalse : Result := 'BOOL';
    nkParen, nkUn : Result := LitType (e.kids[0]);
    nkBin :
      begin
        l := LitType (e.kids[0]);
        r := LitType (e.kids[1]);
        { the arithmetic each kind has, and nothing else (mirrors Sem) }
        if (l = '<int>') and (r = '<int>') and
           ((e.a = '+') or (e.a = '-') or (e.a = '*') or (e.a = 'DIV') or (e.a = 'MOD')) then Result := '<int>'
        else if (l = '<real>') and (r = '<real>') and
           ((e.a = '+') or (e.a = '-') or (e.a = '*') or (e.a = '/')) then Result := '<real>'
        { `+' over string and CHAR literals is one string literal }
        else if (e.a = '+') and IsStrLit (l) and IsStrLit (r) then Result := 'SLICE OF CHAR';
      end;
  end;
end;

{ ---- TModuleInfo ---- }

function TModuleInfo.HasExc (const n: string): Boolean;
var i : Integer;
begin
  for i := 0 to High (exNames) do
    if exNames[i] = n then Exit (True);
  Result := False;
end;

function TModuleInfo.FindProc (const n: string): Integer;
var i : Integer;
begin
  for i := 0 to High (procs) do
    if procs[i].name = n then Exit (i);
  Result := -1;
end;

procedure TModuleInfo.AddProc (const p: TProcInfo);
begin
  SetLength (procs, Length (procs) + 1);
  procs[High (procs)] := p;
end;

function TModuleInfo.FindType (const n: string): TNode;
var i : Integer;
begin
  for i := 0 to High (tdNames) do
    if tdNames[i] = n then Exit (tdNodes[i]);
  Result := nil;
end;

{ ---- TSem plumbing ---- }

constructor TSem.Create;
begin
  Errors := TStringList.Create; Errors.CaseSensitive := True;
  Ledger := TStringList.Create; Ledger.CaseSensitive := True;
  fromMap := TStringList.Create; fromMap.CaseSensitive := True;
  constMap := TStringList.Create; constMap.CaseSensitive := True;
  roScope := TStringList.Create;
  roFrom := TStringList.Create;
  roFresh := TStringList.Create;
  mro := TStringList.Create; mro.CaseSensitive := True;
  RoCand := TStringList.Create; RoCand.CaseSensitive := True;
  varParams := TStringList.Create; varParams.CaseSensitive := True;
  ansMemo := TStringList.Create; ansMemo.CaseSensitive := True;
  keptParams := TStringList.Create; keptParams.CaseSensitive := True;
  keptUsed := TStringList.Create; keptUsed.CaseSensitive := True;
  varWritten := TStringList.Create; varWritten.CaseSensitive := True;
  localConsts := TStringList.Create; localConsts.CaseSensitive := True;
  tyI64 := TNode.Create (nkQualident);
  tyI64.a := 'I64';
  tyCHAR := TNode.Create (nkQualident);
  tyCHAR.a := 'CHAR';
  strNode := TNode.Create (nkSliceType);
  strNode.Add (tyCHAR);
  strNode.Add (nil);              { attribute lives on the STR name }
end;

destructor TSem.Destroy;
begin
  ansMemo.Free;
  Errors.Free;
  Ledger.Free;
  fromMap.Free;
  constMap.Free;
  tyI64.Free;
  inherited;
end;

function TSem.FindMod (const n: string): TModuleInfo;
var i : Integer;
begin
  for i := 0 to High (mods) do
    if mods[i].name = n then Exit (mods[i]);
  Result := nil;
end;

{ ---- does a procedure ANSWER frame storage?  A memoised summary of
  its body; Sem.AnswersFrame says why the signature cannot tell.  A
  frame NEW, a `+` in a function that answers a string, a local POOL
  in one, or a call to a procedure that answers frame storage is the
  evidence; a cycle adds none. ---- }

function TSem.ProcNamed (const modn, callee: string; out pr: TProcInfo): Boolean;
var
  m : TModuleInfo;
  dot, pi : Integer;
begin
  Result := False;
  dot := Pos ('.', callee);
  if dot > 0 then
  begin
    m := FindMod (Copy (callee, 1, dot - 1));
    if m = nil then Exit;
    pi := m.FindProc (Copy (callee, dot + 1, MaxInt));
  end
  else
  begin
    m := FindMod (modn);
    if m = nil then Exit;
    pi := m.FindProc (callee);
  end;
  if pi < 0 then Exit;
  pr := m.procs[pi];
  Result := True;
end;

{ is the NEW's storage the frame's?  A type's name first is the frame
  form, a variable's a pool; decided without the procedure's scope.
  Mirrors Sem.NewIsFrameIn. }
function TSem.NewIsFrameIn (e: TNode; const modn: string): Boolean;
var
  d : TNode;
  m : TModuleInfo;
begin
  d := e.kids[0];
  if d = nil then Exit (True);
  Result := False;
  if Length (d.kids) = 0 then
  begin
    if (d.a = 'OWN') or (d.a = 'HEAP') then Exit;
    if InList (d.a, BuiltinTypes) or (d.a = 'STR') then Exit (True);
    m := FindMod (modn);
    if (m <> nil) and (m.FindType (d.a) <> nil) then Exit (True);
  end
  else if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
  begin
    m := FindMod (d.a);
    if (m <> nil) and (m.FindType (d.kids[0].a) <> nil) then Exit (True);
  end;
end;

{ does any `NAME := rhs` under K have frame evidence on its right? }
function TSem.AssignEvidence (k: TNode; const name, modn: string;
  isStr: Boolean; body: TNode; depth: Integer): Boolean;
var i : Integer;
begin
  Result := False;
  if k = nil then Exit;
  if (k.kind = nkAssign) and (k.kids[0] <> nil) and
     (k.kids[0].kind = nkDesignator) and (Length (k.kids[0].kids) = 0) and
     (k.kids[0].a = name) then
    if ExprEvidence (k.kids[1], modn, isStr, body, depth) then Exit (True);
  for i := 0 to High (k.kids) do
    if AssignEvidence (k.kids[i], name, modn, isStr, body, depth) then
      Exit (True);
end;

{ is the value of expression K frame storage?  Mirrors Sem.ExprEvidence. }
function TSem.ExprEvidence (k: TNode; const modn: string; isStr: Boolean;
  body: TNode; depth: Integer): Boolean;
var
  pr : TProcInfo;
  nm : string;
  i : Integer;
begin
  Result := False;
  if depth > 4 then Exit;
  if k = nil then Exit;
  if (k.kind = nkParen) or (k.kind = nkSomeExpr) then
    Exit (ExprEvidence (k.kids[0], modn, isStr, body, depth));
  if k.kind = nkNewExpr then Exit (NewIsFrameIn (k, modn));
  if k.kind = nkBin then Exit (isStr and (k.a = '+'));
  if k.kind = nkCallExpr then
  begin
    if (k.kids[0] <> nil) and (k.kids[0].kind = nkDesignator) then
    begin
      nm := k.kids[0].a;
      for i := 0 to High (k.kids[0].kids) do
        if k.kids[0].kids[i].kind = nkSelField then
          nm := nm + '.' + k.kids[0].kids[i].a
        else
        begin
          nm := k.kids[0].a;
          break;
        end;
      if ProcNamed (modn, nm, pr) and (pr.foreign = '') then
        Exit (AnswersFrame (pr.modName + '.' + pr.name, pr));
    end;
    Exit;
  end;
  if (k.kind = nkDesignator) and (Length (k.kids) = 0) then
    Result := AssignEvidence (body, k.a, modn, isStr, body, depth + 1);
end;

{ the evidence for a procedure of module MODN whose body is K: a
  RETURN whose expression is frame storage, or -- for a string
  answer -- a local POOL, whose strings are re-homed out at exit }
function TSem.FrameEvidence (k: TNode; const modn: string; isStr: Boolean;
  body: TNode; scratchCounts: Boolean): Boolean;
var i : Integer;
begin
  Result := False;
  if k = nil then Exit;
  if k.kind = nkReturn then
  begin
    if ExprEvidence (k.kids[0], modn, isStr, body, 0) then Exit (True);
  end
  else if (k.kind = nkVarDecl) and isStr and scratchCounts and (k.kids[1] <> nil) and
          (k.kids[1].kind = nkQualident) and (k.kids[1].a = 'POOL') and
          (k.kids[1].b = '') then
    Exit (True);
  for i := 0 to High (k.kids) do
    if FrameEvidence (k.kids[i], modn, isStr, body, scratchCounts) then Exit (True);
end;

function TSem.AnswersFrame (const qual: string; const pr: TProcInfo): Boolean;
var
  ix, g : Integer;
  isStr, hasPool : Boolean;
  pl : TNode;
begin
  ix := ansMemo.IndexOfName (qual);
  if ix >= 0 then Exit (ansMemo.ValueFromIndex[ix] = 'yes');
  { in progress counts as no: a cycle adds no evidence of its own }
  ansMemo.Values[qual] := 'busy';
  Result := False;
  if pr.body <> nil then
  begin
    { a procedure that takes a pool answers in it (docs/pools.md) }
    hasPool := False;
    pl := pr.body.kids[0];
    if pl <> nil then
      for g := 0 to High (pl.kids) do
        if (pl.kids[g] <> nil) and (pl.kids[g].kids[1] <> nil) and
           (pl.kids[g].kids[1].kind = nkQualident) and
           (pl.kids[g].kids[1].a = 'POOL') and (pl.kids[g].kids[1].b = '') then
          hasPool := True;
    { ... but only for what it returns; a local POOL is evidence only
      in a pool-less string function (Sem.AnswersFrame says why) }
    isStr := (pr.body.kids[1] <> nil) and
             (CanonT (pr.body.kids[1], 0) = 'SLICE OF CHAR');
    Result := FrameEvidence (pr.body.kids[4], pr.modName, isStr,
                             pr.body.kids[4], not hasPool);
  end;
  if Result then ansMemo.Values[qual] := 'yes'
  else ansMemo.Values[qual] := 'no';
end;

{ Does this call answer FRAME storage -- the callee's name, or ''?
  Mirrors Sem.CallAnswersFrame: not foreign, no POOL parameter, a
  pointer-bearing answer that is not RO, and AnswersFrame's evidence. }
function TSem.CallAnswersFrame (dn: TNode): string;
var
  name : string;
  pr : TProcInfo;
  i : Integer;
  r, r2 : TNode;
  ref : Boolean;
begin
  Result := '';
  if dn.kind <> nkDesignator then Exit;
  name := dn.a;
  for i := 0 to High (dn.kids) do
    if dn.kids[i].kind = nkSelField then name := name + '.' + dn.kids[i].a
    else Exit;
  if not LookupProcInfo (name, pr) then Exit;
  if pr.foreign <> '' then Exit;
  if not AnswersFrame (pr.modName + '.' + pr.name, pr) then Exit;
  if pr.node = nil then Exit;
  if pr.node.f3 then Exit;
  ref := False;
  r := ResolveType (pr.node.kids[1]);
  if r <> nil then
  begin
    if r.kind in [nkPtrType, nkSliceType, nkGridType] then ref := True
    else if r.kind = nkOptType then
    begin
      r2 := ResolveType (r.kids[0]);
      if (r2 <> nil) and (r2.kind = nkPtrType) then ref := True;
    end;
  end;
  if ref then Result := name;
end;

{ par 2.2.4: what an aggregate CONST must be -- literals of one type,
  at module level, in a module's own part.
    where -- 0 a module's own, 1 exported by a DEFINITION, 2 local to
             a procedure }
procedure TSem.CheckAggregate (cd: TNode; const ctx: string;
                               where: Integer);
var
  i : Integer;
  ag : TNode;
  t0, t : string;
  cv : Int64;
begin
  ag := cd.kids[0];
  if (ag <> nil) and IsRecordCall (ag) then
  begin
    if where = 1 then
      ErrN (cd, ctx, 'a record CONST is not exported yet: ' + cd.a +
        ' (par 2.2.4)')
    else if where = 2 then
      ErrN (cd, ctx, 'a record CONST belongs at module level: ' + cd.a +
        ' (par 2.2.4)');
    CheckRecordConst (ag, ctx, cd.a);
  end;
  { a form the generator cannot emit is refused here, by name (mirrors Sem) }
  if (ag <> nil) and (LitType (ag) = '') then
    ErrN (cd, ctx, 'CONST ' + cd.a +
      ': a constant is a literal, a negated number, or + over string and CHAR literals -- compute anything else in a procedure (par 2.2.4)');
  { an integer expression is folded by the generators with the runtime's
    arithmetic: what would raise at run time is refused here (mirrors Sem) }
  if (ag <> nil) and (LitType (ag) = '<int>') and
     ((ag.kind = nkBin) or (ag.kind = nkParen) or
      ((ag.kind = nkUn) and (Length (ag.kids) > 0) and (ag.kids[0] <> nil) and
       not (ag.kids[0].kind in [nkInt, nkReal]))) then
  begin
    if not FoldInt (ag, cv) then
      ErrN (cd, ctx, 'CONST ' + cd.a +
        ': the expression overflows I64 or divides by zero (par 2.2.4)')
    else if cv = Low (Int64) then
      ErrN (cd, ctx, 'CONST ' + cd.a +
        ': the smallest I64 cannot be written as a constant; give it a procedure (par 2.2.4)');
  end;
  if (ag = nil) or (ag.kind <> nkAggregate) then Exit;
  Inc (nAgg);
  if where = 1 then
    ErrN (cd, ctx, 'an aggregate CONST is not exported yet: ' + cd.a +
      ' (par 2.2.4)')
  else if where = 2 then
    ErrN (cd, ctx, 'an aggregate CONST belongs at module level: ' + cd.a +
      ' (par 2.2.4)');
  t0 := AggElemType (ag.kids[0]);
  for i := 0 to High (ag.kids) do
    if ag.kids[i] <> nil then
    begin
      t := AggElemType (ag.kids[i]);
      if IsRecordCall (ag.kids[i]) then
        CheckRecordConst (ag.kids[i], ctx,
          Format ('element %d of %s', [i + 1, cd.a]));
      if (t = '') and IsRecordCall (ag.kids[i]) then
        { said by CheckRecordConst }
      else if t = '' then
        ErrN (ag.kids[i], ctx, Format (
          'element %d of %s is not a literal: an aggregate holds' +
          ' literals (par 2.2.4)', [i + 1, cd.a]))
      else if (t0 <> '') and (t <> t0) then
        ErrN (ag.kids[i], ctx, Format (
          'element %d of %s is %s where the first is %s: an aggregate' +
          ' has one element type (par 2.2.4)',
          [i + 1, cd.a, TyName (t), TyName (t0)]));
    end;
end;

function FieldTypeOf (rec: TNode; const fname: string): TNode; forward;

{ the dotted name a call names: `Row', `Mod.Row' }
function CalleeOf (e: TNode): string;
var i : Integer;
begin
  Result := '';
  if (e = nil) or (Length (e.kids) = 0) or (e.kids[0] = nil) then Exit;
  Result := e.kids[0].a;
  for i := 0 to High (e.kids[0].kids) do
    if e.kids[0].kids[i].kind = nkSelField then
      Result := Result + '.' + e.kids[0].kids[i].a
    else
      Exit (e.kids[0].a);
end;

{ Sem.RecordNamed: the RECORD a callee names, through aliases; om the
  module that wrote it, canon its canonical type name }
function TSem.RecordNamed (const name: string; out om, canon: string): TNode;
var
  dot : Integer;
  dcl : TNode;
begin
  Result := nil;
  canon := '';
  dcl := nil;
  dot := Pos ('.', name);
  if dot > 0 then
  begin
    om := Copy (name, 1, dot - 1);
    if FindMod (om) <> nil then
      dcl := FindMod (om).FindType (Copy (name, dot + 1, MaxInt));
  end
  else
  begin
    om := curMod;
    if FindMod (curMod) <> nil then dcl := FindMod (curMod).FindType (name);
  end;
  Result := ResolveType (dcl);
  if (Result = nil) or (Result.kind <> nkRecordType) then Exit (nil);
  canon := om + '.' + Copy (name, dot + 1, MaxInt);
  if dcl.kind = nkQualident then
  begin
    canonCtx := om;
    canon := CanonT (dcl, 0);
    canonCtx := '';
  end;
end;

function TSem.IsRecordCall (e: TNode): Boolean;
var om, canon : string;
begin
  Result := (e <> nil) and (e.kind = nkCallExpr) and
            (RecordNamed (CalleeOf (e), om, canon) <> nil);
end;

{ Sem.RecordConstType: a record aggregate whose fields are all
  literals is an element of its record's type }
function TSem.RecordConstType (e: TNode): string;
var
  i : Integer;
  om, canon : string;
begin
  Result := '';
  if (e = nil) or (e.kind <> nkCallExpr) then Exit;
  if RecordNamed (CalleeOf (e), om, canon) = nil then Exit;
  if e.kids[1] <> nil then
    for i := 0 to High (e.kids[1].kids) do
      if AggElemType (e.kids[1].kids[i]) = '' then Exit;
  Result := canon;
end;

{ Sem.ConstFieldType: field f of the record named rec, canonically }
function TSem.ConstFieldType (const rec, f: string): string;
var
  om, canon : string;
  rn, ft : TNode;
begin
  Result := '';
  rn := RecordNamed (rec, om, canon);
  if rn = nil then Exit;
  ft := FieldTypeOf (rn, f);
  if ft = nil then Exit;
  canonCtx := om;
  Result := CanonT (ft, 0);
  canonCtx := '';
end;

{ Sem.CheckRecordConst: every field a literal of its field's type, as
  many as the record has }
procedure TSem.CheckRecordConst (el: TNode; const ctx, what: string);
var
  name, om, canon, pTy, aTy : string;
  rn : TNode;
  flat : array of TNode;
  g, j, k, nargs : Integer;
begin
  name := CalleeOf (el);
  rn := RecordNamed (name, om, canon);
  if rn = nil then Exit;
  if rn.kids[0] <> nil then
  begin
    ErrN (el, ctx, name + ': an aggregate of an extended record is' +
      ' not built; give its fields one by one (par 2.2.4)');
    Exit;
  end;
  SetLength (flat, 0);
  if rn.kids[1] <> nil then
    for g := 0 to High (rn.kids[1].kids) do
      for j := 0 to High (rn.kids[1].kids[g].kids[0].kids) do
      begin
        SetLength (flat, Length (flat) + 1);
        flat[High (flat)] := rn.kids[1].kids[g].kids[1];
      end;
  if el.kids[1] = nil then Exit;
  nargs := Length (el.kids[1].kids);
  if nargs <> Length (flat) then
    ErrN (el, ctx, Format ('%s expects %d argument(s), got %d',
      [name, Length (flat), nargs]));
  for k := 0 to nargs - 1 do
    if el.kids[1].kids[k] <> nil then
    begin
      if AggElemType (el.kids[1].kids[k]) = '' then
        ErrN (el.kids[1].kids[k], ctx, Format ('field %d of %s is not a' +
          ' literal: a CONST holds literals (par 2.2.4)', [k + 1, what]))
      else if k <= High (flat) then
      begin
        canonCtx := om;
        pTy := CanonT (flat[k], 0);
        canonCtx := '';
        aTy := LitType (el.kids[1].kids[k]);
        if not Compat (pTy, aTy) then
          ErrN (el.kids[1].kids[k], ctx, Format (
            'field %d of %s: cannot give %s where %s is expected',
            [k + 1, what, TyName (aTy), TyName (pTy)]));
      end;
    end;
end;

procedure TSem.ErrN (n: TNode; const ctx, msg: string);
var ln, cl : Integer;
begin
  ln := 0; cl := 0;
  if n <> nil then begin ln := n.line; cl := n.col; end;
  Errors.Add (Format ('%d:%d %s: %s', [ln, cl, ctx, msg]));
end;

function TSem.SigOf (p: TNode): string;
begin
  Result := '(' + ParamsText (p.kids[0]) + ')';
  if p.kids[1] <> nil then
    Result := Result + ' : ' + TypeText (p.kids[1]);
  if p.kids[2] <> nil then
    Result := Result + ' RAISES ' + string.Join (', ', RaisesOf (p));
  if p.kids[3] <> nil then
    Result := Result + ' [' + p.kids[3].a + ']';
end;

function TSem.RaisesOf (p: TNode): TStringArray;
var i : Integer;
begin
  SetLength (Result, 0);
  if p.kids[2] = nil then Exit;
  SetLength (Result, Length (p.kids[2].kids));
  for i := 0 to High (p.kids[2].kids) do
    if p.kids[2].kids[i].b <> '' then
      Result[i] := p.kids[2].kids[i].b
    else
      Result[i] := p.kids[2].kids[i].a;
end;

{ an exception cited by RAISE, a RAISES clause or a handler must be
  one the reader (and the generator) can find, resolving exactly as
  the generator's ExcRef does: a qualified name in the module it
  names, a bare name locally, predeclared, or declared in some loaded
  module (both direct and transitive deps register their exceptions).
  A name found nowhere is accepted by neither -- catch it HERE. }
function QualifyTypeIn (t: TNode; const modName: string): TNode; forward;

{ the EXCEPTION declaration a handler names and the module that
  declares it: qualified, that module; bare, the current module first,
  then any (as ExcKnown finds it); nil for a predeclared one }
{ the predeclared payload, as EXCEPTION IndexError (index, length : I64)
  would parse (mirrors Sem.Setup) }
function TSem.IxDecl: TNode;
var xd, fs, g, il, i1, i2, ty : TNode;
begin
  if ixD = nil then
  begin
    xd := TNode.Create (nkExcDecl); xd.a := 'IndexError';
    fs := TNode.Create (nkFieldSeq);
    g := TNode.Create (nkFieldGroup);
    il := TNode.Create (nkIdentList);
    i1 := TNode.Create (nkIdent); i1.a := 'index';
    i2 := TNode.Create (nkIdent); i2.a := 'length';
    ty := TNode.Create (nkQualident); ty.a := 'I64';
    il.Add (i1); il.Add (i2);
    g.Add (il); g.Add (ty);
    fs.Add (g);
    xd.Add (fs);
    ixD := xd;
  end;
  Result := ixD;
end;

function TSem.ExcDeclOf (const qual, nm: string; out owner: string): TNode;
var
  m : TModuleInfo;
  i, j : Integer;
begin
  if nm = 'IndexError' then begin owner := ''; Exit (IxDecl); end;
  Result := nil;
  owner := '';
  if qual <> '' then
  begin
    m := FindMod (qual);
    if m = nil then Exit;
    for i := 0 to High (m.exNames) do
      if m.exNames[i] = nm then begin owner := qual; Exit (m.exDecls[i]); end;
    Exit;
  end;
  m := FindMod (curMod);
  if m <> nil then
    for i := 0 to High (m.exNames) do
      if m.exNames[i] = nm then begin owner := curMod; Exit (m.exDecls[i]); end;
  for j := 0 to High (mods) do
    for i := 0 to High (mods[j].exNames) do
      if mods[j].exNames[i] = nm then begin owner := mods[j].name; Exit (mods[j].exDecls[i]); end;
end;

{ the type of the k-th payload field, qualified in its module; nil past
  the fields or for a bare declaration }
function TSem.ExcFieldType (decl: TNode; const owner: string; k: Integer): TNode;
var
  fs, grp : TNode;
  g, j, ix : Integer;
begin
  Result := nil;
  if (decl = nil) or (decl.kids[0] = nil) then Exit;
  fs := decl.kids[0];
  ix := 0;
  for g := 0 to High (fs.kids) do
  begin
    grp := fs.kids[g];
    if (grp <> nil) and (grp.kids[0] <> nil) then
      for j := 0 to High (grp.kids[0].kids) do
      begin
        if ix = k then Exit (QualifyTypeIn (grp.kids[1], owner));
        Inc (ix);
      end;
  end;
end;

function TSem.ExcKnown (const qual, nm: string): Boolean;
var
  m : TModuleInfo;
  i : Integer;
begin
  Result := True;
  if (qual <> '') and (qual <> curMod) then
  begin
    m := FindMod (qual);
    { an unknown module is the softness contract's business, not
      ours: only a KNOWN module that lacks the exception is an error }
    if (m <> nil) and (m.foreignLang = '') and not m.HasExc (nm) then
      Result := False;
    Exit;
  end;
  { bare, or qualified with the current module }
  if (nm = 'Overflow') or (nm = 'IndexError') or
     (nm = 'OutOfMemory') or (nm = 'ValueRange') then Exit;
  for i := 0 to High (mods) do
    if mods[i].HasExc (nm) then Exit;
  Result := False;
end;

procedure TSem.CheckExcName (n: TNode; const ctx: string);
var qual, nm : string;
begin
  if n = nil then Exit;            { a bare re-raise names nothing }
  qual := ''; nm := n.a;
  if n.b <> '' then begin qual := n.a; nm := n.b; end;
  if not ExcKnown (qual, nm) then
    ErrN (n, ctx, 'unknown exception: ' + nm);
end;

{ ---- a type named in a KNOWN module must exist there ----

  The softness contract stands: an unknown type never diagnoses,
  because a bare name found nowhere may simply be a missing IMPORT,
  and a checker that guesses produces diagnostics nobody can act on.
  But `DynStr.Dstring' names a module that IS loaded and a type it
  does not declare.  That is a typo, not softness -- and it rode
  through --check without a word to surface as cc's `unknown type
  name DynStr_Dstring', the M9 name mangled and the M9 line gone
  (2026-09-15).  Same rule as ExcKnown above: only a known,
  non-foreign module lacking the name is an error.

  Checked ONCE, at the declaration, in declaration order; every
  lookup that follows stays soft, so nothing cascades. }

function TSem.TypeKnown (const qual, nm: string): Boolean;
var m : TModuleInfo;
begin
  Result := True;
  if qual = '' then Exit;
  m := FindMod (qual);
  if m = nil then Exit;
  if m.foreignLang <> '' then Exit;
  if m.FindType (nm) <> nil then Exit;
  Result := InList (nm, m.opaque);
end;

procedure TSem.CheckTypeNode (t: TNode; const ctx: string);
{ every qualident reachable through PTR, OPT, SHARED, SLICE, ARRAY,
  GRID and the fields of a record, monitor or case record }
var i : Integer;
begin
  if t = nil then Exit;
  case t.kind of
    nkQualident :
      if (t.b <> '') and not TypeKnown (t.a, t.b) then
        ErrN (t, ctx, 'unknown type: ' + t.a + '.' + t.b + ' -- '
                      + t.a + ' declares no such type');
    nkPtrType, nkSharedType :
      CheckTypeNode (t.kids[0], ctx);
    nkOptType :
      begin
        CheckTypeNode (t.kids[0], ctx);
        { OPT holds a pointer or a procedure value (mirrors Sem) }
        if OptOverValue (t.kids[0]) then
          ErrN (t, ctx, 'OPT holds a pointer or a procedure value, and ' +
            TypeText (t.kids[0]) +
            ' is neither: keep a BOOL beside the value, or OPT PTR to it (par 2.2)');
      end;
    nkSliceType :
      begin
        CheckTypeNode (t.kids[0], ctx);
        if IsBareProc (t.kids[0]) then
          ErrN (t, ctx, 'a slice or array of procedure values is not in the language yet (par 2.2.3)');
      end;
    nkArrayType :
      begin
        CheckTypeNode (t.kids[1], ctx);
        if IsBareProc (t.kids[1]) then
          ErrN (t, ctx, 'a slice or array of procedure values is not in the language yet (par 2.2.3)');
      end;
    nkGridType :
      CheckTypeNode (t.kids[1], ctx);
    nkProcType :
      begin
        if t.kids[0] <> nil then
          for i := 0 to High (t.kids[0].kids) do
            if t.kids[0].kids[i] <> nil then
              CheckTypeNode (t.kids[0].kids[i].kids[1], ctx);
        CheckTypeNode (t.kids[1], ctx);
      end;
    nkRecordType :
      begin
        { kids[0] is the extension base, when there is one }
        CheckTypeNode (t.kids[0], ctx);
        CheckFieldTypes (t.kids[1], ctx);
      end;
    nkMonitorType :
      CheckFieldTypes (t.kids[0], ctx);
    nkCaseRecordType :
      for i := 0 to High (t.kids) do
        if t.kids[i] <> nil then CheckFieldTypes (t.kids[i].kids[0], ctx);
  end;
end;

procedure TSem.CheckFieldTypes (fs: TNode; const ctx: string);
var i : Integer;
begin
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
    if fs.kids[i] <> nil then
    begin
      CheckTypeNode (fs.kids[i].kids[1], ctx);
      if IsBareProc (fs.kids[i].kids[1]) then
        ErrN (fs.kids[i], ctx, 'a field of procedure type must be OPT (par 2.2.3)');
    end;
end;

procedure TSem.CheckVarTypes (holder: TNode; const ctx: string);
{ the VAR and TYPE sections directly under a unit or a procedure body }
var a, b : Integer;
begin
  if holder = nil then Exit;
  for a := 0 to High (holder.kids) do
    if holder.kids[a] <> nil then
    begin
      if holder.kids[a].kind = nkVarSection then
      begin
        for b := 0 to High (holder.kids[a].kids) do
          if holder.kids[a].kids[b] <> nil then
          begin
            CheckTypeNode (holder.kids[a].kids[b].kids[1], ctx);
            if IsBareProc (holder.kids[a].kids[b].kids[1]) then
              ErrN (holder.kids[a].kids[b], ctx,
                'a variable of procedure type must be OPT (par 2.2.3)');
          end;
      end
      else if holder.kids[a].kind = nkTypeSection then
      begin
        for b := 0 to High (holder.kids[a].kids) do
          if holder.kids[a].kids[b] <> nil then
            CheckTypeNode (holder.kids[a].kids[b].kids[0], ctx);
      end;
    end;
end;

procedure TSem.CheckDeclTypes (u: TNode);
{ one pass over a unit, in declaration order: its TYPE and VAR
  sections under the unit's own name, then each procedure's
  parameters, return type and locals under the procedure's }
var
  i, a : Integer;
  d, pl : TNode;
begin
  CheckVarTypes (u, u.a);
  for i := 0 to High (u.kids) do
  begin
    d := u.kids[i];
    if (d = nil) or (d.kind <> nkProcDecl) then Continue;
    pl := d.kids[0];
    if pl <> nil then
      for a := 0 to High (pl.kids) do
        if pl.kids[a] <> nil then
          CheckTypeNode (pl.kids[a].kids[1], u.a + '.' + d.a);
    CheckTypeNode (d.kids[1], u.a + '.' + d.a);
    if IsBareProc (d.kids[1]) then
      ErrN (d, u.a + '.' + d.a,
        'a procedure cannot answer a procedure value (par 2.2.3)');
    if d.kids[4] <> nil then
      CheckVarTypes (d.kids[4], u.a + '.' + d.a);
  end;
end;

{ ---- registry ---- }

{ QualifiedIn at unit level, for CollectUnit's exported variables
  (decision 28); the same rules as the nested one CheckFile uses }
function QualifyTypeIn (t: TNode; const modName: string): TNode;
var n : TNode;
begin
  Result := t;
  if t = nil then Exit;
  case t.kind of
    nkQualident :
      if (t.b = '') and not InList (t.a, BuiltinTypes) and (t.a <> 'STR') then
      begin
        n := TNode.Create (nkQualident);
        n.a := modName;
        n.b := t.a;
        Result := n;
      end;
    nkPtrType, nkOptType, nkSharedType, nkSliceType :
      begin
        n := TNode.Create (t.kind);
        if Length (t.kids) > 0 then n.Add (QualifyTypeIn (t.kids[0], modName));
        n.Add (nil);
        Result := n;
      end;
    nkArrayType, nkGridType :
      if Length (t.kids) >= 2 then
      begin
        n := TNode.Create (t.kind);
        n.Add (t.kids[0]);
        n.Add (QualifyTypeIn (t.kids[1], modName));
        Result := n;
      end;
  end;
end;

{ ---- the module a designator's type was written in ----

  A component type -- a record's field, a pointer's target, a slice's
  or an array's element -- is written in the module that declared the
  aggregate, and a bare name in it means that module's type.  The two
  designator walks (DesigDeclType, CheckWrite) took such a node and
  resolved it in the CURRENT module, so `tm.kind' with tm a
  Sparql.Term and kind a bare `Kind' resolved to Csv.Kind, the first
  Kind on the search path; the M9 checker qualifies through
  QualifiedIn and accepted it (semtest, 2026-10-07: the canonCtx
  class, the fourth of its kind).  NoteMod remembers the module of
  the last QUALIFIED type the walk passed; InMod qualifies a component
  in it, unless it is the current module. }

procedure TSem.NoteMod (t: TNode; var m: string);
begin
  if (t <> nil) and (t.kind = nkQualident) and (t.b <> '') then m := t.a;
end;

function TSem.InMod (t: TNode; const m: string): TNode;
begin
  if (m = '') or (m = curMod) then Exit (t);
  Result := QualifyTypeIn (t, m);
end;

procedure TSem.CollectUnit (u: TNode);
var
  m : TModuleInfo;
  i, j, k, vi, pi : Integer;
  d, td, cr : TNode;
  p : TProcInfo;
begin
  m := FindMod (u.a);
  if m = nil then
  begin
    m := TModuleInfo.Create;
    m.name := u.a;
    SetLength (mods, Length (mods) + 1);
    mods[High (mods)] := m;
  end;
  if u.kind = nkDefinition then
  begin
    m.hasDef := True;
    if u.b <> '' then m.foreignLang := u.b;
    if u.f2 then m.stateful := True;
  end;
  if u.kind = nkImplementation then m.hasImpl := True;
  for i := 0 to High (u.kids) do
  begin
    d := u.kids[i];
    if d = nil then Continue;
    case d.kind of
      nkProcDecl :
        begin
          pi := m.FindProc (d.a);
          if pi < 0 then
          begin
            p.name := d.a;
            p.modName := m.name;
            p.foreign := d.b;
            if d.kids[3] <> nil then p.attrib := d.kids[3].a
            else p.attrib := '';
            p.raises := RaisesOf (d);
            p.sig := SigOf (d);
            p.node := d;
            p.body := nil;
            p.fromDef := u.kind = nkDefinition;
            p.hasBody := d.kids[4] <> nil;
            if p.hasBody then p.body := d;
            m.AddProc (p);
          end
          else if d.kids[4] <> nil then
          begin
            m.procs[pi].hasBody := True;
            m.procs[pi].body := d;
          end;
        end;
      nkExcSection :
        { the declared exceptions: RAISE/RAISES/handler may only cite
          a name the reader can find -- one declared here, one
          predeclared, or one qualified into the module that owns it }
        for j := 0 to High (d.kids) do
        begin
          SetLength (m.exNames, Length (m.exNames) + 1);
          m.exNames[High (m.exNames)] := d.kids[j].a;
          SetLength (m.exDecls, Length (m.exDecls) + 1);
          m.exDecls[High (m.exDecls)] := d.kids[j];
        end;
      nkVarSection :
        { the definition's variables are the module's exports: an
          importer reads and writes them as Mod.v (decision 28) }
        if u.kind = nkDefinition then
          for j := 0 to High (d.kids) do
            for k := 0 to High (d.kids[j].kids[0].kids) do
            begin
              SetLength (m.vrNames, Length (m.vrNames) + 1);
              SetLength (m.vrTypes, Length (m.vrTypes) + 1);
              SetLength (m.vrRo, Length (m.vrRo) + 1);
              m.vrNames[High (m.vrNames)] := d.kids[j].kids[0].kids[k].a;
              m.vrTypes[High (m.vrTypes)] := QualifyTypeIn (d.kids[j].kids[1], m.name);
              m.vrRo[High (m.vrRo)] := d.kids[j].f3;
            end;
      nkConstSection :
        { a CONST is an untyped literal, so what is remembered is its
          LitType and not a type: `Par.Pi180` must adapt in another
          module exactly as `Pi180` adapts in its own }
        for j := 0 to High (d.kids) do
        begin
          SetLength (m.cnNames, Length (m.cnNames) + 1);
          SetLength (m.cnTypes, Length (m.cnTypes) + 1);
          m.cnNames[High (m.cnNames)] := d.kids[j].a;
          m.cnTypes[High (m.cnTypes)] := LitType (d.kids[j].kids[0]);
        end;
      nkTypeSection :
        for j := 0 to High (d.kids) do
        begin
          td := d.kids[j];
          if td.kids[0] = nil then
          begin
            if u.kind = nkDefinition then
            begin
              SetLength (m.opaque, Length (m.opaque) + 1);
              m.opaque[High (m.opaque)] := td.a;
            end;
            Continue;
          end;
          if m.FindType (td.a) = nil then
          begin
            SetLength (m.tdNames, Length (m.tdNames) + 1);
            SetLength (m.tdNodes, Length (m.tdNodes) + 1);
            m.tdNames[High (m.tdNames)] := td.a;
            m.tdNodes[High (m.tdNodes)] := td.kids[0];
          end;
          { an enumeration is a payload-less case record: its
            members ARE its variants (nkIdent, no payload kid), so it
            registers the same way and inherits construction, CASE
            totality and cross-module reach (docs/enum-plan.md) }
          if td.kids[0].kind in [nkCaseRecordType, nkEnumType] then
          begin
            cr := td.kids[0];
            k := Length (m.vts);
            SetLength (m.vts, k + 1);
            m.vts[k].typeName := td.a;
            SetLength (m.vts[k].variants, Length (cr.kids));
            SetLength (m.vts[k].fields, Length (cr.kids));
            for vi := 0 to High (cr.kids) do
            begin
              m.vts[k].variants[vi] := cr.kids[vi].a;
              if Length (cr.kids[vi].kids) > 0 then
                m.vts[k].fields[vi] := cr.kids[vi].kids[0]
              else
                m.vts[k].fields[vi] := nil;
            end;
          end;
        end;
    end;
  end;
end;

{ Sem.NanWalk: a bare designator NaN becomes the real literal NAN
  (report par 2.1), once per file, as Gen.NanWalk does }
procedure NanWalk (n: TNode);
var i : Integer;
begin
  if n = nil then Exit;
  if (n.kind = nkDesignator) and (Length (n.kids) = 0) and (n.a = 'NaN') then
  begin
    n.kind := nkReal;
    n.a := 'NAN';
  end;
  for i := 0 to High (n.kids) do NanWalk (n.kids[i]);
end;

function IsNanLit (n: TNode): Boolean;
begin
  Result := (n <> nil) and (n.kind = nkReal) and (n.a = 'NAN');
end;

procedure TSem.LoadFile (root: TNode);
var i : Integer;
begin
  recSem := Self;
  for i := 0 to High (root.kids) do
    NanWalk (root.kids[i]);
  for i := 0 to High (root.kids) do
    CollectUnit (root.kids[i]);
end;

{ ---- lookups ---- }

function TSem.LookupProcInfo (const callee: string;
  out pr: TProcInfo): Boolean;
var
  m : TModuleInfo;
  dot, pi : Integer;
  modName, procName : string;
begin
  Result := False;
  dot := Pos ('.', callee);
  if dot > 0 then
  begin
    modName := Copy (callee, 1, dot - 1);
    procName := Copy (callee, dot + 1, MaxInt);
  end
  else
  begin
    procName := callee;
    modName := curMod;
    if fromMap.Values[callee] <> '' then
      modName := fromMap.Values[callee];
  end;
  m := FindMod (modName);
  if m = nil then Exit;
  pi := m.FindProc (procName);
  if pi < 0 then Exit;
  pr := m.procs[pi];
  Result := True;
end;

{ the variant set of a KNOWN selector type ('Json.Value').  Two
  modules may declare a variant type of the same name -- Json and
  Dict both have Value -- so totality must be judged against the
  selector's own type, never against the first module that happens
  to spell a variant the same way. }
function TSem.VariantOfType (const canon: string;
  out vi: TVariantInfo): Boolean;
var
  dot, j : Integer;
  m : TModuleInfo;
begin
  Result := False;
  dot := Pos ('.', canon);
  if dot = 0 then Exit;
  m := FindMod (Copy (canon, 1, dot - 1));
  if m = nil then Exit;
  for j := 0 to High (m.vts) do
    if m.vts[j].typeName = Copy (canon, dot + 1, MaxInt) then
    begin
      vi := m.vts[j];
      Exit (True);
    end;
end;

function TSem.VariantOwner (const vname: string;
  out vi: TVariantInfo): Boolean;
var i, j, k : Integer;
begin
  for i := 0 to High (mods) do
    for j := 0 to High (mods[i].vts) do
      for k := 0 to High (mods[i].vts[j].variants) do
        if mods[i].vts[j].variants[k] = vname then
        begin
          vi := mods[i].vts[j];
          Exit (True);
        end;
  Result := False;
end;

function TSem.IsVariantCtor (const callee: string): Boolean;
var
  dot, i, j, k : Integer;
  tn, vn : string;
begin
  Result := False;
  dot := Pos ('.', callee);
  if dot = 0 then Exit;
  tn := Copy (callee, 1, dot - 1);
  vn := Copy (callee, dot + 1, MaxInt);
  for i := 0 to High (mods) do
    for j := 0 to High (mods[i].vts) do
      if mods[i].vts[j].typeName = tn then
        for k := 0 to High (mods[i].vts[j].variants) do
          if mods[i].vts[j].variants[k] = vn then Exit (True);
end;

function TSem.LookupTypeName (const modName, typeName: string): TNode;
var
  m : TModuleInfo;
  i : Integer;
begin
  if modName <> '' then
  begin
    m := FindMod (modName);
    if m = nil then Exit (nil);
    resolvedIn := modName;
    Exit (m.FindType (typeName));
  end;
  m := FindMod (curMod);
  if m <> nil then
  begin
    Result := m.FindType (typeName);
    if Result <> nil then begin resolvedIn := curMod; Exit; end;
  end;
  for i := 0 to High (mods) do
  begin
    Result := mods[i].FindType (typeName);
    if Result <> nil then begin resolvedIn := mods[i].name; Exit; end;
  end;
  Result := nil;
end;

{ [RO] is a borrow annotation on the binding, not part of type
  identity: written longhand it hangs on the SLICE, written through
  the STR alias it hangs on the name.  Either one forbids writing. }
function TSem.IsReadonlyT (declN, res: TNode): Boolean;
begin
  Result := (res <> nil) and (res.kind = nkSliceType) and
            (Length (res.kids) > 1) and (res.kids[1] <> nil) and
            (res.kids[1].a = 'RO');
  if Result then Exit;
  Result := (declN <> nil) and (declN.kind = nkQualident) and
            (Length (declN.kids) > 0) and (declN.kids[0] <> nil) and
            (declN.kids[0].a = 'RO');
end;

function TSem.ResolveType (t: TNode): TNode;
var depth : Integer;
begin
  Result := t;
  depth := 0;
  resolvedIn := '';
  while (Result <> nil) and (Result.kind = nkQualident) and (depth < 10) do
  begin
    { STR expands to the slice it abbreviates (par 2.2) }
    if (Result.b = '') and (Result.a = 'STR') then
    begin
      Result := strNode;
      Break;
    end;
    if Result.b <> '' then
      Result := LookupTypeName (Result.a, Result.b)
    else
      Result := LookupTypeName ('', Result.a);
    Inc (depth);
  end;
  if (Result <> nil) and (Result.kind = nkQualident) then Result := nil;
end;

{ the variant of a type in EXACTLY the module named: the three-part
  constructor Mod.Type.Variant (args) looks here and nowhere else,
  which is what the qualification says }
function TSem.VariantIn (const mn, tn, vn: string; out ownerMod: string;
  out fields: TNode): Boolean;
var
  m : TModuleInfo;
  a, b : Integer;
begin
  Result := False;
  ownerMod := '';
  fields := nil;
  m := FindMod (mn);
  if m = nil then Exit;
  for a := 0 to High (m.vts) do
    if m.vts[a].typeName = tn then
      for b := 0 to High (m.vts[a].variants) do
        if m.vts[a].variants[b] = vn then
        begin
          ownerMod := m.name;
          fields := m.vts[a].fields[b];
          Exit (True);
        end;
end;

function TSem.FindVariant (const tn, vn: string; out ownerMod: string;
  out fields: TNode): Boolean;
var i, j, k : Integer;

  function TryMod (m: TModuleInfo): Boolean;
  var a, b : Integer;
  begin
    Result := False;
    if m = nil then Exit;
    for a := 0 to High (m.vts) do
      if m.vts[a].typeName = tn then
        for b := 0 to High (m.vts[a].variants) do
          if m.vts[a].variants[b] = vn then
          begin
            ownerMod := m.name;
            fields := m.vts[a].fields[b];
            Exit (True);
          end;
  end;

begin
  ownerMod := '';
  fields := nil;
  { a bare Value.Null resolves in its OWN module first: Json and Dict
    both declare a variant type named Value, and load order must not
    decide which one a constructor means -- the same rule CanonQual
    already applies to bare type names }
  if canonCtx <> '' then Result := TryMod (FindMod (canonCtx))
  else Result := TryMod (FindMod (curMod));
  if Result then Exit;
  for i := 0 to High (mods) do
  begin
    Result := TryMod (mods[i]);
    if Result then Exit;
  end;
end;

{ canonical type of a named type.  Records, case records, monitors,
  and opaque types are nominal -- 'Mod.Name'; aliases chase to their
  structure.  '' when the name cannot be found (softness).           }
{ integer -> enumeration (or payload-less case record), the checked
  inverse of ORD; RAISES ValueRange out of 0..n-1.  Answers the
  canonical type, or '' (docs/enum-plan.md, part 2). }
function TSem.AllPayloadless (n: TNode): Boolean;
var i : Integer;
begin
  Result := False;
  if n = nil then Exit;
  if n.kind = nkEnumType then Exit (True);
  if n.kind = nkCaseRecordType then
  begin
    for i := 0 to High (n.kids) do
      if (n.kids[i] <> nil) and (Length (n.kids[i].kids) > 0)
         and (n.kids[i].kids[0] <> nil) then Exit (False);
    Result := True;
  end;
end;

function TSem.IsTagged (const canon: string): Boolean;
{ the canonical name (Mod.Type) resolves to an enumeration or a case
  record -- a value CASE reaches by tag, which is what NAME can name }
var dot : Integer; t : TNode;
begin
  Result := False;
  dot := Pos ('.', canon);
  if dot = 0 then Exit;
  t := LookupTypeName (Copy (canon, 1, dot - 1), Copy (canon, dot + 1, MaxInt));
  if t <> nil then
    Result := t.kind in [nkEnumType, nkCaseRecordType];
end;

function TSem.EnumConvType (const name: string): string;
var dot : Integer; md, ty : string;
begin
  Result := '';
  dot := Pos ('.', name);
  if dot > 0 then begin md := Copy (name, 1, dot - 1); ty := Copy (name, dot + 1, MaxInt); end
  else begin md := ''; ty := name; end;
  if AllPayloadless (LookupTypeName (md, ty)) then
    Result := CanonQual (md, ty, 0);
end;

function TSem.CanonQual (const modName, typeName: string;
  depth: Integer): string;
var
  i : Integer;

  function TryMod (mm: TModuleInfo): string;
  var td : TNode;
  begin
    Result := '';
    if mm = nil then Exit;
    td := mm.FindType (typeName);
    if td <> nil then
    begin
      if td.kind in [nkRecordType, nkCaseRecordType, nkMonitorType, nkEnumType] then
        Exit (mm.name + '.' + typeName);
      Exit (CanonT (td, depth + 1));
    end;
    if InList (typeName, mm.opaque) then
      Exit (mm.name + '.' + typeName);
  end;

begin
  if modName <> '' then
    Exit (TryMod (FindMod (modName)));
  { bare names resolve in their OWNING module first: a callee's
    signature written in Json must not find Ast's Node just because
    Ast loads earlier (the collision Ast.m9 introduced) }
  if canonCtx <> '' then
    Result := TryMod (FindMod (canonCtx))
  else
    Result := TryMod (FindMod (curMod));
  if Result <> '' then Exit;
  for i := 0 to High (mods) do
  begin
    Result := TryMod (mods[i]);
    if Result <> '' then Exit;
  end;
end;

{ the canonical text of a procedure type, or of a procedure's head
  (par 2.2.3): the parameter modes and types with no names, the result
  with its RO, and the RAISES names bare and sorted.  Two procedure
  types are the same type exactly when this text is the same; a
  procedure FITS a procedure type when its head renders the same up
  to RAISES and it raises no more than the type allows (ProcFits).
  Mirrors Sem.ProcSig. }
function TSem.ProcSig (pl, rt: TNode; ro: Boolean; rs: TNode;
                       depth: Integer): string;
var
  g, j, i, k : Integer;
  first : Boolean;
  s, tmp : string;
  names : array of string;
begin
  Result := 'PROCEDURE (';
  first := True;
  if pl <> nil then
    for g := 0 to High (pl.kids) do
      if pl.kids[g] <> nil then
      begin
        s := CanonT (pl.kids[g].kids[1], depth + 1);
        if s = '' then Exit ('');
        if pl.kids[g].kids[0] <> nil then
          for j := 0 to High (pl.kids[g].kids[0].kids) do
          begin
            if not first then Result := Result + ' ; ';
            first := False;
            if pl.kids[g].f1 then Result := Result + 'VAR ';
            if pl.kids[g].f2 then Result := Result + 'OWN ';
            if pl.kids[g].f3 then Result := Result + 'RO ';
            if pl.kids[g].f4 then Result := Result + 'KEPT ';
            Result := Result + s;
          end;
      end;
  Result := Result + ')';
  if rt <> nil then
  begin
    s := CanonT (rt, depth + 1);
    if s = '' then Exit ('');
    Result := Result + ' : ';
    if ro then Result := Result + 'RO ';
    Result := Result + s;
  end;
  if rs <> nil then
  begin
    SetLength (names, Length (rs.kids));
    for i := 0 to High (rs.kids) do
      if rs.kids[i] <> nil then
        if rs.kids[i].b <> '' then names[i] := rs.kids[i].b
        else names[i] := rs.kids[i].a;
    for i := 1 to High (names) do
    begin
      k := i;
      while (k > 0) and (names[k] < names[k - 1]) do
      begin
        tmp := names[k];
        names[k] := names[k - 1];
        names[k - 1] := tmp;
        Dec (k);
      end;
    end;
    Result := Result + ' RAISES ';
    for i := 0 to High (names) do
    begin
      if i > 0 then Result := Result + ', ';
      Result := Result + names[i];
    end;
  end;
end;

{ does a declared type resolve to a bare procedure type?  The four
  refusals of par 2.2.3 ask this: a variable or field of procedure
  type must be OPT, because a procedure value has no zero. }
function TSem.OptOverValue (t: TNode): Boolean;
var r : TNode;
begin
  r := ResolveType (t);
  if r <> nil then Exit ((r.kind <> nkPtrType) and (r.kind <> nkProcType) and (r.kind <> nkSharedType));
  Result := (t <> nil) and (t.kind = nkQualident) and (t.b = '') and
            (InList (t.a, BuiltinTypes) or (t.a = 'POOL'));
end;

function TSem.IsBareProc (t: TNode): Boolean;
var r : TNode;
begin
  r := ResolveType (t);
  Result := (r <> nil) and (r.kind = nkProcType);
end;

function TSem.CanonT (t: TNode; depth: Integer): string;
var s : string;
begin
  Result := '';
  if (t = nil) or (depth > 8) then Exit;
  case t.kind of
    nkProcType :
      Result := ProcSig (t.kids[0], t.kids[1], t.f3, t.kids[2], depth);
    nkQualident :
      if t.b <> '' then
      begin
        if t.a = 'C' then Result := 'C.' + t.b
        else Result := CanonQual (t.a, t.b, depth);
      end
      else if InList (t.a, BuiltinTypes) then
        Result := t.a
      else if t.a = 'STR' then
        { predeclared alias, par 2.2: identical to what it abbreviates,
          so conformance and assignment see no difference at all }
        Result := 'SLICE OF CHAR'
      else if t.a = 'POOL' then
        { a type like any other to the comparison of an argument with
          its parameter; until 2026-10-01 it had no canonical form and
          both sides of every pool argument were unknown.  Mirrors
          Sem.CanonT, where the measurement is written down. }
        Result := 'POOL'
      else
        Result := CanonQual ('', t.a, depth);
    nkPtrType :
      begin
        s := CanonT (t.kids[0], depth + 1);
        if s <> '' then Result := 'PTR ' + s;
      end;
    nkOptType :
      begin
        s := CanonT (t.kids[0], depth + 1);
        if s <> '' then Result := 'OPT ' + s;
      end;
    nkSharedType :
      begin
        s := CanonT (t.kids[0], depth + 1);
        if s <> '' then Result := 'SHARED PTR ' + s;
      end;
    nkSliceType :
      begin
        s := CanonT (t.kids[0], depth + 1);
        if s <> '' then Result := 'SLICE OF ' + s;
      end;
    nkArrayType :
      begin
        s := CanonT (t.kids[1], depth + 1);
        if s <> '' then
          Result := 'ARRAY ' + ExprText (t.kids[0]) + ' OF ' + s;
      end;
    nkGridType :
      begin
        s := CanonT (t.kids[1], depth + 1);
        if s <> '' then
          Result := 'GRID ' + ExprText (t.kids[0]) + ' OF ' + s;
      end;
  end;
end;

function FieldSeqType (fs: TNode; const fname: string): TNode;
var i, j : Integer;
begin
  Result := nil;
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
    for j := 0 to High (fs.kids[i].kids[0].kids) do
      if fs.kids[i].kids[0].kids[j].a = fname then
        Exit (fs.kids[i].kids[1]);
end;

function FieldTypeOf (rec: TNode; const fname: string): TNode;
begin
  Result := FieldSeqType (rec.kids[1], fname);
end;

{ is this field declared RO?  A record or variant field holding a
  borrowed slice says so with the same mode a parameter uses, and it
  must bite the same way: Json.Value.Str views the caller's document,
  and writing through it would corrupt the input the parser was
  handed.  Without this the annotation would be decoration, which is
  the one thing this language does not tolerate. }
function FieldSeqRO (fs: TNode; const fname: string): Boolean;
var i, j : Integer;
begin
  Result := False;
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
    for j := 0 to High (fs.kids[i].kids[0].kids) do
      if fs.kids[i].kids[0].kids[j].a = fname then
        Exit (fs.kids[i].f3);
end;

function FieldROOf (rec: TNode; const fname: string): Boolean;
begin
  Result := FieldSeqRO (rec.kids[1], fname);
end;

{ ---- checks over one unit ---- }

procedure TSem.CheckForeignDef (u: TNode);
var
  i, j : Integer;
  d, pl : TNode;
  ok : Boolean;

  function IsCType (t: TNode): Boolean;
  begin
    Result := (t <> nil) and (t.kind = nkQualident) and
              (t.a = 'C') and (t.b <> '');
  end;

begin
  for i := 0 to High (u.kids) do
  begin
    d := u.kids[i];
    if (d = nil) or (d.kind <> nkProcDecl) then Continue;
    if d.b = '' then
      ErrN (d, u.a + '.' + d.a,
        'foreign procedure needs a bound C name (= "c_name")');
    pl := d.kids[0];
    ok := True;
    for j := 0 to High (pl.kids) do
      if not IsCType (pl.kids[j].kids[1]) then ok := False;
    if (d.kids[1] <> nil) and not IsCType (d.kids[1]) then ok := False;
    if not ok then
      ErrN (d, u.a + '.' + d.a,
        'native type in foreign signature; use C.* types');
    if (d.kids[3] = nil) or
       ((d.kids[3].a <> 'SERIAL') and (d.kids[3].a <> 'REENTRANT')) then
      ErrN (d, u.a + '.' + d.a,
        'foreign procedure must declare [SERIAL] or [REENTRANT]');
  end;
end;

procedure TSem.CheckConformance (u: TNode);
var
  m : TModuleInfo;
  i, pi : Integer;
  d : TNode;
  hasVars : Boolean;
begin
  m := FindMod (u.a);
  if m = nil then Exit;
  hasVars := False;
  for i := 0 to High (u.kids) do
  begin
    d := u.kids[i];
    if d = nil then Continue;
    if d.kind = nkVarSection then hasVars := True;
    if d.kind <> nkProcDecl then Continue;
    pi := m.FindProc (d.a);
    if pi < 0 then Continue;
    if m.procs[pi].node = d then Continue;
    if m.procs[pi].sig <> SigOf (d) then
      ErrN (d, u.a + '.' + d.a,
        'signature differs from definition:' + LineEnding +
        '    definition     ' + m.procs[pi].sig + LineEnding +
        '    implementation ' + SigOf (d));
  end;
  if hasVars and not m.stateful then
    ErrN (u, u.a,
      'module-level state requires STATEFUL on the definition');
  { completeness: every definition procedure implemented, every
    opaque type defined -- checked at the implementation unit }
  for i := 0 to High (m.procs) do
    if m.procs[i].fromDef and not m.procs[i].hasBody then
      ErrN (u, u.a + '.' + m.procs[i].name,
        'declared in the definition but not implemented');
  for i := 0 to High (m.opaque) do
    if m.FindType (m.opaque[i]) = nil then
      ErrN (u, u.a + '.' + m.opaque[i],
        'opaque type not defined in the implementation');
end;

procedure TSem.CheckBody (body: TNode; const ctx: string;
  const declared: array of string; scope: TStringList;
  const retTy: string);
var
  raised, handled, calls, ownState : TStringList;
  i : Integer;
  { ---- par 4.1, DIRECTIONAL: the ledger names stores; these decide
    which stores anyone outside the frame can still see.  Per local
    (or binder, or value param -- all frame storage) a list of escape
    TARGETS: a reference parameter's name, '<module>', '<return>' or
    '<call>'.  Aliasing (local := local, views, binders) is a
    symmetric edge and targets close over the edges, so the
    approximation can keep an entry in the ledger that a finer
    analysis would drop, never drop one it should keep.  Ledger
    entries are PENDED during the walk and classified at the end,
    once every escape of the destination has been seen. }
  escSet, escEdges : TStringList;
  { par 4.1 value provenance: which BORROWS a local or binder
    carries -- a copied reference, a binder's view, a sub-slice.
    'local=borrow' pairs, plus directed copy edges closed at flush
    (carries of the edge's source flow to its destination).  No kill
    on reassignment: the approximation errs into the ledger. }
  carryPair, carryEdge : TStringList;
  pendLn, pendCl : array of Integer;
  pendSrc, pendDst : array of string;
  pendN : Integer;
  { par 2.3: locals/binders that currently hold a FRAME-SCOPED string
    -- a concatenation, which lives in this frame's arena and dies
    with it.  Escaping one (to a module var, through a reference
    parameter, or via RETURN of the holding name) is the use-after-
    free the frame model would otherwise permit silently.  Tainted on
    assignment of a concatenation, cleared when the name is given a
    durable value again (so a reused local never false-positives). }
  fval : TStringList;
  fvalKind : TStringList;   { parallel to fval: what each name holds }
  pval : TStringList;       { bare names holding a POOL allocation: a copy out is no move (mirrors Sem) }

  function ScopeType (const nm: string): TNode;
  var ix : Integer;
  begin
    ix := scope.IndexOfName (nm);
    if ix < 0 then Exit (nil);
    Result := TNode (scope.Objects[ix]);
  end;

  procedure BindName (const nm: string; t: TNode);
  var ix : Integer;
  begin
    ix := scope.IndexOfName (nm);
    if ix < 0 then
      ix := scope.Add (nm + '=b');
    scope.Objects[ix] := TObject (t);
  end;

  { a type node from module MODNAME made self-contained: its bare
    type names qualified, so canonicalising it later -- from whichever
    module the binder is used in -- resolves them where they were
    declared (the canonCtx lesson, applied to binders).  Pool and
    attribute components are dropped, neither being part of type
    identity.  The synthetic nodes are never freed: a handful per
    check, in a one-shot process, like tyCHAR and strNode. }
  function QualifiedIn (t: TNode; const modName: string): TNode;
  var n : TNode;
  begin
    Result := t;
    if t = nil then Exit;
    case t.kind of
      nkQualident :
        if (t.b = '') and not InList (t.a, BuiltinTypes) and
           (t.a <> 'STR') then
        begin
          n := TNode.Create (nkQualident);
          n.a := modName;
          n.b := t.a;
          Result := n;
        end;
      nkPtrType, nkOptType, nkSharedType, nkSliceType :
        begin
          n := TNode.Create (t.kind);
          if Length (t.kids) > 0 then
            n.Add (QualifiedIn (t.kids[0], modName));
          n.Add (nil);
          Result := n;
        end;
      { the bound or the rank as written, the element qualified: an
        exported ARRAY 3 OF Fr (decision 28) }
      nkArrayType, nkGridType :
        if Length (t.kids) >= 2 then
        begin
          n := TNode.Create (t.kind);
          n.Add (t.kids[0]);
          n.Add (QualifiedIn (t.kids[1], modName));
          Result := n;
        end;
    end;
  end;

  function ScopeMode (const nm: string): string;
  var ix : Integer;
  begin
    ix := scope.IndexOfName (nm);
    if ix < 0 then Exit ('');
    Result := scope.ValueFromIndex[ix];
  end;

  { was the name, as it is seen here, declared `VAR RO'? }
  function ScopeRo (const nm: string): Boolean;
  var ix : Integer;
  begin
    ix := scope.IndexOfName (nm);
    Result := (ix >= 0) and (roScope.IndexOf (IntToStr (ix)) >= 0);
  end;

  { the read-only storage the name was given by an assignment in this
    procedure ('a string literal (line 12)'), or '' -- Sem.ScopeRoFrom }
  function ScopeRoFrom (const nm: string): string;
  var ix : Integer; v : string;
  begin
    ix := scope.IndexOfName (nm);
    if ix < 0 then Exit ('');
    v := roFrom.Values[IntToStr (ix)];
    if v = '' then Exit ('');
    Result := Copy (v, 1, Pos ('|', v) - 1) + ' (line ' +
              Copy (v, Pos ('|', v) + 1, Length (v)) + ')';
  end;

  { is this name, HERE, a constant?  A parameter, a local or a module
    variable of the same name shadows it, as it does in the generated
    C -- the lookup that forgot that typed a parameter named like a
    module CONST as the constant (found 2026-10-01). }
  function IsConstHere (const nm: string): Boolean;
  begin
    Result := (ScopeMode (nm) = '') and (constMap.IndexOfName (nm) >= 0);
  end;

  { a FOR step that is a constant: what ScalarConst folds, or a name --
    this module's CONST, or an imported Mod.N (mirrors Sem.StepConst) }
  function StepConst (s: TNode): Boolean;
  var
    v : Int64;
    ch : Boolean;
    mi : TModuleInfo;
    j : Integer;
  begin
    if ScalarConst (s, v, ch) then Exit (not ch);
    Result := False;
    if s.kind <> nkDesignator then Exit;
    if Length (s.kids) = 0 then Exit (IsConstHere (s.a));
    if (Length (s.kids) = 1) and (s.kids[0].kind = nkSelField) then
    begin
      mi := FindMod (s.a);
      if mi = nil then Exit;
      for j := 0 to High (mi.cnNames) do
        if mi.cnNames[j] = s.kids[0].a then Exit (True);
    end;
  end;

  { ... and a constant TABLE, the value of an aggregate (par 2.2.4) }
  function IsAggConst (const nm: string): Boolean;
  begin
    Result := IsConstHere (nm) and
      StartsWithS (constMap.Values[nm], 'ARRAY ');
  end;

  { par 2.2.4: a constant table is read-only DATA, so its whole value
    goes only where nothing can write through it -- indexed, under
    LEN, or lent to an RO parameter (the call check holds that last
    one, argument by argument).  Anything else that names it bare
    would make an alias: s := Primes, SLICE (Primes, 0, 2), RETURN
    Primes. }
  procedure AggWalk (n: TNode; parent: TNodeKind);
  var i, first : Integer;
  begin
    if (n.kind = nkDesignator) and (Length (n.kids) = 0) and
       (parent <> nkArgList) and IsAggConst (n.a) then
      ErrN (n, ctx, 'the CONST table ' + n.a +
        ' can only be indexed, measured with LEN, or lent to an RO' +
        ' parameter (par 2.2.4)');
    first := 0;
    { the left side of an assignment is CheckWrite's to refuse }
    if (n.kind = nkAssign) and (n.kids[0] <> nil) and
       (Length (n.kids[0].kids) = 0) then
      first := 1;
    for i := first to High (n.kids) do
      if n.kids[i] <> nil then AggWalk (n.kids[i], n.kind);
  end;

  { name NM's storage is reachable from outside the frame via TGT.
    Append-if-absent, so target order is first-encounter order --
    the M9 checker must reproduce it, and semdiff holds both to it }
  procedure EscTarget (const nm, tgt: string);
  begin
    if escSet.IndexOf (nm + '=' + tgt) < 0 then
      escSet.Add (nm + '=' + tgt);
  end;

  procedure EscAlias (const a, b: string);
  begin
    if a = b then Exit;
    if escEdges.IndexOf (a + '=' + b) < 0 then
      escEdges.Add (a + '=' + b);
  end;

  { the frame-storage root a reference expression views: through
    SOME and parens, and through SLICE/VIEW/SHARED,
    whose answers alias their first argument's storage }
  function EscRootOf (e: TNode): string;
  var nm : string;
  begin
    Result := '';
    if e = nil then Exit;
    if e.kind = nkDesignator then Exit (e.a);
    if (e.kind = nkSomeExpr) or (e.kind = nkParen) then
      Exit (EscRootOf (e.kids[0]));
    if (e.kind = nkCallExpr) and (e.kids[0] <> nil) and
       (e.kids[0].kind = nkDesignator) and
       (Length (e.kids[0].kids) = 0) then
    begin
      nm := e.kids[0].a;
      if ((nm = 'SLICE') or (nm = 'VIEW') or (nm = 'SHARED')) and
         (e.kids[1] <> nil) and (Length (e.kids[1].kids) > 0) then
        Exit (EscRootOf (e.kids[1].kids[0]));
    end;
  end;

  { the name of the RO FIELD a designator ends at, resolved as
    CheckWrite resolves a write, or '' (Sem.RoFieldOf) }
  function RoFieldOf (d: TNode): string;
  var
    j : Integer;
    declN, res, sel : TNode;
    tmod : string;
  begin
    Result := '';
    if Length (d.kids) = 0 then Exit;
    tmod := '';
    declN := ScopeType (d.a);
    for j := 0 to High (d.kids) do
    begin
      sel := d.kids[j];
      if declN = nil then Exit;
      NoteMod (declN, tmod);
      res := ResolveType (declN);
      while (res <> nil) and (res.kind in [nkPtrType, nkSharedType]) do
      begin
        declN := InMod (res.kids[0], tmod);
        NoteMod (declN, tmod);
        res := ResolveType (declN);
      end;
      if res = nil then Exit;
      case sel.kind of
        nkSelField :
          if res.kind = nkRecordType then
          begin
            if (j = High (d.kids)) and FieldROOf (res, sel.a) then Exit (sel.a);
            declN := InMod (FieldTypeOf (res, sel.a), tmod);
          end
          else
            Exit;
        nkSelIndex :
          if res.kind = nkGridType then declN := InMod (res.kids[1], tmod)
          else if res.kind = nkSliceType then declN := InMod (res.kids[0], tmod)
          else if res.kind = nkArrayType then declN := InMod (res.kids[1], tmod)
          else Exit;
      end;
    end;
  end;

  { `the RO answer of F' when call E names a procedure whose result is
    declared RO, else '' (Sem.RoAnswerOf) }
  function RoAnswerOf (e: TNode): string;
  var pr : TProcInfo; name : string;
  begin
    Result := '';
    if (e.kids[0] = nil) or (e.kids[0].kind <> nkDesignator) then Exit;
    name := CallName (e.kids[0]);
    if not LookupProcInfo (name, pr) then Exit;
    if (pr.node <> nil) and pr.node.f3 then Result := 'the RO answer of ' + name;
  end;

  function PtrBearing (t: TNode; depth: Integer): Boolean; forward;
  function DesigPath (d: TNode): string; forward;

  { par 2.4, the copy: is the value of expression K read-only storage
    -- a string literal, what an RO parameter or an RO variable views,
    a CONST, or a name that was itself given such storage -- seen
    through SLICE, VIEW and parentheses?  Mirrors Sem.RoWhatOf. }
  function RoWhatOf (k: TNode): string;
  var r, v : string; ix : Integer;
  begin
    Result := '';
    if k = nil then Exit;
    { the empty literal holds no storage: nothing can be written
      through a slice of length 0 }
    if k.kind = nkString then
    begin
      if Length (k.a) = 0 then Exit;
      Exit ('a string literal');
    end;
    if (k.kind = nkSliceOf3) or (k.kind = nkGridOf) then
      Exit (RoWhatOf (k.kids[0]));
    if k.kind = nkCallExpr then Exit (RoAnswerOf (k));
    if (k.kind = nkDesignator) and (Length (k.kids) > 0) then
    begin
      r := RoFieldOf (k);
      if r <> '' then Exit ('the RO field ' + r);
    end;
    r := EscRootOf (k);
    if r = '' then Exit;
    if ScopeMode (r) = 'r' then Exit ('the RO parameter ' + r);
    if ScopeRo (r) then Exit ('the RO variable ' + r);
    ix := scope.IndexOfName (r);
    if ix >= 0 then
    begin
      v := roFrom.Values[IntToStr (ix)];
      if v <> '' then Exit (Copy (v, 1, Pos ('|', v) - 1));
    end;
    if IsConstHere (r) then Exit ('the CONST ' + r);
  end;

  { one pass over the assignments under K: a bare local or parameter
    of slice or grid type given read-only storage is marked with what
    it holds and where.  Mirrors Sem.RoSeedWalk. }
  function RoSeedWalk (k: TNode): Boolean;
  var
    ix, j : Integer;
    what, m, ty : string;
    lhs : TNode;
  begin
    Result := False;
    if k = nil then Exit;
    if (k.kind = nkAssign) and (k.kids[0] <> nil) then
    begin
      lhs := k.kids[0];
      if (lhs.kind = nkDesignator) and (Length (lhs.kids) = 0) then
      begin
        ix := scope.IndexOfName (lhs.a);
        if (ix >= 0) and (roFrom.Values[IntToStr (ix)] = '') then
        begin
          m := scope.ValueFromIndex[ix];
          if (m = 'l') or (m = 'p') or (m = 'v') or (m = 'o') or (m = 'm') then
          begin
            ty := CanonT (TNode (scope.Objects[ix]), 0);
            if StartsWithS (ty, 'SLICE OF') or StartsWithS (ty, 'GRID ') or
               PtrBearing (TNode (scope.Objects[ix]), 0) then
            begin
              what := RoWhatOf (k.kids[1]);
              if what <> '' then
              begin
                roFrom.Values[IntToStr (ix)] := what + '|' + IntToStr (k.line);
                Result := True;
              end;
            end;
          end;
        end;
      end;
    end;
    for j := 0 to High (k.kids) do
      if RoSeedWalk (k.kids[j]) then Result := True;
  end;

  { par 2.4, the copy (2026-10-08): a local or parameter of slice or
    grid type that an assignment anywhere in the procedure gives
    read-only storage holds it for the whole procedure -- a write
    through the name and a lend of it to a writable parameter are
    refused by CheckWrite and the call check.  Mirrors Sem.RoSeed. }
  { a FIELD of a record copy given storage that is not read-only
    (`d := c ; d.defs := NEW (...) ; d.defs[i] := ...', Rdf.CopyCtx)
    is REFRESHED: recorded as the path `d.defs'.  Mirrors
    Sem.RoFreshWalk. }
  procedure RoFreshWalk (k: TNode);
  var
    j : Integer;
    fields : Boolean;
    lhs : TNode;
  begin
    if k = nil then Exit;
    if (k.kind = nkAssign) and (k.kids[0] <> nil) then
    begin
      lhs := k.kids[0];
      if (lhs.kind = nkDesignator) and (Length (lhs.kids) > 0) and
         (ScopeRoFrom (lhs.a) <> '') then
      begin
        fields := True;
        for j := 0 to High (lhs.kids) do
          if (lhs.kids[j] = nil) or (lhs.kids[j].kind <> nkSelField) then
            fields := False;
        if fields and (RoWhatOf (k.kids[1]) = '') then
          roFresh.Add (DesigPath (lhs));
      end;
    end;
    for j := 0 to High (k.kids) do RoFreshWalk (k.kids[j]);
  end;

  { does the designator write through a refreshed field?  Mirrors
    Sem.RoRefreshed. }
  function RoRefreshed (d: TNode): Boolean;
  var
    i : Integer;
    p, f : string;
  begin
    p := DesigPath (d);
    for i := 0 to roFresh.Count - 1 do
    begin
      f := roFresh[i];
      if (Copy (p, 1, Length (f)) = f) and
         ((Length (p) = Length (f)) or (p[Length (f) + 1] = '.') or
          (p[Length (f) + 1] = '[')) then
        Exit (True);
    end;
    Result := False;
  end;

  procedure RoSeed (k: TNode);
  var n : Integer;
  begin
    n := 0;
    roFresh.Clear;
    while RoSeedWalk (k) and (n < 8) do Inc (n);
    RoFreshWalk (k);
  end;

  function IsFrameMode (const m: string): Boolean;
  begin
    Result := (m = 'l') or (m = 'b') or (m = 'p');
  end;

  { the LOCAL pool a kind names -- 'an allocation in pool P' or 'a
    view into pool P' (FrameWhat, par 4.3) -- or '' for a frame kind
    (mirrors Sem.KindPool) }
  function KindPool (const what: string): string;
  begin
    if Copy (what, 1, 22) = 'an allocation in pool ' then
      Exit (Copy (what, 23, Length (what) - 22));
    if Copy (what, 1, 17) = 'a view into pool ' then
      Exit (Copy (what, 18, Length (what) - 17));
    Result := '';
  end;

  { does this right-hand side yield a FRAME-SCOPED string (par 2.3)?
    A concatenation is one -- it is built in the frame arena -- and so
    is a bare name that already holds one (fval).  Through parens and
    SOME.  `u` is the RHS's type, so a numeric `+` (not SLICE OF CHAR)
    is not mistaken for a concatenation. }
  { what the name holds: 'a concatenation', 'a frame allocation', or
    '' when it is not tainted.  The kind rides in fval's Objects. }
  function FvalKindOf (const nm: string): string;
  var ix : Integer;
  begin
    ix := fval.IndexOf (nm);
    if ix < 0 then Exit ('');
    Result := fvalKind[ix];
  end;

  procedure FvalAdd (const nm, what: string);
  var ix : Integer;
  begin
    ix := fval.IndexOf (nm);
    { a name already tainted keeps its kind, unless the new one names
      a local pool: frame storage is re-homed or adopted at exit, a
      local pool's is freed (mirrors Sem.FvalAdd) }
    if ix >= 0 then
    begin
      if KindPool (what) <> '' then fvalKind[ix] := what;
      Exit;
    end;
    fval.Add (nm);
    fvalKind.Add (what);
  end;

  { Is this NEW the FRAME form -- `NEW (T)` or `NEW (T, n...)`, no
    pool named (docs/pool-elision-plan.md, rule 1)?  Decided by NAME:
    a first argument that is a variable in scope, HEAP, or OWN is not
    the frame form.  Quiet; NewForm is the one that diagnoses. }
  function DesigName (d: TNode): string; forward;

  function NewIsFrame (e: TNode): Boolean; forward;

  { a NEW from a named pool or an object's pool: not the frame form,
    not OWN (mirrors Sem.IsPoolNew) }
  function IsPoolNew (e: TNode): Boolean;
  begin
    Result := False;
    if (e = nil) or (e.kind <> nkNewExpr) then Exit;
    if (e.kids[0] <> nil) and (Length (e.kids[0].kids) = 0) and
       (e.kids[0].a = 'OWN') then Exit;
    Result := not NewIsFrame (e);
  end;

  { HEAP, or a name declared POOL in scope (mirrors Sem.IsPoolName) }
  function IsPoolName (const nm: string): Boolean;
  var q : TNode;
  begin
    if nm = 'HEAP' then Exit (True);
    q := ScopeType (nm);
    Result := (q <> nil) and (q.kind = nkQualident) and (q.a = 'POOL') and
              (q.b = '');
  end;

  { the pool an allocation on the right-hand side names, for the
    declared-pool check (mirrors Sem.AllocPoolOf): NEW (Q, T) with Q
    a pool in scope or HEAP, or a call whose result type promises
    `IN r` with a bare name Q handed to r; '' otherwise }
  function AllocPoolOf (e: TNode): string;
  var
    pr : TProcInfo;
    pn, rt, rn, pl, al, an : TNode;
    i, j, ix, want : Integer;
  begin
    Result := '';
    if e = nil then Exit;
    if e.kind = nkNewExpr then
    begin
      if (e.kids[0] <> nil) and (Length (e.kids[0].kids) = 0) and
         (e.kids[0].a <> 'OWN') and IsPoolName (e.kids[0].a) then
        Result := e.kids[0].a;
      Exit;
    end;
    if e.kind <> nkCallExpr then Exit;
    if (e.kids[0] = nil) or (e.kids[0].kind <> nkDesignator) then Exit;
    if not LookupProcInfo (DesigName (e.kids[0]), pr) then Exit;
    pn := pr.node;
    if pn = nil then Exit;
    rt := pn.kids[1];
    if rt = nil then Exit;
    want := -1; ix := 0;
    pl := pn.kids[0];
    if (rt.kind = nkPtrType) and (rt.kids[1] <> nil) then
    begin
      { `: PTR T IN rn': the promise names the pool }
      rn := rt.kids[1];
      if pl <> nil then
        for i := 0 to High (pl.kids) do
          if (pl.kids[i] <> nil) and (pl.kids[i].kids[0] <> nil) then
            for j := 0 to High (pl.kids[i].kids[0].kids) do
            begin
              if (pl.kids[i].kids[0].kids[j] <> nil) and
                 (pl.kids[i].kids[0].kids[j].a = rn.a) then want := ix;
              Inc (ix);
            end;
    end;
    { no promise: a procedure that takes a POOL answers in it, so a
      pointer-bearing answer lives in the first POOL argument
      (corpus/Sem.m9 says what found it, 2026-10-07) }
    if (want < 0) and PtrBearing (rt, 0) then
    begin
      ix := 0;
      if pl <> nil then
        for i := 0 to High (pl.kids) do
          if (pl.kids[i] <> nil) and (pl.kids[i].kids[0] <> nil) then
          begin
            if (want < 0) and (pl.kids[i].kids[1] <> nil) and
               (pl.kids[i].kids[1].kind = nkQualident) and
               (pl.kids[i].kids[1].a = 'POOL') and (pl.kids[i].kids[1].b = '') then
              want := ix;
            Inc (ix, Length (pl.kids[i].kids[0].kids));
          end;
    end;
    al := e.kids[1];
    if (al = nil) or (want < 0) or (want > High (al.kids)) then Exit;
    an := al.kids[want];
    if (an <> nil) and (an.kind = nkDesignator) and (Length (an.kids) = 0) and
       IsPoolName (an.a) then
      Result := an.a;
  end;

  function NewIsFrame (e: TNode): Boolean;
  begin
    if e.kids[0] = nil then Exit (True);
    if Length (e.kids[0].kids) > 0 then Exit (False);
    if (e.kids[0].a = 'OWN') or (e.kids[0].a = 'HEAP') then Exit (False);
    Result := ScopeMode (e.kids[0].a) = '';
  end;

  { what the frame-scoped value IS, for the diagnostic and the taint:
    'a concatenation', 'a frame allocation' (a NEW with no pool), or
    '' when the right-hand side is neither and holds neither }
  function DeclPool (t: TNode): TNode; forward;
  function FrameWhat (e: TNode; const u: string): string; forward;

  { the designator's component path for the taint table: the root,
    `.field' per field selector, `[]' per index (corpus/Sem.m9's
    DesigPath) }
  function DesigPath (d: TNode): string;
  var a : Integer;
  begin
    Result := d.a;
    for a := 0 to High (d.kids) do
      if d.kids[a] <> nil then
        if d.kids[a].kind = nkSelField then
          Result := Result + '.' + d.kids[a].a
        else
          Result := Result + '[]';
  end;

  { the LOCAL pool an expression's storage lives in, by its shape: the
    pool a NEW names or a call's `IN r` promise names (AllocPoolOf),
    or the IN clause of a bare name -- when that pool is a local of
    this procedure (mirrors Sem.LocalPoolOf) }
  function LocalPoolOf (e: TNode): string;
  var p : string;
  begin
    Result := '';
    p := '';
    if (e.kind = nkNewExpr) or (e.kind = nkCallExpr) then
      p := AllocPoolOf (e)
    else if (e.kind = nkDesignator) and (Length (e.kids) = 0) then
    begin
      if DeclPool (ScopeType (e.a)) <> nil then
        p := DeclPool (ScopeType (e.a)).a;
    end;
    if (p <> '') and (ScopeMode (p) = 'l') then Result := p;
  end;

  { the local pool a VIEW looks into: a callee that answers RO
    answers a view of its arguments (DynStr.View), so an argument
    whose storage is in a local pool makes the answer live there too
    (mirrors Sem.ViewedPool) }
  function ViewedPool (dn, args: TNode): string;
  var
    pr : TProcInfo;
    i : Integer;
    p : string;
  begin
    Result := '';
    if dn.kind <> nkDesignator then Exit;
    if not LookupProcInfo (DesigName (dn), pr) then Exit;
    if pr.node = nil then Exit;
    if not pr.node.f3 then Exit;
    if args = nil then Exit;
    for i := 0 to High (args.kids) do
    begin
      p := KindPool (FrameWhat (args.kids[i], ''));
      if p <> '' then Exit (p);
    end;
  end;

  { what the frame-scoped value IS: 'a concatenation', 'a frame
    allocation', 'the answer of F', 'an allocation in pool P' or 'a
    view into pool P' for a LOCAL pool P (par 4.3: dies with the
    frame as the others do, but is neither re-homed nor adopted at
    exit), or '' (mirrors Sem.FrameWhat) }
  function FrameWhat (e: TNode; const u: string): string;
  var nm, p : string;
  begin
    Result := '';
    while (e <> nil) and ((e.kind = nkParen) or (e.kind = nkSomeExpr)) do
      e := e.kids[0];
    if e = nil then Exit;
    if (e.kind = nkBin) and (e.a = '+') and (u = 'SLICE OF CHAR') then
      Exit ('a concatenation');
    if (e.kind = nkNewExpr) and NewIsFrame (e) then
      Exit ('a frame allocation');
    if (e.kind = nkCallExpr) and (e.kids[0] <> nil) then
    begin
      nm := CallAnswersFrame (e.kids[0]);
      if nm <> '' then Exit ('the answer of ' + nm);
      p := ViewedPool (e.kids[0], e.kids[1]);
      if p <> '' then Exit ('a view into pool ' + p);
    end;
    if (e.kind = nkDesignator) and (Length (e.kids) = 0) then
    begin
      nm := FvalKindOf (e.a);
      if nm <> '' then Exit (nm);
    end;
    { a component that was itself given frame storage carries it, by
      its path (corpus/Sem.m9 says why, 2026-10-03) }
    if (e.kind = nkDesignator) and (Length (e.kids) > 0) then
    begin
      nm := FvalKindOf (DesigPath (e));
      if nm <> '' then Exit (nm);
    end;
    p := LocalPoolOf (e);
    if p <> '' then Result := 'an allocation in pool ' + p;
  end;

  function FrameRHS (e: TNode; const u: string): Boolean;
  begin
    Result := FrameWhat (e, u) <> '';
  end;

  { a designator with at most one field selector as the qualident it
    spells, for the type position of a NEW; nil for anything else }
  function AsQual (d: TNode): TNode;
  begin
    Result := nil;
    if d = nil then Exit;
    if (d.kind <> nkQualident) and (d.kind <> nkDesignator) then Exit;
    if Length (d.kids) > 1 then Exit;
    Result := TNode.Create (nkQualident);
    Result.line := d.line;
    Result.col := d.col;
    Result.a := d.a;
    Result.b := d.b;
    if Length (d.kids) = 1 then
    begin
      if d.kids[0].kind <> nkSelField then Exit (nil);
      Result.b := d.kids[0].a;
    end;
  end;

  { a ref value rooted at frame storage SRC was stored into the
    designator rooted DST (dstSel: through a selector) }
  procedure EscStore (const dst: string; dstSel: Boolean; const src: string);
  var m : string;
  begin
    m := ScopeMode (dst);
    if m = 'm' then EscTarget (src, '<module>')
    else if (m = 'v') or (m = 'o') or (m = 'r') then EscTarget (src, dst)
    else if (m = 'p') and dstSel then EscTarget (src, dst)
    else if IsFrameMode (m) then EscAlias (dst, src);
  end;

  procedure CarryAdd (const nm, borrow: string);
  begin
    if carryPair.IndexOf (nm + '=' + borrow) < 0 then
      carryPair.Add (nm + '=' + borrow);
  end;

  procedure CarryEdgeAdd (const dst, src: string);
  begin
    if dst = src then Exit;
    if carryEdge.IndexOf (dst + '=' + src) < 0 then
      carryEdge.Add (dst + '=' + src);
  end;

  { a reference value rooted at SRC now also lives under the bare
    local or binder DST: a borrow is carried, a carrier's cargo is
    inherited }
  procedure CarryFrom (const dst, src: string);
  var m : string;
  begin
    m := ScopeMode (src);
    if (m = 'p') or (m = 'v') or (m = 'r') then CarryAdd (dst, src)
    else if (m = 'l') or (m = 'b') then CarryEdgeAdd (dst, src);
  end;

  function RenderTgt (const t: string): string;
  begin
    if t = '<module>' then Exit ('module state');
    if t = '<return>' then Exit ('the RETURN value');
    if t = '<call>' then Exit ('a callee');
    if t = '<unknown>' then Exit ('an unknown name');
    Result := 'the caller through ' + t;
  end;

  { classify ONE resolved store -- SRC is the borrow, CARRIER the
    local or binder it travelled through ('' when direct) -- and
    write the ledger line, the undeclared-retention error, and the
    KEPT justification }
  procedure EmitPend (ln, cl: Integer; const src, carrier, dst: string);
  var
    tl : TStringList;
    j2 : Integer;
    selfHit : Boolean;
    msg2, msgE, dmode, srcT : string;
  begin
    srcT := src;
    if carrier <> '' then
      srcT := src + ' (carried by ' + carrier + ')';
    tl := TStringList.Create; tl.CaseSensitive := True;
    dmode := ScopeMode (dst);
    if dmode = 'm' then tl.Add ('<module>')
    else if (dmode = 'v') or (dmode = 'o') or (dmode = 'r') or
            (dmode = 'p') then tl.Add (dst)
    else if (dmode = 'l') or (dmode = 'b') then
    begin
      for j2 := 0 to escSet.Count - 1 do
        if escSet.Names[j2] = dst then
          tl.Add (escSet.ValueFromIndex[j2]);
    end
    else tl.Add ('<unknown>');
    { the source among the targets is the destination escaping only
      into the borrow itself -- a tree growing through its own node
      is not a kept borrow }
    selfHit := tl.IndexOf (src) >= 0;
    if selfHit then tl.Delete (tl.IndexOf (src));
    if tl.Count = 0 then
    begin
      if selfHit then
        msg2 := 'self-store: borrowed ' + srcT + ' stored into ' +
          dst + ', which reaches the caller only through ' +
          src + ' itself (par 4.1)'
      else
        msg2 := 'frame-store: borrowed ' + srcT + ' stored into ' +
          dst + ', which never escapes the frame (par 4.1)';
    end
    else
    begin
      msg2 := '';
      for j2 := 0 to tl.Count - 1 do
      begin
        if msg2 <> '' then msg2 := msg2 + ', ';
        msg2 := msg2 + RenderTgt (tl[j2]);
      end;
      msg2 := 'retention: borrowed ' + srcT + ' stored into ' +
        dst + ' -- reaches ' + msg2 + ' (par 4.1/4.2)';
      keptUsed.Add (src);
      { the CHECK behind the measurement: a retention must be in the
        signature, the way a raise must be in RAISES.  '<call>' alone
        does not fire it -- whether a callee keeps its argument is
        that callee's declaration to make, and the caller check reads
        it there (par 4.1). }
      msgE := '';
      for j2 := 0 to tl.Count - 1 do
        if tl[j2] <> '<call>' then
        begin
          if msgE <> '' then msgE := msgE + ', ';
          msgE := msgE + RenderTgt (tl[j2]);
        end;
      if (msgE <> '') and (keptParams.IndexOfName (src) < 0) then
        Errors.Add (Format (
          '%d:%d %s: undeclared retention: borrowed %s reaches %s' +
          ' -- declare KEPT %s (par 4.1)',
          [ln, cl, ctx, srcT, msgE, src]));
    end;
    Ledger.Add (Format ('%d:%d %s: %s', [ln, cl, ctx, msg2]));
    tl.Free;
  end;

  { ---- P3 pass 2: owned-pointer state (par 4.2) ----
    Tracked: locals and OWN params of type PTR T (no IN -- the pool
    owns those) and SHARED PTR T.  Absent from ownState = alive.
    Flow is per-procedure: branches merge conservatively (moved in
    any arm counts as moved after the join); loop-carried moves are
    not yet detected -- pass 3.                                      }

  function OwnedCandKind (const nm: string): Integer;
  var
    mode : string;
    res : TNode;
  begin
    Result := 0;
    mode := ScopeMode (nm);
    if (mode <> 'l') and (mode <> 'o') then Exit;
    res := ResolveType (ScopeType (nm));
    if res = nil then Exit;
    if (res.kind = nkPtrType) and (res.kids[1] = nil) then Exit (1);
    if res.kind = nkSharedType then Exit (2);
  end;

  procedure NoteUse (d: TNode);
  var
    ix : Integer;
    v : string;
  begin
    ix := ownState.IndexOfName (d.a);
    if ix < 0 then Exit;
    v := ownState.ValueFromIndex[ix];
    if v <> 'alive' then
      ErrN (d, ctx, 'use of ' + d.a + ' after it was ' + v +
        ' (par 4.2)');
  end;

  procedure OwnMark (const nm, what: string; site: TNode);
  begin
    ownState.Values[nm] := what + ' at line ' + IntToStr (site.line);
  end;

  procedure OwnAlive (const nm: string);
  begin
    if ownState.IndexOfName (nm) >= 0 then
      ownState.Values[nm] := 'alive';
  end;

  function OwnSnap : string;
  begin
    Result := ownState.Text;
  end;

  procedure OwnRestore (const s: string);
  begin
    ownState.Text := s;
  end;

  { adopt every move recorded in snapshot s: moved in any merged
    path means moved after the join }
  procedure OwnMergeMoves (const s: string);
  var
    tmp : TStringList;
    i2, ix : Integer;
    nm, v : string;
  begin
    tmp := TStringList.Create; tmp.CaseSensitive := True;
    tmp.Text := s;
    for i2 := 0 to tmp.Count - 1 do
    begin
      nm := tmp.Names[i2];
      v := tmp.ValueFromIndex[i2];
      if v <> 'alive' then
      begin
        ix := ownState.IndexOfName (nm);
        if (ix < 0) or (ownState.ValueFromIndex[ix] = 'alive') then
          ownState.Values[nm] := v;
      end;
    end;
    tmp.Free;
  end;

  function StripParens (e: TNode): TNode;
  begin
    Result := e;
    while (Result <> nil) and (Result.kind = nkParen) do
      Result := Result.kids[0];
  end;

  function DesigName (d: TNode): string;
  { the dotted callee name: `P', `Mod.P', `Type.Variant', and -- since
    2026-09-15 -- `Mod.Type.Variant', the three-part imported variant
    constructor.  Every field selector joins; a call target is only
    ever one of these shapes, because F(x).field does not parse and a
    field chain cannot be called.  A leading index or deref stops it. }
  var i : Integer;
  begin
    Result := d.a;
    for i := 0 to High (d.kids) do
      if d.kids[i].kind = nkSelField then
        Result := Result + '.' + d.kids[i].a
      else
        Exit (d.a);
  end;

  function ExprType (e: TNode): string; forward;

  { The four spellings of NEW, told apart by NAME (par 10, item 6):

      NEW (T)             the frame, one T          (par 4.3)
      NEW (T, n ...)      the frame, a slice or a grid
      NEW (pool, T ...)   the named pool, as it always was
      NEW (OWN, T)        one owned T: DISPOSE, SHARED, THREAD (par 4.2)

    Answers 'frame', 'pool' or 'own', or '' after diagnosing.  ty is
    the type's node and ext0 the index of the first extent, whose kid
    is nil when there is none.  Mirrors Sem.NewForm. }
  { can a value of this type carry a pointer?  Gen.HasPtr's twin;
    mirrors Sem.PtrBearing }
  function PtrBearing (t: TNode; depth: Integer): Boolean;
  var
    r, fs, g, arm, afs, ag : TNode;
    i, j : Integer;
  begin
    Result := False;
    if depth > 8 then Exit;
    r := ResolveType (t);
    if r = nil then Exit;
    case r.kind of
      nkPtrType, nkSliceType, nkGridType : Result := True;
      nkOptType : Result := PtrBearing (r.kids[0], depth + 1);
      nkArrayType : Result := PtrBearing (r.kids[1], depth + 1);
      nkRecordType, nkMonitorType :
        begin
          if r.kind = nkMonitorType then fs := r.kids[0] else fs := r.kids[1];
          if fs = nil then Exit;
          for i := 0 to High (fs.kids) do
          begin
            g := fs.kids[i];
            if (g <> nil) and PtrBearing (g.kids[1], depth + 1) then
              Exit (True);
          end;
        end;
      nkCaseRecordType :
        for i := 0 to High (r.kids) do
        begin
          arm := r.kids[i];
          if arm = nil then continue;
          afs := arm.kids[0];
          if afs = nil then continue;
          for j := 0 to High (afs.kids) do
          begin
            ag := afs.kids[j];
            if (ag <> nil) and PtrBearing (ag.kids[1], depth + 1) then
              Exit (True);
          end;
        end;
    end;
  end;

  { does a VAR parameter of this type carry its object's pool as a
    hidden argument (docs/pool-elision-plan.md, rule 2)?  Mirrors
    Sem.PtrParamTy: PTR and OPT PTR by node kind, a pointer-bearing
    record, monitor, array or variant by resolution, never a bare
    slice or grid. }
  function PtrParamTy (t: TNode): Boolean;
  var r : TNode;
  begin
    Result := False;
    if t = nil then Exit;
    if t.kind = nkPtrType then Exit (True);
    if t.kind = nkOptType then
      Exit ((t.kids[0] <> nil) and (t.kids[0].kind = nkPtrType));
    if t.kind in [nkSliceType, nkGridType] then Exit;
    r := ResolveType (t);
    if r = nil then Exit;
    { a name for a pointer is the pointer it names (mirrors Sem) }
    if r.kind = nkPtrType then Exit (True);
    if r.kind = nkOptType then
      Exit ((r.kids[0] <> nil) and (r.kids[0].kind = nkPtrType));
    if r.kind in [nkRecordType, nkMonitorType, nkArrayType, nkCaseRecordType] then
      Result := PtrBearing (t, 0);
  end;

  { the pool a declared type names: the IN clause of `PTR T IN p` or
    `OPT PTR T IN p`, through a type name; nil for anything else }
  function DeclPool (t: TNode): TNode;
  var r : TNode;
  begin
    Result := nil;
    r := ResolveType (t);
    if r = nil then Exit;
    if r.kind = nkOptType then Exit (DeclPool (r.kids[0]));
    if r.kind = nkPtrType then Result := r.kids[1];
  end;

  { the pool of the object a designator names, as a call handing the
    object to a VAR pointer parameter needs it (rule 2): '' when the
    generator can name it from the ROOT, else why not.  Mirrors
    Sem.ObjPoolIssue. }
  function ObjPoolIssue (a: TNode): string;
  var
    m : string;
    res : TNode;
  begin
    m := ScopeMode (a.a);
    if m = 'v' then
    begin
      if PtrParamTy (ScopeType (a.a)) then Exit ('');
      Exit ('VAR parameter ' + a.a + ' carries no pool');
    end
    else if m = 'o' then
      Exit (a.a + ' is an OWN parameter')
    else if (m = 'p') or (m = 'r') then
    begin
      res := ResolveType (ScopeType (a.a));
      if (Length (a.kids) = 0) and (res <> nil) and (res.kind = nkPtrType) then
        Exit ('');
      Exit (a.a + ' is a value parameter');
    end;
    Result := '';
  end;

  { a name a KNOWN module does not declare, a type nobody declares in
    a NEW, a bare name on the left of `:=' declared nowhere: typos,
    said with the generator's wording (corpus/Sem.m9 says what found
    each, 2026-10-08) }
  function ModHasName (const modName, nm: string): Boolean;
  var
    m : TModuleInfo;
    pr : TProcInfo;
    j : Integer;
  begin
    Result := True;
    m := FindMod (modName);
    if m = nil then Exit;
    if m.foreignLang <> '' then Exit;
    if m.FindType (nm) <> nil then Exit;
    if InList (nm, m.opaque) then Exit;
    if LookupProcInfo (modName + '.' + nm, pr) then Exit;
    for j := 0 to High (m.cnNames) do
      if m.cnNames[j] = nm then Exit;
    if ExcKnown (modName, nm) then Exit;
    for j := 0 to High (m.vrNames) do
      if m.vrNames[j] = nm then Exit;
    Result := False;
  end;

  function UnknownNewType (ty, e: TNode): Boolean;
  var q : TNode;
  begin
    Result := False;
    q := AsQual (ty);
    if q = nil then Exit;
    if q.b = '' then
    begin
      if CanonT (q, 0) = '' then
      begin
        ErrN (e, ctx, 'unknown type: ' + q.a);
        Result := True;
      end;
    end
    else if not TypeKnown (q.a, q.b) then
    begin
      ErrN (e, ctx, 'unknown type: ' + q.a + '.' + q.b + ' -- ' + q.a +
        ' declares no such type');
      Result := True;
    end;
  end;

  function NewForm (e: TNode; out ty: TNode; out ext0: Integer): string;
  var
    t : string;
    isVar : Boolean;
    d : TNode;
  begin
    ty := nil;
    ext0 := 2;
    Result := '';
    d := e.kids[0];
    if d <> nil then
    begin
      if (Length (d.kids) = 0) and (d.a = 'OWN') then
      begin
        ty := e.kids[1];
        if e.kids[2] <> nil then
        begin
          ErrN (e, ctx, 'NEW (OWN, T) allocates one object; a slice lives in a pool or in the frame');
          Exit ('');
        end;
        if UnknownNewType (ty, e) then Exit ('');
        Exit ('own');
      end;
      isVar := True;
      if Length (d.kids) = 0 then
      begin
        if (ScopeMode (d.a) = '') and (d.a <> 'HEAP') then isVar := False;
      end
      else if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
      begin
        if (ScopeMode (d.a) = '') and (FindMod (d.a) <> nil) then
          isVar := False;
      end;
      if isVar and (Length (d.kids) = 0) and (ScopeMode (d.a) = 'v') and
         PtrParamTy (ScopeType (d.a)) then
      begin
        { `NEW (d, T)`: the pool d's object lives in, carried in by
          rule 2 -- how a VAR pointer parameter grows its object }
        ty := AsQual (e.kids[1]);
        if ty <> nil then
        begin
          if UnknownNewType (ty, e) then Exit ('');
          Exit ('pool');
        end;
        ErrN (e, ctx, 'NEW needs a type name after the pool');
        Exit ('');
      end;
      if isVar then
      begin
        t := ExprType (e.kids[0]);
        if (t <> '') and (t <> 'POOL') then
        begin
          ErrN (e, ctx, 'NEW''s first argument is the pool, not ' +
            TyName (t));
          Exit ('');
        end;
        ty := AsQual (e.kids[1]);
        if ty <> nil then
        begin
          if UnknownNewType (ty, e) then Exit ('');
          Exit ('pool');
        end;
        ErrN (e, ctx, 'NEW needs a type name after the pool');
        Exit ('');
      end;
      { a type name, so the frame form with extents }
      ty := AsQual (e.kids[0]);
      if (ty <> nil) and (CanonT (ty, 0) = '') then
      begin
        t := ExprType (e.kids[0]);   { says `unknown name` }
        Exit ('');
      end;
      ext0 := 1;
      Exit ('frame');
    end;
    ty := e.kids[1];
    Result := 'frame';
  end;

  function CT (t: TNode): string;
  begin
    Result := CanonT (t, 0);
  end;

  function IsIntish (const s: string): Boolean;
  begin
    Result := (s = '') or (s = '<int>') or IsIntStr (s);
  end;

  { THE LOOP VARIABLE IS A VARIABLE: declared, of a type its bounds
    can count in, and of that type inside the loop.  Until 2026-10-02
    FOR bound the name afresh -- as an I64 here, with no type at all
    in Sem.m9 -- over whatever had been declared, so both checkers
    accepted a loop variable nobody declared, or one declared F64,
    and Sem.m9 passed over every use of every loop variable.
      bound -- the bounds' type when they are an enumeration's
      enum  -- whether they are }
  { a FOR inside a FOR over the SAME control variable (mirrors Sem's
    NFor arm, cp-kernel's issue 3, 2026-10-09) }
  procedure CheckForNest (st: TNode);
  var j : Integer;
  begin
    for j := 0 to High (forNames) do
      if forNames[j] = st.a then
        ErrN (st, ctx, 'FOR variable ' + st.a +
          ' is the control variable of the enclosing FOR at line ' +
          IntToStr (forLines[j]) + ' (par 2.1)');
  end;
  procedure ForPush (st: TNode);
  begin
    SetLength (forNames, Length (forNames) + 1);
    SetLength (forLines, Length (forLines) + 1);
    forNames[High (forNames)] := st.a;
    forLines[High (forLines)] := st.line;
  end;
  procedure ForPop;
  begin
    SetLength (forNames, Length (forNames) - 1);
    SetLength (forLines, Length (forLines) - 1);
  end;
  procedure CheckForVar (st: TNode; const bound: string; enum: Boolean);
  var vt : string;
  begin
    if ScopeMode (st.a) = '' then
    begin
      ErrN (st, ctx, 'FOR variable ' + st.a + ' is not declared');
      { bound without a type, so that its uses say nothing more }
      BindName (st.a, nil);
    end
    else
    begin
      vt := CT (ScopeType (st.a));
      if vt <> '' then
      begin
        if enum then
        begin
          if (bound <> '') and (vt <> bound) then
            ErrN (st, ctx, 'FOR variable ' + st.a + ' is ' + TyName (vt) +
              ', and its bounds are ' + TyName (bound));
        end
        else if not IsIntStr (vt) then
          ErrN (st, ctx, 'FOR variable ' + st.a + ' is ' + TyName (vt) +
            ': a loop over integers counts in an integer variable');
      end;
    end;
  end;

  { the canonical enumeration (or case-record) type an ARRAY bound
    names, or '' when the bound is an integer.  ARRAY Colour OF T is
    indexed by the type: its subscript is a member, not an ordinal, so
    the index check wants the enumeration here (docs/enum-plan.md
    part 2). }
  function ArrEnumBoundOf (declN: TNode): string;
  var r, b : TNode; canon : string;
  begin
    Result := '';
    r := ResolveType (declN);
    if (r = nil) or (r.kind <> nkArrayType) then Exit;
    b := r.kids[0];
    if (b = nil) or (b.kind <> nkDesignator) then Exit;
    canon := '';
    if Length (b.kids) = 0 then canon := CanonQual ('', b.a, 0)
    else if (Length (b.kids) = 1) and (b.kids[0].kind = nkSelField) then
      canon := CanonQual (b.a, b.kids[0].a, 0);
    if IsTagged (canon) then Result := canon;
  end;

  { the designator walk over DECLARED type nodes; guard mode is the
    operand of IS, where the final OPT component is legal.  Errors
    fire only when a selector is applied THROUGH an OPT or CASE
    RECORD component; the walk goes soft (nil) on anything unknown. }
  { the selectors of d from kid FROM on, walked from the type START
    (mirrors Sem.SelWalk): a designator's from its name, a call's
    answer -- F (x).f, nkCallSel -- from the callee's declared result }
  function SelWalk (d: TNode; guard: Boolean; start: TNode;
                    from: Integer): TNode;
  var
    j, k : Integer;
    declN, res, f : TNode;
    sel : TNode;
    it, eb, tmod : string;
  begin
    tmod := '';
    declN := start;
    for j := from to High (d.kids) do
    begin
      sel := d.kids[j];
      if sel.kind = nkSelIndex then
      begin
        eb := ArrEnumBoundOf (declN);
        if eb <> '' then
        begin
          { ARRAY Colour OF T: the one subscript is a Colour value }
          if Length (sel.kids) >= 1 then
          begin
            it := ExprType (sel.kids[0]);
            if (it <> '') and (it <> eb) then
              ErrN (d, ctx, 'an ARRAY ' + TyName (eb) + ' OF is indexed by a '
                + TyName (eb) + ' value, not ' + TyName (it));
          end;
        end
        else
          { every axis, not just the first: a grid subscript list is as
            long as the rank and each one of them is an index }
          for k := 0 to High (sel.kids) do
          begin
            it := ExprType (sel.kids[k]);
            if not IsIntish (it) then
              ErrN (d, ctx, 'index must be an integer, not ' + TyName (it));
          end;
      end;
      if declN = nil then Continue;
      NoteMod (declN, tmod);
      res := ResolveType (declN);
      { auto-deref before applying the selector }
      while (res <> nil) and (res.kind in [nkPtrType, nkSharedType]) do
      begin
        declN := InMod (res.kids[0], tmod);
        NoteMod (declN, tmod);
        res := ResolveType (declN);
      end;
      if res = nil then begin declN := nil; Continue; end;
      if res.kind = nkOptType then
      begin
        if not guard then
          ErrN (d, ctx,
            'OPT value used without IS SOME guard: ' + d.a);
        Exit (nil);
      end;
      if res.kind = nkCaseRecordType then
      begin
        if not guard then
          ErrN (d, ctx,
            'CASE RECORD is reached by CASE, not by selection: ' + d.a);
        Exit (nil);
      end;
      case sel.kind of
        nkSelField :
          if res.kind = nkRecordType then
          begin
            f := InMod (FieldTypeOf (res, sel.a), tmod);
            if (f = nil) and (res.kids[0] = nil) then
              ErrN (d, ctx,
                'no field ' + sel.a + ' in the record type of ' + d.a);
            declN := f;
          end
          else if res.kind = nkMonitorType then
          begin
            { par 6: a monitor's fields are reachable only through the
              procedure bound to it, and the binding is the FIRST
              parameter because M9 has no method syntax.  So the
              monitor must be named by that parameter, bare: `w.next`
              inside `Claim (VAR w: Work)` is the binding, while
              `j.w.next` reaches past it and a second monitor
              parameter is a different lock. }
            if (boundMon = '') or (d.a <> boundMon) or (j <> from) then
              ErrN (d, ctx, 'monitor field ' + sel.a + ' is reached ' +
                'from outside a procedure bound to the monitor (par 6)');
            declN := InMod (FieldSeqType (res.kids[0], sel.a), tmod);
          end
          else
            declN := nil;
        nkSelIndex :
          if res.kind = nkGridType then
          begin
            { the check Mat.Get could not make: one subscript per
              axis, counted against the rank in the type }
            if Length (sel.kids) <> StrToIntDef (ExprText (res.kids[0]), -1) then
              ErrN (d, ctx, 'a GRID ' + ExprText (res.kids[0]) +
                ' needs ' + ExprText (res.kids[0]) + ' subscripts, not ' +
                IntToStr (Length (sel.kids)));
            declN := InMod (res.kids[1], tmod);
          end
          else if res.kind = nkSliceType then
          begin
            if Length (sel.kids) <> 1 then
              ErrN (d, ctx, 'a slice takes one subscript, not ' +
                IntToStr (Length (sel.kids)));
            declN := InMod (res.kids[0], tmod);
          end
          else if res.kind = nkArrayType then
          begin
            if Length (sel.kids) <> 1 then
              ErrN (d, ctx, 'an array takes one subscript, not ' +
                IntToStr (Length (sel.kids)));
            declN := InMod (res.kids[1], tmod);
          end
          else
            declN := nil;
      end;
      { the typed tree: what this selector reaches, qualified where it
        was declared, for the generator to read (M9AST.SetType) }
      SetType (sel, declN);
    end;
    Result := declN;
  end;

  function DesigDeclType (d: TNode; guard: Boolean): TNode;
  begin
    Result := SelWalk (d, guard, ScopeType (d.a), 0);
  end;

  { the declared result type of the procedure a call names, qualified
    in the callee's module; nil for a call through a procedure value
    or a callee the checker does not know (mirrors Sem.CallResultNode) }
  function CallResultNode (ce: TNode): TNode;
  var pr : TProcInfo;
  begin
    Result := nil;
    if (ce = nil) or (ce.kind <> nkCallExpr) or (ce.kids[0] = nil) then Exit;
    if not LookupProcInfo (DesigName (ce.kids[0]), pr) then Exit;
    if (pr.node = nil) or (Length (pr.node.kids) < 2) or
       (pr.node.kids[1] = nil) then Exit;
    Result := InMod (pr.node.kids[1], pr.modName);
  end;

  { a designator as an expression: module CONSTs and payload-less
    variant constructors (Type.Variant) included }
  { is a BARE name one the checker knows -- in scope (any mode,
    including a nil-typed IS SOME binder), a local/impl CONST, a
    def-module CONST referenced across the pair, a predeclared
    identifier, a builtin or user type name, or a module?  If none
    of these, it is undefined, not merely unknown-typed. }
  function BareNameKnown (const nm: string): Boolean;
  var mi2, j2 : Integer;
  begin
    Result := True;
    if ScopeMode (nm) <> '' then Exit;
    if constMap.IndexOfName (nm) >= 0 then Exit;
    if (nm = 'ALL') or (nm = 'HEAP') then Exit;
    if InList (nm, BuiltinTypes) then Exit;
    if FindMod (nm) <> nil then Exit;          { a module name }
    for mi2 := 0 to High (mods) do
    begin
      if mods[mi2].FindType (nm) <> nil then Exit;   { a user type }
      for j2 := 0 to High (mods[mi2].cnNames) do      { a module CONST }
        if mods[mi2].cnNames[j2] = nm then Exit;
    end;
    Result := False;
  end;

  function DesigStrType (d: TNode; guard: Boolean): string;
  var
    ci, j : Integer;
    s, om, it : string;
    sel, fn : TNode;
    mi : TModuleInfo;
  begin
    if ScopeType (d.a) = nil then
    begin
      { ALL is a predeclared identifier, not a keyword -- the same
        decision STR got, and for the same reason: the lexer, the
        keyword table and the grammar stay untouched.  It has a type
        of its own so that using it anywhere but a VIEW axis is a
        type error naming ALL rather than an unknown name. }
      if (d.a = 'ALL') and (Length (d.kids) = 0) then Exit ('<all>');
      { HEAP, the same way: a predeclared POOL that outlives the
        program's frames and is never freed.  Named rather than
        implicit, so `PTR T IN HEAP` still says which pool, and so a
        program that must not grow can grep for it (par 4.3). }
      if (d.a = 'HEAP') and (Length (d.kids) = 0) then Exit ('POOL');
      ci := constMap.IndexOfName (d.a);
      if (ci >= 0) and (ScopeMode (d.a) = '') then
      begin
        s := constMap.ValueFromIndex[ci];
        for j := 0 to High (d.kids) do
        begin
          sel := d.kids[j];
          if sel.kind = nkSelIndex then
          begin
            it := ExprType (sel.kids[0]);
            if not IsIntish (it) then
              ErrN (d, ctx,
                'index must be an integer, not ' + TyName (it));
            if s = 'SLICE OF CHAR' then s := 'CHAR'
            else if StartsWithS (s, 'ARRAY ') then s := ElemOfArray (s)
            else s := '';
          end
          else if sel.kind = nkSelField then
            { a field of a record CONST, or of a table's record element }
            s := ConstFieldType (s, sel.a)
          else
            s := '';
        end;
        Exit (s);
      end;
      if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) and
         FindVariant (d.a, d.kids[0].a, om, fn) then
        Exit (om + '.' + d.a);
      { Mod.Type.Variant with no payload: the cross-module twin of the
        two-part form, Palette.Hue.Warm.  d.a is a module (not in
        scope, or ScopeType would not be nil), the first selector its
        enumeration or case-record type, the second a member.  Typing
        it is what lets FOR over an imported enumeration reach the enum
        branch instead of the integer path (docs/enum-plan.md part 2). }
      if (Length (d.kids) = 2) and (d.kids[0].kind = nkSelField) and
         (d.kids[1].kind = nkSelField) and
         VariantIn (d.a, d.kids[0].a, d.kids[1].a, om, fn) then
        Exit (om + '.' + d.kids[0].a);
      { an imported CONST is still a literal }
      if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
      begin
        mi := FindMod (d.a);
        if mi <> nil then
          for j := 0 to High (mi.cnNames) do
            if mi.cnNames[j] = d.kids[0].a then Exit (mi.cnTypes[j]);
      end;
    end;
    Result := CT (DesigDeclType (d, guard));
  end;

  { P3 pass 1: is this assignment target legal to write, and does
    the write land beyond the current frame?  A value parameter of
    pointer type is a shared read-only borrow (par 4.1): writing
    through it is an error.  A [RO] slice never accepts a
    write.  Returns True when the write dereferences a pointer or
    lands in slice storage -- i.e. outlives the frame.               }
  function CheckWrite0 (d: TNode): Boolean; forward;

  { a write THROUGH a name given read-only storage (RoSeed) is refused
    exactly when it lands beyond the frame (Sem.CheckWrite) }
  function CheckWrite (d: TNode): Boolean;
  begin
    Result := CheckWrite0 (d);
    if Result and (ScopeRoFrom (d.a) <> '') and not RoRefreshed (d) then
      ErrN (d, ctx, 'cannot write through ' + d.a + ', which holds ' +
        ScopeRoFrom (d.a) + ' (par 2.4)');
  end;

  function CheckWrite0 (d: TNode): Boolean;
  var
    j : Integer;
    declN, res : TNode;
    sel : TNode;
    mode, tmod : string;
  begin
    Result := False;
    if IsConstHere (d.a) then
      ErrN (d, ctx, 'cannot write the CONST ' + d.a);
    { RO measurement: a VAR parameter written through is a real
      mutator; one never written (nor re-lent, see the call check)
      is a read-only borrow wearing VAR because M9 has no other
      non-copying mode }
    if varParams.IndexOf (d.a) >= 0 then varWritten.Add (d.a);
    { RO is a read-only borrow whatever the type: unlike the old
      slice-only attribute, this bites for records and arrays too }
    if ScopeMode (d.a) = 'r' then
      ErrN (d, ctx, 'cannot write through the RO parameter ' + d.a +
        ' (par 4.1)');
    { a `VAR RO' variable: a new view yes, a write through it no }
    if (Length (d.kids) > 0) and ScopeRo (d.a) then
      ErrN (d, ctx, 'cannot write through the RO variable ' + d.a +
        ' (par 2.4)');
    { par 3.2: a PURE procedure has no observable effect, so the two
      ways a body can be observed from outside its own frame are
      refused -- writing through a caller's binding, and writing the
      module's state.  Writing a local or a value parameter is
      invisible to everyone and stays legal. }
    if curPure then
    begin
      if (ScopeMode (d.a) = 'v') or (ScopeMode (d.a) = 'o') then
        ErrN (d, ctx, 'cannot write through the VAR parameter ' + d.a +
          ' in a PURE procedure (par 3.2)')
      else if ScopeMode (d.a) = 'm' then
        ErrN (d, ctx, 'cannot write the module variable ' + d.a +
          ' in a PURE procedure (par 3.2)');
    end;
    if Length (d.kids) = 0 then Exit;
    mode := ScopeMode (d.a);
    tmod := '';
    declN := ScopeType (d.a);
    for j := 0 to High (d.kids) do
    begin
      sel := d.kids[j];
      if declN = nil then Exit;
      NoteMod (declN, tmod);
      res := ResolveType (declN);
      while (res <> nil) and (res.kind in [nkPtrType, nkSharedType]) do
      begin
        if not Result then
        begin
          Result := True;
          if mode = 'p' then
            ErrN (d, ctx, 'cannot write through a value parameter: ' +
              d.a + ' is a shared borrow (take VAR, par 4.1)');
        end;
        declN := InMod (res.kids[0], tmod);
        NoteMod (declN, tmod);
        res := ResolveType (declN);
      end;
      if res = nil then Exit;
      case sel.kind of
        nkSelField :
          { RO on a FIELD annotates the view, not the slot: the field
            holds a borrowed slice, so writing THROUGH it is refused
            while assigning the field itself -- which is how the
            record gets filled at all -- stays legal.  C says the
            same thing with `const char *p`.  On a PARAMETER, RO
            forbids both, as Ada's `in` does: there is no
            construction step to make room for. }
          if res.kind = nkRecordType then
          begin
            if (j < High (d.kids)) and FieldROOf (res, sel.a) then
              ErrN (d, ctx, 'cannot write through the RO field ' +
                sel.a + ' (par 4.1)');
            declN := InMod (FieldTypeOf (res, sel.a), tmod);
          end
          else if res.kind = nkMonitorType then
          begin
            if (j < High (d.kids)) and FieldSeqRO (res.kids[0], sel.a) then
              ErrN (d, ctx, 'cannot write through the RO field ' +
                sel.a + ' (par 4.1)');
            declN := InMod (FieldSeqType (res.kids[0], sel.a), tmod);
          end
          else
            Exit;
        nkSelIndex :
          if res.kind = nkSliceType then
          begin
            { the attribute sits on the slice when written longhand and
              on the name when written STR [RO]: both bite }
            if IsReadonlyT (declN, res) then
              ErrN (d, ctx,
                'cannot write through a read-only slice: ' + d.a);
            Result := True;      { slice storage outlives the frame }
            declN := InMod (res.kids[0], tmod);
          end
          else if res.kind = nkGridType then
          begin
            if IsReadonlyT (declN, res) then
              ErrN (d, ctx,
                'cannot write through a read-only grid: ' + d.a);
            Result := True;      { grid storage outlives the frame }
            declN := InMod (res.kids[1], tmod);
          end
          else if res.kind = nkArrayType then
            declN := InMod (res.kids[1], tmod)
          else
            Exit;
      end;
    end;
  end;

  { the base name a stored reference is borrowed from, if the source
    is a plain designator (possibly under SOME/parens) }
  function IsRefTy (const s0: string): Boolean;
  var s : string;
  begin
    s := s0;
    if StartsWithS (s, 'OPT ') then s := Copy (s, 5, MaxInt);
    Result := StartsWithS (s, 'PTR ') or StartsWithS (s, 'SHARED PTR ') or
              StartsWithS (s, 'SLICE OF ');
  end;

  { does a value of canonical type U carry a reference: a pointer or
    slice itself (IsRefTy), or a record, case record, array or OPT
    that holds one by resolution (PtrBearing)?  Mirrors Sem.TyBearing. }
  function TyBearing (const u: string): Boolean;
  var dot : Integer; t : TNode;
  begin
    if IsRefTy (u) then Exit (True);
    Result := False;
    dot := Pos ('.', u);
    if dot = 0 then Exit;
    if Pos (' ', u) > 0 then Exit;
    if FindMod (Copy (u, 1, dot - 1)) = nil then Exit;
    t := LookupTypeName (Copy (u, 1, dot - 1), Copy (u, dot + 1, MaxInt));
    if t = nil then Exit;
    Result := PtrBearing (t, 0);
  end;

  { one reference-valued source stored by an assignment: pended when
    the destination outlives the frame, carried by a local or binder,
    an escape fact when rooted in frame storage.  Mirrors Sem.StoreRef. }
  procedure StoreRef (st, lhs: TNode; const vname: string; beyond: Boolean;
                      const lhsMode: string);
  var m : string;
  begin
    m := ScopeMode (vname);
    if ((m = 'p') or (m = 'v') or (m = 'r') or (m = 'l') or (m = 'b')) and
       (beyond or (lhsMode = 'm') or
        ((lhsMode = 'v') and (Length (lhs.kids) > 0))) then
    begin
      SetLength (pendLn, pendN + 1); SetLength (pendCl, pendN + 1);
      SetLength (pendSrc, pendN + 1); SetLength (pendDst, pendN + 1);
      pendLn[pendN] := st.line; pendCl[pendN] := st.col;
      pendSrc[pendN] := vname; pendDst[pendN] := lhs.a;
      Inc (pendN);
    end;
    if (lhsMode = 'l') or (lhsMode = 'b') then CarryFrom (lhs.a, vname);
    if IsFrameMode (m) then EscStore (lhs.a, Length (lhs.kids) > 0, vname);
  end;

  { the fields, flattened, of the variant or record a call CONSTRUCTS
    -- `Data.F64s (v, miss)', `Mod.T.Arm (...)', `Row (a, b)' -- and
    their module in OM; False when the call constructs nothing.
    Mirrors Sem.CtorFields. }
  function CtorFlat (e: TNode; out om: string; out flat: TNodeArr): Boolean;
  var
    dn, fields, rn : TNode;
    name, t, canon : string;
    dot, g, j : Integer;
    isVar : Boolean;
  begin
    Result := False;
    SetLength (flat, 0);
    om := '';
    if (e = nil) or (e.kind <> nkCallExpr) then Exit;
    dn := e.kids[0];
    if (dn = nil) or (dn.kind <> nkDesignator) then Exit;
    name := DesigName (dn);
    dot := Pos ('.', name);
    isVar := False;
    fields := nil;
    if dot > 0 then
    begin
      t := Copy (name, dot + 1, MaxInt);
      g := Pos ('.', t);
      if g > 0 then
      begin
        om := Copy (name, 1, dot - 1);
        isVar := VariantIn (om, Copy (t, 1, g - 1), Copy (t, g + 1, MaxInt),
                            om, fields);
      end
      else
        isVar := FindVariant (Copy (name, 1, dot - 1), t, om, fields);
    end;
    if not isVar then
    begin
      rn := RecordNamed (name, om, canon);
      if rn = nil then Exit;
      fields := rn.kids[1];
    end;
    if fields <> nil then
      for g := 0 to High (fields.kids) do
        for j := 0 to High (fields.kids[g].kids[0].kids) do
        begin
          SetLength (flat, Length (flat) + 1);
          flat[High (flat)] := fields.kids[g].kids[1];
        end;
    Result := True;
  end;

  { the borrows a CONSTRUCTOR on the right-hand side wraps, each
    stored as the borrow itself would be.  Mirrors the loop in
    Sem.CheckAssign. }
  procedure CtorStores (st: TNode; beyond: Boolean; const lhsMode: string);
  var
    e, al : TNode;
    om, fty, vname, sv : string;
    k : Integer;
    flat : TNodeArr;
  begin
    e := st.kids[1];
    if not CtorFlat (e, om, flat) then Exit;
    al := e.kids[1];
    if al = nil then Exit;
    for k := 0 to High (al.kids) do
      if k <= High (flat) then
      begin
        sv := canonCtx;
        canonCtx := om;
        fty := CanonT (flat[k], 0);
        canonCtx := sv;
        vname := EscRootOf (al.kids[k]);
        if (vname <> '') and TyBearing (fty) and
           not StartsWithS (fty, 'SHARED PTR ') and
           not StartsWithS (fty, 'OPT SHARED PTR ') then
          StoreRef (st, st.kids[0], vname, beyond, lhsMode);
      end;
  end;

  { par 4.1, one root handed to a KEPT parameter -- Sem.KeptRoot }
  procedure KeptRoot (site: TNode; const ctx, name: string; k: Integer;
                      const aroot: string);
  var amode : string;
  begin
    amode := ScopeMode (aroot);
    if (amode = 'p') or (amode = 'v') or (amode = 'r') then
    begin
      keptUsed.Add (aroot);
      if keptParams.IndexOfName (aroot) < 0 then
        ErrN (site, ctx, Format (
          'argument %d of %s: borrowed %s is kept by the' +
          ' callee -- declare KEPT %s (par 4.1)',
          [k + 1, name, aroot, aroot]));
    end;
    if IsFrameMode (amode) then
      EscTarget (aroot, '<call>');
  end;

  { does this designator's declared base type resolve to a pointer? }
  function BaseIsPtr (d: TNode): Boolean;
  var res : TNode;
  begin
    res := ResolveType (ScopeType (d.a));
    Result := (res <> nil) and (res.kind in [nkPtrType, nkSharedType]);
  end;

  function CountParams (pl: TNode): Integer;
  var a : Integer;
  begin
    Result := 0;
    if pl = nil then Exit;
    for a := 0 to High (pl.kids) do
      Result := Result + Length (pl.kids[a].kids[0].kids);
  end;

  { one function for every call site: RAISES accounting, resolution,
    arity, argument typing, and the result type.  '<void>' is a call
    that returns nothing; '' is a call whose result is unknown.      }
  function CallType (dnode, argl, site: TNode): string;
  var
    name, om, pTy, amode, aliasTo, t, what, why, roWhat : string;
    cOm, cFty, cSv : string;
    cFlat : TNodeArr;
    cj : Integer;
    nargs, j, g, k, kept, dot, nFrameKept : Integer;
    aTy : array of string;
    aNode : array of TNode;
    pr : TProcInfo;
    pl, grp, vfields, ares, dcl, rec : TNode;
    mi : TModuleInfo;
    hint : string;
    isVar : Boolean;
    flat : array of TNode;
    ptn, sty : TNode;                { a call through a procedure value }
    haveHead : Boolean;

    procedure Arity (want: Integer);
    begin
      if nargs <> want then
        ErrN (site, ctx, Format ('%s expects %d argument(s), got %d',
          [name, want, nargs]));
    end;

    { is the pool P itself one of the arguments?  Then the callee
      keeps in P what it keeps (mirrors Sem.PoolAmong) }
    function PoolAmong (const p: string): Boolean;
    var i : Integer;
    begin
      Result := False;
      if p = '' then Exit;
      for i := 0 to nargs - 1 do
        if (aNode[i] <> nil) and (aNode[i].kind = nkDesignator) and
           (Length (aNode[i].kids) = 0) and (aNode[i].a = p) then
          Exit (True);
    end;

  begin
    Result := '';
    name := DesigName (dnode);
    nargs := 0;
    if argl <> nil then nargs := Length (argl.kids);
    SetLength (aTy, nargs);
    SetLength (aNode, nargs);
    for j := 0 to nargs - 1 do
    begin
      aNode[j] := argl.kids[j];
      aTy[j] := ExprType (argl.kids[j]);
    end;
    { WIDTH DISPATCH BY DECLARED TWIN.  `Math.Sqrt (x)` with an F32
      argument is `Math.SqrtF32 (x)`, because sqrtf's answer is not
      sqrt's answer narrowed and a port held bit-identical to a
      single-precision original needs the single-precision libm.  The
      twin has to EXIST -- the suffix is how a module declares a
      function width-generic -- so nothing changes for a module that
      declares none. }
    if (nargs >= 1) and (Length (name) > 3) and
       (Copy (name, Length (name) - 2, 3) <> 'F32') then
    begin
      { SOME argument is F32 and NONE is F64.  Not "the first
        argument", which met Math.Pow (10.0, c): a literal types as
        neither width because it adapts, so it must not decide and
        must not block. }
      g := 0; k := 0;
      for j := 0 to nargs - 1 do
      begin
        if aTy[j] = 'F32' then Inc (g);
        if aTy[j] = 'F64' then Inc (k);
      end;
      if (g > 0) and (k = 0) and LookupProcInfo (name + 'F32', pr) then
        name := name + 'F32';
    end;
    calls.Add (name);
    if InList (name, ConvVR) then
    begin
      { I64 of a NARROWER integer is TOTAL: every BYTE, I8..I32 and
        U8..U32 value is an I64 value, as are C.Int and C.SSizeT,
        so the conversion has no failing case
        and must not be made to declare one.  Requiring RAISES here
        would push a ValueRange nobody can trigger up through every
        caller of a foreign wrapper -- the accounting would stop
        describing what can actually happen, which is the only thing
        that makes exhaustive RAISES worth having.  (par 2 pass 4,
        pre-registered; narrowing conversions still raise.) }
      if (name = 'I64') and (Length (aTy) = 1) and
         ((aTy[0] = 'C.Int') or (aTy[0] = 'C.SSizeT') or
          (aTy[0] = 'BYTE') or (aTy[0] = 'I8') or (aTy[0] = 'I16') or
          (aTy[0] = 'I32') or (aTy[0] = 'U8') or (aTy[0] = 'U16') or
          (aTy[0] = 'U32')) then
      begin
        Arity (1);
        Exit ('I64');
      end;
      if raised.Values['ValueRange'] = '' then
        raised.Values['ValueRange'] := name + ' conversion';
      Arity (1);
      if name = 'CHR' then Exit ('CHAR');
      Exit (name);
    end;
    if name = 'ADR' then
    begin
      if not curUnsafe then
        ErrN (site, ctx, 'ADR exists only inside UNSAFE modules');
      Arity (1);
      Exit ('C.Ptr');       { a C pointer, fitting any C.*Ptr parameter (mirrors Sem) }
    end;
    if (name = 'F32') or (name = 'F64') then
    begin
      Arity (1);
      Exit (name);
    end;
    if name = 'LEN' then
    begin
      { LEN (s) on a slice or array; LEN (g, axis) on a grid, because
        a grid has one length per axis and answering "the length"
        would be answering a question nobody asked }
      if nargs = 2 then
      begin
        if GridRank (aTy[0]) = 0 then
          ErrN (site, ctx,
            'LEN takes an axis only on a GRID, not on ' + TyName (aTy[0]));
        if not IsIntish (aTy[1]) then
          ErrN (site, ctx,
            'LEN axis must be an integer, not ' + TyName (aTy[1]));
        if (aNode[1].kind = nkInt) and (GridRank (aTy[0]) > 0) then
          if StrToIntDef (aNode[1].a, 0) >= GridRank (aTy[0]) then
            ErrN (site, ctx, 'axis ' + aNode[1].a + ' of a ' +
              aTy[0] + ' does not exist');
        Exit ('I64');
      end;
      if GridRank (aTy[0]) > 0 then
        ErrN (site, ctx,
          'LEN of a GRID needs an axis: LEN (g, 0)');
      Arity (1);
      Exit ('I64');
    end;
    if name = 'ORD' then
    begin
      Arity (1);
      Exit ('I64');
    end;
  if name = 'NAME' then
  begin
    { the identifier text of an enumeration member (or any case-record
      variant), as a STR: NAME (Colour.Red) is 'Red' }
    Arity (1);
    if (nargs = 1) and not IsTagged (aTy[0]) and (aTy[0] <> '') then
      ErrN (site, ctx, 'NAME needs an enumeration or a case record, not '
        + TyName (aTy[0]));
    Exit ('SLICE OF CHAR');
  end;
    if name = 'VIEW' then
    begin
      { VIEW (g, i, ALL, ...) -- one argument per axis: an index drops
        that axis, ALL keeps it.  The rank of the answer is therefore
        computable here, which is what lets a view be typed at all. }
      if nargs < 2 then
      begin
        ErrN (site, ctx, 'VIEW needs a grid and one argument per axis');
        Exit ('');
      end;
      k := GridRank (aTy[0]);
      if k = 0 then
      begin
        if aTy[0] <> '' then
          ErrN (site, ctx, 'VIEW needs a GRID, not ' + TyName (aTy[0]));
        Exit ('');
      end;
      if nargs - 1 <> k then
      begin
        ErrN (site, ctx, 'a ' + aTy[0] + ' needs ' + IntToStr (k) +
          ' axis arguments, not ' + IntToStr (nargs - 1));
        Exit ('');
      end;
      kept := 0;
      for j := 1 to nargs - 1 do
        if aTy[j] = '<all>' then
          Inc (kept)
        else if not IsIntish (aTy[j]) then
          ErrN (site, ctx,
            'a VIEW axis is an index or ALL, not ' + TyName (aTy[j]));
      if kept = 0 then
      begin
        ErrN (site, ctx,
          'a VIEW that keeps no axis is an index: write the subscripts');
        Exit ('');
      end;
      Exit (GridOf (kept, ElemOfArray (aTy[0])));
    end;
    if name = 'MAX' then
    begin
      Arity (1);
      if (nargs = 1) and (aNode[0].kind = nkDesignator) and
         (Length (aNode[0].kids) = 0) and
         InList (aNode[0].a, BuiltinTypes) then
        Exit (aNode[0].a);
      Exit ('');
    end;
    { SizeOf (x): the byte size of x's type (I64).  Accepts a type
      name or a value; a slice's SizeOf is its descriptor, the data
      is ByteSize.  In-memory only -- a wire uses the exact-width
      types and ToBytesLE. }
    if name = 'SizeOf' then
    begin
      Arity (1);
      Exit ('I64');
    end;
    if name = 'ByteSize' then
    begin
      Arity (1);
      if (nargs >= 1) and (aTy[0] <> '') and
         not StartsWithS (aTy[0], 'SLICE OF ') then
        ErrN (site, ctx, 'ByteSize needs a slice, not ' + TyName (aTy[0]));
      Exit ('I64');
    end;
    if (name = 'F64.FromBytesLE') or (name = 'F32.FromBytesLE') then
    begin
      Arity (1);
      Exit (Copy (name, 1, 3));
    end;
    if (name = 'F64.ToBytesLE') or (name = 'F32.ToBytesLE') then
    begin
      Arity (2);
      Exit ('<void>');
    end;
    if (Length (name) > 2) and (Copy (name, 1, 2) = 'C.') then
    begin
      Arity (1);
      Exit (name);
    end;
    { a call THROUGH A PROCEDURE VALUE (par 2.2.3): a parameter or an
      IS SOME binder whose type is a procedure type.  The type's own
      head stands in for the callee's declaration and the same checks
      run over it; nothing is known about which procedure runs, so a
      PURE body may not make the call.  Mirrors Sem.CallType. }
    haveHead := False;
    sty := ScopeType (name);
    if sty <> nil then
    begin
      ptn := ResolveType (sty);
      if (ptn <> nil) and (ptn.kind = nkProcType) then
      begin
        if curPure then
          ErrN (site, ctx, 'PURE procedure calls through the procedure value '
            + name + ' (par 3.2)');
        pr.node := ptn;
        pr.modName := '';
        pr.foreign := '';
        if (sty.kind = nkQualident) and (sty.b <> '') then
          pr.modName := sty.a;
        SetLength (pr.raises, 0);
        if ptn.kids[2] <> nil then
        begin
          SetLength (pr.raises, Length (ptn.kids[2].kids));
          for j := 0 to High (ptn.kids[2].kids) do
            if ptn.kids[2].kids[j].b <> '' then
              pr.raises[j] := ptn.kids[2].kids[j].b
            else
              pr.raises[j] := ptn.kids[2].kids[j].a;
        end;
        haveHead := True;
      end;
    end;
    if haveHead or LookupProcInfo (name, pr) then
    begin
      for j := 0 to High (pr.raises) do
        if raised.Values[pr.raises[j]] = '' then
          raised.Values[pr.raises[j]] := 'call to ' + name;
      canonCtx := pr.modName;
      pl := pr.node.kids[0];
      Arity (CountParams (pl));
      { how many VAR or KEPT arguments are FRAME values: a frame value
        handed to a KEPT parameter is refused unless another frame
        value is the keeper (mirrors Sem.CallType) }
      nFrameKept := 0;
      k := 0;
      if pl <> nil then
        for g := 0 to High (pl.kids) do
        begin
          grp := pl.kids[g];
          for j := 0 to High (grp.kids[0].kids) do
          begin
            if (k < nargs) and (grp.f1 or grp.f2 or grp.f4) and
               (FrameWhat (aNode[k], aTy[k]) <> '') then
              Inc (nFrameKept);
            Inc (k);
          end;
        end;
      k := 0;
      if pl <> nil then
        for g := 0 to High (pl.kids) do
        begin
          grp := pl.kids[g];
          pTy := CT (grp.kids[1]);
          isVar := grp.f1 or grp.f2;
          for j := 0 to High (grp.kids[0].kids) do
          begin
            if k < nargs then
            begin
              { an argument that names a constant: it cannot be a VAR
                or OWN argument (there is nothing to write), and a
                constant table goes only to an RO parameter
                (par 2.2.4) }
              if (aNode[k] <> nil) and (aNode[k].kind = nkDesignator) and
                 IsConstHere (aNode[k].a) then
              begin
                if isVar then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: the CONST %s cannot be passed' +
                    ' to a VAR or OWN parameter',
                    [k + 1, name, aNode[k].a]))
                else if (Length (aNode[k].kids) = 0) and not grp.f3 and
                        IsAggConst (aNode[k].a) then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: the CONST table %s can be lent' +
                    ' only to an RO parameter (par 2.2.4)',
                    [k + 1, name, aNode[k].a]));
              end;
              { par 2.4: read-only storage -- a string literal, what
                an RO parameter views, a CONST -- is lent only to an
                RO parameter.  A by-value SLICE or GRID parameter can
                be written through, and `Up ('abc')` with `s[0] :=
                'X'` inside was accepted and died with SIGSEGV until
                2026-10-01 (museum/write-through-literal.m9). }
              if (not isVar) and (not grp.f3) and (aNode[k] <> nil) and
                 (StartsWithS (pTy, 'SLICE OF') or
                  StartsWithS (pTy, 'GRID ')) then
              begin
                roWhat := '';
                if aNode[k].kind = nkString then
                  roWhat := 'a string literal'
                else if (aNode[k].kind = nkDesignator) and
                        (StartsWithS (aTy[k], 'SLICE OF') or
                         StartsWithS (aTy[k], 'GRID ') or
                         (aTy[k] = '<str1>')) then
                begin
                  if ScopeMode (aNode[k].a) = 'r' then
                    roWhat := 'the RO parameter ' + aNode[k].a
                  else if ScopeRo (aNode[k].a) then
                    roWhat := 'the RO variable ' + aNode[k].a
                  else if ScopeRoFrom (aNode[k].a) <> '' then
                    roWhat := aNode[k].a + ', which holds ' +
                              ScopeRoFrom (aNode[k].a) + ','
                  else if IsConstHere (aNode[k].a) then
                    roWhat := 'the CONST ' + aNode[k].a
                  else if RoFieldOf (aNode[k]) <> '' then
                    roWhat := 'the RO field ' + RoFieldOf (aNode[k]);
                end
                else if (aNode[k].kind = nkCallExpr) and
                        (StartsWithS (aTy[k], 'SLICE OF') or
                         StartsWithS (aTy[k], 'GRID ')) then
                  roWhat := RoAnswerOf (aNode[k]);
                if roWhat <> '' then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: %s can be lent only to an RO' +
                    ' parameter (par 2.4)', [k + 1, name, roWhat]));
              end;
              if aTy[k] = '<void>' then
                ErrN (site, ctx, Format (
                  'argument %d of %s returns no value', [k + 1, name]))
              else if not Compat (pTy, aTy[k]) then
                ErrN (site, ctx, Format (
                  'argument %d of %s: cannot pass %s where %s is expected',
                  [k + 1, name, TyName (aTy[k]), TyName (pTy)]));
              if isVar and (aNode[k].kind <> nkDesignator) then
                ErrN (site, ctx, Format (
                  'argument %d of %s must be a variable (VAR/OWN parameter)',
                  [k + 1, name]));
              { P3: a value parameter of pointer type is a shared
                borrow; lending it onward as VAR would launder the
                write restriction through a call (par 4.1) }
              if isVar and (aNode[k].kind = nkDesignator) and
                 (Length (aNode[k].kids) = 0) and
                 (ScopeMode (aNode[k].a) = 'p') and
                 BaseIsPtr (aNode[k]) then
                ErrN (site, ctx, Format (
                  'argument %d of %s: cannot lend the value parameter ' +
                  '%s as VAR (shared borrow, par 4.1)',
                  [k + 1, name, aNode[k].a]));
              { rule 2: the callee may allocate in the object's pool,
                which the generator names from the ROOT of this
                designator's declaration -- so the root must have one
                to name (mirrors Sem.CheckArg) }
              if grp.f1 and (aNode[k].kind = nkDesignator) and
                 PtrParamTy (grp.kids[1]) and (pr.foreign = '') then
              begin
                why := ObjPoolIssue (aNode[k]);
                if why <> '' then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: the pool of %s is not known here,' +
                    ' and the callee may allocate in it -- %s (par 4.3)',
                    [k + 1, name, aNode[k].a, why]));
              end;
              { RO measurement: lending a VAR param onward as VAR or
                OWN is a potential write -- conservatively not RO }
              if (grp.f1 or grp.f2) and (aNode[k].kind = nkDesignator)
                 and (varParams.IndexOf (aNode[k].a) >= 0) then
                varWritten.Add (aNode[k].a);
              { an OWN parameter MOVES its argument (par 4.2) }
              if grp.f2 and (aNode[k].kind = nkDesignator) and
                 (Length (aNode[k].kids) = 0) then
              begin
                amode := ScopeMode (aNode[k].a);
                if (amode = 'p') or (amode = 'v') or (amode = 'b') or (amode = 'r') then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: cannot move borrowed %s into ' +
                    'an OWN parameter (par 4.2)',
                    [k + 1, name, aNode[k].a]))
                else if fval.IndexOf (aNode[k].a) >= 0 then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: cannot move %s into ' +
                    'an OWN parameter -- it lives in the frame (par 4.3)',
                    [k + 1, name, aNode[k].a]))
                else
                begin
                  ares := ResolveType (ScopeType (aNode[k].a));
                  if (ares <> nil) and (ares.kind = nkPtrType) and
                     (ares.kids[1] <> nil) then
                    ErrN (site, ctx, Format (
                      'argument %d of %s: the pool owns %s (par 4.3)',
                      [k + 1, name, aNode[k].a]))
                  else if OwnedCandKind (aNode[k].a) > 0 then
                    OwnMark (aNode[k].a,
                      'moved into an OWN parameter of ' + name, site);
                end;
              end;
              { par 4.1, the caller side of KEPT.  A parameter's KEPT
                is read HERE, which is what narrows the old blanket
                every-callee-may-keep '<call>' fact to the parameters
                that declare it.  Two refusals, the RAISES-style
                upward composition: what is handed to a KEPT
                parameter must survive the call, so a concatenation
                (frame storage, par 2.3) is refused outright, and a
                borrow is a retention the CALLER must declare in
                turn. }
              if grp.f4 then
              begin
                { a concatenation, a frame allocation, or a name
                  holding either }
                what := FrameWhat (aNode[k], aTy[k]);
                if (what <> '') and (nFrameKept <= 1) and
                   not PoolAmong (KindPool (what)) then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: a KEPT parameter cannot take' +
                    ' %s -- it dies with this frame' +
                    ' (par 4.1); give it storage that outlives the call:' +
                    ' a string through Text.Keep (pool, s), an allocation' +
                    ' through NEW (pool, T)', [k + 1, name, what]));
                { a record value carries what its fields hold
                  (TyBearing, decision 34), and a CONSTRUCTOR wrapping
                  a borrow hands the borrow to the keeper (2026-10-08) }
                aliasTo := EscRootOf (aNode[k]);
                if (aliasTo <> '') and TyBearing (aTy[k]) then
                  KeptRoot (site, ctx, name, k, aliasTo)
                else if (aliasTo = '') and CtorFlat (aNode[k], cOm, cFlat) and
                        (aNode[k].kids[1] <> nil) then
                  for cj := 0 to High (aNode[k].kids[1].kids) do
                    if cj <= High (cFlat) then
                    begin
                      cSv := canonCtx;
                      canonCtx := cOm;
                      cFty := CanonT (cFlat[cj], 0);
                      canonCtx := cSv;
                      aliasTo := EscRootOf (aNode[k].kids[1].kids[cj]);
                      if (aliasTo <> '') and TyBearing (cFty) then
                        KeptRoot (site, ctx, name, k, aliasTo);
                    end;
              end;
            end;
            Inc (k);
          end;
        end;
      pTy := '';
      if pr.node.kids[1] <> nil then
        pTy := CanonT (pr.node.kids[1], 0);
      canonCtx := '';
      if pTy <> '' then Exit (pTy);
      if pr.node.kids[1] <> nil then Exit ('');
      Exit ('<void>');
    end;
    { a variant constructor with payload: Type.Variant (args), or
      Mod.Type.Variant (args) from another module.  The three-part
      form was read as a two-part one -- type `Csv', variant
      `Kind.Stamp' -- and refused as `unknown procedure: Csv' until
      2026-09-15; nobody had written one, so nothing knew.  With a
      module named, the variant is looked for THERE and nowhere else. }
    dot := Pos ('.', name);
    isVar := False;
    if dot > 0 then
    begin
      t := Copy (name, dot + 1, MaxInt);
      g := Pos ('.', t);
      if g > 0 then
      begin
        isVar := VariantIn (Copy (name, 1, dot - 1), Copy (t, 1, g - 1),
                            Copy (t, g + 1, MaxInt), om, vfields);
        t := Copy (t, 1, g - 1);
      end
      else
      begin
        isVar := FindVariant (Copy (name, 1, dot - 1), t, om, vfields);
        t := Copy (name, 1, dot - 1);
      end;
    end;
    if isVar then
    begin
      SetLength (flat, 0);
      if vfields <> nil then
        for g := 0 to High (vfields.kids) do
          for j := 0 to High (vfields.kids[g].kids[0].kids) do
          begin
            SetLength (flat, Length (flat) + 1);
            flat[High (flat)] := vfields.kids[g].kids[1];
          end;
      Arity (Length (flat));
      canonCtx := om;
      for k := 0 to nargs - 1 do
        if k <= High (flat) then
        begin
          pTy := CT (flat[k]);
          if not Compat (pTy, aTy[k]) then
            ErrN (site, ctx, Format (
              'argument %d of %s: cannot pass %s where %s is expected',
              [k + 1, name, TyName (aTy[k]), TyName (pTy)]));
        end;
      canonCtx := '';
      Exit (om + '.' + t);
    end;
    { the integer-to-enumeration conversion: returns the type and
      raises ValueRange, like every other narrowing }
    t := EnumConvType (name);
    if t <> '' then
    begin
      Arity (1);
      if (nargs = 1) and not IsIntish (aTy[0]) then
        ErrN (site, ctx, 'argument 1 of ' + name +
          ': cannot convert ' + TyName (aTy[0]) +
          ' to an enumeration; an integer position is expected');
      if raised.Values['ValueRange'] = '' then
        raised.Values['ValueRange'] := name + ' conversion';
      Exit (t);
    end;
    { a RECORD AGGREGATE: Row (200, 'OK'), or Mod.Row (...) for an
      imported type -- every field, in declaration order, each held
      to its field's type (Sem.RecordNamed) }
    rec := nil;
    dcl := nil;
    dot := Pos ('.', name);
    if dot > 0 then
    begin
      om := Copy (name, 1, dot - 1);
      if FindMod (om) <> nil then
        dcl := FindMod (om).FindType (Copy (name, dot + 1, MaxInt));
    end
    else
    begin
      om := curMod;
      if FindMod (curMod) <> nil then
        dcl := FindMod (curMod).FindType (name);
    end;
    rec := ResolveType (dcl);
    if (rec <> nil) and (rec.kind = nkRecordType) then
    begin
      { the type's canonical name: its own, or through an alias the
        record's (Sem.RecordNamed) }
      t := om + '.' + Copy (name, dot + 1, MaxInt);
      if dcl.kind = nkQualident then
      begin
        canonCtx := om;
        t := CT (dcl);
        canonCtx := '';
      end;
      if rec.kids[0] <> nil then
      begin
        ErrN (site, ctx, name + ': an aggregate of an extended record is' +
          ' not built; give its fields one by one (par 2.2.4)');
        Exit (t);
      end;
      SetLength (flat, 0);
      if rec.kids[1] <> nil then
        for g := 0 to High (rec.kids[1].kids) do
          for j := 0 to High (rec.kids[1].kids[g].kids[0].kids) do
          begin
            SetLength (flat, Length (flat) + 1);
            flat[High (flat)] := rec.kids[1].kids[g].kids[1];
          end;
      Arity (Length (flat));
      canonCtx := om;
      for k := 0 to nargs - 1 do
        if k <= High (flat) then
        begin
          pTy := CT (flat[k]);
          if not Compat (pTy, aTy[k]) then
            ErrN (site, ctx, Format (
              'field %d of %s: cannot give %s where %s is expected',
              [k + 1, name, TyName (aTy[k]), TyName (pTy)]));
        end;
      canonCtx := '';
      Exit (t);
    end;
    { Sem.CaseTwin: the procedure meant when only its CASE differs }
    hint := '';
    dot := Pos ('.', name);
    if dot > 0 then mi := FindMod (Copy (name, 1, dot - 1))
    else mi := FindMod (curMod);
    if mi <> nil then
      for k := 0 to High (mi.procs) do
        if (hint = '') and
           (LowerCase (mi.procs[k].name) = LowerCase (Copy (name, dot + 1, MaxInt))) then
        begin
          if dot > 0 then hint := Copy (name, 1, dot - 1) + '.' + mi.procs[k].name
          else hint := mi.procs[k].name;
        end;
    if hint <> '' then
      ErrN (site, ctx, 'unknown procedure: ' + name + ' -- did you mean ' + hint + '?')
    else
      ErrN (site, ctx, 'unknown procedure: ' + name);
  end;

  function BinType (e: TNode): string;
  var lt, rt, op : string;

    function NumSide (const s: string): Boolean;
    begin
      Result := (s = '') or (s = '<int>') or (s = '<real>') or
                IsIntStr (s) or IsFloatStr (s);
    end;

    function StrSide (const s: string): Boolean;
    begin
      Result := (s = 'SLICE OF CHAR') or (s = '<str1>');
    end;

    { a value two of which no single operator compares: a slice, an
      array, a grid, a record, a monitor, a case record that carries
      a payload -- what the C has no == for }
    function IsComposite (const t: string): Boolean;
    var
      dot : Integer;
      md, ty : string;
      n : TNode;
    begin
      if StartsWithS (t, 'SLICE OF ') or StartsWithS (t, 'ARRAY ') or
         StartsWithS (t, 'GRID ') then
        Exit (True);
      Result := False;
      dot := Pos ('.', t);
      if dot > 0 then
      begin
        md := Copy (t, 1, dot - 1);
        ty := Copy (t, dot + 1, MaxInt);
      end
      else
      begin
        md := '';
        ty := t;
      end;
      n := LookupTypeName (md, ty);
      if n = nil then Exit;
      if n.kind in [nkRecordType, nkMonitorType] then Exit (True);
      if n.kind = nkCaseRecordType then Result := not AllPayloadless (n);
    end;

  begin
    op := e.a;
    lt := ExprType (e.kids[0]);
    rt := ExprType (e.kids[1]);
    Result := '';
    if (op = 'AND') or (op = 'OR') then
    begin
      if (lt <> '') and (lt <> 'BOOL') then
        ErrN (e, ctx, op + ' needs BOOL operands, not ' + TyName (lt));
      if (rt <> '') and (rt <> 'BOOL') then
        ErrN (e, ctx, op + ' needs BOOL operands, not ' + TyName (rt));
      Exit ('BOOL');
    end;
    if (op = '=') or (op = '#') or (op = '<') or (op = '<=') or
       (op = '>') or (op = '>=') then
    begin
      if (lt = '<void>') or (rt = '<void>') then
        ErrN (e, ctx, 'comparing a call that returns no value')
      else if IsNanLit (e.kids[0]) or IsNanLit (e.kids[1]) then
        ErrN (e, ctx, 'no ''' + op + ''' with NaN: no comparison with NaN is' +
          ' ever TRUE, except ''#'', which always is; Math.IsNaN (x) asks' +
          ' (par 2.1)')
      else if not (Compat (lt, rt) or Compat (rt, lt)) then
        ErrN (e, ctx, Format ('cannot compare %s with %s',
          [TyName (lt), TyName (rt)]))
      { an operator compares SCALARS.  Two strings, two arrays, two
        records agree in type and were let through to a C that has no
        == for a struct: `IF name = 'cancel'` was the C compiler's to
        refuse until 2026-10-02 (par 2.3). }
      else if StrSide (lt) and StrSide (rt) and
              ((lt = 'SLICE OF CHAR') or (rt = 'SLICE OF CHAR')) then
        ErrN (e, ctx, 'no ''' + op + ''' between two strings: Text.Eq' +
          ' (a, b) answers equality, and no operator orders them' +
          ' (par 2.3)')
      else if IsComposite (lt) then
        ErrN (e, ctx, 'no ''' + op + ''' between two values of type ' +
          TyName (lt) + ': an operator compares numbers, characters,' +
          ' booleans, enumeration values and pointers (par 2.3)')
      else if IsComposite (rt) then
        ErrN (e, ctx, 'no ''' + op + ''' between two values of type ' +
          TyName (rt) + ': an operator compares numbers, characters,' +
          ' booleans, enumeration values and pointers (par 2.3)');
      Exit ('BOOL');
    end;
    { string concatenation, before the arithmetic rules: `+` on two
      strings answers a string, allocated in HEAP (par 4.3).  A CHAR
      on either side is one code point appended or prepended -- a
      CHAR converts to nothing implicitly, so there is nothing for
      `s + c` to decide silently (the rule used to refuse it, on a
      Pascal/C worry M9 does not have; revised 2026-09-06).  Anything
      else -- a number, a record -- must be formatted first. }
    if (op = '+') and (StrSide (lt) or StrSide (rt)) then
    begin
      if not (StrSide (lt) or (lt = 'CHAR')) then
        ErrN (e, ctx, 'cannot concatenate ' + TyName (lt) + ' with a string')
      else if not (StrSide (rt) or (rt = 'CHAR')) then
        ErrN (e, ctx, 'cannot concatenate a string with ' + TyName (rt));
      Exit ('SLICE OF CHAR');
    end;
    { arithmetic: + - * / DIV MOD and the wrapping three }
    if (lt = 'BYTE') or (rt = 'BYTE') then
    begin
      ErrN (e, ctx,
        'BYTE is a raw octet: no arithmetic (convert first, par 2.1)');
      Exit ('');
    end;
    if not NumSide (lt) then
      ErrN (e, ctx, op + ' needs numeric operands, not ' + TyName (lt))
    else if not NumSide (rt) then
      ErrN (e, ctx, op + ' needs numeric operands, not ' + TyName (rt))
    else if not (Compat (lt, rt) or Compat (rt, lt)) then
      ErrN (e, ctx, Format ('no implicit conversions: %s %s %s',
        [TyName (lt), op, TyName (rt)]));
    if op = '/' then
    begin
      if IsIntStr (lt) or (lt = '<int>') or
         IsIntStr (rt) or (rt = '<int>') then
        ErrN (e, ctx, '''/'' is float division; integers use DIV');
    end
    else if (op = 'DIV') or (op = 'MOD') then
    begin
      if IsFloatStr (lt) or (lt = '<real>') or
         IsFloatStr (rt) or (rt = '<real>') then
        ErrN (e, ctx, op + ' is integer division; floats use ''/''');
    end
    else if (op = '+%') or (op = '-%') or (op = '*%') then
    begin
      if IsFloatStr (lt) or (lt = '<real>') or
         IsFloatStr (rt) or (rt = '<real>') then
        ErrN (e, ctx, 'wrapping arithmetic is for integers');
    end;
    { the concrete side wins over a literal }
    if lt = rt then Exit (lt);
    if (lt = '') or (rt = '') then Exit ('');
    if (lt = '<int>') or (lt = '<real>') then Exit (rt);
    if (rt = '<int>') or (rt = '<real>') then Exit (lt);
    Result := '';
  end;

  function ExprType0 (e: TNode): string;
  var
    j, ext0, nx, ne : Integer;
    t, u, form : string;
    res, inr, pt, tyk, rtn : TNode;
    pr : TProcInfo;
  begin
    Result := '';
    if e = nil then Exit;
    case e.kind of
      nkInt  : Result := '<int>';
      nkReal : Result := '<real>';
      nkChar : Result := 'CHAR';
      nkString :
        if Utf8Len (e.a) = 1 then Result := '<str1>'
        else Result := 'SLICE OF CHAR';
      nkTrue, nkFalse : Result := 'BOOL';
      nkNoneLit : Result := '<none>';
      nkParen : Result := ExprType (e.kids[0]);
      nkSomeExpr :
        begin
          t := ExprType (e.kids[0]);
          if (t <> '') and (t <> '<void>') then Result := 'OPT ' + t;
        end;
      nkSharedExpr :
        begin
          t := ExprType (e.kids[0]);
          if StartsWithS (t, 'PTR ') then Result := 'SHARED ' + t;
          { SHARED consumes the owned pointer (par 4.2) }
          inr := StripParens (e.kids[0]);
          if (inr <> nil) and (inr.kind = nkDesignator) and
             (Length (inr.kids) = 0) and StartsWithS (t, 'PTR ') then
          begin
            u := ScopeMode (inr.a);
            if (u = 'p') or (u = 'v') or (u = 'b') or (u = 'r') then
              ErrN (e, ctx, 'SHARED consumes an owned pointer; ' +
                inr.a + ' is a borrow (par 4.2)')
            else if fval.IndexOf (inr.a) >= 0 then
              { a frame allocation has no rc header and dies with the
                frame: only NEW (OWN, T) can become SHARED }
              ErrN (e, ctx, 'SHARED needs an OWN allocation; ' +
                inr.a + ' lives in the frame (par 4.2)')
            else if OwnedCandKind (inr.a) = 1 then
              OwnMark (inr.a, 'consumed by SHARED', e);
          end;
        end;
      nkNewExpr :
        begin
          { THE SHAPE: pool FIRST, then the type.  `NEW (Point, pool)`
            used to type-check in silence -- the pool position holds a
            name that is not a value, so it types as unknown, and
            unknown never diagnoses -- and only the GENERATOR objected,
            with `unknown name: Point`.  A tutorial reader followed
            chapter 4's own example into exactly this (2026-08-29).
            A checker softer than the generator is a checker that
            misses; the second argument BEING a pool is conclusive. }
          form := NewForm (e, tyk, ext0);
          if form = '' then Exit ('');
          if form = 'pool' then
          begin
            { par 3.2: allocating from a pool the CALLER owns consumes
              the caller's storage and answers a slice into the
              caller's arena -- an effect, and the one a PURE body
              could still have, since NEW is a builtin (rule 3 does
              not see it) and not an assignment target (rules 1 and 2
              do not either).  A pool declared LOCAL is invisible
              outside the frame and stays legal, and so is the frame
              itself, so the test is the pool's binding MODE. }
            if curPure and (e.kids[0].kind = nkDesignator) and
               ((ScopeMode (e.kids[0].a) = 'v') or
                (ScopeMode (e.kids[0].a) = 'o') or
                (ScopeMode (e.kids[0].a) = 'm')) then
              ErrN (e, ctx, 'cannot allocate from the pool ' + e.kids[0].a +
                ' in a PURE procedure (par 3.2)');
          end;
          if form = 'frame' then
            { `NEW (Point, pool)`, the reversed spelling: it reads as
              the frame form with a pool for an extent, so name what
              was meant.  A tutorial reader followed chapter 4's own
              example into exactly this (2026-08-29). }
            for j := ext0 to High (e.kids) do
              if (e.kids[j] <> nil) and (e.kids[j].kind = nkDesignator) and
                 (Length (e.kids[j].kids) = 0) then
              begin
                pt := ScopeType (e.kids[j].a);
                if (pt <> nil) and (pt.kind = nkQualident) and
                   (pt.a = 'POOL') then
                begin
                  ErrN (e, ctx, 'NEW takes the pool first, then the type');
                  Exit ('');
                end;
              end;
          t := CanonT (tyk, 0);
          nx := 0;
          for j := ext0 to High (e.kids) do
            if e.kids[j] <> nil then
            begin
              Inc (nx);
              u := ExprType (e.kids[j]);
              if not IsIntish (u) then
                ErrN (e, ctx,
                  'NEW extent must be an integer, not ' + TyName (u));
            end;
          { one extent is a slice; more than one is a GRID, and the
            arity states the rank so the two cannot disagree }
          if nx = 1 then
          begin
            if t <> '' then Result := 'SLICE OF ' + t;
          end
          else if nx > 1 then
            Result := GridOf (nx, t)
          else if t <> '' then
            Result := 'PTR ' + t;
        end;
      nkGridOf :
        begin
          { GRID (s, n0, ..., nR): mirrors Sem (par 2.2.1) }
          t := ExprType (e.kids[0]);
          for j := 1 to High (e.kids) do
          begin
            u := ExprType (e.kids[j]);
            if not IsIntish (u) then
              ErrN (e, ctx,
                'GRID extent must be an integer, not ' + TyName (u));
          end;
          if High (e.kids) > 4 then
            ErrN (e, ctx, 'GRID takes at most 4 extents (par 2.2.1)');
          if (e.kids[0] <> nil) and (e.kids[0].kind <> nkDesignator) then
            ErrN (e, ctx, 'GRID lays over a slice NAMED by a designator: SLICE it into a variable first (par 2.2.1)');
          if StartsWithS (t, 'SLICE OF ') then
            Result := GridOf (High (e.kids), Copy (t, Length ('SLICE OF ') + 1, Length (t)))
          else if t <> '' then
            ErrN (e, ctx, 'GRID needs a slice, not ' + TyName (t));
        end;
      nkSliceOf3 :
        begin
          t := ExprType (e.kids[0]);
          u := ExprType (e.kids[1]);
          if not IsIntish (u) then
            ErrN (e, ctx,
              'SLICE start must be an integer, not ' + TyName (u));
          u := ExprType (e.kids[2]);
          if not IsIntish (u) then
            ErrN (e, ctx,
              'SLICE length must be an integer, not ' + TyName (u));
          if StartsWithS (t, 'SLICE OF ') then Result := t
          else if StartsWithS (t, 'ARRAY ') then
            Result := 'SLICE OF ' + ElemOfArray (t)
          else if t <> '' then
            ErrN (e, ctx,
              'SLICE needs a slice or array, not ' + TyName (t));
        end;
      nkIs :
        begin
          { the IS operand is the guard itself: the final OPT is
            legal, and SOME binds its payload }
          if e.kids[0].kind = nkDesignator then
          begin
            NoteUse (e.kids[0]);
            res := DesigDeclType (e.kids[0], True);
            if (e.kids[1].kind = nkIsSome) and (e.kids[1].a = '') then
            begin
              { `x IS SOME' / `x IS NONE': a BOOL, nothing bound (mirrors Sem) }
              t := CT (res);
              if (t <> '') and not StartsWithS (t, 'OPT ') then
                ErrN (e, ctx, 'IS SOME needs an OPT operand');
            end
            else if e.kids[1].kind = nkIsSome then
            begin
              t := CT (res);
              res := ResolveType (res);
              if (res <> nil) and (res.kind = nkOptType) then
                { the payload in the module that DECLARED the OPT
                  (mirrors Sem: an alias such as Ast.Kid) }
                BindName (e.kids[1].a, InMod (res.kids[0], resolvedIn))
              else
              begin
                if (t <> '') and not StartsWithS (t, 'OPT ') then
                  ErrN (e, ctx, 'IS SOME needs an OPT operand');
                BindName (e.kids[1].a, nil);
              end;
              { par 4.1 direction: the binder is a VIEW of the
                operand -- storing into the binder stores into the
                operand's storage, so the binder inherits the
                operand's reach (dst = operand, src = binder) --
                and, provenance, the binder CARRIES the operand }
              EscStore (e.kids[0].a, True, e.kids[1].a);
              CarryFrom (e.kids[1].a, e.kids[0].a);
            end;
          end
          else
          begin
            t := ExprType (e.kids[0]);
            if (e.kids[1].kind = nkIsSome) and (e.kids[1].a = '') then
            begin
              if (t <> '') and not StartsWithS (t, 'OPT ') then
                ErrN (e, ctx, 'IS SOME needs an OPT operand');
            end
            else if e.kids[1].kind = nkIsSome then
            begin
              res := nil;
              { a CALL's result: the binder takes the callee's declared
                payload type, made self-contained in the callee's
                module, so an argument made of the binder is checked
                like any other.  Before 2026-09-06 it was bound
                untyped, passed by softness, and gcc objected. }
              if (e.kids[0].kind = nkCallExpr) and
                 LookupProcInfo (DesigName (e.kids[0].kids[0]), pr) and
                 (pr.node.kids[1] <> nil) then
              begin
                canonCtx := pr.modName;
                res := ResolveType (pr.node.kids[1]);
                canonCtx := '';
                if (res <> nil) and (res.kind = nkOptType) then
                begin
                  if resolvedIn <> '' then
                    res := QualifiedIn (res.kids[0], resolvedIn)
                  else
                    res := QualifiedIn (res.kids[0], pr.modName);
                end
                else
                  res := nil;
              end;
              if (t <> '') and not StartsWithS (t, 'OPT ') then
                ErrN (e, ctx, 'IS SOME needs an OPT operand');
              BindName (e.kids[1].a, res);
            end;
          end;
          Result := 'BOOL';
        end;
      nkUn :
        begin
          t := ExprType (e.kids[0]);
          if e.a = 'NOT' then
          begin
            if (t <> '') and (t <> 'BOOL') then
              ErrN (e, ctx, 'NOT needs a BOOL operand, not ' + TyName (t));
            Result := 'BOOL';
          end
          else
          begin
            if not ((t = '') or (t = '<int>') or (t = '<real>') or
                    IsIntStr (t) or IsFloatStr (t)) then
              ErrN (e, ctx, 'unary ' + e.a +
                ' needs a numeric operand, not ' + TyName (t));
            Result := t;
          end;
        end;
      nkBin : Result := BinType (e);
      nkDesignator :
        begin
          NoteUse (e);
          { a top-level M9 procedure named as a VALUE has its head's
            type (par 2.2.3) -- Up, or Mod.Up; a scope name shadows
            it as it shadows anything.  A foreign procedure is a C
            symbol with another ABI and no value at all. }
          if ((Length (e.kids) = 0) or
              ((Length (e.kids) = 1) and (FindMod (e.a) <> nil))) and
             (ScopeType (e.a) = nil) and
             LookupProcInfo (DesigName (e), pr) and (pr.node <> nil) then
          begin
            if pr.foreign <> '' then
            begin
              ErrN (e, ctx, 'a foreign procedure is not a value: '
                + DesigName (e) + ' (par 2.2.3)');
              Exit ('');
            end;
            canonCtx := pr.modName;
            t := ProcSig (pr.node.kids[0], pr.node.kids[1], pr.node.f3,
                          pr.node.kids[2], 0);
            canonCtx := '';
            Exit (t);
          end;
          { a bare value name known to NO part of the checker's name
            universe is undefined -- the symmetric twin of the
            unknown-procedure check.  Only in ExprType (a body-walk
            value context, scope populated), never in DesigStrType,
            which the signature checks also call without a scope. }
          if (Length (e.kids) = 0) and not BareNameKnown (e.a) then
            ErrN (e, ctx, 'unknown name: ' + e.a);
          { a member a LOADED module does not declare: Math.Nosuch }
          if (Length (e.kids) >= 1) and (ScopeType (e.a) = nil) and
             (FindMod (e.a) <> nil) and (e.kids[0] <> nil) and
             (e.kids[0].kind = nkSelField) and
             not ModHasName (e.a, e.kids[0].a) then
            ErrN (e, ctx, 'unknown name: ' + e.a + '.' + e.kids[0].a +
              ' -- ' + e.a + ' declares no such name');
          Result := DesigStrType (e, False);
        end;
      nkCallExpr : Result := CallType (e.kids[0], e.kids[1], e);
      nkCallSel :
        begin
          { F (x).f, F (x)[i] (mirrors Sem.ExprType0) }
          t := ExprType (e.kids[0]);
          rtn := CallResultNode (e.kids[0]);
          if rtn <> nil then
          begin
            SetType (e, rtn);
            ne := Errors.Count;
            rtn := SelWalk (e, False, rtn, 1);
            if rtn <> nil then Exit (CT (rtn));
            if Errors.Count = ne then
              ErrN (e, ctx, 'cannot select from an answer of type ' +
                TyName (t) + ': a field needs a record, a subscript a slice, array or grid');
          end
          else if t <> '' then
            ErrN (e, ctx,
              'select from the answer of a procedure value through a variable: assign the answer first');
          Exit ('');
        end;
    else
      for j := 0 to High (e.kids) do
        ExprType (e.kids[j]);
    end;
  end;


  { the typed tree's stage 3: every expression's type, recorded as the
    checker computes it, for the generator to read (M9AST.SetTyStr) }
  function ExprType (e: TNode): string;
  begin
    Result := ExprType0 (e);
    SetTyStr (e, Result);
  end;
  procedure WalkSeq (s: TNode); forward;

  procedure BindPattern (lbl: TNode; const selRoot: string);
  var
    vi : TVariantInfo;
    v, g, j, n : Integer;
    fs : TNode;
    flat : array of TNode;
  begin
    { positional binders take the variant's field types }
    SetLength (flat, 0);
    if VariantOwner (lbl.a, vi) then
      for v := 0 to High (vi.variants) do
        if vi.variants[v] = lbl.a then
        begin
          fs := vi.fields[v];
          if fs <> nil then
            for g := 0 to High (fs.kids) do
              for j := 0 to High (fs.kids[g].kids[0].kids) do
              begin
                SetLength (flat, Length (flat) + 1);
                flat[High (flat)] := fs.kids[g].kids[1];
              end;
        end;
    for n := 0 to High (lbl.kids[0].kids) do
    begin
      if n <= High (flat) then
        BindName (lbl.kids[0].kids[n].a, flat[n])
      else
        BindName (lbl.kids[0].kids[n].a, nil);
      { par 4.1 direction: a pattern binder views the selector's
        payload, so it inherits the selector's reach -- and,
        provenance, carries the selector }
      if selRoot <> '' then
      begin
        EscStore (selRoot, True, lbl.kids[0].kids[n].a);
        CarryFrom (lbl.kids[0].kids[n].a, selRoot);
      end;
    end;
  end;

  { a RAISE's payload held to its EXCEPTION's fields: the count, and
    each value against its field's type (mirrors Sem.CheckRaisePayload) }
  procedure CheckRaisePayload (xn, args: TNode);
  var
    decl : TNode;
    owner, nm, at, ft : string;
    nf, na, k : Integer;
  begin
    if xn.b <> '' then
    begin
      decl := ExcDeclOf (xn.a, xn.b, owner);
      nm := xn.a + '.' + xn.b;
    end
    else
    begin
      decl := ExcDeclOf ('', xn.a, owner);
      nm := xn.a;
    end;
    if decl = nil then Exit;
    nf := 0;
    while ExcFieldType (decl, owner, nf) <> nil do Inc (nf);
    na := 0;
    if args <> nil then na := Length (args.kids);
    { the predeclared IndexError raised bare }
    if (na = 0) and (owner = '') and (nm = 'IndexError') then Exit;
    if na <> nf then
      ErrN (xn, ctx, Format ('%s expects %d argument(s), got %d', [nm, nf, na]));
    for k := 0 to na - 1 do
      if k < nf then
      begin
        at := ExprType (args.kids[k]);
        ft := CT (ExcFieldType (decl, owner, k));
        if (at <> '') and (ft <> '') and not Compat (ft, at) then
          ErrN (xn, ctx, 'field ' + IntToStr (k + 1) + ' of ' + nm +
            ': cannot give ' + TyName (at) + ' where ' + TyName (ft) +
            ' is expected');
      end;
  end;

  procedure WalkStmt (st: TNode);
  var
    xowner : string;
    xdecl : TNode;
    j, k : Integer;
    lv : Int64;                      { an out-of-range literal's value }
    sv64 : Int64;                    { a FOR step's value }
    sch : Boolean;
    tname, tpTy, taTy, tamode : string;   { THREAD's target and argument }
    tpr : TProcInfo;
    tpl, tares : TNode;
    lblTxt : string;                 { a scalar CASE label, printed }
    labelsVariant, hasElse, beyond, haveSelVi : Boolean;
    vi, selVi : TVariantInfo;
    haveVi : Boolean;
    covered : TStringList;
    lbl, dcl : TNode;
    vname : string;
    t, u, selTy, dmode, what, apool, par : string;
    said : Boolean;
    pre, hpre : string;
    snaps : array of string;
  begin
    case st.kind of
      nkAssign :
        begin
          t := DesigStrType (st.kids[0], False);
          { a bare name on the left declared nowhere: `x := 1' with no x }
          if (Length (st.kids[0].kids) = 0) and not BareNameKnown (st.kids[0].a) then
            ErrN (st.kids[0], ctx, 'unknown name: ' + st.kids[0].a);
          u := ExprType (st.kids[1]);
          { par 2.3: a FRAME-SCOPED string (a concatenation, or a name
            already holding one) may not be stored where it will be
            read after this frame is freed -- a module variable, or a
            COMPONENT reached through a reference parameter (or a
            value pointer's target).  A bare VAR/OWN STR parameter is
            not refused: the generator re-homes its target into the
            caller's arena at exit, as it does the result.  A bare
            frame-mode destination merely inherits the taint and is
            cleared when given a durable value. }
          what := FrameWhat (st.kids[1], u);
          if what <> '' then
          begin
            { a frame value is par 2.3's rule; storage in a local
              pool, or a view of it, is par 4.3's, refused at the same
              places, and where the destination is declared IN a pool
              that is NOT local (mirrors Sem.CheckAssign) }
            if KindPool (what) <> '' then par := '4.3' else par := '2.3';
            dmode := ScopeMode (st.kids[0].a);
            if (dmode = 'm') and not curInBody then
              ErrN (st.kids[1], ctx, what + ' dies with this' +
                ' frame; it cannot be stored in module variable ' +
                st.kids[0].a + ' (par ' + par + ')' +
                ' -- allocate it in a module pool (VAR mpool : POOL ;' +
                ' NEW (mpool, T)), or copy a string: Text.Keep (mpool, s)')
            else if (dmode = 'r') or
                    (((dmode = 'v') or (dmode = 'o') or (dmode = 'p')) and
                     (Length (st.kids[0].kids) > 0)) then
              ErrN (st.kids[1], ctx, what + ' dies with this' +
                ' frame; it cannot be stored through ' + st.kids[0].a +
                ', which outlives it (par ' + par + ')')
            else if (Length (st.kids[0].kids) = 0) and
                    IsFrameMode (dmode) then
            begin
              { a local declared IN a pool claims that pool's
                lifetime, and rule 2 hands that pool to every callee
                that grows the object (mirrors Sem.CheckAssign) }
              if (dmode = 'l') and
                 (DeclPool (ScopeType (st.kids[0].a)) <> nil) then
              begin
                if KindPool (what) = '' then
                  ErrN (st.kids[1], ctx, what + ' dies with this' +
                    ' frame; it cannot be held by ' + st.kids[0].a +
                    ', which is declared IN a pool (par 4.3)')
                else if (ScopeMode (DeclPool (ScopeType (st.kids[0].a)).a) <> 'l')
                        and (AllocPoolOf (st.kids[1]) = '') then
                  ErrN (st.kids[1], ctx, what + ' dies with this' +
                    ' frame; it cannot be held by ' + st.kids[0].a +
                    ', which is declared IN a pool (par 4.3)');
              end
              else
                FvalAdd (st.kids[0].a, what);
            end
            else if (Length (st.kids[0].kids) > 0) and (dmode = 'l') then
            begin
              { a COMPONENT of a local: declared IN a pool the target
                outlives the frame; otherwise the local carries the
                taint (mirrors Sem.CheckAssign, stage 5 of the pool
                elision) }
              if DeclPool (ScopeType (st.kids[0].a)) <> nil then
              begin
                if (KindPool (what) = '') or
                   (ScopeMode (DeclPool (ScopeType (st.kids[0].a)).a) <> 'l') then
                  ErrN (st.kids[1], ctx, what + ' dies with this' +
                    ' frame; it cannot be stored through ' + st.kids[0].a +
                    ', which is declared IN a pool (par 4.3)');
              end
              else
              begin
                FvalAdd (st.kids[0].a, what);
                { and the component itself, by its path }
                FvalAdd (DesigPath (st.kids[0]), what);
              end;
            end;
          end
          else if (Length (st.kids[0].kids) = 0) and
                  (fval.IndexOf (st.kids[0].a) >= 0) then
          begin
            fvalKind.Delete (fval.IndexOf (st.kids[0].a));
            fval.Delete (fval.IndexOf (st.kids[0].a));
          end
          else if (Length (st.kids[0].kids) > 0) and
                  (ScopeMode (st.kids[0].a) = 'l') and
                  (fval.IndexOf (DesigPath (st.kids[0])) >= 0) then
          begin
            fvalKind.Delete (fval.IndexOf (DesigPath (st.kids[0])));
            fval.Delete (fval.IndexOf (DesigPath (st.kids[0])));
          end;
          { a bare name given a pool allocation holds nobody's object }
          if Length (st.kids[0].kids) = 0 then
          begin
            if IsPoolNew (st.kids[1]) then
            begin
              if pval.IndexOf (st.kids[0].a) < 0 then pval.Add (st.kids[0].a);
            end
            else if pval.IndexOf (st.kids[0].a) >= 0 then
              pval.Delete (pval.IndexOf (st.kids[0].a));
          end;
          { par 4.3: the IN clause must be the pool the object was
            allocated in (mirrors Sem.CheckAssign, stage 5) }
          if (Length (st.kids[0].kids) = 0) and
             (DeclPool (ScopeType (st.kids[0].a)) <> nil) then
          begin
            apool := AllocPoolOf (st.kids[1]);
            if (apool <> '') and
               (apool <> DeclPool (ScopeType (st.kids[0].a)).a) then
              ErrN (st.kids[1], ctx, st.kids[0].a + ' is declared IN ' +
                DeclPool (ScopeType (st.kids[0].a)).a +
                ' but allocated in ' + apool + ' (par 4.3)');
          end;
          { anchored at the RIGHT-HAND SIDE, not the statement: a
            value on its own line used to be reported one line too
            high, at the := (found by the first m9edit user) }
          if u = '<void>' then
            ErrN (st.kids[1], ctx, 'the right-hand side returns no value')
          else if not Compat (t, u) then
            ErrN (st.kids[1], ctx, Format (
              'cannot assign %s to %s (no implicit conversions, par 2.1)',
              [TyName (u), TyName (t)]))
          else if LitOut (st.kids[1], t, lv) then
            ErrN (st.kids[1], ctx, 'integer literal ' + IntToStr (lv)
              + ' does not fit ' + TyName (t));
          { P3: borrow-write legality, then the retention ledger --
            a borrowed reference param stored beyond the frame is
            measured, not (yet) rejected: the kill-gate reads it }
          if Length (st.kids[0].kids) > 0 then
            NoteUse (st.kids[0]);
          beyond := CheckWrite (st.kids[0]);
          { EscRootOf, not RefRootOf: a sub-slice view of a borrow
            stored beyond the frame retains the borrow just as the
            whole of it would }
          vname := EscRootOf (st.kids[1]);
          { SHARED handles are excluded: copying one IS the sanctioned
            retention -- refcounted, created explicitly (par 4.2).
            PENDED, not emitted: the class -- retention, self-store,
            frame-store -- needs every escape of the destination, so
            the walk finishes first; a local or binder may CARRY a
            borrow, resolved at flush.  A RECORD value that holds a
            reference (TyBearing) is stored as the reference would be
            -- until 2026-10-08 only a bare pointer or slice was, and
            a record local whose field viewed a borrow went through a
            VAR parameter's component unseen (Frame.AddF64). }
          if (vname <> '') and TyBearing (u) and
             not StartsWithS (u, 'SHARED PTR ') and
             not StartsWithS (u, 'OPT SHARED PTR ') then
            StoreRef (st, st.kids[0], vname, beyond, ScopeMode (st.kids[0].a));
          { a value CONSTRUCTED around a borrow retains it as the
            borrow itself would (2026-10-08) }
          if vname = '' then
            CtorStores (st, beyond, ScopeMode (st.kids[0].a));
          { moves: a bare owned pointer on the right moves out; a
            bare name on the left is (re)initialized }
          dcl := StripParens (st.kids[1]);
          { a name holding a FRAME allocation is not owned -- the
            frame is -- so copying it is a copy, not a move }
          if (dcl <> nil) and (dcl.kind = nkDesignator) and
             (Length (dcl.kids) = 0) and
             (OwnedCandKind (dcl.a) = 1) and (fval.IndexOf (dcl.a) < 0) and
             (pval.IndexOf (dcl.a) < 0) then
            OwnMark (dcl.a, 'moved', st);
          if Length (st.kids[0].kids) = 0 then
            OwnAlive (st.kids[0].a);
        end;
      nkCallStmt :
        begin
          t := CallType (st.kids[0], st.kids[1], st);
          if (t <> '') and (t <> '<void>') then
            ErrN (st, ctx, 'function result discarded: ' +
              DesigName (st.kids[0]) + ' returns ' + TyName (t));
        end;
      nkIf :
        begin
          t := ExprType (st.kids[0]);
          if (t <> '') and (t <> 'BOOL') then
            ErrN (st.kids[0], ctx,
              'condition must be BOOL, not ' + TyName (t));
          pre := OwnSnap;
          SetLength (snaps, 0);
          WalkSeq (st.kids[1]);
          SetLength (snaps, 1);
          snaps[0] := OwnSnap;
          OwnRestore (pre);
          for j := 2 to High (st.kids) do
          begin
            if st.kids[j].kind = nkElsif then
            begin
              t := ExprType (st.kids[j].kids[0]);
              if (t <> '') and (t <> 'BOOL') then
                ErrN (st.kids[j].kids[0], ctx,
                  'condition must be BOOL, not ' + TyName (t));
              WalkSeq (st.kids[j].kids[1]);
            end
            else
              WalkSeq (st.kids[j].kids[0]);
            SetLength (snaps, Length (snaps) + 1);
            snaps[High (snaps)] := OwnSnap;
            OwnRestore (pre);
          end;
          for j := 0 to High (snaps) do
            OwnMergeMoves (snaps[j]);
        end;
      nkWhile :
        begin
          t := ExprType (st.kids[0]);
          if (t <> '') and (t <> 'BOOL') then
            ErrN (st.kids[0], ctx,
              'condition must be BOOL, not ' + TyName (t));
          k := finSinceLoop; finSinceLoop := 0; Inc (loopsOpen);
          pre := OwnSnap;
          WalkSeq (st.kids[1]);
          Dec (loopsOpen); finSinceLoop := k;
          hpre := OwnSnap;
          OwnRestore (pre);
          OwnMergeMoves (hpre);
        end;
      nkFor :
        begin
          { integer bounds, or two bounds of ONE enumeration:
            FOR c := Colour.Red TO Colour.Blue walks the members in
            declaration order (docs/enum-plan.md, part 2) }
          t := ExprType (st.kids[0]);
          u := ExprType (st.kids[1]);
          if IsTagged (t) or IsTagged (u) then
          begin
            if t <> u then
              ErrN (st, ctx, 'FOR over an enumeration needs both bounds of one type, not ' +
                TyName (t) + ' and ' + TyName (u));
            if st.kids[2] <> nil then
              ErrN (st, ctx, 'FOR over an enumeration takes no BY step');
            { the loop variable keeps its declared enumeration type }
            CheckForVar (st, t, True);
            CheckForNest (st);
            pre := OwnSnap;
            ForPush (st);
            k := finSinceLoop; finSinceLoop := 0; Inc (loopsOpen);
            WalkSeq (st.kids[3]);
            Dec (loopsOpen); finSinceLoop := k;
            ForPop;
            hpre := OwnSnap;
            OwnRestore (pre);
            OwnMergeMoves (hpre);
            Exit;
          end;
          if not IsIntish (t) then
            ErrN (st, ctx, 'FOR bounds must be integers, not ' + TyName (t));
          if not IsIntish (u) then
            ErrN (st, ctx, 'FOR bounds must be integers, not ' + TyName (u));
          if st.kids[2] <> nil then
          begin
            u := ExprType (st.kids[2]);
            if not IsIntish (u) then
              ErrN (st, ctx, 'FOR step must be an integer, not ' + TyName (u))
            { par 10: FOR ... BY ConstExpr (mirrors Sem.StepConst) }
            else if not StepConst (st.kids[2]) then
              ErrN (st, ctx,
                'a FOR step is a constant: BY takes a literal, a CONST or an expression of them (par 10)')
            else if ScalarConst (st.kids[2], sv64, sch) and (sv64 = 0) then
              ErrN (st, ctx, 'a FOR step of 0 never reaches its bound');
          end;
          CheckForVar (st, '', False);
          CheckForNest (st);
          pre := OwnSnap;
          ForPush (st);
          k := finSinceLoop; finSinceLoop := 0; Inc (loopsOpen);
          WalkSeq (st.kids[3]);
          Dec (loopsOpen); finSinceLoop := k;
          ForPop;
          hpre := OwnSnap;
          OwnRestore (pre);
          OwnMergeMoves (hpre);
        end;
      nkLoop :
        begin
          k := finSinceLoop;
          finSinceLoop := 0;
          Inc (loopsOpen);
          pre := OwnSnap;
          WalkSeq (st.kids[0]);
          Dec (loopsOpen);
          finSinceLoop := k;
          hpre := OwnSnap;
          OwnRestore (pre);
          OwnMergeMoves (hpre);
        end;
      nkCase :
        begin
          selTy := ExprType (st.kids[0]);
          labelsVariant := False;
          hasElse := False;
          haveVi := False;
          lblTxt := '';
          { judge totality against the SELECTOR's variant type when it
            is known; VariantOwner's by-name search cannot tell
            Json.Value.Str from Dict.Value.Str }
          haveSelVi := VariantOfType (selTy, selVi);
          covered := TStringList.Create; covered.CaseSensitive := True;
          pre := OwnSnap;
          SetLength (snaps, 0);
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkCaseArm then
            begin
              for k := 0 to High (st.kids[j].kids[0].kids) do
              begin
                lbl := st.kids[j].kids[0].kids[k];
                vname := '';
                if lbl.kind = nkLabelPattern then
                begin
                  vname := lbl.a;
                  BindPattern (lbl, EscRootOf (st.kids[0]));
                end
                else if (LabelName (lbl.kids[0]) <> '') and
                        (lbl.kids[1] = nil) then
                  vname := LabelName (lbl.kids[0]);
                if (vname <> '') and
                   ((haveSelVi and (InList (vname, selVi.variants)))
                    or ((not haveSelVi) and VariantOwner (vname, vi))) then
                begin
                  labelsVariant := True;
                  haveVi := True;
                  covered.Add (vname);
                end
                else if lbl.kind = nkLabelRange then
                begin
                  t := ExprType (lbl.kids[0]);
                  if not (Compat (selTy, t) or Compat (t, selTy)) then
                    ErrN (lbl.kids[0], ctx, Format (
                      'CASE label is %s but the selector is %s',
                      [TyName (t), TyName (selTy)]));
                  { a repeated label is decided at compile time, and
                    until now only the C compiler decided it -- which
                    reports against generated code the author never
                    wrote.  Single literal labels only: a range needs
                    interval overlap and a CONST designator needs the
                    value, and guessing at either would be worse than
                    the gap. }
                  if lbl.kids[1] = nil then
                  begin
                    lblTxt := ExprText (lbl.kids[0]);
                    if (lblTxt <> '') and (covered.IndexOf (lblTxt) >= 0) then
                      ErrN (lbl.kids[0], ctx,
                        'CASE label ' + lblTxt + ' appears twice')
                    else if lblTxt <> '' then
                      covered.Add (lblTxt);
                  end;
                  if lbl.kids[1] <> nil then
                  begin
                    t := ExprType (lbl.kids[1]);
                    if not (Compat (selTy, t) or Compat (t, selTy)) then
                      ErrN (lbl.kids[1], ctx, Format (
                        'CASE label is %s but the selector is %s',
                        [TyName (t), TyName (selTy)]));
                  end;
                end;
              end;
              WalkSeq (st.kids[j].kids[1]);
              SetLength (snaps, Length (snaps) + 1);
              snaps[High (snaps)] := OwnSnap;
              OwnRestore (pre);
            end
            else
            begin
              hasElse := True;
              WalkSeq (st.kids[j].kids[0]);
              SetLength (snaps, Length (snaps) + 1);
              snaps[High (snaps)] := OwnSnap;
              OwnRestore (pre);
            end;
          for k := 0 to High (snaps) do
            OwnMergeMoves (snaps[k]);
          if labelsVariant and (not hasElse) and haveVi then
          begin
            if haveSelVi then vi := selVi
            else VariantOwner (covered[0], vi);
            for k := 0 to High (vi.variants) do
              if covered.IndexOf (vi.variants[k]) < 0 then
                ErrN (st, ctx,
                  'CASE over CASE RECORD is not total (missing ' +
                  vi.variants[k] + ')');
          end;
          { a CASE over a CHAR or an integer needs an ELSE (mirrors
            Sem.CheckCaseElse) }
          if (not hasElse) and ((selTy = 'CHAR') or IsIntStr (selTy) or (selTy = 'BYTE')) then
            ErrN (st, ctx, 'a CASE over ' + TyName (selTy) +
              ' needs an ELSE: a value no label names would have nowhere to go (par 8)');
          covered.Free;
        end;
      nkReturn :
        begin
          if st.kids[0] = nil then
          begin
            if retTy <> '<void>' then
              ErrN (st, ctx, 'RETURN without a value in a function');
          end
          else
          begin
            t := ExprType (st.kids[0]);
            if retTy = '<void>' then
              ErrN (st, ctx, 'RETURN with a value in a proper procedure')
            else if t = '<void>' then
              ErrN (st.kids[0], ctx, 'RETURN of a call that returns no value')
            else if not Compat (retTy, t) then
              ErrN (st.kids[0], ctx, Format (
                'cannot RETURN %s from a function of type %s',
                [TyName (t), TyName (retTy)]));
            { P3: a pool-interior pointer may not escape a pool that
              dies with this frame (par 4.3) }
            said := False;
            if (st.kids[0].kind = nkDesignator) and
               (Length (st.kids[0].kids) = 0) then
            begin
              dcl := ScopeType (st.kids[0].a);
              if (dcl <> nil) and (dcl.kind = nkPtrType) and
                 (dcl.kids[1] <> nil) and
                 (ScopeMode (dcl.kids[1].a) = 'l') then
              begin
                ErrN (st, ctx,
                  'pool-interior pointer escapes its pool: ' +
                  st.kids[0].a + ' lives in ' + dcl.kids[1].a +
                  ', which dies with this frame (par 4.3)');
                said := True;
              end;
            end;
            { the same by SHAPE: an allocation in a local pool held in
              a pool-less name, or a view of one -- except a string,
              re-homed at exit (mirrors Sem.CheckReturn) }
            if (not said) and (t <> 'SLICE OF CHAR') then
            begin
              what := FrameWhat (st.kids[0], t);
              if KindPool (what) <> '' then
                ErrN (st, ctx, what +
                  ' escapes its pool, which dies with this frame (par 4.3)');
            end;
            { par 4.1 direction: what is RETURNed reaches the caller }
            vname := EscRootOf (st.kids[0]);
            if (vname <> '') and IsFrameMode (ScopeMode (vname)) then
              EscTarget (vname, '<return>');
            { par 2.3: a string RETURN needs no refusal -- the
              generator re-homes it into the caller's arena, copying a
              frame-local designator's bytes across (m9_strdup). }
          end;
        end;
      nkRaiseStmt :
        begin
          CheckExcName (st.kids[0], ctx);
          { a qualified name raises its BARE name -- `RAISE Io.IOError`
            raises IOError, not "Io".  Found by System.Exec, the first
            corpus procedure to raise another module's exception; the
            M9 checker had it right and semdiff said so. }
          if st.kids[0].b <> '' then
          begin
            if raised.Values[st.kids[0].b] = '' then
              raised.Values[st.kids[0].b] := 'RAISE';
          end
          else if raised.Values[st.kids[0].a] = '' then
            raised.Values[st.kids[0].a] := 'RAISE';
          CheckRaisePayload (st.kids[0], st.kids[1]);
          if st.kids[1] <> nil then
            for j := 0 to High (st.kids[1].kids) do
              ExprType (st.kids[1].kids[j]);
        end;
      nkDispose :
        begin
          DesigStrType (st.kids[0], False);
          if Length (st.kids[0].kids) = 0 then
          begin
            NoteUse (st.kids[0]);
            vname := ScopeMode (st.kids[0].a);
            if (vname = 'p') or (vname = 'v') or (vname = 'b') or (vname = 'r') then
              ErrN (st, ctx, 'cannot DISPOSE ' + st.kids[0].a +
                ': a borrow is not yours to free (take OWN, par 4.2)')
            else if fval.IndexOf (st.kids[0].a) >= 0 then
              ErrN (st, ctx, 'the frame owns ' + st.kids[0].a +
                '; it is freed at exit, not by DISPOSE (par 4.3)')
            else
            begin
              dcl := ResolveType (ScopeType (st.kids[0].a));
              if (dcl <> nil) and (dcl.kind = nkPtrType) and
                 (dcl.kids[1] <> nil) then
                ErrN (st, ctx, 'the pool owns ' + st.kids[0].a +
                  '; free the pool, not the pointer (par 4.3)')
              else if OwnedCandKind (st.kids[0].a) > 0 then
                OwnMark (st.kids[0].a, 'DISPOSEd', st);
            end;
          end;
        end;
      nkThread :
        begin
          { par 6: the argument held to the target's first parameter,
            and a bare owned pointer MOVED into the thread.  Mirrors
            Sem.CheckThread; neither checker looked at the argument
            before 2026-09-27 (docs/agent-review-2026-09-27.md F2). }
          taTy := ExprType (st.kids[1]);
          if st.kids[0].kind = nkDesignator then
          begin
            tname := DesigName (st.kids[0]);
            { the target is a procedure of THIS module (Sem.CheckThread) }
            if (Pos ('.', tname) > 0) and
               (Copy (tname, 1, Pos ('.', tname) - 1) <> curMod) then
            begin
              ErrN (st, ctx, 'THREAD (' + tname + '): the target must be a procedure of this module, not ' +
                Copy (tname, 1, Pos ('.', tname) - 1) + '''s -- start it from a procedure declared here (par 6)');
              Exit;
            end;
            { a frame allocation, or a name holding one, dies when
              this frame exits, which a thread does not wait for:
              storage handed to a thread is allocated with OWN }
            what := FrameWhat (st.kids[1], taTy);
            { a local pool's object is lent as any pool pointer is,
              unchecked until SHARABLE (mirrors Sem) }
            if (what <> '') and (KindPool (what) = '') then
              ErrN (st, ctx, 'THREAD (' + tname + '): cannot hand ' + what +
                ' to a thread -- it dies with this frame; allocate it' +
                ' with OWN (par 4.3)');
            tpTy := '';
            if LookupProcInfo (tname, tpr) then
            begin
              canonCtx := tpr.modName;
              tpl := tpr.node.kids[0];
              if (tpl <> nil) and (Length (tpl.kids) > 0) then
                tpTy := CanonT (tpl.kids[0].kids[1], 0);
              canonCtx := '';
            end;
            if (tpTy <> '') and (taTy <> '') then
              if not (Compat (tpTy, taTy) or Compat ('PTR ' + tpTy, taTy) or
                      Compat ('SHARED PTR ' + tpTy, taTy)) then
                ErrN (st, ctx, Format (
                  'THREAD (%s): cannot pass %s where %s is expected',
                  [tname, TyName (taTy), TyName (tpTy)]));
            if (st.kids[1].kind = nkDesignator) and
               (Length (st.kids[1].kids) = 0) then
            begin
              tamode := ScopeMode (st.kids[1].a);
              if not ((tamode = 'p') or (tamode = 'v') or
                      (tamode = 'b') or (tamode = 'r')) then
              begin
                tares := ResolveType (ScopeType (st.kids[1].a));
                if (tares <> nil) and (tares.kind = nkPtrType) and
                   (tares.kids[1] = nil) and
                   (OwnedCandKind (st.kids[1].a) > 0) and
                   (fval.IndexOf (st.kids[1].a) < 0) then
                  OwnMark (st.kids[1].a,
                    'moved into a THREAD running ' + tname, st);
              end;
            end;
          end;
        end;
      nkTransfer :
        begin ExprType (st.kids[0]); ExprType (st.kids[1]); end;
      nkWait, nkSignal :
        ExprType (st.kids[0]);
      nkExit :
        begin
          { EXIT leaves the innermost LOOP (mirrors Sem's NExit) }
          if loopsOpen = 0 then
            ErrN (st, ctx, 'EXIT outside a loop: EXIT leaves the innermost LOOP, WHILE or FOR (par 5)')
          else if finSinceLoop > 0 then
            ErrN (st, ctx, 'EXIT across a FINALLY would skip its cleanup: leave the protected block first, or move the loop inside it (par 5)');
        end;
      nkBlock :
        begin
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkFinally then Inc (finSinceLoop);
          WalkSeq (st.kids[0]);
          hpre := OwnSnap;
          SetLength (snaps, 0);
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkHandler then
            begin
              CheckExcName (st.kids[j].kids[0], ctx);
              if st.kids[j].kids[0].b <> '' then
                handled.Add (st.kids[j].kids[0].b)
              else
                handled.Add (st.kids[j].kids[0].a);
              { handler binders are names, TYPED since 2026-10-08 by
                the EXCEPTION declaration's fields in order, qualified
                in the declaring module (corpus/Sem.m9 says why) }
              xowner := '';
              if st.kids[j].kids[0].b <> '' then
                xdecl := ExcDeclOf (st.kids[j].kids[0].a, st.kids[j].kids[0].b, xowner)
              else
                xdecl := ExcDeclOf ('', st.kids[j].kids[0].a, xowner);
              if st.kids[j].kids[1] <> nil then
                for k := 0 to High (st.kids[j].kids[1].kids) do
                  if st.kids[j].kids[1].kids[k].kind = nkIdent then
                    BindName (st.kids[j].kids[1].kids[k].a,
                              ExcFieldType (xdecl, xowner, k));
              WalkSeq (st.kids[j].kids[2]);
              SetLength (snaps, Length (snaps) + 1);
              snaps[High (snaps)] := OwnSnap;
              OwnRestore (hpre);
            end
            else if st.kids[j].kind = nkFinally then
            begin
              for k := 0 to High (snaps) do
                OwnMergeMoves (snaps[k]);
              SetLength (snaps, 0);
              { the cleanup itself is outside its protected block }
              Dec (finSinceLoop);
              WalkSeq (st.kids[j].kids[0]);
            end;
          for k := 0 to High (snaps) do
            OwnMergeMoves (snaps[k]);
        end;
    end;
  end;

  procedure WalkSeq (s: TNode);
  var j : Integer;
  begin
    if s = nil then Exit;
    for j := 0 to High (s.kids) do
      WalkStmt (s.kids[j]);
  end;

var
  nm, origin : string;
  prc : TProcInfo;
  changed, selfHit : Boolean;
  a2, b2, msg2, msgE, dmode : string;
  j2 : Integer;
  tl : TStringList;
begin
  raised := TStringList.Create; raised.CaseSensitive := True;
  handled := TStringList.Create; handled.CaseSensitive := True;
  calls := TStringList.Create; calls.CaseSensitive := True;
  ownState := TStringList.Create; ownState.CaseSensitive := True;
  escSet := TStringList.Create; escSet.CaseSensitive := True;
  escEdges := TStringList.Create; escEdges.CaseSensitive := True;
  carryPair := TStringList.Create; carryPair.CaseSensitive := True;
  carryEdge := TStringList.Create; carryEdge.CaseSensitive := True;
  fval := TStringList.Create; fval.CaseSensitive := True;
  fvalKind := TStringList.Create;
  pval := TStringList.Create; pval.CaseSensitive := True;
  pendN := 0;
  SetLength (pendLn, 0); SetLength (pendCl, 0);
  SetLength (pendSrc, 0); SetLength (pendDst, 0);
  { par 2.4, the copy: the marks before the walk, since a write may
    precede the assignment that marks the name (Sem.CheckProcBody) }
  RoSeed (body);
  if nAgg > 0 then AggWalk (body, nkProcBody);
  if body.kind = nkStmtSeq then
    WalkSeq (body)
  else
    WalkStmt (body);
  { par 4.1, the DIRECTION: close the escape targets over the alias
    edges (symmetric, so the approximation errs INTO the ledger),
    then classify every pended store by where its destination
    reaches.  A for-loop's bound is fixed at entry, so entries added
    during a round are processed in the next one -- the repeat
    terminates because escSet only grows and is bounded by
    names x targets. }
  repeat
    changed := False;
    for i := 0 to escEdges.Count - 1 do
    begin
      a2 := escEdges.Names[i];
      b2 := escEdges.ValueFromIndex[i];
      for j2 := 0 to escSet.Count - 1 do
      begin
        if escSet.Names[j2] = a2 then
          if escSet.IndexOf (b2 + '=' + escSet.ValueFromIndex[j2]) < 0 then
          begin
            escSet.Add (b2 + '=' + escSet.ValueFromIndex[j2]);
            changed := True;
          end;
        if escSet.Names[j2] = b2 then
          if escSet.IndexOf (a2 + '=' + escSet.ValueFromIndex[j2]) < 0 then
          begin
            escSet.Add (a2 + '=' + escSet.ValueFromIndex[j2]);
            changed := True;
          end;
      end;
    end;
  until not changed;
  { close the carries over the copy edges, exactly as the escape
    targets closed over the alias edges }
  repeat
    changed := False;
    for i := 0 to carryEdge.Count - 1 do
    begin
      a2 := carryEdge.Names[i];
      b2 := carryEdge.ValueFromIndex[i];
      for j2 := 0 to carryPair.Count - 1 do
        if carryPair.Names[j2] = b2 then
          if carryPair.IndexOf (a2 + '=' + carryPair.ValueFromIndex[j2]) < 0 then
          begin
            carryPair.Add (a2 + '=' + carryPair.ValueFromIndex[j2]);
            changed := True;
          end;
    end;
  until not changed;
  for i := 0 to pendN - 1 do
  begin
    dmode := ScopeMode (pendSrc[i]);
    if (dmode = 'p') or (dmode = 'v') or (dmode = 'r') then
      EmitPend (pendLn[i], pendCl[i], pendSrc[i], '', pendDst[i])
    else if (dmode = 'l') or (dmode = 'b') then
    begin
      { a carrier resolves to one entry per borrow it carries -- and
        to NONE when it carries none, which is most locals }
      for j2 := 0 to carryPair.Count - 1 do
        if carryPair.Names[j2] = pendSrc[i] then
          EmitPend (pendLn[i], pendCl[i], carryPair.ValueFromIndex[j2],
                    pendSrc[i], pendDst[i]);
    end;
  end;
  { the lie detector: a KEPT parameter the analysis never saw
    retained.  A ledger class, not an error -- a borrow laundered
    through a call result is not yet seen, so an overstatement is a
    signal to read, not proof of a lie. }
  for i := 0 to keptParams.Count - 1 do
    if keptUsed.IndexOf (keptParams.Names[i]) < 0 then
      Ledger.Add (Format (
        '%s %s: kept-unseen: KEPT %s is not seen retained by this' +
        ' analysis (par 4.1)',
        [keptParams.ValueFromIndex[i], ctx, keptParams.Names[i]]));
  for i := 0 to raised.Count - 1 do
  begin
    nm := raised.Names[i];
    origin := raised.ValueFromIndex[i];
    if InList (nm, Unchecked) then Continue;
    if handled.IndexOf (nm) >= 0 then Continue;
    if InList (nm, declared) then Continue;
    { the edit, said (mirrors Sem.ReportUnhandled) }
    ErrN (body, ctx, 'unhandled RAISES ' + nm + ' from ' + origin +
      ' -- add it to this procedure''s RAISES, or handle it: EXCEPT | ' +
      nm + ' : ...');
  end;
  { par 3.2 rule 3: a PURE procedure may call only PURE procedures.
    This is what makes "no I/O" true without the checker knowing what
    I/O is -- a foreign procedure carries [SERIAL] or [REENTRANT] and
    is therefore never PURE, and neither is Io.WriteLine, so neither
    can be reached from a PURE body.  Purity is transitive by
    construction rather than by a second analysis.

    A callee that does not resolve to a declared procedure is a
    builtin -- LEN, ORD, a checked conversion, a variant constructor
    -- and those are pure, so they are skipped. }
  if curPure then
    for i := 0 to calls.Count - 1 do
      if LookupProcInfo (calls[i], prc) then
        if prc.attrib <> 'PURE' then
          ErrN (body, ctx, 'PURE procedure calls ' + calls[i] +
            ', which is not PURE (par 3.2)');
  raised.Free;
  handled.Free;
  calls.Free;
  ownState.Free;
  escSet.Free;
  escEdges.Free;
  carryPair.Free;
  carryEdge.Free;
  fval.Free;
  fvalKind.Free;
  pval.Free;
end;

procedure TSem.CheckFile (root: TNode);
var
  ui, i, j, k2 : Integer;
  u, d, p, sec : TNode;
  fmi : TModuleInfo;
  scope : TStringList;
  seenImp : TStringList;
  impB : TStringList;                { CheckImports: the binders in scope }
  declared : TStringArray;
  ctx, rt : string;

  { scope entries are 'name=mode': p value param, v VAR param,
    o OWN param, l proc-local, m module var, b binder }
  procedure AddVarsOf (holder: TNode; const mode: string);
  var a, b, c : Integer;
  begin
    if holder = nil then Exit;
    for a := 0 to High (holder.kids) do
      if (holder.kids[a] <> nil) and
         (holder.kids[a].kind = nkVarSection) then
        for b := 0 to High (holder.kids[a].kids) do
          for c := 0 to High (holder.kids[a].kids[b].kids[0].kids) do
          begin
            scope.AddObject (
              holder.kids[a].kids[b].kids[0].kids[c].a + '=' + mode,
              TObject (holder.kids[a].kids[b].kids[1]));
            if holder.kids[a].kids[b].f3 then
              roScope.Add (IntToStr (scope.Count - 1));
            { a module variable carries the unit-wide mark ModRoSeed
              gave it into every scope it enters (Sem.AddVarsOf) }
            if (mode = 'm') and
               (mro.Values[holder.kids[a].kids[b].kids[0].kids[c].a] <> '') then
              roFrom.Values[IntToStr (scope.Count - 1)] :=
                mro.Values[holder.kids[a].kids[b].kids[0].kids[c].a];
          end;
  end;

  { ---- par 2.4, the copy, for MODULE VARIABLES (Sem.ModRoSeed):
    before the bodies, every assignment in the unit whose left side is
    a bare module variable of slice or grid type, not shadowed by the
    enclosing procedure's declarations, and whose right side is a
    string literal, a CONST, a marked module variable or a SLICE of
    one, is recorded in `mro' as name=what|line. ---- }
  function ProcDeclares (sc: TNode; const name: string): Boolean; forward;

  function ModVarType (uu: TNode; const nm: string): TNode;
  var i, a, b, c : Integer; un, sect, vd : TNode;
  begin
    Result := nil;
    for i := 0 to High (root.kids) do
    begin
      un := root.kids[i];
      if (un = nil) or (un.a <> uu.a) then Continue;
      for a := 0 to High (un.kids) do
      begin
        sect := un.kids[a];
        if (sect = nil) or (sect.kind <> nkVarSection) then Continue;
        for b := 0 to High (sect.kids) do
        begin
          vd := sect.kids[b];
          if (vd = nil) or (vd.kids[0] = nil) then Continue;
          for c := 0 to High (vd.kids[0].kids) do
            if vd.kids[0].kids[c].a = nm then Exit (vd.kids[1]);
        end;
      end;
    end;
  end;

  { the designator at the root of K, through SLICE/VIEW/SHARED,
    parentheses and SOME -- Sem.EscRootOf, which lives in CheckBody }
  function MroRoot (e: TNode): string;
  var nm : string;
  begin
    Result := '';
    if e = nil then Exit;
    if e.kind = nkDesignator then Exit (e.a);
    if (e.kind = nkSomeExpr) or (e.kind = nkParen) then
      Exit (MroRoot (e.kids[0]));
    if (e.kind = nkCallExpr) and (e.kids[0] <> nil) and
       (e.kids[0].kind = nkDesignator) and
       (Length (e.kids[0].kids) = 0) then
    begin
      nm := e.kids[0].a;
      if ((nm = 'SLICE') or (nm = 'VIEW') or (nm = 'SHARED')) and
         (e.kids[1] <> nil) and (Length (e.kids[1].kids) > 0) then
        Exit (MroRoot (e.kids[1].kids[0]));
    end;
  end;

  { Sem.RoAnswerOf, for the unit-wide prepass (RoAnswerOf lives in
    CheckBody) }
  function MroAnswer (e: TNode): string;
  var pr : TProcInfo; name : string;
  begin
    Result := '';
    if (e.kids[0] = nil) or (e.kids[0].kind <> nkDesignator) then Exit;
    name := CallName (e.kids[0]);
    if not LookupProcInfo (name, pr) then Exit;
    if (pr.node <> nil) and pr.node.f3 then Result := 'the RO answer of ' + name;
  end;

  function ModRoWhat (k, sc: TNode): string;
  var r, v : string;
  begin
    Result := '';
    if k = nil then Exit;
    if k.kind = nkString then
    begin
      if Length (k.a) = 0 then Exit;
      Exit ('a string literal');
    end;
    if (k.kind = nkSliceOf3) or (k.kind = nkGridOf) then
      Exit (ModRoWhat (k.kids[0], sc));
    if k.kind = nkCallExpr then Exit (MroAnswer (k));
    r := MroRoot (k);
    if r = '' then Exit;
    if ProcDeclares (sc, r) then Exit;
    v := mro.Values[r];
    if v <> '' then Exit (Copy (v, 1, Pos ('|', v) - 1));
    if constMap.IndexOfName (r) >= 0 then Exit ('the CONST ' + r);
  end;

  function ModRoWalk (uu, sc, k: TNode): Boolean;
  var j : Integer; what, ty : string; lhs : TNode;
  begin
    Result := False;
    if k = nil then Exit;
    if (k.kind = nkAssign) and (k.kids[0] <> nil) then
    begin
      lhs := k.kids[0];
      if (lhs.kind = nkDesignator) and (Length (lhs.kids) = 0) and
         (mro.Values[lhs.a] = '') and not ProcDeclares (sc, lhs.a) then
      begin
        if ModVarType (uu, lhs.a) = nil then ty := ''
        else ty := CanonT (ModVarType (uu, lhs.a), 0);
        if StartsWithS (ty, 'SLICE OF') or StartsWithS (ty, 'GRID ') then
        begin
          what := ModRoWhat (k.kids[1], sc);
          if what <> '' then
          begin
            mro.Values[lhs.a] := what + '|' + IntToStr (k.line);
            Result := True;
          end;
        end;
      end;
    end;
    for j := 0 to High (k.kids) do
      if k.kind in [nkProcDecl, nkModBody] then
      begin
        if ModRoWalk (uu, k, k.kids[j]) then Result := True;
      end
      else
        if ModRoWalk (uu, sc, k.kids[j]) then Result := True;
  end;

  procedure ModRoSeed (uu: TNode);
  var n : Integer;
  begin
    mro.Clear;
    n := 0;
    while ModRoWalk (uu, nil, uu) and (n < 8) do Inc (n);
  end;

  { par 6: the name of the first parameter when its type is a
    MONITOR RECORD, else ''.  That parameter is the binding. }
  function BoundMonitorOf (procNode: TNode): string;
  var
    grp, rt : TNode;
  begin
    Result := '';
    if procNode = nil then Exit;
    if Length (procNode.kids[0].kids) = 0 then Exit;
    grp := procNode.kids[0].kids[0];
    if Length (grp.kids[0].kids) = 0 then Exit;
    rt := ResolveType (grp.kids[1]);
    while (rt <> nil) and (rt.kind in [nkPtrType, nkSharedType]) do
      rt := ResolveType (rt.kids[0]);
    if (rt <> nil) and (rt.kind = nkMonitorType) then
      Result := grp.kids[0].kids[0].a;
  end;

  { ---- a module is named only where it is imported (report par 3,
    rule 5).  corpus/Sem.m9's CheckImports says why; this is the same
    walk, in the same order, with the same words. ---- }
  function ModImports (const me, name: string): Boolean;
  var
    a, b, c : Integer;
    uu, imp : TNode;
  begin
    if me = name then Exit (True);
    for a := 0 to High (root.kids) do
    begin
      uu := root.kids[a];
      if (uu = nil) or (uu.a <> me) then Continue;
      for b := 0 to High (uu.kids) do
      begin
        imp := uu.kids[b];
        if imp = nil then Continue;
        if imp.kind = nkFromImport then
        begin
          if imp.a = name then Exit (True);
        end
        else if (imp.kind = nkImportList) and (imp.kids[0] <> nil) then
          for c := 0 to High (imp.kids[0].kids) do
            if (imp.kids[0].kids[c] <> nil) and
               (imp.kids[0].kids[c].a = name) then Exit (True);
      end;
    end;
    Result := False;
  end;

  function DeclaresName (n: TNode; const name: string): Boolean;
  var a : Integer;
  begin
    Result := False;
    if n = nil then Exit;
    if (n.kind in [nkIdent, nkIsSome, nkTypeDecl, nkConstDecl, nkExcDecl])
       and (n.a = name) then Exit (True);
    for a := 0 to High (n.kids) do
      if DeclaresName (n.kids[a], name) then Exit (True);
  end;

  { at the level of the module `me' -- Sem.ModuleDeclares }
  function ModuleDeclares (const me, name: string): Boolean;
  var
    a, b : Integer;
    uu, dd : TNode;
  begin
    for a := 0 to High (root.kids) do
    begin
      uu := root.kids[a];
      if (uu = nil) or (uu.a <> me) then Continue;
      for b := 0 to High (uu.kids) do
      begin
        dd := uu.kids[b];
        if dd = nil then Continue;
        if not (dd.kind in [nkProcDecl, nkModBody, nkImportList,
                            nkFromImport]) then
          if DeclaresName (dd, name) then Exit (True);
      end;
    end;
    Result := False;
  end;

  { anywhere under the procedure or module body `sc', a binder in any
    arm included, or at the module's level: ExportWalk's test
    (decision 28); ImportWalk has the scoped one since 2026-10-08 }
  function NameShadowed (const me: string; sc: TNode;
                         const name: string): Boolean;
  begin
    if DeclaresName (sc, name) then Exit (True);
    Result := ModuleDeclares (me, name);
  end;

  { the procedure's own declarations -- parameters and the sections
    of its body -- and not the binders in its statements (Sem.ProcDeclares) }
  function ProcDeclares (sc: TNode; const name: string): Boolean;
  var a : Integer;
  begin
    Result := False;
    if (sc = nil) or (sc.kind <> nkProcDecl) then Exit;
    if DeclaresName (sc.kids[0], name) then Exit (True);
    if sc.kids[4] <> nil then
      for a := 0 to High (sc.kids[4].kids) - 1 do
        if DeclaresName (sc.kids[4].kids[a], name) then Exit (True);
  end;

  { the name `IS SOME' binds in a condition, or '' (Sem.CondBinder) }
  function CondBinder (c: TNode): string;
  begin
    Result := '';
    if (c <> nil) and (c.kind = nkIs) and (Length (c.kids) > 1) and
       (c.kids[1] <> nil) and (c.kids[1].kind = nkIsSome) then
      Result := c.kids[1].a;
  end;

  { push the binders of a CASE arm's label patterns, or of a handler's
    payload list; answer how many (Sem.PushBinders) }
  function PushBinders (l: TNode): Integer;
  var a, b : Integer;
  begin
    Result := 0;
    if l = nil then Exit;
    if l.kind = nkLabelList then
    begin
      for a := 0 to High (l.kids) do
        if (l.kids[a] <> nil) and (l.kids[a].kind = nkLabelPattern) and
           (l.kids[a].kids[0] <> nil) then
          for b := 0 to High (l.kids[a].kids[0].kids) do
          begin
            impB.Add (l.kids[a].kids[0].kids[b].a);
            Inc (Result);
          end;
    end
    else if l.kind = nkArgList then
      for a := 0 to High (l.kids) do
        if (l.kids[a] <> nil) and (l.kids[a].kind = nkIdent) then
        begin
          impB.Add (l.kids[a].a);
          Inc (Result);
        end;
  end;

  procedure BinderPop (n: Integer);
  begin
    while (n > 0) and (impB.Count > 0) do
    begin
      impB.Delete (impB.Count - 1);
      Dec (n);
    end;
  end;

  { Sem.ExportWalk: the designator Mod.v... of an imported, unshadowed
    module's exported variable becomes the designator rooted at the one
    name Mod.v (decision 28) }
  procedure ExportWalk (uu, sc, n: TNode);
  var
    a : Integer;
    s : TNode;
    mi : TModuleInfo;
    hit : Boolean;
  begin
    if n = nil then Exit;
    if (n.kind = nkDesignator) and (Length (n.kids) > 0) and
       (n.kids[0] <> nil) and (n.kids[0].kind = nkSelField) and
       (n.a <> uu.a) then
    begin
      s := n.kids[0];
      mi := FindMod (n.a);
      hit := False;
      if mi <> nil then
        for a := 0 to High (mi.vrNames) do
          if mi.vrNames[a] = s.a then hit := True;
      if hit and ModImports (uu.a, n.a) and not NameShadowed (uu.a, sc, n.a) then
      begin
        n.a := n.a + '.' + s.a;
        for a := 0 to High (n.kids) - 1 do n.kids[a] := n.kids[a + 1];
        SetLength (n.kids, Length (n.kids) - 1);
      end;
    end;
    for a := 0 to High (n.kids) do
      if n.kind in [nkProcDecl, nkModBody] then
        ExportWalk (uu, n, n.kids[a])
      else
        ExportWalk (uu, sc, n.kids[a]);
  end;

  { Sem.AddModuleVars, after AddVarsOf (u, 'm'): an implementation's
    definition's variables, and every other module's exports as Mod.v }
  procedure AddModuleExtra (u: TNode);
  var
    i, k : Integer;
  begin
    if u.kind = nkImplementation then
      for i := 0 to High (root.kids) do
        if (root.kids[i] <> nil) and (root.kids[i].kind = nkDefinition) and
           (root.kids[i].a = u.a) then
          AddVarsOf (root.kids[i], 'm');
    for i := 0 to High (mods) do
      if mods[i].name <> u.a then
        for k := 0 to High (mods[i].vrNames) do
        begin
          scope.AddObject (mods[i].name + '.' + mods[i].vrNames[k] + '=m',
            TObject (mods[i].vrTypes[k]));
          if mods[i].vrRo[k] then roScope.Add (IntToStr (scope.Count - 1));
        end;
  end;

  procedure ImportWalk (uu, sc, n: TNode; seen: TStringList);
  var
    a, np : Integer;
    qualified : Boolean;
    b : string;
  begin
    if n = nil then Exit;
    qualified := False;
    if n.kind = nkQualident then
      qualified := n.b <> ''
    else if (n.kind = nkDesignator) and (Length (n.kids) > 0) and
            (n.kids[0] <> nil) then
      qualified := n.kids[0].kind = nkSelField;
    { shadowed by a declaration of the procedure or the module, or by
      a binder IN SCOPE HERE -- until 2026-10-08 by a binder anywhere
      in the procedure, so a binder in one arm stood for the module in
      the next }
    if qualified and (FindMod (n.a) <> nil) and (seen.IndexOf (n.a) < 0) then
      if not ModImports (uu.a, n.a) then
        if not ProcDeclares (sc, n.a) and (impB.IndexOf (n.a) < 0) and
           not ModuleDeclares (uu.a, n.a) then
        begin
          seen.Add (n.a);
          ErrN (n, uu.a, 'module ' + n.a +
                ' is named and not imported: write IMPORT ' + n.a +
                ' (par 3)');
        end;
    if n.kind in [nkIf, nkElsif, nkWhile] then
    begin
      { the binder of `IS SOME' is in scope for the THEN or DO part
        and nowhere else: not the ELSIFs, not the ELSE }
      ImportWalk (uu, sc, n.kids[0], seen);
      b := CondBinder (n.kids[0]);
      if b <> '' then impB.Add (b);
      if Length (n.kids) > 1 then ImportWalk (uu, sc, n.kids[1], seen);
      if b <> '' then BinderPop (1);
      for a := 2 to High (n.kids) do ImportWalk (uu, sc, n.kids[a], seen);
    end
    else if n.kind = nkCaseArm then
    begin
      ImportWalk (uu, sc, n.kids[0], seen);
      np := PushBinders (n.kids[0]);
      if Length (n.kids) > 1 then ImportWalk (uu, sc, n.kids[1], seen);
      BinderPop (np);
    end
    else if n.kind = nkHandler then
    begin
      ImportWalk (uu, sc, n.kids[0], seen);
      if Length (n.kids) > 1 then ImportWalk (uu, sc, n.kids[1], seen);
      np := PushBinders (n.kids[1]);
      if Length (n.kids) > 2 then ImportWalk (uu, sc, n.kids[2], seen);
      BinderPop (np);
    end
    else
      for a := 0 to High (n.kids) do
        if n.kind in [nkProcDecl, nkModBody] then
          ImportWalk (uu, n, n.kids[a], seen)
        else
          ImportWalk (uu, sc, n.kids[a], seen);
  end;

  { ---- a name is declared once in its scope (report par 3, rule 6).
    corpus/Sem.m9's CheckDeclaredOnce says why; the same walk, the
    same words.  `once' holds the scope's names, each with its line
    and, for a forward heading, whether it is still open: the entry
    is 'name=line' for a closed one and 'name=line!' for an open
    forward heading. ---- }
  procedure DeclOnce (id: TNode; what: Integer; const me, where: string;
                      once: TStringList);
  var
    a : Integer;
    first : string;
  begin
    for a := 0 to once.Count - 1 do
      if once.Names[a] = id.a then
      begin
        first := once.ValueFromIndex[a];
        if (first <> '') and (first[Length (first)] = '!') and (what = 2) then
          once[a] := id.a + '=' + Copy (first, 1, Length (first) - 1)
        else
          ErrN (id, me, id.a + ' is declared twice in ' + where +
                ': the first is at line ' +
                IntToStr (StrToIntDef (StringReplace (first, '!', '',
                                                      []), 0)) +
                ' (par 3)');
        Exit;
      end;
    { a name entered for the first time -- not the body that closes a
      FORWARD, which exited above }
    if id.a = 'NaN' then
      ErrN (id, me, 'NaN is predeclared, the quiet NaN: a declaration may' +
            ' not take its name (par 2.1)');
    if what = 1 then
      once.Add (id.a + '=' + IntToStr (id.line) + '!')
    else
      once.Add (id.a + '=' + IntToStr (id.line));
  end;

  procedure SectionNames (sec: TNode; const me, where: string;
                          once: TStringList);
  var a, b : Integer;
  begin
    if sec = nil then Exit;
    if sec.kind in [nkConstSection, nkTypeSection, nkExcSection] then
    begin
      for a := 0 to High (sec.kids) do
        if sec.kids[a] <> nil then
          DeclOnce (sec.kids[a], 0, me, where, once);
    end
    else if sec.kind = nkVarSection then
      for a := 0 to High (sec.kids) do
        if (sec.kids[a] <> nil) and (sec.kids[a].kids[0] <> nil) then
          for b := 0 to High (sec.kids[a].kids[0].kids) do
            if sec.kids[a].kids[0].kids[b] <> nil then
              DeclOnce (sec.kids[a].kids[0].kids[b], 0, me, where, once);
  end;

  procedure CheckDeclaredOnce (uu: TNode);
  var
    once : TStringList;
    a, b, c, what : Integer;
    where : string;
    dd, prm : TNode;
  begin
    once := TStringList.Create;
    once.CaseSensitive := True;
    where := 'module ' + uu.a;
    for a := 0 to High (uu.kids) do
    begin
      dd := uu.kids[a];
      if dd = nil then Continue;
      if dd.kind = nkProcDecl then
      begin
        what := 1;
        if (Length (dd.kids) > 4) and (dd.kids[4] <> nil) then what := 2;
        DeclOnce (dd, what, uu.a, where, once);
      end
      else
        SectionNames (dd, uu.a, where, once);
    end;
    { each procedure: its parameters, then its locals, one scope }
    for a := 0 to High (uu.kids) do
    begin
      dd := uu.kids[a];
      if (dd = nil) or (dd.kind <> nkProcDecl) then Continue;
      once.Clear;
      where := 'procedure ' + dd.a;
      if dd.kids[0] <> nil then
        for b := 0 to High (dd.kids[0].kids) do
        begin
          prm := dd.kids[0].kids[b];
          if (prm = nil) or (prm.kids[0] = nil) then Continue;
          for c := 0 to High (prm.kids[0].kids) do
            if prm.kids[0].kids[c] <> nil then
              DeclOnce (prm.kids[0].kids[c], 0, uu.a, where, once);
        end;
      if (Length (dd.kids) > 4) and (dd.kids[4] <> nil) then
        for b := 0 to High (dd.kids[4].kids) do
          SectionNames (dd.kids[4].kids[b], uu.a, where, once);
    end;
    once.Free;
  end;

  procedure AddParamsOf (procNode: TNode);
  var
    a, b : Integer;
    grp : TNode;
    mode : string;
  begin
    if procNode = nil then Exit;
    for a := 0 to High (procNode.kids[0].kids) do
    begin
      grp := procNode.kids[0].kids[a];
      if grp.f1 then mode := 'v'
      else if grp.f2 then mode := 'o'
      else if grp.f3 then mode := 'r'      { RO: read-only borrow }
      else mode := 'p';
      for b := 0 to High (grp.kids[0].kids) do
      begin
        scope.AddObject (
          grp.kids[0].kids[b].a + '=' + mode,
          TObject (grp.kids[1]));
        { a POOL is not a candidate: NEW (pool, ...) mutates the arena
          without ever writing through the name, so "never written"
          would be an artifact of syntax, not a finding }
        if (mode = 'v') and not ((grp.kids[1] <> nil) and
           (grp.kids[1].kind = nkQualident) and
           (grp.kids[1].a = 'POOL')) then
          varParams.Add (grp.kids[0].kids[b].a);
        if grp.f4 then
          keptParams.Values[grp.kids[0].kids[b].a] :=
            IntToStr (grp.kids[0].kids[b].line) + ':' +
            IntToStr (grp.kids[0].kids[b].col);
      end;
    end;
  end;

begin
  for ui := 0 to High (root.kids) do
  begin
    u := root.kids[ui];
    curMod := u.a;
    curUnsafe := u.f1;
    fromMap.Clear;
    for i := 0 to High (u.kids) do
      if u.kids[i] <> nil then
        if u.kids[i].kind = nkFromImport then
        begin
          { FROM is for foreign FOR-C units only (there is no
            u.m9 to resolve).  A FROM of a loaded M9 module is a
            Modula-2 habit the generator cannot honour -- catch
            it HERE, at the mistake, not as a gen error later. }
          fmi := FindMod (u.kids[i].a);
          if (fmi <> nil) and (fmi.foreignLang = '') then
            ErrN (u.kids[i], u.a,
              'FROM imports from a foreign FOR-C unit; ' +
              u.kids[i].a + ' is an M9 module -- use IMPORT ' +
              u.kids[i].a + ' and write ' + u.kids[i].a + '.Name');
          for j := 0 to High (u.kids[i].kids[0].kids) do
            fromMap.Values[u.kids[i].kids[0].kids[j].a] := u.kids[i].a;
        end;
    seenImp := TStringList.Create; seenImp.CaseSensitive := True;
    impB := TStringList.Create; impB.CaseSensitive := True;
    for i := 0 to High (u.kids) do
      ImportWalk (u, nil, u.kids[i], seenImp);
    impB.Free;
    seenImp.Free;
    for i := 0 to High (u.kids) do
      ExportWalk (u, nil, u.kids[i]);
    CheckDeclaredOnce (u);
    constMap.Clear;
    nAgg := 0;
    { an IMPLEMENTATION sees the constants of its DEFINITION, the unit
      of the same name in this file.  It saw only its own until
      2026-10-02, so `n := K' -- K a real constant of the definition,
      n an I64 -- passed here, built, and answered 1 for 1.5, while a
      client's `n := Mod.K' was refused.  Entered FIRST: a constant
      the implementation declares under the same name is the
      implementation's. }
    if u.kind = nkImplementation then
      for i := 0 to High (root.kids) do
      begin
        d := root.kids[i];
        if (d <> nil) and (d.kind = nkDefinition) and (d.b = '') and
           (d.a = u.a) then
          for j := 0 to High (d.kids) do
            if (d.kids[j] <> nil) and (d.kids[j].kind = nkConstSection) then
              for k2 := 0 to High (d.kids[j].kids) do
                constMap.Values[d.kids[j].kids[k2].a] :=
                  LitType (d.kids[j].kids[k2].kids[0]);
      end;
    for i := 0 to High (u.kids) do
      if (u.kids[i] <> nil) and (u.kids[i].kind = nkConstSection) then
        for j := 0 to High (u.kids[i].kids) do
        begin
          if u.kind = nkDefinition then
            CheckAggregate (u.kids[i].kids[j], u.a, 1)
          else
            CheckAggregate (u.kids[i].kids[j], u.a, 0);
          constMap.Values[u.kids[i].kids[j].a] :=
            LitType (u.kids[i].kids[j].kids[0]);
        end;
    ModRoSeed (u);

    if (u.kind = nkDefinition) and (u.b <> '') then
    begin
      CheckForeignDef (u);
      Continue;
    end;
    { declarations before bodies: a type spelled wrong is reported
      where it is written, once, ahead of whatever the bodies make of
      a variable that has no type }
    CheckDeclTypes (u);
    if u.kind = nkImplementation then
      CheckConformance (u);

    for i := 0 to High (u.kids) do
    begin
      d := u.kids[i];
      if (d = nil) or (d.kind <> nkProcDecl) then Continue;
      if d.kids[4] = nil then Continue;
      p := d.kids[4];
      ctx := u.a + '.' + d.a;
      { a nested procedure parses and neither end supports one:
        refused by name (Sem.CheckProcBody) }
      for j := 0 to High (p.kids) - 1 do
        if (p.kids[j] <> nil) and (p.kids[j].kind = nkProcDecl) then
          ErrN (p.kids[j], ctx, 'a nested procedure is not supported: ' +
            p.kids[j].a + ' is declared inside ' + d.a +
            '; declare it at module level (par 3)');
      scope := TStringList.Create; scope.CaseSensitive := True; roScope.Clear; roFrom.Clear;
      varParams.Clear;
      keptParams.Clear;
      keptUsed.Clear;
      varWritten.Clear;
      { params and locals first: IndexOfName answers the first hit,
        so they shadow module-level vars of the same name }
      AddParamsOf (d);
      AddVarsOf (p, 'l');
      AddVarsOf (u, 'm');
      AddModuleExtra (u);
      { PROCEDURE-LOCAL CONSTs.  The grammar always allowed them and
        neither end implemented them: the generator said `unknown
        name` and this said NOTHING, because an unregistered name
        types as unknown and par 3's softness contract never
        diagnoses one.  A shadow of a module CONST is REFUSED rather
        than resolved: the map answers the first hit, so which one
        won would depend on insertion order. }
      localConsts.Clear;
      for j := 0 to High (p.kids) do
        if (p.kids[j] <> nil) and (p.kids[j].kind = nkConstSection) then
          for k2 := 0 to High (p.kids[j].kids) do
          begin
            if constMap.IndexOfName (p.kids[j].kids[k2].a) >= 0 then
              ErrN (p.kids[j].kids[k2], ctx,
                'a local CONST may not shadow a module CONST: ' +
                p.kids[j].kids[k2].a);
            CheckAggregate (p.kids[j].kids[k2], ctx, 2);
            constMap.Values[p.kids[j].kids[k2].a] :=
              LitType (p.kids[j].kids[k2].kids[0]);
            localConsts.Add (p.kids[j].kids[k2].a);
          end;
      declared := RaisesOf (d);
      { a RAISES clause may only cite an exception the reader can find }
      if d.kids[2] <> nil then
        for k2 := 0 to High (d.kids[2].kids) do
          CheckExcName (d.kids[2].kids[k2], ctx);
      { par 3.2: kid 3 is the attribute, if any }
      curPure := (d.kids[3] <> nil) and (d.kids[3].a = 'PURE');
      curInBody := False;
      boundMon := BoundMonitorOf (d);
      if d.kids[1] <> nil then
        rt := CanonT (d.kids[1], 0)
      else
        rt := '<void>';
      { par 3 rule 4, before the walk so that it is the procedure's
        first diagnostic on both sides }
      if (d.kids[1] <> nil) and (p.kids[High (p.kids)] <> nil) and
         not EndsStmt (p.kids[High (p.kids)]) then
        ErrN (d, ctx, 'a function must RETURN or RAISE on every path: ' +
                      d.a + ' can reach its END (par 3)');
      CheckBody (p.kids[High (p.kids)], ctx, declared, scope, rt);
      { RO evidence: VAR parameters this procedure never writes
        through and never lends onward.  Each is a read-only borrow
        wearing VAR because M9 has no other non-copying mode -- and
        a place the checker cannot tell a reader from a writer. }
      for j := 0 to varParams.Count - 1 do
        if varWritten.IndexOf (varParams[j]) < 0 then
          RoCand.Add (ctx + ': VAR ' + varParams[j] +
            ' is never written through');
      RoProcs := RoProcs + 1;
      { the locals go out of scope with the procedure }
      for j := 0 to localConsts.Count - 1 do
        if constMap.IndexOfName (localConsts[j]) >= 0 then
          constMap.Delete (constMap.IndexOfName (localConsts[j]));
      scope.Free;
    end;

    for i := 0 to High (u.kids) do
    begin
      sec := u.kids[i];
      if (sec = nil) or (sec.kind <> nkModBody) then Continue;
      ctx := u.a + ' body';
      scope := TStringList.Create; scope.CaseSensitive := True; roScope.Clear; roFrom.Clear;
      { a module body declares no parameters, so the KEPT lists must
        not carry the last procedure's into this frame's flush }
      keptParams.Clear;
      keptUsed.Clear;
      AddVarsOf (u, 'm');
      AddModuleExtra (u);
      { the program body is the one frame with no caller to declare
        RAISES to, and that makes it the frame where a program must
        SAY what it does about failure -- not the frame excused from
        saying.  museum/trunc-nan is a program body whose escaping
        ValueRange is the whole point, and excusing the root frame
        accepted it. }
      SetLength (declared, 0);
      { the module body is never PURE, and curPure must be cleared
        rather than inherited from whichever procedure was checked
        last -- it leaked into this frame on the first run and
        reported the body writing its own module variables }
      curPure := False;
      curInBody := True;
      boundMon := '';            { a module body binds no monitor }
      CheckBody (sec.kids[0], ctx, declared, scope, '<void>');
      scope.Free;
    end;

  end;
end;

end.
