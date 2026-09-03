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
  TProcInfo = record
    name, foreign, attrib : string;
    modName : string;
    raises : array of string;
    sig    : string;
    node   : TNode;
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
    tyI64 : TNode;                     { synthetic 'I64' for FOR vars }
    strNode : TNode;                   { the SLICE OF CHAR that STR names }
    tyCHAR : TNode;                    { its element }
    threadRoots : array of string;
    callGraph : TStringList;
    function FindMod (const n: string): TModuleInfo;
    procedure ErrN (n: TNode; const ctx, msg: string);
    function SigOf (p: TNode): string;
    function RaisesOf (p: TNode): TStringArray;
    function ExcKnown (const qual, nm: string): Boolean;
    procedure CheckExcName (n: TNode; const ctx: string);
    procedure CollectUnit (u: TNode);
    procedure CheckForeignDef (u: TNode);
    procedure CheckConformance (u: TNode);
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
    function ResolveType (t: TNode): TNode;
    function LookupTypeName (const modName, typeName: string): TNode;
    function CanonQual (const modName, typeName: string;
                        depth: Integer): string;
    function CanonT (t: TNode; depth: Integer): string;
    function IsReadonlyT (declN, res: TNode): Boolean;
    procedure CheckThreadChains;
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
  { ARRAY N OF T is the view of all N elements (par 2.2) }
  if StartsWithS (dst, 'SLICE OF ') and StartsWithS (src, 'ARRAY ') then
    Exit (ElemOfArray (src) = Copy (dst, 10, MaxInt));
  { a shared handle lends like a plain borrow (par 4.1) }
  if StartsWithS (dst, 'PTR ') and (src = 'SHARED ' + dst) then
    Exit (True);
  Result := False;
end;

{ type of a module-level CONST expression: literals and literal
  arithmetic; anything fancier stays unknown }
function LitType (e: TNode): string;
var l, r : string;
begin
  Result := '';
  if e = nil then Exit;
  case e.kind of
    nkInt  : Result := '<int>';
    nkReal : Result := '<real>';
    nkChar : Result := 'CHAR';
    nkString :
      if Length (e.a) = 1 then Result := '<str1>'
      else Result := 'SLICE OF CHAR';
    nkTrue, nkFalse : Result := 'BOOL';
    nkParen, nkUn : Result := LitType (e.kids[0]);
    nkBin :
      begin
        l := LitType (e.kids[0]);
        r := LitType (e.kids[1]);
        if (l = '<int>') and (r = '<int>') then Result := '<int>'
        else if (l = '<real>') and (r = '<real>') then Result := '<real>';
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
  callGraph := TStringList.Create; callGraph.CaseSensitive := True;
  RoCand := TStringList.Create; RoCand.CaseSensitive := True;
  varParams := TStringList.Create; varParams.CaseSensitive := True;
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
  Errors.Free;
  Ledger.Free;
  fromMap.Free;
  constMap.Free;
  callGraph.Free;
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

{ ---- registry ---- }

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
            p.fromDef := u.kind = nkDefinition;
            p.hasBody := d.kids[4] <> nil;
            m.AddProc (p);
          end
          else if d.kids[4] <> nil then
            m.procs[pi].hasBody := True;
        end;
      nkExcSection :
        { the declared exceptions: RAISE/RAISES/handler may only cite
          a name the reader can find -- one declared here, one
          predeclared, or one qualified into the module that owns it }
        for j := 0 to High (d.kids) do
        begin
          SetLength (m.exNames, Length (m.exNames) + 1);
          m.exNames[High (m.exNames)] := d.kids[j].a;
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
          if td.kids[0].kind = nkCaseRecordType then
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
              m.vts[k].fields[vi] := cr.kids[vi].kids[0];
            end;
          end;
        end;
    end;
  end;
end;

procedure TSem.LoadFile (root: TNode);
var i : Integer;
begin
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
    Exit (m.FindType (typeName));
  end;
  m := FindMod (curMod);
  if m <> nil then
  begin
    Result := m.FindType (typeName);
    if Result <> nil then Exit;
  end;
  for i := 0 to High (mods) do
  begin
    Result := mods[i].FindType (typeName);
    if Result <> nil then Exit;
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
      if td.kind in [nkRecordType, nkCaseRecordType, nkMonitorType] then
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

function TSem.CanonT (t: TNode; depth: Integer): string;
var s : string;
begin
  Result := '';
  if (t = nil) or (depth > 8) then Exit;
  case t.kind of
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

  function ScopeMode (const nm: string): string;
  var ix : Integer;
  begin
    ix := scope.IndexOfName (nm);
    if ix < 0 then Exit ('');
    Result := scope.ValueFromIndex[ix];
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

  function IsFrameMode (const m: string): Boolean;
  begin
    Result := (m = 'l') or (m = 'b') or (m = 'p');
  end;

  { does this right-hand side yield a FRAME-SCOPED string (par 2.3)?
    A concatenation is one -- it is built in the frame arena -- and so
    is a bare name that already holds one (fval).  Through parens and
    SOME.  `u` is the RHS's type, so a numeric `+` (not SLICE OF CHAR)
    is not mistaken for a concatenation. }
  function FrameRHS (e: TNode; const u: string): Boolean;
  begin
    Result := False;
    while (e <> nil) and ((e.kind = nkParen) or (e.kind = nkSomeExpr)) do
      e := e.kids[0];
    if e = nil then Exit;
    if (e.kind = nkBin) and (e.a = '+') and (u = 'SLICE OF CHAR') then
      Exit (True);
    if (e.kind = nkDesignator) and (Length (e.kids) = 0) then
      Result := fval.IndexOf (e.a) >= 0;
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
  begin
    Result := d.a;
    if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
      Result := Result + '.' + d.kids[0].a;
  end;

  function ExprType (e: TNode): string; forward;

  function CT (t: TNode): string;
  begin
    Result := CanonT (t, 0);
  end;

  function IsIntish (const s: string): Boolean;
  begin
    Result := (s = '') or (s = '<int>') or IsIntStr (s);
  end;

  { the designator walk over DECLARED type nodes; guard mode is the
    operand of IS, where the final OPT component is legal.  Errors
    fire only when a selector is applied THROUGH an OPT or CASE
    RECORD component; the walk goes soft (nil) on anything unknown. }
  function DesigDeclType (d: TNode; guard: Boolean): TNode;
  var
    j, k : Integer;
    declN, res, f : TNode;
    sel : TNode;
    it : string;
  begin
    declN := ScopeType (d.a);
    for j := 0 to High (d.kids) do
    begin
      sel := d.kids[j];
      if sel.kind = nkSelIndex then
        { every axis, not just the first: a grid subscript list is as
          long as the rank and each one of them is an index }
        for k := 0 to High (sel.kids) do
        begin
          it := ExprType (sel.kids[k]);
          if not IsIntish (it) then
            ErrN (d, ctx, 'index must be an integer, not ' + TyName (it));
        end;
      if declN = nil then Continue;
      res := ResolveType (declN);
      { auto-deref before applying the selector }
      while (res <> nil) and (res.kind in [nkPtrType, nkSharedType]) do
      begin
        declN := res.kids[0];
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
            f := FieldTypeOf (res, sel.a);
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
            if (boundMon = '') or (d.a <> boundMon) or (j <> 0) then
              ErrN (d, ctx, 'monitor field ' + sel.a + ' is reached ' +
                'from outside a procedure bound to the monitor (par 6)');
            declN := FieldSeqType (res.kids[0], sel.a);
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
            declN := res.kids[1];
          end
          else if res.kind = nkSliceType then
          begin
            if Length (sel.kids) <> 1 then
              ErrN (d, ctx, 'a slice takes one subscript, not ' +
                IntToStr (Length (sel.kids)));
            declN := res.kids[0];
          end
          else if res.kind = nkArrayType then
          begin
            if Length (sel.kids) <> 1 then
              ErrN (d, ctx, 'an array takes one subscript, not ' +
                IntToStr (Length (sel.kids)));
            declN := res.kids[1];
          end
          else
            declN := nil;
      end;
    end;
    Result := declN;
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
      if ci >= 0 then
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
          else
            s := '';
        end;
        Exit (s);
      end;
      if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) and
         FindVariant (d.a, d.kids[0].a, om, fn) then
        Exit (om + '.' + d.a);
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
  function CheckWrite (d: TNode): Boolean;
  var
    j : Integer;
    declN, res : TNode;
    sel : TNode;
    mode : string;
  begin
    Result := False;
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
    declN := ScopeType (d.a);
    for j := 0 to High (d.kids) do
    begin
      sel := d.kids[j];
      if declN = nil then Exit;
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
        declN := res.kids[0];
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
            declN := FieldTypeOf (res, sel.a);
          end
          else if res.kind = nkMonitorType then
          begin
            if (j < High (d.kids)) and FieldSeqRO (res.kids[0], sel.a) then
              ErrN (d, ctx, 'cannot write through the RO field ' +
                sel.a + ' (par 4.1)');
            declN := FieldSeqType (res.kids[0], sel.a);
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
            declN := res.kids[0];
          end
          else if res.kind = nkGridType then
          begin
            if IsReadonlyT (declN, res) then
              ErrN (d, ctx,
                'cannot write through a read-only grid: ' + d.a);
            Result := True;      { grid storage outlives the frame }
            declN := res.kids[1];
          end
          else if res.kind = nkArrayType then
            declN := res.kids[1]
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
    name, om, pTy, amode, aliasTo : string;
    nargs, j, g, k, kept, dot : Integer;
    aTy : array of string;
    aNode : array of TNode;
    pr : TProcInfo;
    pl, grp, vfields, ares, dcl : TNode;
    isVar : Boolean;
    flat : array of TNode;

    procedure Arity (want: Integer);
    begin
      if nargs <> want then
        ErrN (site, ctx, Format ('%s expects %d argument(s), got %d',
          [name, want, nargs]));
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
      Exit ('');
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
    if LookupProcInfo (name, pr) then
    begin
      for j := 0 to High (pr.raises) do
        if raised.Values[pr.raises[j]] = '' then
          raised.Values[pr.raises[j]] := 'call to ' + name;
      canonCtx := pr.modName;
      pl := pr.node.kids[0];
      Arity (CountParams (pl));
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
                dcl := StripParens (aNode[k]);
                if (dcl <> nil) and (dcl.kind = nkBin) and
                   (dcl.a = '+') and (aTy[k] = 'SLICE OF CHAR') then
                  ErrN (site, ctx, Format (
                    'argument %d of %s: a KEPT parameter cannot take' +
                    ' a concatenation -- it dies with this frame' +
                    ' (par 4.1)', [k + 1, name]));
                aliasTo := EscRootOf (aNode[k]);
                if (aliasTo <> '') and IsRefTy (aTy[k]) then
                begin
                  amode := ScopeMode (aliasTo);
                  { handing a borrow onward to a KEPT parameter is
                    what justifies the caller's own KEPT }
                  if (amode = 'p') or (amode = 'v') or (amode = 'r') then
                    keptUsed.Add (aliasTo);
                  if ((amode = 'p') or (amode = 'v') or (amode = 'r'))
                     and (keptParams.IndexOfName (aliasTo) < 0) then
                    ErrN (site, ctx, Format (
                      'argument %d of %s: borrowed %s is kept by the' +
                      ' callee -- declare KEPT %s (par 4.1)',
                      [k + 1, name, aliasTo, aliasTo]));
                  if IsFrameMode (amode) then
                    EscTarget (aliasTo, '<call>');
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
    dot := Pos ('.', name);
    if (dot > 0) and
       FindVariant (Copy (name, 1, dot - 1),
                    Copy (name, dot + 1, MaxInt), om, vfields) then
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
      Exit (om + '.' + Copy (name, 1, dot - 1));
    end;
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
      else if not (Compat (lt, rt) or Compat (rt, lt)) then
        ErrN (e, ctx, Format ('cannot compare %s with %s',
          [TyName (lt), TyName (rt)]));
      Exit ('BOOL');
    end;
    { string concatenation, before the arithmetic rules: `+` on two
      strings answers a string, allocated in HEAP (par 4.3).  Not on
      a bare CHAR -- a character is a scalar, and `s + c` would have
      to decide silently whether c is a character or a number; write
      DynStr.AppendChar, or a one-character literal, which IS a
      string. }
    if (op = '+') and (StrSide (lt) or StrSide (rt)) then
    begin
      if not StrSide (lt) then
        ErrN (e, ctx, 'cannot concatenate ' + TyName (lt) + ' with a string')
      else if not StrSide (rt) then
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

  function ExprType (e: TNode): string;
  var
    j : Integer;
    t, u : string;
    res, inr, pt : TNode;
  begin
    Result := '';
    if e = nil then Exit;
    case e.kind of
      nkInt  : Result := '<int>';
      nkReal : Result := '<real>';
      nkChar : Result := 'CHAR';
      nkString :
        if Length (e.a) = 1 then Result := '<str1>'
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
          if e.kids[0] <> nil then u := ExprType (e.kids[0])
          else u := '';
          { the type position holding the name of a POOL VARIABLE is
            conclusive: a pool is not a type and nothing can be
            allocated OF one.  A pool's own type is not recorded as a
            value type -- ExprType of a pool name is unknown, which is
            why the softer tests said nothing -- so the scope's
            declared TYPE NODE is what answers. }
          { par 3.2: allocating from a pool the CALLER owns consumes
            the caller's storage and answers a slice into the caller's
            arena -- an effect, and the one a PURE body could still
            have, since NEW is a builtin (rule 3 does not see it) and
            not an assignment target (rules 1 and 2 do not either).
            A pool declared LOCAL is invisible outside the frame and
            stays legal. }
          if curPure and (e.kids[0] <> nil) and
             (e.kids[0].kind = nkDesignator) and
             ((ScopeMode (e.kids[0].a) = 'v') or
              (ScopeMode (e.kids[0].a) = 'o') or
              (ScopeMode (e.kids[0].a) = 'm')) then
            ErrN (e, ctx, 'cannot allocate from the pool ' + e.kids[0].a +
              ' in a PURE procedure (par 3.2)');
          pt := ScopeType (e.kids[1].a);
          if (e.kids[1].kind = nkQualident) and (pt <> nil) and
             (pt.kind = nkQualident) and (pt.a = 'POOL') then
            ErrN (e, ctx, 'NEW takes the pool first, then the type');
          if (u <> '') and (u <> 'POOL') then
            ErrN (e, ctx, 'NEW''s first argument is the pool, not '
                          + TyName (u));
          t := CanonT (e.kids[1], 0);
          if e.kids[2] <> nil then
          begin
            { one extent is a slice; more than one is a GRID, and the
              arity states the rank so the two cannot disagree }
            for j := 2 to High (e.kids) do
            begin
              u := ExprType (e.kids[j]);
              if not IsIntish (u) then
                ErrN (e, ctx,
                  'NEW extent must be an integer, not ' + TyName (u));
            end;
            { one extent is a SLICE, as it always was; more than one
              is a GRID, and the arity states the rank }
            if Length (e.kids) = 3 then
            begin
              if t <> '' then Result := 'SLICE OF ' + t;
            end
            else
              Result := GridOf (Length (e.kids) - 2, t);
          end
          else if t <> '' then
            Result := 'PTR ' + t;
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
            if e.kids[1].kind = nkIsSome then
            begin
              t := CT (res);
              res := ResolveType (res);
              if (res <> nil) and (res.kind = nkOptType) then
                BindName (e.kids[1].a, res.kids[0])
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
            ExprType (e.kids[0]);
            if e.kids[1].kind = nkIsSome then
              BindName (e.kids[1].a, nil);
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
          { a bare value name known to NO part of the checker's name
            universe is undefined -- the symmetric twin of the
            unknown-procedure check.  Only in ExprType (a body-walk
            value context, scope populated), never in DesigStrType,
            which the signature checks also call without a scope. }
          if (Length (e.kids) = 0) and not BareNameKnown (e.a) then
            ErrN (e, ctx, 'unknown name: ' + e.a);
          Result := DesigStrType (e, False);
        end;
      nkCallExpr : Result := CallType (e.kids[0], e.kids[1], e);
    else
      for j := 0 to High (e.kids) do
        ExprType (e.kids[j]);
    end;
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

  procedure WalkStmt (st: TNode);
  var
    j, k : Integer;
    lblTxt : string;                 { a scalar CASE label, printed }
    labelsVariant, hasElse, beyond, haveSelVi : Boolean;
    vi, selVi : TVariantInfo;
    haveVi : Boolean;
    covered : TStringList;
    lbl, dcl : TNode;
    vname : string;
    t, u, selTy, dmode : string;
    pre, hpre : string;
    snaps : array of string;
  begin
    case st.kind of
      nkAssign :
        begin
          t := DesigStrType (st.kids[0], False);
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
          if FrameRHS (st.kids[1], u) then
          begin
            dmode := ScopeMode (st.kids[0].a);
            if (dmode = 'm') and not curInBody then
              ErrN (st.kids[1], ctx, 'a concatenation dies with this' +
                ' frame; it cannot be stored in module variable ' +
                st.kids[0].a + ' (par 2.3)')
            else if (dmode = 'r') or
                    (((dmode = 'v') or (dmode = 'o') or (dmode = 'p')) and
                     (Length (st.kids[0].kids) > 0)) then
              ErrN (st.kids[1], ctx, 'a concatenation dies with this' +
                ' frame; it cannot be stored through ' + st.kids[0].a +
                ', which outlives it (par 2.3)')
            else if (Length (st.kids[0].kids) = 0) and
                    IsFrameMode (dmode) and
                    (fval.IndexOf (st.kids[0].a) < 0) then
              fval.Add (st.kids[0].a);
          end
          else if (Length (st.kids[0].kids) = 0) and
                  (fval.IndexOf (st.kids[0].a) >= 0) then
            fval.Delete (fval.IndexOf (st.kids[0].a));
          { anchored at the RIGHT-HAND SIDE, not the statement: a
            value on its own line used to be reported one line too
            high, at the := (found by the first m9edit user) }
          if u = '<void>' then
            ErrN (st.kids[1], ctx, 'the right-hand side returns no value')
          else if not Compat (t, u) then
            ErrN (st.kids[1], ctx, Format (
              'cannot assign %s to %s (no implicit conversions, par 2.1)',
              [TyName (u), TyName (t)]));
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
            retention -- refcounted, created explicitly (par 4.2) }
          if (vname <> '') and IsRefTy (u) and
             not StartsWithS (u, 'SHARED PTR ') and
             not StartsWithS (u, 'OPT SHARED PTR ') and
             ((ScopeMode (vname) = 'p') or (ScopeMode (vname) = 'v') or
              (ScopeMode (vname) = 'r') or   { RO is a borrow, and
                             the most borrow-like mode there is }
              { a local or binder may CARRY a borrow: recorded now,
                resolved at flush once the carries are closed, and
                dropped there if it carries none }
              (ScopeMode (vname) = 'l') or (ScopeMode (vname) = 'b')) and
             (beyond or (ScopeMode (st.kids[0].a) = 'm') or
              ((ScopeMode (st.kids[0].a) = 'v') and
               (Length (st.kids[0].kids) > 0))) then
          begin
            { PENDED, not emitted: the class -- retention, self-store,
              frame-store -- needs every escape of the destination,
              so the walk finishes first }
            SetLength (pendLn, pendN + 1); SetLength (pendCl, pendN + 1);
            SetLength (pendSrc, pendN + 1); SetLength (pendDst, pendN + 1);
            pendLn[pendN] := st.line; pendCl[pendN] := st.col;
            pendSrc[pendN] := vname; pendDst[pendN] := st.kids[0].a;
            Inc (pendN);
          end;
          { par 4.1 provenance: a bare local or binder now holds this
            reference -- a borrow is carried, a carrier's cargo is
            inherited }
          if (vname <> '') and IsRefTy (u) and
             (Length (st.kids[0].kids) = 0) and
             ((ScopeMode (st.kids[0].a) = 'l') or
              (ScopeMode (st.kids[0].a) = 'b')) then
            CarryFrom (st.kids[0].a, vname);
          { par 4.1 direction: a ref value rooted in frame storage,
            stored anywhere, is an escape fact for the fixpoint }
          if (vname <> '') and IsRefTy (u) and
             IsFrameMode (ScopeMode (vname)) then
            EscStore (st.kids[0].a, Length (st.kids[0].kids) > 0, vname);
          { moves: a bare owned pointer on the right moves out; a
            bare name on the left is (re)initialized }
          dcl := StripParens (st.kids[1]);
          if (dcl <> nil) and (dcl.kind = nkDesignator) and
             (Length (dcl.kids) = 0) and
             (OwnedCandKind (dcl.a) = 1) then
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
          pre := OwnSnap;
          WalkSeq (st.kids[1]);
          hpre := OwnSnap;
          OwnRestore (pre);
          OwnMergeMoves (hpre);
        end;
      nkFor :
        begin
          t := ExprType (st.kids[0]);
          if not IsIntish (t) then
            ErrN (st, ctx, 'FOR bounds must be integers, not ' + TyName (t));
          u := ExprType (st.kids[1]);
          if not IsIntish (u) then
            ErrN (st, ctx, 'FOR bounds must be integers, not ' + TyName (u));
          if st.kids[2] <> nil then
          begin
            u := ExprType (st.kids[2]);
            if not IsIntish (u) then
              ErrN (st, ctx, 'FOR step must be an integer, not ' + TyName (u));
          end;
          BindName (st.a, tyI64);
          pre := OwnSnap;
          WalkSeq (st.kids[3]);
          hpre := OwnSnap;
          OwnRestore (pre);
          OwnMergeMoves (hpre);
        end;
      nkLoop :
        begin
          pre := OwnSnap;
          WalkSeq (st.kids[0]);
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
                else if (lbl.kids[0].kind = nkDesignator) and
                        (Length (lbl.kids[0].kids) = 0) and
                        (lbl.kids[1] = nil) then
                  vname := lbl.kids[0].a;
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
            if (st.kids[0].kind = nkDesignator) and
               (Length (st.kids[0].kids) = 0) then
            begin
              dcl := ScopeType (st.kids[0].a);
              if (dcl <> nil) and (dcl.kind = nkPtrType) and
                 (dcl.kids[1] <> nil) and
                 (ScopeMode (dcl.kids[1].a) = 'l') then
                ErrN (st, ctx,
                  'pool-interior pointer escapes its pool: ' +
                  st.kids[0].a + ' lives in ' + dcl.kids[1].a +
                  ', which dies with this frame (par 4.3)');
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
          if raised.Values[st.kids[0].a] = '' then
            raised.Values[st.kids[0].a] := 'RAISE';
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
          if st.kids[0].kind = nkDesignator then
          begin
            SetLength (threadRoots, Length (threadRoots) + 1);
            threadRoots[High (threadRoots)] := DesigName (st.kids[0]);
          end;
          ExprType (st.kids[1]);
        end;
      nkTransfer :
        begin ExprType (st.kids[0]); ExprType (st.kids[1]); end;
      nkWait, nkSignal :
        ExprType (st.kids[0]);
      nkBlock :
        begin
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
              { handler binders are names too }
              if st.kids[j].kids[1] <> nil then
                for k := 0 to High (st.kids[j].kids[1].kids) do
                  if st.kids[j].kids[1].kids[k].kind = nkIdent then
                    BindName (st.kids[j].kids[1].kids[k].a, nil);
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
  nm, origin, callerKey : string;
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
  pendN := 0;
  SetLength (pendLn, 0); SetLength (pendCl, 0);
  SetLength (pendSrc, 0); SetLength (pendDst, 0);
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
    ErrN (body, ctx, 'unhandled RAISES ' + nm + ' from ' + origin);
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
  callerKey := ctx;
  callGraph.Values[callerKey] := string.Join (',', calls.ToStringArray);
  raised.Free;
  handled.Free;
  calls.Free;
  ownState.Free;
  escSet.Free;
  escEdges.Free;
  carryPair.Free;
  carryEdge.Free;
  fval.Free;
end;

procedure TSem.CheckThreadChains;
var
  i, j : Integer;
  work, seen : TStringList;
  c, callees : string;
  parts : TStringArray;
  pr : TProcInfo;
begin
  for i := 0 to High (threadRoots) do
  begin
    work := TStringList.Create; work.CaseSensitive := True;
    seen := TStringList.Create; seen.CaseSensitive := True;
    work.Add (threadRoots[i]);
    while work.Count > 0 do
    begin
      c := work[0];
      work.Delete (0);
      if seen.IndexOf (c) >= 0 then Continue;
      seen.Add (c);
      if LookupProcInfo (c, pr) then
        if pr.attrib = 'SERIAL' then
          Errors.Add (Format ('0:0 %s: SERIAL procedure called from ' +
            'THREAD context (%s reaches %s)',
            [threadRoots[i], threadRoots[i], c]));
      callees := callGraph.Values[curMod + '.' + c];
      if callees = '' then
        callees := callGraph.Values[c];
      if callees <> '' then
      begin
        parts := callees.Split (',');
        for j := 0 to High (parts) do
          if parts[j] <> '' then work.Add (parts[j]);
      end;
    end;
    work.Free;
    seen.Free;
  end;
end;

procedure TSem.CheckFile (root: TNode);
var
  ui, i, j, k2 : Integer;
  u, d, p, sec : TNode;
  fmi : TModuleInfo;
  scope : TStringList;
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
          end;
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
    SetLength (threadRoots, 0);
    callGraph.Clear;
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
    constMap.Clear;
    for i := 0 to High (u.kids) do
      if (u.kids[i] <> nil) and (u.kids[i].kind = nkConstSection) then
        for j := 0 to High (u.kids[i].kids) do
          constMap.Values[u.kids[i].kids[j].a] :=
            LitType (u.kids[i].kids[j].kids[0]);

    if (u.kind = nkDefinition) and (u.b <> '') then
    begin
      CheckForeignDef (u);
      Continue;
    end;
    if u.kind = nkImplementation then
      CheckConformance (u);

    for i := 0 to High (u.kids) do
    begin
      d := u.kids[i];
      if (d = nil) or (d.kind <> nkProcDecl) then Continue;
      if d.kids[4] = nil then Continue;
      p := d.kids[4];
      ctx := u.a + '.' + d.a;
      scope := TStringList.Create; scope.CaseSensitive := True;
      varParams.Clear;
      keptParams.Clear;
      keptUsed.Clear;
      varWritten.Clear;
      { params and locals first: IndexOfName answers the first hit,
        so they shadow module-level vars of the same name }
      AddParamsOf (d);
      AddVarsOf (p, 'l');
      AddVarsOf (u, 'm');
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
      scope := TStringList.Create; scope.CaseSensitive := True;
      { a module body declares no parameters, so the KEPT lists must
        not carry the last procedure's into this frame's flush }
      keptParams.Clear;
      keptUsed.Clear;
      AddVarsOf (u, 'm');
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

    CheckThreadChains;
  end;
end;

end.
