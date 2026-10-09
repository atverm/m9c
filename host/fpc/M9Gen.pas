unit M9Gen;
{ P4 code generator, first cut: emits C11 per report par 11 for the
  subset the DynStr milestone needs -- records, slices, pools,
  checked arithmetic and conversions, FOR/WHILE/IF/RETURN, calls.
  Anything outside the subset lands in Errors, loudly; a silent
  wrong translation is the one unforgivable output.
  ABI: every procedure takes a trailing m9_state *err; checks emit as
  m9rt helper calls that poison their result and set the slot; after
  any statement that can raise, `if (err->exc) goto L_ret;`.        }
{$mode objfpc}{$H+}
interface

uses SysUtils, Classes, M9AST;

type
  TGProc = record
    name : string;
    node : TNode;               { the head carrying params/rettype }
    body : TNode;               { nkProcBody or nil }
    exported : Boolean;
  end;

  TGen = class
  private
    modName : string;
    dbgSrc  : string;            { SetDebugSource; '' = no #line }
    defU, implU : TNode;
    tyNames : array of string;  { module types (def+impl) }
    tyNodes : array of TNode;
    tyOpaque : array of Boolean;
    tyFromDef : array of Boolean;
    excN : array of string;     { module exceptions }
    excF : array of TNode;      { payload fieldseq or nil }
    ixF : TNode;                { IndexError's (index, length : I64) }
    excDef : array of Boolean;
    modVarN : array of string;  { STATEFUL module state -> statics }
    modVarT : array of TNode;
    modVarDef : array of Boolean; { declared in the definition: exported }
    aggN : array of string;     { constant tables (par 2.2.4): name, }
    aggT : array of TNode;      { the ARRAY n OF T made for it,      }
    aggV : array of TNode;      { and the aggregate itself           }
    procs : array of TGProc;
    consts : TStringList;       { name -> expr node in Objects }
    hdr, src, tdefs, pbuf, sprotos, arrSeen, litBuf : TStringList;
    thrBuf, thrSeen : TStringList;   { THREAD trampolines, one per proc }
    rec2Gates : TStringList;         { one m9_mon per [SERIAL] FOR-C unit }
    scope : TStringList;        { name=mode; Objects = declared type }
    extProcs : TStringList;     { 'Mod.Proc' -> head node }
    extMods : TStringList;      { imported modules to #include }
    extExcs : TStringList;      { 'Exc=Mod' -> fieldseq node }
    extTypes : TStringList;     { 'Mod.T' -> type node }
    extConsts : TStringList;    { 'Mod.C' -> expr node }
    extVars : TStringList;      { 'Mod.v' -> its type, qualified in Mod:
                                  the imported module variables (decision 28) }
    hdrRecs, hdrProtos, hdrConsts : TStringList;
    { Gen.KArrRec / KHdrArrRec: an ARRAY OF a record of this module,
      typedef'd after the struct it contains }
    arrRec, hdrArrRec : TStringList;
    foreignProcs : TStringList; { bare name -> foreign head node }
    foreignUnit : TStringList;  { bare name -> its FOR-C unit }
    gateSeen : TStringList;     { units that got a [SERIAL] gate }
    tmpN : Integer;
    inSwitch : Integer;         { EXIT inside a switch would break
                                  the wrong thing: refuse loudly }
    finDepth : Integer;         { EXIT across a FINALLY boundary
                                  would skip the cleanup: refuse }
    stRaise : Boolean;
    hoistOk : Boolean;                 { HoistArg may emit: an assignment,
                                         a call statement, a RETURN }
    hoistInd, nhoist, hoistOpen : Integer;
    dry : Integer;              { >0 inside TagOfExpr's recomputation:
                                  answering a type must not emit code
                                  (dead string literals otherwise) }
    curRetTag : string;
    exitLbl : string;           { where RETURNs jump: L_ret, or the
                                  innermost FINALLY label }
    raiseLbl : string;          { where RAISEs and guards jump: the
                                  innermost handler dispatch or
                                  FINALLY label, else L_ret }
    curRetq : string;           { the innermost block's return flag }
    localPools : array of string;
    mvBase : Integer;           { where the module variables start in
                                  scope (rule 2: a root that is one
                                  lives in the module frame) }
    bpool : TStringList;        { binder=pool expression (rule 2); the
                                  last entry of a name is the live one }
    strNode : TNode;            { the SLICE OF CHAR that STR names }
    isProgram : Boolean;        { MODULE m -- emit a main () }
    mainBody : TNode;           { its statement sequence }
    function NewTmp : string;
    function FindType (const n: string): TNode;
    function IsOpaque (const n: string): Boolean;
    function FindProc (const n: string): Integer;
    function ExtBare (const nm: string): Integer;
    function Resolve (t: TNode): TNode;
    function ConstValue (e: TNode): TNode;
    function IsAdaptive (e: TNode): Boolean;
    function BuiltinC (const n: string): string;
    function ISuf (const t: string): string;
    function ProcTypedefC (const name: string; ptn: TNode): string;
    function TyC (t: TNode): string;
    function ArrBucket (elem: TNode): TStringList;
    function SliceTy (elem: TNode): string;
    function GridTy (elem: TNode; const rank: string): string;
    function IxFields: TNode;
    function IsAllArg (e: TNode): Boolean;
    function ArrCount (e: TNode): string;
    function ArrEnumBoundNode (b: TNode): TNode;
    function CRPrefix (const tn: string): string;
    function CRNode (const tn: string): TNode;
    function TagOfType (t: TNode): string;
    function TagOfExpr (e: TNode): string;
    function ScopeFind (const n: string): Integer;
    procedure ModuleScope;
    function QualIn (t: TNode; const inMod: string): TNode;
    procedure NoteMod (t: TNode; var m: string);
    function InMod (t: TNode; const m: string): TNode;
    procedure ExportVars (rec2: TStringList);
    function NameShadowed (sc: TNode; const name: string): Boolean;
    procedure ExportWalk (n, sc: TNode);
    function ScopeNode (const n: string): TNode;
    function ScopeMode (const n: string): string;
    function FieldType (rec: TNode; const f: string): TNode;
    function AsQualG (d: TNode): TNode;
    function NewShape (e: TNode; out ty: TNode; out ext0: Integer): string;
    function HasPtr (t: TNode; depth: Integer): Boolean;
    function PoolParamTy (t: TNode): Boolean;
    procedure AdoptEmit (const expr: string; t: TNode; const dst: string;
                         ind, depth: Integer);
    function PoolAddrC (pd: TNode): string;
    function ObjPoolC (a: TNode): string;
    function OriginPool (k: TNode): string;
    procedure Err (n: TNode; const msg: string);
    function CharVal (const lit: string): Int64;
    function StrLeaf (e: TNode; var s: string): Boolean;
    function FoldStr (e: TNode): TNode;
    function StrCodes (const s: string; n: TNode): string;
    procedure AddAgg (const nm: string; ag: TNode);
    function RecordConstQual (e: TNode): TNode;
    function LitC (e: TNode; const sname, what: string): string;
    procedure StrC (tgt: TStringList; e: TNode; const sname: string);
    procedure RecStrs (tgt: TStringList; e: TNode; const base: string);
    function RecC (e: TNode; const base, what: string): string;
    procedure PushAggs;
    procedure EmitAggs (tgt: TStringList);
    function DES (d: TNode; out tag: string): string;
    function EX (e: TNode; const want: string): string;
    function HoistArg (const a: string): string;
    procedure CloseHoists (ind: Integer);
    function EnumConvCount (n: TNode): Integer;
    function RecordAt (const name: string; out ctype: string): TNode;
    function CallC (dnode, argl, site: TNode; out tag: string): string;
    function ConstLbl (d: TNode): string;
    function DesigDecl (d: TNode): TNode;
    function ExcRef (const qual, nm: string; out fields: TNode): string;
    function OptInner (e: TNode): TNode;
    procedure EmitHandler (h: TNode; const dlbl: string; ind: Integer);
    procedure EmitStmt (st: TNode; ind: Integer);
    procedure EmitSeq (s: TNode; ind: Integer);
    procedure Line (sl: TStringList; ind: Integer; const s: string);
    procedure GenProc (const gp: TGProc);
    procedure GenMain;
    procedure GenInit (const forModule: string);
  public
    Errors : TStringList;
    HText, CText : string;
    constructor Create;
    destructor Destroy; override;
    procedure LoadUnit (u: TNode);
    procedure RegisterExtern (u: TNode; addInclude: Boolean);
    procedure LoadExtern (u: TNode);
    procedure LoadExternDeep (u: TNode);
    procedure SetDebugSource (const f: string);
    procedure DbgLine (st: TNode);
    procedure PoolReg (const nm: string);
    procedure Emit (const forModule: string);
  end;

implementation

const
  Builtins : array [0..12] of string = ('I8','I16','I32','I64','U8',
    'U16','U32','U64','F32','F64','BYTE','BOOL','CHAR');

function InL (const s: string; const a: array of string): Boolean;
var i : Integer;
begin
  for i := 0 to High (a) do
    if a[i] = s then Exit (True);
  Result := False;
end;

{ an M9 identifier that is a C keyword (or our err slot) gets a
  trailing underscore -- par 11's naming rule, completed }
{ libm functions a FOR-C unit may bind (C99 math.h, double + float):
  a LOCAL named like one shadows the extern -- `float cosf;` beside
  `extern float cosf (float);` makes a call to cosf resolve to the
  variable, "called object is not a function".  Escaped like the C
  keywords below.  No corpus identifier matches one; the beneficiaries
  are float-heavy modules with their own math bindings. }
function IsLibM (const n: string): boolean;
begin
  Result :=
    (n = 'acos') or (n = 'acosf') or (n = 'acosh') or (n = 'acoshf') or
    (n = 'asin') or (n = 'asinf') or (n = 'asinh') or (n = 'asinhf') or
    (n = 'atan') or (n = 'atanf') or (n = 'atan2') or (n = 'atan2f') or
    (n = 'atanh') or (n = 'atanhf') or (n = 'cbrt') or (n = 'cbrtf') or
    (n = 'ceil') or (n = 'ceilf') or (n = 'copysign') or (n = 'copysignf') or
    (n = 'cos') or (n = 'cosf') or (n = 'cosh') or (n = 'coshf') or
    (n = 'erf') or (n = 'erff') or (n = 'erfc') or (n = 'erfcf') or
    (n = 'exp') or (n = 'expf') or (n = 'exp2') or (n = 'exp2f') or
    (n = 'expm1') or (n = 'expm1f') or (n = 'fabs') or (n = 'fabsf') or
    (n = 'fdim') or (n = 'fdimf') or (n = 'floor') or (n = 'floorf') or
    (n = 'fma') or (n = 'fmaf') or (n = 'fmax') or (n = 'fmaxf') or
    (n = 'fmin') or (n = 'fminf') or (n = 'fmod') or (n = 'fmodf') or
    (n = 'frexp') or (n = 'frexpf') or (n = 'hypot') or (n = 'hypotf') or
    (n = 'ldexp') or (n = 'ldexpf') or (n = 'lgamma') or (n = 'lgammaf') or
    (n = 'log') or (n = 'logf') or (n = 'log10') or (n = 'log10f') or
    (n = 'log1p') or (n = 'log1pf') or (n = 'log2') or (n = 'log2f') or
    (n = 'modf') or (n = 'modff') or (n = 'nan') or (n = 'nanf') or
    (n = 'nearbyint') or (n = 'nearbyintf') or (n = 'nextafter') or (n = 'nextafterf') or
    (n = 'pow') or (n = 'powf') or (n = 'remainder') or (n = 'remainderf') or
    (n = 'rint') or (n = 'rintf') or (n = 'round') or (n = 'roundf') or
    (n = 'scalbn') or (n = 'scalbnf') or (n = 'sin') or (n = 'sinf') or
    (n = 'sinh') or (n = 'sinhf') or (n = 'sqrt') or (n = 'sqrtf') or
    (n = 'tan') or (n = 'tanf') or (n = 'tanh') or (n = 'tanhf') or
    (n = 'tgamma') or (n = 'tgammaf') or (n = 'trunc') or (n = 'truncf') or
    (n = 'j0') or (n = 'j1') or (n = 'jn') or (n = 'y0') or (n = 'y1') or (n = 'yn');
end;

function CN (const n: string): string;
begin
  { an imported variable is in scope as Mod.v (decision 28); its C name
    is the pointer the exporter defines, Mod_v }
  if Pos ('.', n) > 0 then Exit (StringReplace (n, '.', '_', [rfReplaceAll]));
  if (n = 'signed') or (n = 'unsigned') or (n = 'int') or (n = 'char')
     or (n = 'long') or (n = 'short') or (n = 'float') or (n = 'double')
     or (n = 'void') or (n = 'return') or (n = 'if') or (n = 'else')
     or (n = 'while') or (n = 'for') or (n = 'do') or (n = 'switch')
     or (n = 'case') or (n = 'default') or (n = 'break')
     or (n = 'continue') or (n = 'goto') or (n = 'struct')
     or (n = 'union') or (n = 'enum') or (n = 'typedef')
     or (n = 'static') or (n = 'extern') or (n = 'const')
     or (n = 'volatile') or (n = 'register') or (n = 'auto')
     or (n = 'sizeof') or (n = 'inline') or (n = 'restrict')
     or (n = 'bool') or (n = 'true') or (n = 'false') or (n = 'err')
     or (n = 'main') then   { not a keyword, but reserved at file
                              scope in a hosted environment -- the
                              gm2 collision in the ledger, met again
                              by M9's own compiler }
    Exit (n + '_');
  if IsLibM (n) then Exit (n + '_');
  Result := n;
end;

{ C.* ABI types, par 7/11 }
function CMap (const n: string): string;
begin
  if n = 'Int' then Exit ('int');
  if n = 'SizeT' then Exit ('size_t');
  if n = 'SSizeT' then Exit ('int64_t');
  if n = 'ConstPtr' then Exit ('const void *');
  if n = 'MutPtr' then Exit ('void *');
  if n = 'Double' then Exit ('double');
  if n = 'Float' then Exit ('float');
  if n = 'LongDouble' then Exit ('long double');
  Result := '';
end;

constructor TGen.Create;
var ch : TNode;
begin
  ch := TNode.Create (nkQualident);
  ch.a := 'CHAR';
  strNode := TNode.Create (nkSliceType);
  strNode.Add (ch);
  Errors := TStringList.Create; Errors.CaseSensitive := True;
  consts := TStringList.Create; consts.CaseSensitive := True;
  hdr := TStringList.Create; hdr.CaseSensitive := True;
  src := TStringList.Create; src.CaseSensitive := True;
  tdefs := TStringList.Create; tdefs.CaseSensitive := True;
  pbuf := TStringList.Create; pbuf.CaseSensitive := True;
  sprotos := TStringList.Create; sprotos.CaseSensitive := True;
  thrBuf := TStringList.Create; thrBuf.CaseSensitive := True;
  rec2Gates := TStringList.Create; rec2Gates.CaseSensitive := True;
  thrSeen := TStringList.Create; thrSeen.CaseSensitive := True;
  bpool := TStringList.Create; bpool.CaseSensitive := True;
  arrSeen := TStringList.Create; arrSeen.CaseSensitive := True;
  scope := TStringList.Create; scope.CaseSensitive := True;
  extProcs := TStringList.Create; extProcs.CaseSensitive := True;
  extMods := TStringList.Create; extMods.CaseSensitive := True;
  foreignProcs := TStringList.Create; foreignProcs.CaseSensitive := True;
  foreignUnit := TStringList.Create; foreignUnit.CaseSensitive := True;
  gateSeen := TStringList.Create; gateSeen.CaseSensitive := True;
  litBuf := TStringList.Create; litBuf.CaseSensitive := True;
  extExcs := TStringList.Create; extExcs.CaseSensitive := True;
  extTypes := TStringList.Create; extTypes.CaseSensitive := True;
  extConsts := TStringList.Create; extConsts.CaseSensitive := True;
  extVars := TStringList.Create; extVars.CaseSensitive := True;
  hdrRecs := TStringList.Create; hdrRecs.CaseSensitive := True;
  hdrProtos := TStringList.Create; hdrProtos.CaseSensitive := True;
  hdrConsts := TStringList.Create; hdrConsts.CaseSensitive := True;
  arrRec := TStringList.Create; arrRec.CaseSensitive := True;
  hdrArrRec := TStringList.Create; hdrArrRec.CaseSensitive := True;
end;

destructor TGen.Destroy;
begin
  Errors.Free; consts.Free; hdr.Free; src.Free; tdefs.Free;
  pbuf.Free; sprotos.Free; arrSeen.Free; scope.Free;
  thrBuf.Free; thrSeen.Free; rec2Gates.Free; bpool.Free;
  extProcs.Free; extMods.Free; foreignProcs.Free; litBuf.Free;
  foreignUnit.Free; gateSeen.Free;
  extExcs.Free; extTypes.Free; extConsts.Free; extVars.Free;
  hdrRecs.Free; hdrProtos.Free; hdrConsts.Free; arrRec.Free; hdrArrRec.Free;
  inherited;
end;

procedure TGen.Err (n: TNode; const msg: string);
var ln : Integer;
begin
  ln := 0;
  if n <> nil then ln := n.line;
  Errors.Add (Format ('%d: gen: %s', [ln, msg]));
end;

function TGen.NewTmp : string;
begin
  Inc (tmpN);
  Result := 'm9t' + IntToStr (tmpN);
end;

procedure TGen.Line (sl: TStringList; ind: Integer; const s: string);
begin
  sl.Add (StringOfChar (' ', ind * 2) + s);
end;

{ ---- registry ---- }

{ Gen.NanWalk: a bare designator NaN becomes the real literal NAN
  (report par 2.1) }
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

procedure TGen.LoadUnit (u: TNode);
var
  i, j : Integer;
  d, td : TNode;
  gp : TGProc;
  pi : Integer;
begin
  for i := 0 to High (u.kids) do NanWalk (u.kids[i]);
  { a FOR "C" unit contributes foreign procedures, nothing else }
  if (u.kind = nkDefinition) and (u.b <> '') then
  begin
    for i := 0 to High (u.kids) do
      if (u.kids[i] <> nil) and (u.kids[i].kind = nkProcDecl) then
      begin
        foreignProcs.AddObject (u.kids[i].a, TObject (u.kids[i]));
        foreignUnit.Add (u.kids[i].a + '=' + u.a);
      end;
    Exit;
  end;
  if u.kind = nkDefinition then defU := u;
  if u.kind = nkImplementation then implU := u;
  { a program module is the one unit that becomes an executable }
  if u.kind = nkProgram then isProgram := True;
  if modName = '' then modName := u.a;
  for i := 0 to High (u.kids) do
  begin
    d := u.kids[i];
    if d = nil then Continue;
    case d.kind of
      nkProcDecl :
        begin
          pi := FindProc (d.a);
          if pi < 0 then
          begin
            gp.name := d.a;
            gp.node := d;
            gp.body := d.kids[4];
            gp.exported := u.kind = nkDefinition;
            SetLength (procs, Length (procs) + 1);
            procs[High (procs)] := gp;
          end
          else
          begin
            if d.kids[4] <> nil then
            begin
              procs[pi].body := d.kids[4];
              procs[pi].node := d;   { impl node carries the body's head }
            end;
          end;
        end;
      nkTypeSection :
        for j := 0 to High (d.kids) do
        begin
          td := d.kids[j];
          SetLength (tyNames, Length (tyNames) + 1);
          SetLength (tyNodes, Length (tyNodes) + 1);
          SetLength (tyOpaque, Length (tyOpaque) + 1);
          SetLength (tyFromDef, Length (tyFromDef) + 1);
          tyNames[High (tyNames)] := td.a;
          tyNodes[High (tyNodes)] := td.kids[0];
          tyOpaque[High (tyOpaque)] :=
            (u.kind = nkDefinition) and (td.kids[0] = nil);
          tyFromDef[High (tyFromDef)] := u.kind = nkDefinition;
        end;
      nkConstSection :
        for j := 0 to High (d.kids) do
          if (d.kids[j].kids[0] <> nil) and
             ((d.kids[j].kids[0].kind = nkAggregate) or
              (RecordConstQual (d.kids[j].kids[0]) <> nil)) then
            AddAgg (d.kids[j].a, d.kids[j].kids[0])
          else
            consts.AddObject (d.kids[j].a, TObject (FoldStr (d.kids[j].kids[0])));
      nkExcSection :
        for j := 0 to High (d.kids) do
        begin
          SetLength (excN, Length (excN) + 1);
          SetLength (excF, Length (excF) + 1);
          SetLength (excDef, Length (excDef) + 1);
          excN[High (excN)] := d.kids[j].a;
          excF[High (excF)] := d.kids[j].kids[0];
          excDef[High (excDef)] := u.kind = nkDefinition;
        end;
      nkVarSection :
        for j := 0 to High (d.kids) do
          for pi := 0 to High (d.kids[j].kids[0].kids) do
          begin
            SetLength (modVarN, Length (modVarN) + 1);
            SetLength (modVarT, Length (modVarT) + 1);
            SetLength (modVarDef, Length (modVarDef) + 1);
            modVarN[High (modVarN)] := d.kids[j].kids[0].kids[pi].a;
            modVarT[High (modVarT)] := d.kids[j].kids[1];
            modVarDef[High (modVarDef)] := u.kind = nkDefinition;
          end;
      nkModBody :
        mainBody := d.kids[0];
    end;
  end;
end;

procedure TGen.RegisterExtern (u: TNode; addInclude: Boolean);
var i, j, k : Integer;
begin
  if u.kind <> nkDefinition then Exit;
  { a dependency's FOR-C unit contributes foreign procs by bare
    name (FROM csock IMPORT ...), and there is no csock.h }
  if u.b <> '' then
  begin
    for i := 0 to High (u.kids) do
      if (u.kids[i] <> nil) and (u.kids[i].kind = nkProcDecl) then
      begin
        foreignProcs.AddObject (u.kids[i].a, TObject (u.kids[i]));
        foreignUnit.Add (u.kids[i].a + '=' + u.a);
      end;
    Exit;
  end;
  { the include list is the DIRECT imports only; a deep load
    registers the declarations so types resolve and stops there }
  if addInclude and (extMods.IndexOf (u.a) < 0) then extMods.Add (u.a);
  for i := 0 to High (u.kids) do
    if u.kids[i] <> nil then
    begin
      if u.kids[i].kind = nkProcDecl then
        extProcs.AddObject (u.a + '.' + u.kids[i].a, TObject (u.kids[i]));
      if u.kids[i].kind = nkExcSection then
        for j := 0 to High (u.kids[i].kids) do
          extExcs.AddObject (u.kids[i].kids[j].a + '=' + u.a,
            TObject (u.kids[i].kids[j].kids[0]));
      if u.kids[i].kind = nkTypeSection then
        for j := 0 to High (u.kids[i].kids) do
          if u.kids[i].kids[j].kids[0] <> nil then
            extTypes.AddObject (u.a + '.' + u.kids[i].kids[j].a,
              TObject (u.kids[i].kids[j].kids[0]));
      if u.kids[i].kind = nkConstSection then
        for j := 0 to High (u.kids[i].kids) do
          extConsts.AddObject (u.a + '.' + u.kids[i].kids[j].a,
            TObject (u.kids[i].kids[j].kids[0]));
      { the definition's variables: an importer's Mod.v, a pointer to the
        exporter's storage in VAR-parameter mode, C name Mod_v (decision 28;
        Gen.RegisterExtern) }
      if u.kids[i].kind = nkVarSection then
        for j := 0 to High (u.kids[i].kids) do
          for k := 0 to High (u.kids[i].kids[j].kids[0].kids) do
            extVars.AddObject (u.a + '.' + u.kids[i].kids[j].kids[0].kids[k].a,
              TObject (QualIn (u.kids[i].kids[j].kids[1], u.a)));
    end;
end;

{ a DIRECT import: its declarations are registered and its header is
  included, because this module names things in it }
procedure TGen.LoadExtern (u: TNode);
begin
  RegisterExtern (u, True);
end;

{ a dependency of a dependency: its declarations are registered so
  that a callee's signature can be RESOLVED -- Qvsat.Ew answers a
  Kind.FlexFloat and its caller has no business importing Kind -- but
  no #include is emitted, because this module names nothing in it }
procedure TGen.LoadExternDeep (u: TNode);
begin
  RegisterExtern (u, False);
end;

function TGen.FindType (const n: string): TNode;
var i : Integer;
begin
  for i := 0 to High (tyNames) do
    if (tyNames[i] = n) and (tyNodes[i] <> nil) then Exit (tyNodes[i]);
  Result := nil;
end;

function TGen.IsOpaque (const n: string): Boolean;
var i : Integer;
begin
  for i := 0 to High (tyNames) do
    if (tyNames[i] = n) and tyOpaque[i] then Exit (True);
  Result := False;
end;

function TGen.FindProc (const n: string): Integer;
var i : Integer;
begin
  for i := 0 to High (procs) do
    if procs[i].name = n then Exit (i);
  Result := -1;
end;

{ suffix scan: an unqualified name written inside an imported module
  resolves against the loaded dependency defs -- unambiguous because
  each TGen loads only its module's declared deps }
function TGen.ExtBare (const nm: string): Integer;
var i : Integer;
begin
  for i := 0 to extTypes.Count - 1 do
    if (Length (extTypes[i]) > Length (nm)) and
       (Copy (extTypes[i], Length (extTypes[i]) - Length (nm), 1) = '.') and
       (Copy (extTypes[i], Length (extTypes[i]) - Length (nm) + 1,
             Length (nm)) = nm) then
      Exit (i);
  Result := -1;
end;

function TGen.Resolve (t: TNode): TNode;
var
  depth, ei : Integer;
  nxt : TNode;
begin
  Result := t;
  { STR expands to the slice it abbreviates (par 2.2), so nothing
    downstream needs a case for it }
  if (Result <> nil) and (Result.kind = nkQualident) and
     (Result.b = '') and (Result.a = 'STR') then
    Result := strNode;
  depth := 0;
  while (Result <> nil) and (Result.kind = nkQualident) and
        not InL (Result.a, Builtins) and
        (Result.a <> 'POOL') and (Result.a <> 'C') and (depth < 8) do
  begin
    if Result.b <> '' then
    begin
      ei := extTypes.IndexOf (Result.a + '.' + Result.b);
      if ei < 0 then Exit;               { opaque ext or unknown }
      Result := TNode (extTypes.Objects[ei]);
    end
    else
    begin
      nxt := FindType (Result.a);
      if nxt = nil then
      begin
        ei := ExtBare (Result.a);
        if ei < 0 then Exit (nil);
        nxt := TNode (extTypes.Objects[ei]);
      end;
      Result := nxt;
    end;
    Inc (depth);
  end;
end;

{ ---- type mapping ---- }

{ the checked helper's width suffix for an integer type tag.  Each of
  the eight exact widths has its own helper since 2026-09-27: before
  that everything went through the I64 one and a narrow result was
  stored unchecked, so `I32 max + 1` wrapped in silence
  (docs/agent-review-2026-09-27.md F1).  A tag that is none of the
  eight -- a C.* value, an enumeration's ordinal -- is a 64-bit value
  to the checker and keeps the I64 helper.  Mirrors Gen.ISuf. }
function TGen.ISuf (const t: string): string;
begin
  if t = 'I8' then Exit ('i8');
  if t = 'I16' then Exit ('i16');
  if t = 'I32' then Exit ('i32');
  if t = 'U8' then Exit ('u8');
  if t = 'U16' then Exit ('u16');
  if t = 'U32' then Exit ('u32');
  if t = 'U64' then Exit ('u64');
  Result := 'i64';
end;

function TGen.BuiltinC (const n: string): string;
begin
  if n = 'I8'  then Exit ('int8_t');
  if n = 'I16' then Exit ('int16_t');
  if n = 'I32' then Exit ('int32_t');
  if n = 'I64' then Exit ('int64_t');
  if n = 'U8'  then Exit ('uint8_t');
  if n = 'U16' then Exit ('uint16_t');
  if n = 'U32' then Exit ('uint32_t');
  if n = 'U64' then Exit ('uint64_t');
  if n = 'F32' then Exit ('float');
  if n = 'F64' then Exit ('double');
  if n = 'BYTE' then Exit ('uint8_t');
  if n = 'BOOL' then Exit ('bool');
  if n = 'CHAR' then Exit ('uint32_t');
  Result := '';
end;

{ Gen.ArrBucket: where an ARRAY OF elem's typedef goes -- after the
  struct of a record of this module (arrRec for a private one,
  hdrArrRec for a transparent one), with the other typedefs
  otherwise; a nested array follows its innermost element }
function TGen.ArrBucket (elem: TNode): TStringList;
var i : Integer;
begin
  Result := tdefs;
  if elem = nil then Exit;
  if elem.kind = nkArrayType then Exit (ArrBucket (elem.kids[1]));
  if (elem.kind = nkQualident) and (elem.b = '') then
    for i := 0 to High (tyNames) do
      if (tyNames[i] = elem.a) and (tyNodes[i] <> nil) and
         (tyNodes[i].kind in [nkRecordType, nkMonitorType]) then
      begin
        if tyFromDef[i] and not IsOpaque (tyNames[i]) then
          Exit (hdrArrRec);
        Exit (arrRec);
      end;
end;

function TGen.TyC (t: TNode): string;
var
  s, nested : string;
  ei, i : Integer;
  r2 : TNode;
  ab : TStringList;
begin
  Result := 'void';
  if t = nil then Exit;
  case t.kind of
    nkQualident :
      begin
        if t.b <> '' then
        begin
          if t.a = 'C' then
          begin
            s := CMap (t.b);
            if s = '' then Err (t, 'unknown C type C.' + t.b);
            Exit (s);
          end;
          ei := extTypes.IndexOf (t.a + '.' + t.b);
          if ei >= 0 then
          begin
            r2 := TNode (extTypes.Objects[ei]);
            if r2.kind in [nkRecordType, nkCaseRecordType,
                           nkMonitorType, nkEnumType, nkProcType] then
              Exit (t.a + '_' + t.b);
            Exit (TyC (r2));              { alias, chased }
          end;
          if extMods.IndexOf (t.a) >= 0 then
            Exit (t.a + '_' + t.b);       { opaque: typedef from Mod.h }
          Err (t, 'qualified type ' + t.a + '.' + t.b + ' unsupported yet');
          Exit;
        end;
        if t.a = 'POOL' then Exit ('m9_pool');
        if t.a = 'STR' then Exit (SliceTy (strNode.kids[0]));
        s := BuiltinC (t.a);
        if s <> '' then Exit (s);
        r2 := FindType (t.a);
        if r2 <> nil then
        begin
          { a procedure type is a NAMED C typedef like a record's,
            emitted into the header beside the slice typedefs
            (par 2.2.3) }
          if r2.kind in [nkRecordType, nkCaseRecordType,
                         nkMonitorType, nkEnumType, nkProcType] then
            Exit (modName + '_' + t.a);
          Exit (TyC (r2));                { local alias, chased }
        end;
        { a bare name written inside an imported module }
        ei := ExtBare (t.a);
        if ei >= 0 then
        begin
          r2 := TNode (extTypes.Objects[ei]);
          if r2.kind in [nkRecordType, nkCaseRecordType,
                         nkMonitorType, nkEnumType, nkProcType] then
            Exit (Copy (extTypes[ei], 1,
              Length (extTypes[ei]) - Length (t.a) - 1) + '_' + t.a);
          Exit (TyC (r2));
        end;
        Exit (modName + '_' + t.a);       { local opaque }
      end;
    nkPtrType, nkSharedType : Exit (TyC (t.kids[0]) + ' *');
    nkOptType :
      begin
        { a procedure value is pointer-shaped too: NONE is NULL }
        if Resolve (t.kids[0]) <> nil then
          if Resolve (t.kids[0]).kind in [nkPtrType, nkSharedType, nkProcType] then
            Exit (TyC (t.kids[0]));
        Err (t, 'OPT of non-pointer unsupported yet');
      end;
    nkSliceType : Exit (SliceTy (t.kids[0]));
    nkGridType : Exit (GridTy (t.kids[1], ArrCount (t.kids[0])));
    nkArrayType :
      begin
        { the element's own typedefs first (idempotent), and the
          NAME derives from the element's C type the way SliceTy's
          does: TagOfType collapsed every nested array to ARR and
          every record to REC, so ARRAY 8 OF ARRAY 160 OF CHAR and
          ARRAY 8 OF ARRAY 262144 OF CHAR shared one typedef and the
          second field was silently laid out as the first -- found
          by ASan under the proxy's session registry, checked writes
          landing past a 72 KB struct the source said was 9 MB }
        nested := TyC (t.kids[1]);
        s := 'm9_arr_' + ArrCount (t.kids[0]) + '_';
        for i := 1 to Length (nested) do
          if nested[i] = '*' then s := s + 'p'
          else if nested[i] <> ' ' then s := s + nested[i];
        if (arrSeen.IndexOf (s) < 0) and (dry = 0) then
        begin
          arrSeen.Add (s);
          { each typedef defines a fresh anonymous struct, so two
            modules emitting the same name are conflicting types, not
            a legal C11 redefinition: guard every one }
          ab := ArrBucket (t.kids[1]);
          ab.Add ('#ifndef M9SL_' + s);
          ab.Add ('#define M9SL_' + s);
          ab.Add ('typedef struct { ' + nested + ' v[' +
            ArrCount (t.kids[0]) + ']; } ' + s + ';');
          ab.Add ('#endif');
        end;
        Exit (s);
      end;
  else
    Err (t, 'type kind unsupported yet (kind ' + IntToStr (Ord (t.kind)) + ')');
  end;
end;

function TGen.SliceTy (elem: TNode): string;
var
  r : TNode;
  nm, ec : string;
  i : Integer;
begin
  r := Resolve (elem);
  if (r <> nil) and (r.kind = nkQualident) and (r.b = '') and
     InL (r.a, Builtins) then
    Exit ('m9_sl_' + r.a);
  { any other element: a typedef derived from its C type }
  ec := TyC (elem);
  nm := 'm9_sl_';
  for i := 1 to Length (ec) do
    if ec[i] = '*' then nm := nm + 'p'
    else if ec[i] <> ' ' then nm := nm + ec[i];
  if (arrSeen.IndexOf (nm) < 0) and (dry = 0) then
  begin
    arrSeen.Add (nm);
    tdefs.Add ('#ifndef M9SL_' + nm);
    tdefs.Add ('#define M9SL_' + nm);
    tdefs.Add ('typedef struct { ' + ec + ' *p; int64_t len; } ' +
      nm + ';');
    tdefs.Add ('#endif');
  end;
  Result := nm;
end;

{ one struct per rank per element type, guarded like the slice
  typedefs: each typedef defines a fresh anonymous struct, so the
  same name from two modules is a conflicting type rather than a
  legal C11 redefinition }
{ the ALL axis marker: a predeclared identifier, so it is a bare
  designator with that name and nothing else }
function TGen.IsAllArg (e: TNode): Boolean;
begin
  Result := (e <> nil) and (e.kind = nkDesignator) and (e.a = 'ALL') and
            (Length (e.kids) = 0);
end;

function TGen.GridTy (elem: TNode; const rank: string): string;
var
  nm, ec : string;
  i : Integer;
begin
  ec := TyC (elem);
  nm := 'm9_gd' + rank + '_';
  for i := 1 to Length (ec) do
    if ec[i] = '*' then nm := nm + 'p'
    else if ec[i] <> ' ' then nm := nm + ec[i];
  if (arrSeen.IndexOf (nm) < 0) and (dry = 0) then
  begin
    arrSeen.Add (nm);
    tdefs.Add ('#ifndef M9SL_' + nm);
    tdefs.Add ('#define M9SL_' + nm);
    tdefs.Add ('M9_GRID_T (' + nm + ', ' + ec + ', ' + rank + ')');
    tdefs.Add ('#endif');
  end;
  Result := nm;
end;

{ the enumeration or case-record type node an ARRAY bound names, or
  nil when the bound is an integer.  ARRAY Colour OF T is indexed by
  the type: its length is the variant count and its subscript is a
  member, not an ordinal (docs/enum-plan.md, part 2). }
function TGen.ArrEnumBoundNode (b: TNode): TNode;
var ci : Integer; t : TNode;
begin
  Result := nil;
  if (b = nil) or (b.kind <> nkDesignator) then Exit;
  if Length (b.kids) = 0 then
  begin
    t := FindType (b.a);
    if (t <> nil) and (t.kind in [nkEnumType, nkCaseRecordType]) then
      Result := t;
  end
  else if (Length (b.kids) = 1) and (b.kids[0].kind = nkSelField) then
  begin
    ci := extTypes.IndexOf (b.a + '.' + b.kids[0].a);
    if ci >= 0 then
    begin
      t := TNode (extTypes.Objects[ci]);
      if (t <> nil) and (t.kind in [nkEnumType, nkCaseRecordType]) then
        Result := t;
    end;
  end;
end;

function TGen.ArrCount (e: TNode): string;
var ci : Integer; et : TNode;
begin
  if e.kind = nkInt then Exit (e.a);
  et := ArrEnumBoundNode (e);
  if et <> nil then Exit (IntToStr (Length (et.kids)));
  if (e.kind = nkDesignator) and (Length (e.kids) = 0) then
  begin
    ci := consts.IndexOf (e.a);
    if (ci >= 0) and (TNode (consts.Objects[ci]).kind = nkInt) then
      Exit (TNode (consts.Objects[ci]).a);
  end;
  { ARRAY Mod.N OF T: an imported CONST (mirrors Gen.ArrCount) }
  if (e.kind = nkDesignator) and (Length (e.kids) = 1) and
     (e.kids[0].kind = nkSelField) then
  begin
    ci := extConsts.IndexOf (e.a + '.' + e.kids[0].a);
    if (ci >= 0) and (TNode (extConsts.Objects[ci]).kind = nkInt) then
      Exit (TNode (extConsts.Objects[ci]).a);
  end;
  Err (e, 'array bound must be a literal or literal CONST');
  Result := '0';
end;

{ ---- a case record that lives in another module ----

  A CR: tag names the case record type; until 2026-09-15 it named it
  BARE, so every consumer prefixed modName and looked it up locally,
  and a value typed `Shape.Kind' -- a parameter, a variable, a call
  result -- could not be CASEd ("CASE over this selector unsupported
  yet") nor built ("unknown name: Shape").  Csv, Frame and Plot each
  grew an integer face to route around it, in their own comments.

  Now the tag carries the module when there is one -- `CR:Kind' at
  home, `CR:Shape.Kind' abroad -- and these two answer, for either
  spelling, the C prefix and the declaring node.  The header of the
  other module already declares Shape_Kind and its tags; nothing has
  to be re-emitted. }

function TGen.CRPrefix (const tn: string): string;
var i : Integer;
begin
  i := Pos ('.', tn);
  if i > 0 then
    Exit (Copy (tn, 1, i - 1) + '_' + Copy (tn, i + 1, MaxInt));
  Result := modName + '_' + tn;
end;

function TGen.CRNode (const tn: string): TNode;
var ei : Integer;
begin
  if Pos ('.', tn) > 0 then
  begin
    ei := extTypes.IndexOf (tn);
    if ei >= 0 then Exit (TNode (extTypes.Objects[ei]));
    Exit (nil);
  end;
  Result := FindType (tn);
end;

function TGen.TagOfType (t: TNode): string;
var
  r : TNode;
  ei : Integer;
begin
  Result := '?';
  if (t <> nil) and (t.kind = nkQualident) and (t.b = '') then
  begin
    r := FindType (t.a);
    if (r <> nil) and (r.kind in [nkCaseRecordType, nkEnumType]) then
      Exit ('CR:' + t.a);
  end;
  if (t <> nil) and (t.kind = nkQualident) and (t.b <> '') then
  begin
    ei := extTypes.IndexOf (t.a + '.' + t.b);
    if ei >= 0 then
    begin
      r := TNode (extTypes.Objects[ei]);
      if (r <> nil) and (r.kind in [nkCaseRecordType, nkEnumType]) then
        Exit ('CR:' + t.a + '.' + t.b);
    end;
  end;
  r := Resolve (t);
  if r = nil then Exit;
  case r.kind of
    nkQualident :
      if r.a = 'POOL' then Result := 'POOL'
      else if InL (r.a, Builtins) then Result := r.a;
    nkPtrType : Result := 'PTR';
    nkSharedType : Result := 'SHARED';
    nkOptType : Result := 'OPTPTR';
    nkSliceType : Result := 'SLICE';
    nkGridType : Result := 'GRID';
    nkArrayType : Result := 'ARR';
    nkRecordType, nkMonitorType : Result := 'REC';
    nkProcType : Result := 'PROC';
  end;
end;

{ a name in the scope table, by the language's order: parameters and
  locals, then the binders pushed on top of the module block (innermost
  first), then module state and the constant tables.  corpus/Gen.m9's
  ScopeFind says why (2026-10-03). }
function TGen.ScopeFind (const n: string): Integer;
var i, lo, hi : Integer;
begin
  lo := mvBase;
  if lo > scope.Count then lo := scope.Count;
  hi := mvBase + Length (modVarN) + extVars.Count + Length (aggN);
  if hi > scope.Count then hi := scope.Count;
  for i := 0 to lo - 1 do
    if scope.Names[i] = n then Exit (i);
  for i := scope.Count - 1 downto hi do
    if scope.Names[i] = n then Exit (i);
  for i := lo to hi - 1 do
    if scope.Names[i] = n then Exit (i);
  Result := -1;
end;

{ the module block: this module's variables, then every imported
  module's exports as Mod.v in VAR-parameter mode (Gen.ModuleScope) }
procedure TGen.ModuleScope;
var i : Integer;
begin
  mvBase := scope.Count;
  for i := 0 to High (modVarN) do
    scope.AddObject (modVarN[i] + '=l', TObject (modVarT[i]));
  for i := 0 to extVars.Count - 1 do
    scope.AddObject (extVars[i] + '=v', extVars.Objects[i]);
end;

{ Gen.QualIn: a type node from module modName with its bare type names
  qualified, so an importer reads it where it was declared }
function TGen.QualIn (t: TNode; const inMod: string): TNode;
var n : TNode;
begin
  Result := t;
  if t = nil then Exit;
  if t.kind = nkQualident then
  begin
    if (t.b = '') and not InL (t.a, Builtins) and (t.a <> 'STR') and
       (t.a <> 'POOL') then
    begin
      n := TNode.Create (nkQualident);
      n.line := t.line; n.col := t.col;
      n.a := inMod; n.b := t.a;
      Result := n;
    end;
  end
  else if t.kind in [nkPtrType, nkOptType, nkSharedType, nkSliceType] then
  begin
    n := TNode.Create (t.kind);
    n.line := t.line; n.col := t.col;
    if Length (t.kids) > 0 then n.Add (QualIn (t.kids[0], inMod));
    n.Add (nil);
    Result := n;
  end
  else if (t.kind in [nkArrayType, nkGridType]) and (Length (t.kids) >= 2) then
  begin
    n := TNode.Create (t.kind);
    n.line := t.line; n.col := t.col;
    n.Add (t.kids[0]);
    n.Add (QualIn (t.kids[1], inMod));
    Result := n;
  end;
end;

{ Gen.NoteMod/InMod: the module a qualified type name points into,
  so a foreign aggregate's component types are read where they were
  declared (canonCtx) }
procedure TGen.NoteMod (t: TNode; var m: string);
begin
  if (t <> nil) and (t.kind = nkQualident) and (t.b <> '') then m := t.a;
end;

function TGen.InMod (t: TNode; const m: string): TNode;
begin
  if (m = '') or (m = modName) then Exit (t);
  Result := QualIn (t, m);
end;

{ Gen.ExportVars: the exporter publishes a constant pointer to each
  variable its definition declares, and a pointer-bearing one's pool }
procedure TGen.ExportVars (rec2: TStringList);
var
  i : Integer;
  ty, cname, pl : string;
  t, r : TNode;
  any : Boolean;
begin
  any := False;
  for i := 0 to High (modVarN) do
    if modVarDef[i] then
    begin
      any := True;
      ty := TyC (modVarT[i]);
      cname := modName + '_' + modVarN[i];
      rec2.Add (ty + ' * const ' + cname + ' = &' + CN (modVarN[i]) + ';');
      hdrProtos.Add ('extern ' + ty + ' * const ' + cname + ';');
      if PoolParamTy (modVarT[i]) then
      begin
        pl := '&m9mframe';
        t := modVarT[i];
        if (t <> nil) and (t.kind = nkOptType) then t := t.kids[0];
        r := Resolve (t);
        if (r <> nil) and (r.kind = nkPtrType) and (Length (r.kids) > 1) and
           (r.kids[1] <> nil) and (Length (r.kids[1].kids) = 0) then
          pl := '&' + CN (r.kids[1].a);
        rec2.Add ('m9_pool * const ' + cname + '_pool = ' + pl + ';');
        hdrProtos.Add ('extern m9_pool * const ' + cname + '_pool;');
      end;
    end;
  if any then rec2.Add ('');
end;

function GDeclaresName (k: TNode; const name: string): Boolean;
var i : Integer;
begin
  Result := False;
  if k = nil then Exit;
  if (k.kind in [nkIdent, nkIsSome, nkTypeDecl, nkConstDecl, nkExcDecl]) and
     (k.a = name) then Exit (True);
  for i := 0 to High (k.kids) do
    if GDeclaresName (k.kids[i], name) then Exit (True);
end;

function TGen.NameShadowed (sc: TNode; const name: string): Boolean;
var i : Integer;
begin
  if GDeclaresName (sc, name) then Exit (True);
  if (FindProc (name) >= 0) or (consts.IndexOf (name) >= 0) then Exit (True);
  if FindType (name) <> nil then Exit (True);
  for i := 0 to High (modVarN) do
    if modVarN[i] = name then Exit (True);
  Result := False;
end;

{ Gen.ExportWalk: the designator Mod.v... of a directly imported module's
  exported variable becomes the designator rooted at the one name Mod.v }
procedure TGen.ExportWalk (n, sc: TNode);
var
  i : Integer;
  s : TNode;
begin
  if n = nil then Exit;
  if (n.kind = nkDesignator) and (Length (n.kids) > 0) and (n.kids[0] <> nil) then
  begin
    s := n.kids[0];
    if (s.kind = nkSelField) and (extMods.IndexOf (n.a) >= 0) and
       (extVars.IndexOf (n.a + '.' + s.a) >= 0) and not NameShadowed (sc, n.a) then
    begin
      n.a := n.a + '.' + s.a;
      for i := 0 to High (n.kids) - 1 do n.kids[i] := n.kids[i + 1];
      SetLength (n.kids, Length (n.kids) - 1);
    end;
  end;
  for i := 0 to High (n.kids) do
    if n.kind = nkProcDecl then ExportWalk (n.kids[i], n)
    else ExportWalk (n.kids[i], sc);
end;

function TGen.ScopeNode (const n: string): TNode;
var ix : Integer;
begin
  ix := ScopeFind (n);
  if ix < 0 then Exit (nil);
  Result := TNode (scope.Objects[ix]);
end;

function TGen.ScopeMode (const n: string): string;
var ix : Integer;
begin
  ix := ScopeFind (n);
  if ix < 0 then Exit ('');
  Result := scope.ValueFromIndex[ix];
end;

function TGen.FieldType (rec: TNode; const f: string): TNode;
var
  fs : TNode;
  i, j : Integer;
begin
  Result := nil;
  { nkRecordType carries kids[0]=base, kids[1]=fields; nkMonitorType
    has no base, so its fields are kids[0] }
  if rec.kind = nkMonitorType then fs := rec.kids[0]
  else fs := rec.kids[1];
  if fs = nil then Exit;
  for i := 0 to High (fs.kids) do
    for j := 0 to High (fs.kids[i].kids[0].kids) do
      if fs.kids[i].kids[0].kids[j].a = f then
        Exit (fs.kids[i].kids[1]);
end;

{ ---- the frame form of NEW, and adoption at exit (rule 1 of
  docs/pool-elision-plan.md); mirrors Gen.AsQualG, NewShape, HasPtr
  and AdoptEmit ---- }

function TGen.AsQualG (d: TNode): TNode;
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

{ 'frame' for NEW (T) and NEW (T, n...), 'pool' for NEW (pool, T...),
  'own' for NEW (OWN, T), told apart by NAME; the checker has refused
  anything else.  ty is the type's node, ext0 the first extent's index. }
function TGen.NewShape (e: TNode; out ty: TNode; out ext0: Integer): string;
var
  d : TNode;
  isVar : Boolean;
begin
  ty := nil;
  ext0 := 2;
  d := e.kids[0];
  if d <> nil then
  begin
    if (Length (d.kids) = 0) and (d.a = 'OWN') then
    begin
      ty := e.kids[1];
      Exit ('own');
    end;
    isVar := True;
    if Length (d.kids) = 0 then
    begin
      if (ScopeMode (d.a) = '') and (d.a <> 'HEAP') then isVar := False;
    end
    else if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
    begin
      if (ScopeMode (d.a) = '') and (extMods.IndexOf (d.a) >= 0) then
        isVar := False;
    end;
    if isVar then
    begin
      ty := AsQualG (e.kids[1]);
      Exit ('pool');
    end;
    ty := AsQualG (e.kids[0]);
    ext0 := 1;
    Exit ('frame');
  end;
  ty := e.kids[1];
  Result := 'frame';
end;

{ can a value of this type carry a pointer into the frame? }
function TGen.HasPtr (t: TNode; depth: Integer): Boolean;
var
  r, fs : TNode;
  i, j : Integer;
begin
  Result := False;
  if depth > 8 then Exit;
  r := Resolve (t);
  if r = nil then Exit;
  case r.kind of
    nkPtrType, nkSliceType, nkGridType : Result := True;
    nkOptType : Result := HasPtr (r.kids[0], depth + 1);
    nkArrayType : Result := HasPtr (r.kids[1], depth + 1);
    nkRecordType, nkMonitorType :
      begin
        if r.kind = nkMonitorType then fs := r.kids[0] else fs := r.kids[1];
        if fs = nil then Exit;
        for i := 0 to High (fs.kids) do
          if (fs.kids[i] <> nil) and HasPtr (fs.kids[i].kids[1], depth + 1) then
            Exit (True);
      end;
    nkCaseRecordType :
      for i := 0 to High (r.kids) do
        if (r.kids[i] <> nil) and (r.kids[i].kids[0] <> nil) then
          for j := 0 to High (r.kids[i].kids[0].kids) do
            if (r.kids[i].kids[0].kids[j] <> nil) and
               HasPtr (r.kids[i].kids[0].kids[j].kids[1], depth + 1) then
              Exit (True);
  end;
end;

{ does a VAR parameter of this type carry its object's pool as a
  hidden argument (docs/pool-elision-plan.md, rule 2)?  Mirrors
  Gen.PoolParamTy: PTR and OPT PTR by node kind, a pointer-bearing
  record, monitor, array or variant by resolution, never a bare slice
  or grid. }
function TGen.PoolParamTy (t: TNode): Boolean;
var r : TNode;
begin
  Result := False;
  if t = nil then Exit;
  if t.kind = nkPtrType then Exit (True);
  if t.kind = nkOptType then
    Exit ((t.kids[0] <> nil) and (t.kids[0].kind = nkPtrType));
  if t.kind in [nkSliceType, nkGridType] then Exit;
  r := Resolve (t);
  if r = nil then Exit;
  { a name for a pointer is the pointer it names (mirrors Gen) }
  if r.kind = nkPtrType then Exit (True);
  if r.kind = nkOptType then
    Exit ((r.kids[0] <> nil) and (r.kids[0].kind = nkPtrType));
  if r.kind in [nkRecordType, nkMonitorType, nkArrayType, nkCaseRecordType] then
    Result := HasPtr (t, 0);
end;

{ the exit test, one line per pointer component of EXPR of type T,
  each adopting the frame into DST: the caller's arena for a result,
  the object's own pool for a VAR parameter's target (rule 2) }
procedure TGen.AdoptEmit (const expr: string; t: TNode; const dst: string;
                          ind, depth: Integer);
var
  r, fs, g, ids, v, vfs, fg, fids : TNode;
  i, j, k : Integer;
  kv : string;
begin
  if depth > 8 then Exit;
  r := Resolve (t);
  if r = nil then Exit;
  case r.kind of
    nkPtrType :
      Line (pbuf, ind, 'm9_adopt_if (&m9frame, ' + dst + ', ' + expr + ');');
    nkOptType :
      if HasPtr (r.kids[0], depth + 1) then
        Line (pbuf, ind, 'm9_adopt_if (&m9frame, ' + dst + ', ' + expr + ');');
    nkSliceType, nkGridType :
      Line (pbuf, ind, 'm9_adopt_if (&m9frame, ' + dst + ', ' + expr + '.p);');
    nkArrayType :
      if HasPtr (r.kids[1], depth + 1) then
      begin
        kv := 'm9k' + IntToStr (depth);
        Line (pbuf, ind, 'for (int64_t ' + kv + ' = 0; ' + kv + ' < ' +
          ArrCount (r.kids[0]) + '; ' + kv + '++) {');
        AdoptEmit (expr + '.v[' + kv + ']', r.kids[1], dst, ind + 1, depth + 1);
        Line (pbuf, ind, '}');
      end;
    nkRecordType, nkMonitorType :
      begin
        if r.kind = nkMonitorType then fs := r.kids[0] else fs := r.kids[1];
        if fs = nil then Exit;
        for i := 0 to High (fs.kids) do
        begin
          g := fs.kids[i];
          if (g = nil) or not HasPtr (g.kids[1], depth + 1) then continue;
          ids := g.kids[0];
          if ids = nil then continue;
          for j := 0 to High (ids.kids) do
            if ids.kids[j] <> nil then
              AdoptEmit (expr + '.' + CN (ids.kids[j].a), g.kids[1], dst,
                         ind, depth + 1);
        end;
      end;
    nkCaseRecordType :
      for i := 0 to High (r.kids) do
      begin
        v := r.kids[i];
        if v = nil then continue;
        vfs := v.kids[0];
        if vfs = nil then continue;
        for j := 0 to High (vfs.kids) do
        begin
          fg := vfs.kids[j];
          if (fg = nil) or not HasPtr (fg.kids[1], depth + 1) then continue;
          fids := fg.kids[0];
          if fids = nil then continue;
          for k := 0 to High (fids.kids) do
            if fids.kids[k] <> nil then
              AdoptEmit (expr + '.u.' + v.a + '.' + CN (fids.kids[k].a),
                         fg.kids[1], dst, ind, depth + 1);
        end;
      end;
  end;
end;

{ the C address of the pool a NEW's first argument names: a POOL
  variable or HEAP by designator, or a VAR parameter's hidden pool
  (rule 2), which is a pointer already.  Mirrors Gen.PoolAddrC. }
function TGen.PoolAddrC (pd: TNode): string;
var tg : string;
begin
  if (Length (pd.kids) = 0) and (ScopeMode (pd.a) = 'v') and
     PoolParamTy (ScopeNode (pd.a)) then
    Exit (CN (pd.a) + '_pool');
  Result := '&(' + DES (pd, tg) + ')';
end;

{ the pool of the object a designator names, from its ROOT (rule 2
  of docs/pool-elision-plan.md).  Mirrors Gen.ObjPoolC, which says
  which root gets what. }
function TGen.ObjPoolC (a: TNode): string;
var
  m : string;
  ix, i : Integer;
  t, r : TNode;
begin
  m := ScopeMode (a.a);
  if m = 'v' then
  begin
    if PoolParamTy (ScopeNode (a.a)) then Exit (CN (a.a) + '_pool');
    Exit ('err->res');
  end;
  if m = 'b' then
  begin
    for i := bpool.Count - 1 downto 0 do
      if bpool.Names[i] = a.a then Exit (bpool.ValueFromIndex[i]);
    Exit ('err->res');
  end;
  if m = 'l' then
  begin
    t := ScopeNode (a.a);
    if (t <> nil) and (t.kind = nkOptType) then t := t.kids[0];
    r := Resolve (t);
    if (r <> nil) and (r.kind = nkPtrType) and (r.kids[1] <> nil) then
      Exit (PoolAddrC (r.kids[1]));
    ix := ScopeFind (a.a);
    if (ix >= mvBase) and (ix < mvBase + Length (modVarN)) then
      Exit ('&m9mframe');
    Exit ('err->res');
  end;
  Result := 'err->res';
end;

{ a binder's pool is its origin's when the origin is a designator,
  else the arena a call's answer lands in }
function TGen.OriginPool (k: TNode): string;
begin
  if (k <> nil) and (k.kind = nkDesignator) then Exit (ObjPoolC (k));
  Result := 'err->res';
end;

function TGen.TagOfExpr (e: TNode): string;
var
  t, u, sh : string;
  ci, ext0, nx : Integer;
  tyk : TNode;
begin
  Result := '?';
  if e = nil then Exit;
  case e.kind of
    nkInt : Result := 'I64';
    nkReal : Result := 'F64';
    nkChar : Result := 'CHAR';
    nkString :
      if Utf8Len (e.a) = 1 then Result := 'STR1' else Result := 'SLICE';
    nkTrue, nkFalse : Result := 'BOOL';
    nkParen : Result := TagOfExpr (e.kids[0]);
    nkDesignator :
      begin
        Inc (dry); DES (e, t); Dec (dry);   { recompute, emit nothing }
        Result := t;
      end;
    nkCallExpr :
      begin
        Inc (dry); CallC (e.kids[0], e.kids[1], e, t); Dec (dry);
        Result := t;
      end;
    nkBin :
      begin
        if (e.a = 'AND') or (e.a = 'OR') or (e.a = '=') or (e.a = '#') or
           (e.a = '<') or (e.a = '<=') or (e.a = '>') or (e.a = '>=') then
          Exit ('BOOL');
        t := TagOfExpr (e.kids[0]);
        if t = 'I64' then t := TagOfExpr (e.kids[1]);
        { and a real literal adapts the same way }
        if IsAdaptive (e.kids[0]) then t := TagOfExpr (e.kids[1]);
        { a string concatenation is a STRING whatever its left
          operand's own tag: a one-character literal, or a CHAR
          prepended to a string (par 2.3, revised 2026-09-06) }
        if (e.a = '+') and ((t = 'STR1') or (t = 'CHAR')) then
        begin
          u := TagOfExpr (e.kids[1]);
          if (t = 'STR1') or (u = 'SLICE') or (u = 'STR1') then t := 'SLICE';
        end;
        Result := t;
      end;
    nkUn :
      if e.a = 'NOT' then Result := 'BOOL'
      else Result := TagOfExpr (e.kids[0]);
    nkNewExpr :
      begin
        sh := NewShape (e, tyk, ext0);
        nx := 0;
        for ci := ext0 to High (e.kids) do
          if e.kids[ci] <> nil then Inc (nx);
        if nx > 1 then Result := 'GRID'
        else if nx = 1 then Result := 'SLICE'
        else Result := 'PTR';
      end;
    nkSliceOf3 : Result := 'SLICE';
    nkGridOf : Result := 'GRID';
    nkNoneLit : Result := 'OPTPTR';
  end;
  if (e.kind = nkDesignator) and (Result = '?') and
     (Length (e.kids) = 0) then
  begin
    ci := consts.IndexOf (e.a);
    if ci >= 0 then Result := TagOfExpr (TNode (consts.Objects[ci]));
  end;
end;

{ the value node of a designator naming a CONST, or nil.  Both
  spellings: a bare name in this module, and Mod.Name imported. }
function TGen.ConstValue (e: TNode): TNode;
var ci : Integer;
begin
  Result := nil;
  if (e = nil) or (e.kind <> nkDesignator) then Exit;
  if Length (e.kids) = 0 then
  begin
    ci := consts.IndexOf (e.a);
    if ci >= 0 then Result := TNode (consts.Objects[ci]);
    Exit;
  end;
  if (Length (e.kids) = 1) and (e.kids[0].kind = nkSelField) then
  begin
    ci := extConsts.IndexOf (e.a + '.' + e.kids[0].a);
    if ci >= 0 then Result := TNode (extConsts.Objects[ci]);
  end;
end;

{ ADAPTIVE: carries no width of its own, so it takes the other
  operand's.  A real or integer literal, arithmetic over such, and a
  CONST whose value is one -- M9's CONST is an untyped literal, not a
  typed constant, which is the whole reason `Satfwb * p` is legal at
  either width. }
function TGen.IsAdaptive (e: TNode): Boolean;
var v : TNode;
begin
  Result := False;
  if e = nil then Exit;
  if (e.kind = nkReal) or (e.kind = nkInt) then Exit (True);
  if e.kind = nkParen then Exit (IsAdaptive (e.kids[0]));
  if (e.kind = nkUn) and (e.a = '-') then Exit (IsAdaptive (e.kids[0]));
  if (e.kind = nkBin) and
     ((e.a = '+') or (e.a = '-') or (e.a = '*') or (e.a = '/')) then
    Exit (IsAdaptive (e.kids[0]) and IsAdaptive (e.kids[1]));
  v := ConstValue (e);
  if v <> nil then Exit (IsAdaptive (v));
end;

{ a CONST built with `+' over string and CHAR literals is FOLDED into
  one literal where it is registered (mirrors Gen.FoldStr, 2026-10-09) }
function TGen.StrLeaf (e: TNode; var s: string): Boolean;
begin
  Result := False;
  if e = nil then Exit;
  if e.kind = nkString then begin s := s + e.a; Exit (True); end;
  if e.kind = nkChar then begin s := s + Utf8Enc (Cardinal (CharVal (e.a))); Exit (True); end;
  if e.kind = nkParen then Exit (StrLeaf (e.kids[0], s));
  if (e.kind = nkBin) and (e.a = '+') then
    if StrLeaf (e.kids[0], s) then Exit (StrLeaf (e.kids[1], s));
end;

function TGen.FoldStr (e: TNode): TNode;
var s : string; n : TNode;
begin
  Result := e;
  if (e = nil) or (e.kind <> nkBin) or (e.a <> '+') then Exit;
  s := '';
  if StrLeaf (e, s) then
  begin
    n := TNode.Create (nkString);
    n.a := s; n.line := e.line; n.col := e.col;
    Result := n;
  end;
end;

function TGen.CharVal (const lit: string): Int64;
begin
  { hex digits + trailing C: 0AC = U+000A }
  Result := StrToInt64 ('$' + Copy (lit, 1, Length (lit) - 1));
end;

{ a constant table (par 2.2.4): CONST X = [ e1, ..., en ] is kept as
  an ARRAY n OF T built here, T read off the first element -- the
  checker has held every element to it }
{ Gen.RecordConstQual: the record a CONST's call names, as a type
  node, an alias followed -- or nil }
function TGen.RecordConstQual (e: TNode): TNode;
var
  name, ct, m, tn : string;
  j, dot, depth, ei : Integer;
  t : TNode;
begin
  Result := nil;
  if (e = nil) or (e.kind <> nkCallExpr) or (e.kids[0] = nil) then Exit;
  name := e.kids[0].a;
  for j := 0 to High (e.kids[0].kids) do
    if e.kids[0].kids[j].kind = nkSelField then
      name := name + '.' + e.kids[0].kids[j].a;
  if RecordAt (name, ct) = nil then Exit;
  { the same walk RecordAt makes, for the name it ends on }
  dot := Pos ('.', name);
  if dot = 0 then begin m := modName; tn := name; end
  else begin m := Copy (name, 1, dot - 1); tn := Copy (name, dot + 1, MaxInt); end;
  for depth := 0 to 7 do
  begin
    if m = modName then t := FindType (tn)
    else
    begin
      ei := extTypes.IndexOf (m + '.' + tn);
      if ei < 0 then Exit;
      t := TNode (extTypes.Objects[ei]);
    end;
    if t = nil then Exit;
    if t.kind = nkRecordType then Break;
    if t.b <> '' then begin m := t.a; tn := t.b; end else tn := t.a;
  end;
  Result := TNode.Create (nkQualident);
  if m = modName then Result.a := tn
  else begin Result.a := m; Result.b := tn; end;
end;

procedure TGen.AddAgg (const nm: string; ag: TNode);
var
  cnt, at, el, q : TNode;
begin
  { a record CONST: its type is the record (par 2.2.4) }
  q := RecordConstQual (ag);
  if q <> nil then
  begin
    SetLength (aggN, Length (aggN) + 1);
    SetLength (aggT, Length (aggT) + 1);
    SetLength (aggV, Length (aggV) + 1);
    aggN[High (aggN)] := nm;
    aggT[High (aggT)] := q;
    aggV[High (aggV)] := ag;
    Exit;
  end;
  cnt := TNode.Create (nkInt);
  cnt.a := IntToStr (Length (ag.kids));
  el := ag.kids[0];
  if (el <> nil) and (el.kind = nkUn) then el := el.kids[0];
  q := TNode.Create (nkQualident);
  q.a := 'I64';
  if el <> nil then
    case el.kind of
      nkReal : q.a := 'F64';
      nkChar : q.a := 'CHAR';
      nkTrue, nkFalse : q.a := 'BOOL';
      nkString : q := strNode;
    end;
  if RecordConstQual (ag.kids[0]) <> nil then q := RecordConstQual (ag.kids[0]);
  at := TNode.Create (nkArrayType);
  at.Add (cnt);
  at.Add (q);
  SetLength (aggN, Length (aggN) + 1);
  SetLength (aggT, Length (aggT) + 1);
  SetLength (aggV, Length (aggV) + 1);
  aggN[High (aggN)] := nm;
  aggT[High (aggT)] := at;
  aggV[High (aggV)] := ag;
end;

{ ... visible in every body after the module variables, in the mode
  of a VAR parameter: the name is a POINTER to the table, so index,
  LEN and lending take the paths a VAR array parameter takes }
procedure TGen.PushAggs;
var i : Integer;
begin
  for i := 0 to High (aggN) do
    scope.AddObject (aggN[i] + '=v', TObject (aggT[i]));
end;

{ ... and emitted as const data -- read-only storage, so a write the
  checker missed is a fault and not a changed constant -- with the
  name a pointer to it.  One element per line: a table is read. }
{ Gen.LitC: a literal of a constant table or record CONST as C }
function TGen.LitC (e: TNode; const sname, what: string): string;
begin
  Result := '0';
  case e.kind of
    nkInt : Result := 'INT64_C(' + e.a + ')';
    nkReal : Result := '(' + e.a + ')';
    nkChar : Result := IntToStr (CharVal (e.a)) + 'u';
    nkTrue : Result := 'true';
    nkFalse : Result := 'false';
    nkString :
      if Length (e.a) > 0 then
        Result := '{ (uint32_t *) ' + sname + ', ' +
          IntToStr (Utf8Len (e.a)) + ' }'
      else
        Result := '{ 0, 0 }';
    nkUn :
      if (e.kids[0] <> nil) and (e.kids[0].kind = nkInt) then
        Result := 'INT64_C(-' + e.kids[0].a + ')'
      else if e.kids[0] <> nil then
        Result := '(-' + e.kids[0].a + ')';
  else
    Err (e, 'aggregate element unsupported yet: ' + what);
  end;
end;

procedure TGen.StrC (tgt: TStringList; e: TNode; const sname: string);
begin
  if (e <> nil) and (e.kind = nkString) and (Length (e.a) > 0) then
    tgt.Add ('static const uint32_t ' + sname + '[' +
      IntToStr (Utf8Len (e.a)) + '] = { ' + StrCodes (e.a, e) + ' };');
end;

procedure TGen.RecStrs (tgt: TStringList; e: TNode; const base: string);
var f : Integer;
begin
  if e.kids[1] <> nil then
    for f := 0 to High (e.kids[1].kids) do
      StrC (tgt, e.kids[1].kids[f], base + '_' + IntToStr (f));
end;

function TGen.RecC (e: TNode; const base, what: string): string;
var f : Integer;
begin
  Result := '{ ';
  if e.kids[1] <> nil then
    for f := 0 to High (e.kids[1].kids) do
    begin
      if f > 0 then Result := Result + ', ';
      Result := Result + LitC (e.kids[1].kids[f], base + '_' + IntToStr (f), what);
    end;
  Result := Result + ' }';
end;

procedure TGen.EmitAggs (tgt: TStringList);
var
  i, k : Integer;
  ty, nm, cs : string;
  e : TNode;
begin
  for i := 0 to High (aggN) do
  begin
    ty := TyC (aggT[i]);
    nm := CN (aggN[i]);
    if aggV[i].kind = nkCallExpr then
    begin
      { a record CONST: one record of const data }
      RecStrs (tgt, aggV[i], nm + '_s0');
      tgt.Add ('static const ' + ty + ' ' + nm + '_k = ' +
        RecC (aggV[i], nm + '_s0', aggN[i]) + ';');
      tgt.Add ('static ' + ty + ' * const ' + nm + ' = (' + ty + ' *) &' +
        nm + '_k;');
      Continue;
    end;
    for k := 0 to High (aggV[i].kids) do
    begin
      e := aggV[i].kids[k];
      if (e <> nil) and (e.kind = nkCallExpr) then
        RecStrs (tgt, e, nm + '_s' + IntToStr (k))
      else
        StrC (tgt, e, nm + '_s' + IntToStr (k));
    end;
    tgt.Add ('static const ' + ty + ' ' + nm + '_k = { {');
    for k := 0 to High (aggV[i].kids) do
    begin
      e := aggV[i].kids[k];
      cs := '0';
      if e <> nil then
      begin
        if e.kind = nkCallExpr then
          cs := RecC (e, nm + '_s' + IntToStr (k), aggN[i])
        else
          cs := LitC (e, nm + '_s' + IntToStr (k), aggN[i]);
      end;
      if k < High (aggV[i].kids) then cs := cs + ',';
      tgt.Add ('  ' + cs);
    end;
    tgt.Add ('} };');
    tgt.Add ('static ' + ty + ' * const ' + nm + ' = (' + ty + ' *) &' +
      nm + '_k;');
  end;
end;

function TGen.StrCodes (const s: string; n: TNode): string;
var
  i : Integer;
  cs : string;
begin
  { every Unicode scalar as its code: the literal's text is UTF-8
    octets here (M9AST.Utf8Next), scalars on the M9 side }
  cs := '';
  i := 1;
  while i <= Length (s) do
  begin
    if i > 1 then cs := cs + ', ';
    cs := cs + IntToStr (Utf8Next (s, i)) + 'u';
  end;
  Result := cs;
end;

{ ---- designators ---- }

function TGen.DES (d: TNode; out tag: string): string;
var
  ci, j, k, rk, ei : Integer;
  tnd, r, inner : TNode;
  sel : TNode;
  base, ix, ec, nsx : string;
  enumIx : Boolean;
  tmod : string;
begin
  tag := '?';
  tmod := '';
  tnd := ScopeNode (d.a);
  if tnd = nil then
  begin
    ci := consts.IndexOf (d.a);
    if ci >= 0 then
    begin
      Result := modName + '_' + d.a;
      tag := TagOfExpr (TNode (consts.Objects[ci]));
      { const slice indexing }
      for j := 0 to High (d.kids) do
        if d.kids[j].kind = nkSelIndex then
        begin
          base := Result;
          ix := EX (d.kids[j].kids[0], '');
          Result := '(*(uint32_t *) m9_at (' + base + '.p, ' + ix +
            ', ' + base + '.len, sizeof (uint32_t), err))';
          stRaise := True;
          if tag = 'SLICE' then tag := 'CHAR';   { const strings only }
        end;
      Exit;
    end;
    { imported constant: Mod.Name (a #define in Mod.h) }
    if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
    begin
      ci := extConsts.IndexOf (d.a + '.' + d.kids[0].a);
      if ci >= 0 then
      begin
        tag := TagOfExpr (TNode (extConsts.Objects[ci]));
        Exit (d.a + '_' + d.kids[0].a);
      end;
    end;
    { a top-level procedure named as a VALUE (par 2.2.3): its C
      function, this module's or an imported module's }
    if (Length (d.kids) = 0) and (FindProc (d.a) >= 0) then
    begin
      tag := 'PROC';
      Exit (modName + '_' + d.a);
    end;
    if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) and
       (extProcs.IndexOf (d.a + '.' + d.kids[0].a) >= 0) then
    begin
      tag := 'PROC';
      Exit (d.a + '_' + d.kids[0].a);
    end;
    { payload-less variant constructor: Type.Variant }
    r := FindType (d.a);
    if (r <> nil) and (r.kind in [nkCaseRecordType, nkEnumType]) and
       (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
    begin
      tag := 'CR:' + d.a;
      Exit ('((' + modName + '_' + d.a + '){ .tag = ' + modName +
        '_' + d.a + '_' + d.kids[0].a + ' })');
    end;
    { and across a module: Mod.Type.Variant, the checker's spelling
      for an imported variant, refused here until 2026-09-15 }
    if (extMods.IndexOf (d.a) >= 0) and (Length (d.kids) = 2) and
       (d.kids[0].kind = nkSelField) and (d.kids[1].kind = nkSelField) then
    begin
      ei := extTypes.IndexOf (d.a + '.' + d.kids[0].a);
      if ei >= 0 then
      begin
        r := TNode (extTypes.Objects[ei]);
        if (r <> nil) and (r.kind in [nkCaseRecordType, nkEnumType]) then
        begin
          tag := 'CR:' + d.a + '.' + d.kids[0].a;
          Exit ('((' + d.a + '_' + d.kids[0].a + '){ .tag = ' +
            d.a + '_' + d.kids[0].a + '_' + d.kids[1].a + ' })');
        end;
      end;
    end;
    { HEAP: the predeclared pool that is never freed (par 4.3).  A
      name in both ends or neither -- the checker types it, so the
      generator emits it. }
    if (d.a = 'HEAP') and (Length (d.kids) = 0) then
    begin
      tag := 'POOL';
      Exit ('m9_heap');
    end;
    Err (d, 'unknown name: ' + d.a);
    Exit ('0');
  end;
  Result := CN (d.a);
  if (ScopeMode (d.a) = 'v') or (ScopeMode (d.a) = 'o') then
    Result := '(*' + CN (d.a) + ')';
  for j := 0 to High (d.kids) do
  begin
    sel := d.kids[j];
    NoteMod (tnd, tmod);
    r := Resolve (tnd);
    if r = nil then begin Err (d, 'cannot type ' + d.a); Exit ('0'); end;
    case sel.kind of
      nkSelField :
        begin
          if r.kind in [nkPtrType, nkSharedType] then
          begin
            inner := Resolve (InMod (r.kids[0], tmod));
            if (inner = nil) or
               not (inner.kind in [nkRecordType, nkMonitorType]) then
              begin Err (d, 'field on non-record'); Exit ('0'); end;
            Result := Result + '->' + CN (sel.a);
            tnd := InMod (FieldType (inner, sel.a), tmod);
          end
          else if r.kind in [nkRecordType, nkMonitorType] then
          begin
            Result := Result + '.' + CN (sel.a);
            tnd := InMod (FieldType (r, sel.a), tmod);
          end
          else
            begin Err (d, 'field on non-record'); Exit ('0'); end;
          if tnd = nil then
            begin Err (d, 'no field ' + sel.a); Exit ('0'); end;
        end;
      nkSelIndex :
        begin
          if r.kind = nkGridType then
          begin
            { every axis checked against its own extent, in one call:
              the check a hand-rolled d[r*cols+c] cannot make }
            base := Result;
            ec := TyC (r.kids[1]);
            ix := '';
            for k := 0 to High (sel.kids) do
            begin
              if k > 0 then ix := ix + ', ';
              ix := ix + EX (sel.kids[k], '');
            end;
            rk := High (sel.kids) + 1;
            if (rk >= 1) and (rk <= 4) then
            begin
              { ranks 1..4 go to the written-out form: extents and
                strides by value, no index array, no loop over the
                rank.  2.60x -> 1.29x on the port's kernel, with the
                same checks -- see runtime/m9rt.h and
                the port's gat_cost.c. }
              nsx := '';
              for k := 0 to rk - 1 do
                nsx := nsx + base + '.n[' + IntToStr (k) + '], ';
              for k := 0 to rk - 1 do
                nsx := nsx + base + '.s[' + IntToStr (k) + '], ';
              Result := '(*(' + ec + ' *) m9_gat' + IntToStr (rk) + ' (' +
                base + '.p, sizeof (' + ec + '), ' + nsx + ix + ', err))';
            end
            else
              Result := '(*(' + ec + ' *) m9_gat (' + base + '.p, sizeof (' +
                ec + '), ' + base + '.n, ' + base + '.s, (int64_t[]){' + ix +
                '}, ' + ArrCount (r.kids[0]) + ', err))';
            stRaise := True;
            tnd := InMod (r.kids[1], tmod);
            Continue;
          end;
          ix := EX (sel.kids[0], '');
          if r.kind = nkSliceType then
          begin
            base := Result;
            ec := TyC (r.kids[0]);
            Result := '(*(' + ec + ' *) m9_at (' + base + '.p, ' + ix +
              ', ' + base + '.len, sizeof (' + ec + '), err))';
            stRaise := True;
            tnd := InMod (r.kids[0], tmod);
          end
          else if r.kind = nkArrayType then
          begin
            base := Result;
            ec := TyC (r.kids[1]);
            { ARRAY Colour OF T: the subscript is an enum value, its
              tag 0..n-1 by construction -- no runtime bounds check,
              a.v[(k).tag] directly.  Detect it from the SUBSCRIPT's
              type, not the array's bound: an imported enum indexes an
              imported record's field the same way, where the bound
              resolves only in its own module (docs/enum-plan.md). }
            enumIx := ArrEnumBoundNode (r.kids[0]) <> nil;
            if (not enumIx) and (Length (sel.kids) >= 1) then
              enumIx := Copy (TagOfExpr (sel.kids[0]), 1, 3) = 'CR:';
            if enumIx then
              Result := '(' + base + '.v[(' + ix + ').tag])'
            else
            begin
              Result := '(*(' + ec + ' *) m9_at (' + base + '.v, ' + ix +
                ', INT64_C(' + ArrCount (r.kids[0]) + '), sizeof (' + ec +
                '), err))';
              stRaise := True;
            end;
            tnd := InMod (r.kids[1], tmod);
          end
          else
            begin Err (d, 'index on non-slice'); Exit ('0'); end;
        end;
    end;
  end;
  tag := TagOfType (tnd);
end;

{ ---- calls ---- }

{ the member count of a type convertible from an integer -- an
  enumeration, or a case record all of whose variants are payload-less
  -- else -1 (docs/enum-plan.md, part 2). }
function TGen.EnumConvCount (n: TNode): Integer;
var i : Integer;
begin
  Result := -1;
  if n = nil then Exit;
  if n.kind = nkEnumType then Exit (Length (n.kids));
  if n.kind = nkCaseRecordType then
  begin
    for i := 0 to High (n.kids) do
      if (Length (n.kids[i].kids) > 0) and (n.kids[i].kids[0] <> nil) then Exit (-1);
    Exit (Length (n.kids));
  end;
end;

{ Gen.RecordAt: the RECORD a callee names and its C type name,
  following an alias by name to the record it stands for }
function TGen.RecordAt (const name: string; out ctype: string): TNode;
var
  dot, depth, ei : Integer;
  m, tn : string;
  t : TNode;
begin
  Result := nil;
  dot := Pos ('.', name);
  if dot = 0 then begin m := modName; tn := name; end
  else begin m := Copy (name, 1, dot - 1); tn := Copy (name, dot + 1, MaxInt); end;
  for depth := 0 to 7 do
  begin
    if m = modName then
      t := FindType (tn)
    else
    begin
      ei := extTypes.IndexOf (m + '.' + tn);
      if ei < 0 then Exit;
      t := TNode (extTypes.Objects[ei]);
    end;
    if t = nil then Exit;
    if t.kind = nkRecordType then
    begin
      ctype := m + '_' + tn;
      Exit (t);
    end;
    if t.kind <> nkQualident then Exit;
    if t.b <> '' then begin m := t.a; tn := t.b; end
    else tn := t.a;
  end;
end;

{ a raising call nested as an argument is guarded before the
  enclosing call runs -- corpus/Gen.m9's HoistArg says why }
function TGen.HoistArg (const a: string): string;
var tmp : string;
begin
  if (not hoistOk) or (dry > 0) then Exit (a);
  Inc (nhoist);
  tmp := 'm9a' + IntToStr (nhoist);
  Line (pbuf, hoistInd, '{ __typeof__(' + a + ') ' + tmp + ' = ' + a + ';');
  Line (pbuf, hoistInd + 1, 'if (err->exc) goto ' + raiseLbl + ';');
  Inc (hoistOpen);
  Result := tmp;
end;

procedure TGen.CloseHoists (ind: Integer);
begin
  while hoistOpen > 0 do
  begin
    Line (pbuf, ind, '}');
    Dec (hoistOpen);
  end;
  hoistOk := False;
end;

function TGen.CallC (dnode, argl, site: TNode; out tag: string): string;
var
  svRaise : Boolean;
  e2 : string;
  name, args, at, want, tn, vn, cfunc, gname : string;
  pv : Boolean;                     { a call through a procedure value }
  svt : TNode;
  pi, g, j, k, nargs, dot : Integer;
  pl, grp, arg, vt, vd, pnode, xvt, enode, rec : TNode;
  ec, rk : Integer;
  isref : Boolean;
  ctype : string;
begin
  tag := '?';
  name := dnode.a;
  { the dotted callee name: every field selector joins, so
    Mod.Type.Variant reaches the constructor branch whole -- the
    two-part cut read it as procedure `Csv' and refused it as
    `callee unsupported yet' until 2026-09-15 }
  for k := 0 to High (dnode.kids) do
    if dnode.kids[k].kind = nkSelField then
      name := name + '.' + dnode.kids[k].a;
  nargs := 0;
  if argl <> nil then nargs := Length (argl.kids);

  { A RECORD AGGREGATE: Row (a, b), or Mod.Row (a, b) -- a compound
    literal of the record's C type, the fields in declaration order,
    which is the struct's order (Gen.RecordAt) }
  rec := RecordAt (name, ctype);
  if rec <> nil then
  begin
    tag := 'REC';
    args := '';
    rk := 0;
    if rec.kids[1] <> nil then
      for g := 0 to High (rec.kids[1].kids) do
      begin
        grp := rec.kids[1].kids[g];
        for j := 0 to High (grp.kids[0].kids) do
        begin
          if (rk < nargs) and (argl <> nil) then
          begin
            if args <> '' then args := args + ', ';
            args := args + EX (argl.kids[rk], TagOfType (grp.kids[1]));
          end;
          Inc (rk);
        end;
      end;
    if rk <> nargs then Err (site, 'record aggregate arity wrong');
    Exit ('((' + ctype + '){ ' + args + ' })');
  end;

  { AN INTEGER TO AN ENUMERATION: Colour (i), or Palette.Hue (i), the
    checked inverse of ORD.  The callee is a type -- an enum or a
    payload-less case record -- and CRNode/CRPrefix resolve it for
    either spelling.  m9_enum raises ValueRange for a value that names
    no member (docs/enum-plan.md, part 2). }
  if nargs = 1 then
  begin
    enode := CRNode (name);
    ec := EnumConvCount (enode);
    if ec >= 0 then
    begin
      tag := 'CR:' + name;
      stRaise := True;
      Exit ('((' + CRPrefix (name) + '){ .tag = m9_enum ((int64_t)(' +
        EX (argl.kids[0], '') + '), INT64_C(' + IntToStr (ec) +
        '), err) })');
    end;
  end;

  { An ALIAS FOR A SCALAR IS A CONVERSION under its own name.  The
    checker already treats `TYPE Real = F32` as F32 for assignment,
    arguments and RETURN -- aliases chase to structure -- so `Real
    (x)` meaning anything other than `F32 (x)` would be the odd case.
    Chased here, once, so every conversion below applies unchanged.
    Forced by a Fortran port, which needs one source buildable at
    both of the original's real kinds (-fdefault-real-8 is commented
    out in its makefile, so single is what ships and double is what
    the flag is for), and that needs the default kind to have a name
    that also converts. }
  if (nargs = 1) and not InL (name, Builtins) then
  begin
    dot := Pos ('.', name);
    if dot > 0 then
    begin
      pi := extTypes.IndexOf (name);
      if pi >= 0 then vt := TNode (extTypes.Objects[pi]) else vt := nil;
    end
    else
    begin
      vt := FindType (name);
      if vt = nil then
      begin
        pi := ExtBare (name);
        if pi >= 0 then vt := TNode (extTypes.Objects[pi]);
      end;
    end;
    if vt <> nil then vt := Resolve (vt);
    if (vt <> nil) and (vt.kind = nkQualident) and (vt.b = '') and
       InL (vt.a, Builtins) then
      name := vt.a;
  end;

  { builtins the milestone needs }
  if name = 'LEN' then
  begin
    at := TagOfExpr (argl.kids[0]);
    { a grid has one length per axis, so LEN names the axis }
    if (at = 'GRID') and (nargs = 2) then
    begin
      tag := 'I64';
      Exit ('(' + EX (argl.kids[0], '') + ').n[' +
        EX (argl.kids[1], '') + ']');
    end;
    if at = 'SLICE' then begin tag := 'I64'; Exit ('(' + EX (argl.kids[0], '') + ').len') end;
    if at = 'ARR' then
    begin
      arg := Resolve (ScopeNode (argl.kids[0].a));
      if (arg <> nil) and (arg.kind = nkArrayType) then
      begin
        tag := 'I64';
        Exit ('INT64_C(' + ArrCount (arg.kids[0]) + ')');
      end;
    end;
    tag := 'I64';
    Exit ('(' + EX (argl.kids[0], '') + ').len');
  end;
  { VIEW (g, i, ALL, ...): a borrowed sub-grid.  The axes are known
    here, so the loop is unrolled and the result's rank is a compile
    time fact -- which is what lets a view have a type at all.  The
    dropped axes are CHECKED where the view is taken, not later where
    it is read, so an out-of-range view is diagnosed at the mistake. }
  if name = 'VIEW' then
  begin
    vd := Resolve (DesigDecl (argl.kids[0]));
    if (vd = nil) or (vd.kind <> nkGridType) then
    begin
      Err (site, 'VIEW of an unresolvable grid');
      Exit ('0');
    end;
    k := 0;                              { axes kept }
    for j := 1 to nargs - 1 do
      if IsAllArg (argl.kids[j]) then Inc (k);
    vn := NewTmp;
    tn := TyC (vd);                                   { the source }
    want := GridTy (vd.kids[1], IntToStr (k));        { the answer }
    args := '({ ' + tn + ' ' + vn + ' = ' + EX (argl.kids[0], '') + '; ' +
      want + ' ' + vn + 'r; int64_t ' + vn + 'o = 0; ';
    g := 0;
    for j := 1 to nargs - 1 do
      if IsAllArg (argl.kids[j]) then
      begin
        args := args + vn + 'r.n[' + IntToStr (g) + '] = ' + vn + '.n[' +
          IntToStr (j - 1) + ']; ' + vn + 'r.s[' + IntToStr (g) + '] = ' +
          vn + '.s[' + IntToStr (j - 1) + ']; ';
        Inc (g);
      end
      else
        args := args + vn + 'o += m9_gdrop (' + EX (argl.kids[j], '') +
          ', ' + vn + '.n[' + IntToStr (j - 1) + '], ' + vn + '.s[' +
          IntToStr (j - 1) + '], err); ';
    args := args + vn + 'r.p = ' + vn + '.p + ' + vn + 'o; ' + vn + 'r; })';
    stRaise := True;
    tag := 'GRID';
    Exit (args);
  end;
  if name = 'ORD' then
  begin
    tag := 'I64';
    { an enumeration (or any payload-less case record) answers its
      tag; a CHAR answers its code point.  ORD (Colour.Red) is 0,
      ORD (c) is the member's position, 0..n-1 (docs/enum-plan.md) }
    if Copy (TagOfExpr (argl.kids[0]), 1, 3) = 'CR:' then
      Exit ('(int64_t)((' + EX (argl.kids[0], '') + ').tag)');
    Exit ('(int64_t)(' + EX (argl.kids[0], 'CHAR') + ')');
  end;
  if name = 'NAME' then
  begin
    { the member's identifier as a STR, from the table emitted beside
      the tag #defines: NAME (Colour.Red) is 'Red' }
    tag := 'SLICE';
    at := TagOfExpr (argl.kids[0]);
    Exit ('(' + CRPrefix (Copy (at, 4, MaxInt)) + '_names[(' +
      EX (argl.kids[0], '') + ').tag])');
  end;
  if name = 'CHR' then
  begin
    tag := 'CHAR'; stRaise := True;
    Exit ('m9_chr (' + EX (argl.kids[0], '') + ', err)');
  end;
  if name = 'BYTE' then
  begin
    tag := 'BYTE'; stRaise := True;
    Exit ('m9_byte (' + EX (argl.kids[0], '') + ', err)');
  end;
  { the other widths, each a checked narrowing: the museum's founding
    bug is a width that converted itself, so every one of these is a
    call that can raise rather than a cast that cannot }
  if (name = 'I8') or (name = 'I16') or (name = 'I32') or
     (name = 'U8') or (name = 'U16') or (name = 'U32') or
     (name = 'U64') then
  begin
    tag := name; stRaise := True;
    Exit ('m9_' + LowerCase (name) + ' (' + EX (argl.kids[0], '') +
      ', err)');
  end;
  if name = 'I64' then
  begin
    tag := 'I64';
    at := TagOfExpr (argl.kids[0]);
    if (at = 'F64') or (at = 'F32') then
    begin
      stRaise := True;
      Exit ('m9_i64_f64 ((double)(' + EX (argl.kids[0], '') + '), err)');
    end;
    Exit ('(int64_t)(' + EX (argl.kids[0], '') + ')');
  end;
  if name = 'F64' then
  begin
    tag := 'F64';
    Exit ('(double)(' + EX (argl.kids[0], '') + ')');
  end;
  if name = 'F32' then
  begin
    tag := 'F32';
    { from a double: checked (mirrors Gen.CallC) }
    at := TagOfExpr (argl.kids[0]);
    if at = 'F64' then
    begin
      stRaise := True;
      Exit ('m9_f32_f64 (' + EX (argl.kids[0], '') + ', err)');
    end;
    Exit ('(float)(' + EX (argl.kids[0], '') + ')');
  end;
  if name = 'MAX' then
  begin
    tag := argl.kids[0].a;
    if argl.kids[0].a = 'I64' then Exit ('INT64_MAX');
    Err (site, 'MAX of ' + argl.kids[0].a + ' unsupported yet');
    Exit ('0');
  end;
  { SizeOf (x): the byte size of x's TYPE, a compile-time constant
    folding to C sizeof.  A bare builtin or user type name asks the
    named type; anything else asks the value's type (sizeof does not
    evaluate its operand).  A slice's own SizeOf is its descriptor;
    the DATA a slice points at is ByteSize.  In-memory only -- a wire
    uses the exact-width types and ToBytesLE. }
  if name = 'SizeOf' then
  begin
    tag := 'I64';
    if (argl.kids[0].kind = nkDesignator) and
       (Length (argl.kids[0].kids) = 0) then
    begin
      if BuiltinC (argl.kids[0].a) <> '' then
        Exit ('((int64_t) sizeof (' + BuiltinC (argl.kids[0].a) + '))');
      if FindType (argl.kids[0].a) <> nil then
        Exit ('((int64_t) sizeof (' + modName + '_' + argl.kids[0].a + '))');
    end;
    Exit ('((int64_t) sizeof (' + EX (argl.kids[0], '') + '))');
  end;
  { ByteSize (s): the bytes s's elements occupy -- LEN * elem size.
    sizeof (*(s).p) reads the element size off the slice's own pointer
    type without evaluating s. }
  if name = 'ByteSize' then
  begin
    tag := 'I64';
    at := EX (argl.kids[0], '');
    Exit ('((int64_t) (' + at + ').len * (int64_t) sizeof (*(' + at + ').p))');
  end;
  if name = 'ADR' then
  begin
    tag := '?';
    at := TagOfExpr (argl.kids[0]);
    if at = 'SLICE' then
      Exit ('((void *)(' + EX (argl.kids[0], '') + ').p)');
    if at = 'ARR' then
      Exit ('((void *)(' + EX (argl.kids[0], '') + ').v)');
    Err (site, 'ADR of non-slice unsupported yet');
    Exit ('0');
  end;

  { WIDTH DISPATCH BY DECLARED TWIN, the generator half.  The checker
    resolved `Math.Sqrt (x)` on an F32 to Math.SqrtF32 and typed it;
    the call must be EMITTED to the same procedure or the two ends
    disagree about which program this is.

    HERE, and not before the builtins: up there it asked TagOfExpr
    for the first argument's type on every call, and `MAX (I64)`
    passes a TYPE NAME, not an expression.  A builtin has no twin by
    construction, so the only place this can apply is where user
    procedures are resolved. }
  if (nargs >= 1) and (Length (name) > 3) and
     (Copy (name, Length (name) - 2, 3) <> 'F32') and
     ((Pos ('.', name) > 0) or (FindProc (name) >= 0)) then
  begin
    { SOME argument is F32 and NONE is F64 -- the checker's rule,
      character for character, because the two must agree about which
      procedure this call is.  A literal types as neither width, so
      `Math.Pow (10.0, c)` dispatches on c. }
    g := 0; j := 0;
    for k := 0 to nargs - 1 do
      if not IsAdaptive (argl.kids[k]) then
      begin
        { an adaptive argument is neither width and must not vote:
          `Math.Pow (10.0, c)` dispatches on c }
        at := TagOfExpr (argl.kids[k]);
        if at = 'F32' then Inc (g);
        if at = 'F64' then Inc (j);
      end;
    if (g > 0) and (j = 0) then
    begin
      if Pos ('.', name) > 0 then
      begin
        if extProcs.IndexOf (name + 'F32') >= 0 then name := name + 'F32';
      end
      else if FindProc (name + 'F32') >= 0 then
        name := name + 'F32';
    end;
  end;

  pnode := nil;
  cfunc := '';
  dot := Pos ('.', name);
  if dot > 0 then
  begin
    tn := Copy (name, 1, dot - 1);
    vn := Copy (name, dot + 1, MaxInt);
    { C.* conversion: a cast at the foreign boundary }
    if tn = 'C' then
    begin
      at := CMap (vn);
      if at = '' then
      begin
        Err (site, 'unknown C type C.' + vn);
        Exit ('0');
      end;
      tag := '?';
      if nargs <> 1 then Err (site, 'C.' + vn + ' takes one argument');
      Exit ('((' + at + ')(' + EX (argl.kids[0], '') + '))');
    end;
    { the wire boundary: F64/F32 . From/ToBytesLE (par 2.1) }
    if ((tn = 'F64') or (tn = 'F32')) and (vn = 'FromBytesLE') then
    begin
      if nargs <> 1 then Err (site, name + ' takes one argument');
      stRaise := True;
      tag := tn;
      if tn = 'F64' then
        Exit ('m9_f64_from_le (' + EX (argl.kids[0], '') + ', err)');
      Exit ('m9_f32_from_le (' + EX (argl.kids[0], '') + ', err)');
    end;
    if ((tn = 'F64') or (tn = 'F32')) and (vn = 'ToBytesLE') then
    begin
      if nargs <> 2 then Err (site, name + ' takes two arguments');
      stRaise := True;
      tag := '?';
      if tn = 'F64' then
        Exit ('m9_f64_to_le (' + EX (argl.kids[0], '') + ', ' +
          EX (argl.kids[1], '') + ', err)');
      Exit ('m9_f32_to_le (' + EX (argl.kids[0], '') + ', ' +
        EX (argl.kids[1], '') + ', err)');
    end;
    { variant constructor with payload: Type.Variant (args) }
    vt := FindType (tn);
    { and Mod.Type.Variant (args), the type's module named: the
      callee split at its first dot reads as module Mod, procedure
      `Type.Variant', which is no procedure.  CRPrefix and the CR:
      tag both carry `Mod.Type' since 2026-09-15. }
    if (vt = nil) and (Pos ('.', vn) > 0) then
    begin
      xvt := CRNode (tn + '.' + Copy (vn, 1, Pos ('.', vn) - 1));
      if (xvt <> nil) and (xvt.kind in [nkCaseRecordType, nkEnumType]) then
      begin
        tn := tn + '.' + Copy (vn, 1, Pos ('.', vn) - 1);
        vn := Copy (vn, Pos ('.', vn) + 1, MaxInt);
        vt := xvt;
      end;
    end;
    if (vt <> nil) and (vt.kind in [nkCaseRecordType, nkEnumType]) then
    begin
      vd := nil;
      for g := 0 to High (vt.kids) do
        if vt.kids[g].a = vn then vd := vt.kids[g];
      if vd = nil then
      begin
        Err (site, 'no variant ' + vn + ' in ' + tn);
        Exit ('0');
      end;
      tag := 'CR:' + tn;
      args := '';
      k := 0;
      if vd.kids[0] <> nil then
        for g := 0 to High (vd.kids[0].kids) do
          for j := 0 to High (vd.kids[0].kids[g].kids[0].kids) do
          begin
            if k < nargs then
            begin
              if args <> '' then args := args + ', ';
              args := args + EX (argl.kids[k],
                TagOfType (vd.kids[0].kids[g].kids[1]));
            end;
            Inc (k);
          end;
      if k <> nargs then Err (site, 'arity mismatch constructing ' + name);
      Result := '((' + CRPrefix (tn) + '){ .tag = ' + CRPrefix (tn) +
        '_' + vn;
      if args <> '' then
        Result := Result + ', .u.' + vn + ' = { ' + args + ' }';
      Result := Result + ' })';
      Exit;
    end;
    { cross-module call: Mod.Proc against a loaded extern def }
    g := extProcs.IndexOf (name);
    if g >= 0 then
    begin
      pnode := TNode (extProcs.Objects[g]);
      cfunc := tn + '_' + vn;
    end;
  end
  else
  begin
    { a call THROUGH A PROCEDURE VALUE (par 2.2.3): a parameter or an
      IS SOME binder whose type is a procedure type.  Its head drives
      the argument conversion below exactly as a declaration's would,
      and the call is `name (args, err)` on the C pointer. }
    pv := False;
    svt := Resolve (ScopeNode (name));
    if (svt <> nil) and (svt.kind = nkProcType) then
    begin
      pnode := svt;
      cfunc := CN (name);
      pv := True;
    end;
    { the module's own procedures shadow foreign imports }
    if pv then
      pi := -1
    else
      pi := FindProc (name);
    if pv then
      { nothing: the value is the callee }
    else if pi >= 0 then
    begin
      pnode := procs[pi].node;
      cfunc := modName + '_' + name;
    end
    else
    begin
      { foreign procedure: direct extern call, no err slot (par 11) }
      pi := foreignProcs.IndexOf (name);
      if pi >= 0 then
      begin
        vt := TNode (foreignProcs.Objects[pi]);
        tag := '?';
        args := '';
        k := 0;
        pl := vt.kids[0];
        if pl <> nil then
          for g := 0 to High (pl.kids) do
            for j := 0 to High (pl.kids[g].kids[0].kids) do
            begin
              if k < nargs then
              begin
                if args <> '' then args := args + ', ';
                args := args + EX (argl.kids[k], '');
              end;
              Inc (k);
            end;
        if k <> nargs then Err (site, 'arity mismatch calling ' + name);

        { [SERIAL] MEANS SERIALISED, NOT FORBIDDEN.

          The attribute says this foreign procedure may not be called
          concurrently -- ecCodes on a global context, blosc on global
          state, the museum's founding race.  The checker's rule was
          that a THREAD may not REACH one, which is unenforceable in
          practice: its BFS walks a per-unit call graph and cannot see
          a [SERIAL] two modules away, which is every realistic case.

          So the generator makes it true instead of checking it.  One
          gate per FOR-C unit, because the state these procedures
          share is the LIBRARY's, not the procedure's; a caller that
          arrives while another thread is inside waits.  Single
          threaded the mutex is uncontended and costs about twenty
          nanoseconds against a foreign call that costs microseconds.

          A GNU statement expression, because a call is an expression
          and the lock has to bracket it. }
        gname := foreignUnit.Values[name];
        if (vt.kids[3] <> nil) and (vt.kids[3].a = 'SERIAL') and
           (gname <> '') then
        begin
          if gateSeen.IndexOf (gname) < 0 then
          begin
            gateSeen.Add (gname);
            rec2Gates.Add ('static m9_mon m9_gate_' + gname + ';');
          end;
          if vt.kids[1] = nil then
            Exit ('({ m9_mon_enter (&m9_gate_' + gname + '); ' +
                  vt.b + ' (' + args + '); ' +
                  'm9_mon_leave (&m9_gate_' + gname + '); })');
          Exit ('({ m9_mon_enter (&m9_gate_' + gname + '); ' +
                '__typeof__(' + vt.b + ' (' + args + ')) m9gv = ' +
                vt.b + ' (' + args + '); ' +
                'm9_mon_leave (&m9_gate_' + gname + '); m9gv; })');
        end;
        Exit (vt.b + ' (' + args + ')');
      end;
    end;
  end;
  if pnode = nil then
  begin
    Err (site, 'callee unsupported yet: ' + name);
    Exit ('0');
  end;
  if pnode.kids[1] <> nil then
    tag := TagOfType (pnode.kids[1]);
  args := '';
  pl := pnode.kids[0];
  k := 0;
  if pl <> nil then
    for g := 0 to High (pl.kids) do
    begin
      grp := pl.kids[g];
      isref := grp.f1 or grp.f2;
      for j := 0 to High (grp.kids[0].kids) do
      begin
        if k < nargs then
        begin
          arg := argl.kids[k];
          if args <> '' then args := args + ', ';
          if isref then
          begin
            if (arg.kind = nkDesignator) and (Length (arg.kids) = 0) and
               ((ScopeMode (arg.a) = 'v') or (ScopeMode (arg.a) = 'o')) then
              args := args + CN (arg.a)     { pass the pointer along }
            else if arg.kind = nkDesignator then
            begin
              args := args + '&(' + DES (arg, at) + ')';
            end
            else
              Err (site, 'VAR argument must be a designator');
            { rule 2: the object's pool rides behind it, named from
              the root of the designator (mirrors Gen.CallC) }
            if grp.f1 and (arg.kind = nkDesignator) and
               PoolParamTy (grp.kids[1]) then
              args := args + ', ' + ObjPoolC (arg);
          end
          else
          begin
            want := TagOfType (grp.kids[1]);
            { ARRAY N OF T is the view of all N elements where a
              SLICE OF T is expected (par 2.2) }
            if (want = 'SLICE') and (arg.kind = nkDesignator) and
               (TagOfExpr (arg) = 'ARR') then
            begin
              vt := Resolve (DesigDecl (arg));
              if (vt <> nil) and (vt.kind = nkArrayType) then
                args := args + '((' + TyC (grp.kids[1]) + '){ (' +
                  EX (arg, '') + ').v, INT64_C(' +
                  ArrCount (vt.kids[0]) + ') })'
              else
                Err (site, 'array view argument unresolvable');
            end
            else
            begin
              { a raising argument is guarded before this call runs }
              svRaise := stRaise;
              stRaise := False;
              e2 := EX (arg, want);
              if stRaise then e2 := HoistArg (e2);
              stRaise := svRaise or stRaise;
              args := args + e2;
            end;
          end;
        end;
        Inc (k);
      end;
    end;
  if k <> nargs then Err (site, 'arity mismatch calling ' + name);
  if args <> '' then args := args + ', ';
  stRaise := True;                        { every call gets a guard }
  Result := cfunc + ' (' + args + 'err)';
end;

{ ---- expressions ---- }

function TGen.EX (e: TNode; const want: string): string;
var
  svHoist : Boolean;
  l, r, lt, rt, w, tg, sh : string;
  cop : string;
  i, j, k, ext0, nx : Integer;
  inr, tyk : TNode;
begin
  Result := '0';
  if e = nil then Exit;
  case e.kind of
    nkInt :
      if want = 'U64' then Result := 'UINT64_C(' + e.a + ')'
      else Result := 'INT64_C(' + e.a + ')';
    nkReal :
      { NaN's NAN is a float already, and the same NaN as a double }
      if (want = 'F32') and (e.a <> 'NAN') then Result := e.a + 'f' else Result := e.a;
    nkChar : Result := IntToStr (CharVal (e.a)) + 'u';
    nkString :
      if (want = 'CHAR') and (Utf8Len (e.a) = 1) then
      begin
        i := 1;
        Result := IntToStr (Utf8Next (e.a, i)) + 'u'   { the scalar, not its first byte }
      end
      else if Length (e.a) = 0 then
        Result := '(m9_sl_CHAR){ NULL, 0 }'
      else if dry > 0 then
        Result := 'm9s_dry'          { a type answer, not code }
      else
      begin
        { static storage, never a stack compound literal: a returned
          literal (Reason's 'Not Found') must not dangle }
        l := 'm9s' + IntToStr (litBuf.Count);
        litBuf.Add ('static const uint32_t ' + l + '[' +
          IntToStr (Utf8Len (e.a)) + '] = { ' + StrCodes (e.a, e) + ' };');
        Result := '((m9_sl_CHAR){ (uint32_t *) ' + l + ', ' +
          IntToStr (Utf8Len (e.a)) + ' })';
      end;
    nkTrue : Result := 'true';
    nkFalse : Result := 'false';
    nkNoneLit : Result := 'NULL';
    nkSomeExpr : Result := EX (e.kids[0], '');   { OPT PTR is nullable }
    nkSharedExpr :
      begin
        { rc lives in the hidden header: rc := 1 in place (par 11) }
        l := EX (e.kids[0], '');
        Result := '((__typeof__(' + l + ')) m9_share (' + l + '))';
      end;
    nkParen : Result := '(' + EX (e.kids[0], want) + ')';
    nkDesignator :
      begin
        Result := DES (e, tg);
        { a CONST is a C macro holding a double literal, so in an F32
          context it must be cast or the expression widens around it }
        if (want = 'F32') and (ConstValue (e) <> nil) and
           IsAdaptive (e) then
          Result := '((float) ' + Result + ')';
      end;
    nkCallExpr : Result := CallC (e.kids[0], e.kids[1], e, tg);
    nkNewExpr :
      begin
        stRaise := True;
        sh := NewShape (e, tyk, ext0);
        if sh = 'own' then
        begin
          l := TyC (tyk);
          Exit ('(' + l + ' *) m9_new (sizeof (' + l + '), err)');
        end;
        if sh = 'pool' then
        begin
          r := 'err->res';
          if e.kids[0] <> nil then r := PoolAddrC (e.kids[0]);
        end
        else
          { the frame form: the result slot, which is this frame's
            arena in the body and the caller's while a RETURN
            expression is emitted -- `+`'s rule exactly (par 2.3) }
          r := 'err->res';
        nx := 0;
        for j := ext0 to High (e.kids) do
          if e.kids[j] <> nil then Inc (nx);
        if nx > 1 then
        begin
          { more than one extent is a GRID.  Row-major: the last
            axis has stride 1, so the innermost loop over the
            rightmost subscript walks memory in order.  The extents
            are stored before they are multiplied, so a shape that
            overflows raises rather than allocating a small buffer
            and then indexing past it. }
          l := TyC (tyk);
          w := NewTmp;
          k := nx;
          Result := '({ ' + GridTy (tyk, IntToStr (k)) + ' ' + w + '; ';
          for j := ext0 to High (e.kids) do
            Result := Result + w + '.n[' + IntToStr (j - ext0) + '] = ' +
              EX (e.kids[j], '') + '; ';
          Result := Result + w + '.s[' + IntToStr (k - 1) + '] = 1; ';
          for j := k - 2 downto 0 do
            Result := Result + w + '.s[' + IntToStr (j) + '] = ' + w +
              '.s[' + IntToStr (j + 1) + '] * ' + w + '.n[' +
              IntToStr (j + 1) + ']; ';
          Result := Result + w + '.p = (' + l + ' *) m9_pool_alloc (' + r +
            ', sizeof (' + l + '), m9_gcount (' + w + '.n, ' +
            IntToStr (k) + ', err), err); ' + w + '; })';
        end
        else if nx = 1 then
        begin
          l := TyC (tyk);
          Result := 'M9_POOL_SL (' + SliceTy (tyk) + ', ' + l +
            ', ' + r + ', ' + EX (e.kids[ext0], '') + ', err)';
        end
        else
        begin
          l := TyC (tyk);
          Result := '(' + l + ' *) m9_pool_alloc (' + r +
            ', sizeof (' + l + '), 1, err)';
        end;
      end;
    nkGridOf :
      begin
        { GRID (s, n0, ..., nR): mirrors Sem's NGridOf (par 2.2.1) }
        stRaise := True;
        inr := nil;
        if (e.kids[0] <> nil) and (e.kids[0].kind = nkDesignator) then
          inr := Resolve (DesigDecl (e.kids[0]));
        tyk := nil;
        if (inr <> nil) and (inr.kind = nkSliceType) then tyk := inr.kids[0];
        if tyk = nil then
        begin
          Err (e, 'GRID of an expression that is not a slice designator');
          Exit ('0');
        end;
        k := Length (e.kids) - 1;
        tg := GridTy (tyk, IntToStr (k));
        l := EX (e.kids[0], '');
        w := NewTmp;
        Result := '({ __typeof__(' + l + ') ' + w + ' = ' + l + '; ' + tg +
          ' ' + w + 'r; int64_t ' + w + 'n[' + IntToStr (k) + '] = { ';
        for j := 1 to High (e.kids) do
        begin
          if j > 1 then Result := Result + ', ';
          Result := Result + EX (e.kids[j], '');
        end;
        Result := Result + ' }; m9_gridof (' + w + '.len, ' + w + 'n, ' +
          IntToStr (k) + ', ' + w + 'r.n, ' + w + 'r.s, err); ' + w +
          'r.p = ' + w + '.p; ' + w + 'r; })';
      end;
    nkSliceOf3 :
      begin
        stRaise := True;
        lt := TagOfExpr (e.kids[0]);
        l := EX (e.kids[0], '');
        w := NewTmp;
        if lt = 'SLICE' then
          Result := '({ __typeof__(' + l + ') ' + w + ' = ' + l +
            '; int64_t ' + w + 'a = ' + EX (e.kids[1], '') +
            ', ' + w + 'n = ' + EX (e.kids[2], '') +
            '; (__typeof__(' + w + ')){ ' + w + '.p + m9_chk_slice (' +
            w + 'a, ' + w + 'n, ' + w + '.len, err), ' + w + 'n }; })'
        else if (lt = 'ARR') and (e.kids[0].kind = nkDesignator) then
        begin
          { the view of an array's elements (par 2.2) }
          inr := Resolve (DesigDecl (e.kids[0]));
          if (inr = nil) or (inr.kind <> nkArrayType) then
          begin
            Err (e, 'SLICE() of unresolvable array');
            Exit ('0');
          end;
          Result := '({ int64_t ' + w + 'a = ' + EX (e.kids[1], '') +
            ', ' + w + 'n = ' + EX (e.kids[2], '') + '; (' +
            SliceTy (inr.kids[1]) + '){ (' + l +
            ').v + m9_chk_slice (' + w + 'a, ' + w + 'n, INT64_C(' +
            ArrCount (inr.kids[0]) + '), err), ' + w + 'n }; })';
        end
        else
        begin
          Err (e, 'SLICE() of non-slice unsupported yet');
          Exit ('0');
        end;
      end;
    nkIs :
      begin
        { `x IS SOME' / `x IS NONE' with no binder: an OPT is a nullable
          pointer in C (mirrors Gen) }
        if (e.kids[1] <> nil) and (e.kids[1].kind = nkIsSome) and (e.kids[1].a = '') then
        begin
          if e.kids[1].f1 then Result := '(' + EX (e.kids[0], '') + ' == NULL)'
          else Result := '(' + EX (e.kids[0], '') + ' != NULL)';
        end
        else
        begin
          Err (e, 'IS with a binder is the whole condition of an IF, ELSIF or WHILE');
          Result := '0';
        end;
      end;
    nkBin :
      begin
        lt := TagOfExpr (e.kids[0]);
        if lt = 'I64' then lt := TagOfExpr (e.kids[1]);
        if IsAdaptive (e.kids[0]) then lt := TagOfExpr (e.kids[1]);
        { string concatenation: `+` where either side is a slice.
          The checker has already refused every other slice element
          type, so a SLICE tag here is a string.  Both sides are
          wanted AS SLICES -- a one-character literal is a string in
          this position, not a CHAR. }
        rt := '';
        if e.a = '+' then rt := TagOfExpr (e.kids[1]);
        if (e.a = '+') and ((lt = 'SLICE') or (lt = 'STR1') or
                            (rt = 'SLICE') or (rt = 'STR1')) then
        begin
          { a CHAR on one side is one code point appended or
            prepended: m9_cat over a one-element view of it (par 2.3,
            revised 2026-09-06).  A one-character LITERAL is STR1,
            not CHAR, and stays on the slice path. }
          if lt = 'CHAR' then
          begin
            l := EX (e.kids[0], 'CHAR');
            r := EX (e.kids[1], 'SLICE');
            stRaise := True;
            Exit ('m9_ch_cat (err->res, ' + l + ', ' + r + ', err)');
          end;
          if rt = 'CHAR' then
          begin
            l := EX (e.kids[0], 'SLICE');
            r := EX (e.kids[1], 'CHAR');
            stRaise := True;
            Exit ('m9_cat_ch (err->res, ' + l + ', ' + r + ', err)');
          end;
          l := EX (e.kids[0], 'SLICE');
          r := EX (e.kids[1], 'SLICE');
          stRaise := True;
          Exit ('m9_cat (err->res, ' + l + ', ' + r + ', err)');
        end;
        w := '';
        if (lt = 'CHAR') or (lt = 'STR1') then w := 'CHAR';
        { at single precision the literals must be single too, or C
          widens the whole expression and narrows once at the end }
        if lt = 'F32' then w := 'F32';
        if lt = 'U64' then w := 'U64';
        { and an adaptive node -- `5.02808 * 0.43429`, all literals --
          has no width of its own, so it takes the context's rather
          than recomputing one from operands that have none }
        if (want <> '') and IsAdaptive (e) then w := want;
        l := EX (e.kids[0], w);
        { the right operand of AND and OR is evaluated only when the
          left decides nothing: no hoist out of it (corpus/Gen.m9) }
        if (e.a = 'AND') or (e.a = 'OR') then
        begin
          svHoist := hoistOk;
          hoistOk := False;
          r := EX (e.kids[1], w);
          hoistOk := svHoist;
        end
        else
          r := EX (e.kids[1], w);
        cop := e.a;
        if cop = '=' then cop := '=='
        else if cop = '#' then cop := '!='
        else if cop = 'AND' then cop := '&&'
        else if cop = 'OR' then cop := '||';
        if (cop = '+') or (cop = '-') or (cop = '*') then
        begin
          { AN UNKNOWN TYPE MUST NOT BECOME INTEGER ARITHMETIC.  A
            tag of '?' here means the generator could not resolve one
            operand's type -- most often a callee whose signature
            names a type from a module this one does not import --
            and falling through to m9_add_i64 emits checked 64-bit
            integer arithmetic over doubles.  That compiles, runs,
            and answers plausible numbers: rhoh 0.3% out, found by
            the one kernel held to bit-identity. }
          if lt = '?' then
          begin
            Err (e, 'arithmetic on an operand of unresolved type'
              + ' (' + e.a + '): the generator cannot tell whether'
              + ' this is integer or floating point');
            Exit ('0');
          end;
          if (lt = 'F64') or (lt = 'F32') then
            Result := '(' + l + ' ' + cop + ' ' + r + ')'
          else
          begin
            stRaise := True;
            if cop = '+' then Result := 'm9_add_' + ISuf (lt) + ' (' + l + ', ' + r + ', err)'
            else if cop = '-' then Result := 'm9_sub_' + ISuf (lt) + ' (' + l + ', ' + r + ', err)'
            else Result := 'm9_mul_' + ISuf (lt) + ' (' + l + ', ' + r + ', err)';
          end;
        end
        else if cop = '/' then
          Result := '(' + l + ' / ' + r + ')'
        else if cop = 'DIV' then
          begin stRaise := True; Result := 'm9_div_' + ISuf (lt) + ' (' + l + ', ' + r + ', err)' end
        else if cop = 'MOD' then
          begin stRaise := True; Result := 'm9_mod_' + ISuf (lt) + ' (' + l + ', ' + r + ', err)' end
        else if cop = '+%' then Result := 'm9_addw_i64 (' + l + ', ' + r + ')'
        else if cop = '-%' then Result := 'm9_subw_i64 (' + l + ', ' + r + ')'
        else if cop = '*%' then Result := 'm9_mulw_i64 (' + l + ', ' + r + ')'
        else if ((cop = '==') or (cop = '!=')) and (Copy (lt, 1, 3) = 'CR:') then
          { two enumeration (or case-record) values compare by tag: a
            struct == is not valid C (docs/enum-plan.md) }
          Result := '((' + l + ').tag ' + cop + ' (' + r + ').tag)'
        else
          Result := '(' + l + ' ' + cop + ' ' + r + ')';
      end;
    nkUn :
      begin
        l := EX (e.kids[0], want);
        if e.a = 'NOT' then Result := '(!' + l + ')'
        else if e.a = '-' then
        begin
          lt := TagOfExpr (e.kids[0]);
          if (lt = 'F64') or (lt = 'F32') then Result := '(- ' + l + ')'
          else begin stRaise := True; Result := 'm9_neg_' + ISuf (lt) + ' (' + l + ', err)' end;
        end
        else Result := l;
      end;
  else
    Err (e, 'expression kind unsupported yet');
  end;
end;

{ an integer-constant CASE label: local CONST or imported Mod.CONST }
function TGen.ConstLbl (d: TNode): string;
var
  ci : Integer;
  e : TNode;
begin
  Result := '';
  e := nil;
  if Length (d.kids) = 0 then
  begin
    ci := consts.IndexOf (d.a);
    if ci >= 0 then e := TNode (consts.Objects[ci]);
  end
  else if (Length (d.kids) = 1) and (d.kids[0].kind = nkSelField) then
  begin
    ci := extConsts.IndexOf (d.a + '.' + d.kids[0].a);
    if ci >= 0 then e := TNode (extConsts.Objects[ci]);
  end;
  if (e <> nil) and (e.kind = nkInt) then
    Result := 'INT64_C(' + e.a + ')';
end;

{ the declared type node a designator lands on (no code emitted) }
function TGen.DesigDecl (d: TNode): TNode;
var
  j : Integer;
  r : TNode;
  tmod : string;
begin
  tmod := '';
  Result := ScopeNode (d.a);
  for j := 0 to High (d.kids) do
  begin
    if Result = nil then Exit;
    NoteMod (Result, tmod);
    r := Resolve (Result);
    while (r <> nil) and (r.kind in [nkPtrType, nkSharedType]) do
      r := Resolve (InMod (r.kids[0], tmod));
    if r = nil then Exit (nil);
    case d.kids[j].kind of
      nkSelField :
        if r.kind in [nkRecordType, nkMonitorType] then
          Result := InMod (FieldType (r, d.kids[j].a), tmod)
        else
          Exit (nil);
      nkSelIndex :
        if r.kind = nkSliceType then Result := InMod (r.kids[0], tmod)
        else if r.kind = nkArrayType then Result := InMod (r.kids[1], tmod)
        else Exit (nil);
    end;
  end;
end;

{ exception descriptor reference: this module, the predeclared four,
  then imported definitions.  A QUALIFIED name resolves in exactly
  the module it states: Io.IOError and ZarrStore.IOError are two
  descriptors, and the first version dropped the qualifier and
  answered whichever module registered the bare name first -- a
  handler for ZarrStore.IOError compiled to a test against
  &Io_IOError and matched nothing, found by the tutorial service's
  no-network zarr cell. }
{ IndexError (index, length : I64) as the field sequence a declared
  exception would have parsed to (mirrors Sem/Gen.IxFields) }
function TGen.IxFields: TNode;
var fs, g, il, i1, i2, ty : TNode;
begin
  if ixF = nil then
  begin
    fs := TNode.Create (nkFieldSeq);
    g := TNode.Create (nkFieldGroup);
    il := TNode.Create (nkIdentList);
    i1 := TNode.Create (nkIdent); i1.a := 'index';
    i2 := TNode.Create (nkIdent); i2.a := 'length';
    ty := TNode.Create (nkQualident); ty.a := 'I64';
    il.Add (i1); il.Add (i2);
    g.Add (il); g.Add (ty);
    fs.Add (g);
    ixF := fs;
  end;
  Result := ixF;
end;

function TGen.ExcRef (const qual, nm: string; out fields: TNode): string;
var i : Integer;
begin
  fields := nil;
  if (qual <> '') and (qual <> modName) then
  begin
    for i := 0 to extExcs.Count - 1 do
      if (extExcs.Names[i] = nm) and
         (extExcs.ValueFromIndex[i] = qual) then
      begin
        fields := TNode (extExcs.Objects[i]);
        Exit (qual + '_' + nm);
      end;
    Exit ('');
  end;
  for i := 0 to High (excN) do
    if excN[i] = nm then
    begin
      fields := excF[i];
      Exit (modName + '_' + nm);
    end;
  if nm = 'IndexError' then
  begin
    fields := IxFields;
    Exit ('m9_exc_IndexError');
  end;
  if (nm = 'Overflow') or (nm = 'OutOfMemory') or (nm = 'ValueRange') then
    Exit ('m9_exc_' + nm);
  i := extExcs.IndexOfName (nm);
  if i >= 0 then
  begin
    fields := TNode (extExcs.Objects[i]);
    Exit (extExcs.ValueFromIndex[i] + '_' + nm);
  end;
  Result := '';
end;

{ the OPT payload type of an IS SOME operand: a designator's declared
  type or a call's return type }
function TGen.OptInner (e: TNode): TNode;
var
  r : TNode;
  nm : string;
  pi, dot : Integer;
begin
  Result := nil;
  r := nil;
  dot := 0;
  if e.kind = nkDesignator then
    r := Resolve (DesigDecl (e))
  else if e.kind = nkCallExpr then
  begin
    nm := e.kids[0].a;
    if (Length (e.kids[0].kids) = 1) and
       (e.kids[0].kids[0].kind = nkSelField) then
      nm := nm + '.' + e.kids[0].kids[0].a;
    dot := Pos ('.', nm);
    if dot > 0 then
    begin
      pi := extProcs.IndexOf (nm);
      if pi >= 0 then r := Resolve (TNode (extProcs.Objects[pi]).kids[1]);
    end
    else
    begin
      pi := FindProc (nm);
      if pi >= 0 then r := Resolve (procs[pi].node.kids[1]);
    end;
  end;
  if (r <> nil) and (r.kind = nkOptType) then
    Result := r.kids[0];
  { an extern return type names its OWN module's types bare: qualify }
  if (Result <> nil) and (e.kind = nkCallExpr) and (dot > 0) and
     (Result.kind = nkPtrType) and (Result.kids[0] <> nil) and
     (Result.kids[0].kind = nkQualident) and
     (Result.kids[0].b = '') and
     (not InL (Result.kids[0].a, Builtins)) then
  begin
    r := TNode.Create (nkQualident);
    r.a := Copy (nm, 1, dot - 1);
    r.b := Result.kids[0].a;
    e := TNode.Create (nkPtrType);
    e.Add (r);
    e.Add (nil);
    Result := e;
  end;
end;

{ one EXCEPT arm: identity match, literal payload guards, binders
  copied out of the slots before the slot is cleared }
procedure TGen.EmitHandler (h: TNode; const dlbl: string; ind: Integer);
var
  nm, qual, desc, cond, slot, ety : string;
  fields, arg, fld : TNode;
  savedScope, ii, di, si, k, g, j : Integer;
  binderLines : TStringList;
begin
  nm := h.kids[0].a; qual := '';
  if h.kids[0].b <> '' then
  begin
    qual := h.kids[0].a;
    nm := h.kids[0].b;
  end;
  desc := ExcRef (qual, nm, fields);
  if desc = '' then
  begin
    Err (h, 'unknown exception in handler: ' + nm);
    Exit;
  end;
  cond := 'err->exc == &' + desc;
  binderLines := TStringList.Create; binderLines.CaseSensitive := True;
  savedScope := scope.Count;
  k := 0; ii := 0; di := 0; si := 0;
  if (h.kids[1] <> nil) and (fields = nil) then
    Err (h, 'handler payload on an exception without declared fields')
  else if h.kids[1] <> nil then
    for g := 0 to High (fields.kids) do
      for j := 0 to High (fields.kids[g].kids[0].kids) do
      begin
        fld := fields.kids[g].kids[1];
        ety := TagOfType (fld);
        if (ety = 'F64') or (ety = 'F32') then
        begin
          slot := 'err->d[' + IntToStr (di) + ']';
          Inc (di);
        end
        else if ety = 'SLICE' then
        begin
          slot := '';
          Inc (si);
        end
        else
        begin
          slot := 'err->i[' + IntToStr (ii) + ']';
          Inc (ii);
        end;
        if k <= High (h.kids[1].kids) then
        begin
          arg := h.kids[1].kids[k];
          if arg.kind = nkIdent then
          begin
            if ety = 'SLICE' then
              { a copy in this procedure's frame: the in-flight one is
                overwritten by the next raise (m9rt.h, m9_pay_take) }
              binderLines.Add (TyC (fld) + ' ' + CN (arg.a) + ' = { (' +
                TyC (Resolve (fld).kids[0]) + ' *) m9_pay_take (err, ' +
                IntToStr (si - 1) + ', sizeof (' +
                TyC (Resolve (fld).kids[0]) + ')), err->s[' +
                IntToStr (si - 1) + '].len }; (void) ' + CN (arg.a) + ';')
            else
              binderLines.Add (TyC (fld) + ' ' + CN (arg.a) + ' = ' +
                slot + '; (void) ' + CN (arg.a) + ';');
            bpool.Add (arg.a + '=err->res');
            scope.AddObject (arg.a + '=b', TObject (fld));
          end
          else if arg.kind = nkInt then
            cond := cond + ' && ' + slot + ' == INT64_C(' + arg.a + ')'
          else
            Err (h, 'handler payload form unsupported yet');
        end;
        Inc (k);
      end;
  Line (pbuf, ind, 'if (' + cond + ') {');
  for j := 0 to binderLines.Count - 1 do
    Line (pbuf, ind + 1, binderLines[j]);
  Line (pbuf, ind + 1, 'err->exc = NULL;');
  EmitSeq (h.kids[2], ind + 1);
  Line (pbuf, ind + 1, 'goto ' + dlbl + ';');
  Line (pbuf, ind, '}');
  while scope.Count > savedScope do scope.Delete (scope.Count - 1);
  binderLines.Free;
end;

{ ---- statements ---- }

procedure TGen.EmitSeq (s: TNode; ind: Integer);
var j : Integer;
begin
  if s = nil then Exit;
  for j := 0 to High (s.kids) do
    EmitStmt (s.kids[j], ind);
end;

procedure TGen.SetDebugSource (const f: string);
begin
  dbgSrc := f;
end;

{ One directive per statement, at column 0 and into the procedure
  buffer, so the C compiler attributes what follows to the M9 line it
  came from.  Nothing when dbgSrc is empty (the default, and what
  every gate compares) or during TagOfExpr's dry recomputation. }
{ register a pool to be freed at L_ret.  Two callers: a local
  `VAR p: POOL`, and the implicit frame arena every procedure gets. }
procedure TGen.PoolReg (const nm: string);
begin
  SetLength (localPools, Length (localPools) + 1);
  localPools[High (localPools)] := nm;
end;

procedure TGen.DbgLine (st: TNode);
begin
  if dry > 0 then Exit;
  if dbgSrc = '' then Exit;
  Line (pbuf, 0, '#line ' + IntToStr (st.line) + ' "' + dbgSrc + '"');
  { and record it for an unhandled exception's message: one store
    per statement, under -g only, so hot production code (no -g) is
    untouched and its default generated C is unchanged }
  Line (pbuf, 1, 'err->line = ' + IntToStr (st.line) + ';');
end;

procedure TGen.EmitStmt (st: TNode; ind: Integer);
var
  l, l2, r, tg, w, cnd, stp, bname, fldn : string;
  j, i2, j2, k2, savedScope, g2, jj, sv, thrPi : Integer;
  vtN, vd, lbl : TNode;
  opened, hadElse, thrWants, lRaise, shared : Boolean;
begin
  DbgLine (st);
  case st.kind of
    nkAssign :
      begin
        stRaise := False;
        hoistOk := True;
        hoistInd := ind;
        l := DES (st.kids[0], tg);
        lRaise := stRaise;
        stRaise := False;
        r := EX (st.kids[1], tg);
        { copying a SHARED handle refcounts it (par 4.2); SHARED(x)
          itself already set rc=1 and is not re-counted }
        shared := (tg = 'SHARED') and (TagOfExpr (st.kids[1]) = 'SHARED');
        if stRaise then
        begin
          { a call that raised answered nothing (report par 5,
            2026-10-03): the right side into a temporary, the error
            slot read, then the store.  corpus/Gen.m9 says why. }
          Line (pbuf, ind, '{ __typeof__(' + l + ') m9v = ' + r + ';');
          Line (pbuf, ind + 1, 'if (err->exc) goto ' + raiseLbl + ';');
          if shared then
            r := '((__typeof__(' + l + ')) m9_share_copy (m9v))'
          else
            r := 'm9v';
          Line (pbuf, ind + 1, l + ' = ' + r + ';');
          if lRaise then
            Line (pbuf, ind + 1, 'if (err->exc) goto ' + raiseLbl + ';');
          Line (pbuf, ind, '}');
          stRaise := False;
        end
        else
        begin
          if shared then
            r := '((__typeof__(' + r + ')) m9_share_copy (' + r + '))';
          Line (pbuf, ind, l + ' = ' + r + ';');
          if lRaise then
            Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
        end;
        CloseHoists (ind);
      end;
    nkCallStmt :
      begin
        stRaise := False;
        hoistOk := True;
        hoistInd := ind;
        Line (pbuf, ind, CallC (st.kids[0], st.kids[1], st, tg) + ';');
        if stRaise then Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
        CloseHoists (ind);
      end;
    nkIf :
      begin
        { IF x IS SOME p THEN: bind the payload, test for NULL }
        if (st.kids[0].kind = nkIs) and
           (st.kids[0].kids[1].kind = nkIsSome) and (st.kids[0].kids[1].a <> '') then
        begin
          vtN := OptInner (st.kids[0].kids[0]);
          if vtN = nil then
          begin
            Err (st, 'IS SOME operand type unresolvable');
            Exit;
          end;
          stRaise := False;
          cnd := EX (st.kids[0].kids[0], '');
          bname := st.kids[0].kids[1].a;
          Line (pbuf, ind, '{ ' + TyC (vtN) + ' ' + CN (bname) +
            ' = ' + cnd + ';');
          if stRaise then Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
          savedScope := scope.Count;
          bpool.Add (bname + '=' + OriginPool (st.kids[0].kids[0]));
          scope.AddObject (bname + '=b', TObject (vtN));
          Line (pbuf, ind, 'if (' + CN (bname) + ' != NULL) {');
          EmitSeq (st.kids[1], ind + 1);
          for j := 2 to High (st.kids) do
            if st.kids[j].kind = nkElsif then
              Err (st, 'ELSIF after IS SOME unsupported yet')
            else
            begin
              Line (pbuf, ind, '} else {');
              EmitSeq (st.kids[j].kids[0], ind + 1);
            end;
          Line (pbuf, ind, '} }');
          while scope.Count > savedScope do
            scope.Delete (scope.Count - 1);
          Exit;
        end;
        stRaise := False;
        cnd := EX (st.kids[0], '');
        if stRaise then
        begin
          w := NewTmp;
          Line (pbuf, ind, 'bool ' + w + ' = ' + cnd + ';');
          Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
          cnd := w;
        end;
        Line (pbuf, ind, 'if (' + cnd + ') {');
        EmitSeq (st.kids[1], ind + 1);
        { ELSIF becomes a nested else-block so a raising condition
          can be hoisted with its guard before the test }
        j2 := 0;
        for j := 2 to High (st.kids) do
          if st.kids[j].kind = nkElsif then
          begin
            Line (pbuf, ind, '} else {');
            stRaise := False;
            cnd := EX (st.kids[j].kids[0], '');
            if stRaise then
            begin
              w := NewTmp;
              Line (pbuf, ind + 1, 'bool ' + w + ' = ' + cnd + ';');
              Line (pbuf, ind + 1, 'if (err->exc) goto ' + raiseLbl + ';');
              cnd := w;
            end;
            Line (pbuf, ind + 1, 'if (' + cnd + ') {');
            EmitSeq (st.kids[j].kids[1], ind + 2);
            Inc (j2);
          end
          else
          begin
            Line (pbuf, ind, '} else {');
            EmitSeq (st.kids[j].kids[0], ind + 1);
          end;
        cnd := '}';
        for j := 1 to j2 do cnd := cnd + ' }';
        Line (pbuf, ind, cnd);
      end;
    nkWhile :
      begin
        { WHILE x IS SOME p DO: rebind per iteration }
        if (st.kids[0].kind = nkIs) and
           (st.kids[0].kids[1].kind = nkIsSome) and (st.kids[0].kids[1].a <> '') then
        begin
          vtN := OptInner (st.kids[0].kids[0]);
          if vtN = nil then
          begin
            Err (st, 'IS SOME operand type unresolvable');
            Exit;
          end;
          bname := st.kids[0].kids[1].a;
          Line (pbuf, ind, 'for (;;) {');
          stRaise := False;
          cnd := EX (st.kids[0].kids[0], '');
          Line (pbuf, ind + 1, TyC (vtN) + ' ' + CN (bname) +
            ' = ' + cnd + ';');
          if stRaise then
            Line (pbuf, ind + 1, 'if (err->exc) goto ' + raiseLbl + ';');
          Line (pbuf, ind + 1, 'if (!(' + CN (bname) + ' != NULL)) break;');
          savedScope := scope.Count;
          bpool.Add (bname + '=' + OriginPool (st.kids[0].kids[0]));
          scope.AddObject (bname + '=b', TObject (vtN));
          sv := inSwitch; inSwitch := 0; j2 := finDepth; finDepth := 0;
          EmitSeq (st.kids[1], ind + 1);
          inSwitch := sv; finDepth := j2;
          while scope.Count > savedScope do
            scope.Delete (scope.Count - 1);
          Line (pbuf, ind, '}');
          Exit;
        end;
        Line (pbuf, ind, 'for (;;) {');
        stRaise := False;
        cnd := EX (st.kids[0], '');
        if stRaise then
        begin
          w := NewTmp;
          Line (pbuf, ind + 1, 'bool ' + w + ' = ' + cnd + ';');
          Line (pbuf, ind + 1, 'if (err->exc) goto ' + raiseLbl + ';');
          cnd := w;
        end;
        Line (pbuf, ind + 1, 'if (!(' + cnd + ')) break;');
        sv := inSwitch; inSwitch := 0; j2 := finDepth; finDepth := 0;
        EmitSeq (st.kids[1], ind + 1);
        inSwitch := sv; finDepth := j2;
        Line (pbuf, ind, '}');
      end;
    nkFor :
      begin
        stRaise := False;
        { FOR over an enumeration walks its tags: the variable is a
          struct, so the loop runs on `.tag' (docs/enum-plan.md, 2) }
        if Copy (TagOfExpr (st.kids[0]), 1, 3) = 'CR:' then
        begin
          w := NewTmp;
          Line (pbuf, ind, '{ int32_t ' + w + 'to;');
          Line (pbuf, ind, CN (st.a) + '.tag = (' + EX (st.kids[0], '') + ').tag;');
          Line (pbuf, ind, w + 'to = (' + EX (st.kids[1], '') + ').tag;');
          Line (pbuf, ind, 'for (; ' + CN (st.a) + '.tag <= ' + w +
            'to; ' + CN (st.a) + '.tag++) {');
          sv := inSwitch; inSwitch := 0; j2 := finDepth; finDepth := 0;
          EmitSeq (st.kids[3], ind + 1);
          inSwitch := sv; finDepth := j2;
          Line (pbuf, ind, '} }');
          Exit;
        end;
        l := EX (st.kids[0], '');
        w := NewTmp;
        Line (pbuf, ind, '{ int64_t ' + w + 'to;');
        Line (pbuf, ind, CN (st.a) + ' = ' + l + ';');
        r := EX (st.kids[1], '');
        Line (pbuf, ind, w + 'to = ' + r + ';');
        if stRaise then Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
        stp := '1';
        if st.kids[2] <> nil then
        begin
          if (st.kids[2].kind = nkInt) then stp := st.kids[2].a
          else if (st.kids[2].kind = nkUn) and (st.kids[2].a = '-') and
                  (st.kids[2].kids[0].kind = nkInt) then
            stp := '-' + st.kids[2].kids[0].a
          else Err (st, 'FOR BY must be a literal');
        end;
        if Copy (stp, 1, 1) = '-' then
          Line (pbuf, ind, 'for (; ' + CN (st.a) + ' >= ' + w + 'to; ' +
            CN (st.a) + ' += ' + stp + ') {')
        else
          Line (pbuf, ind, 'for (; ' + CN (st.a) + ' <= ' + w + 'to; ' +
            CN (st.a) + ' += ' + stp + ') {');
        sv := inSwitch; inSwitch := 0; j2 := finDepth; finDepth := 0;
        EmitSeq (st.kids[3], ind + 1);
        inSwitch := sv; finDepth := j2;
        Line (pbuf, ind, '} }');
      end;
    nkLoop :
      begin
        Line (pbuf, ind, 'for (;;) {');
        sv := inSwitch; inSwitch := 0; j2 := finDepth; finDepth := 0;
        EmitSeq (st.kids[0], ind + 1);
        inSwitch := sv; finDepth := j2;
        Line (pbuf, ind, '}');
      end;
    nkExit :
      begin
        if inSwitch > 0 then
          Err (st, 'EXIT inside a CASE arm would break the switch, ' +
            'not the loop: unsupported yet');
        if finDepth > 0 then
          Err (st, 'EXIT across a FINALLY boundary would skip the ' +
            'cleanup: unsupported yet');
        Line (pbuf, ind, 'break;');
      end;
    nkBlock :
      begin
        opened := False;                    { any handler? }
        vd := nil;                          { the FINALLY node }
        for j := 1 to High (st.kids) do
          if st.kids[j].kind = nkHandler then opened := True
          else if st.kids[j].kind = nkFinally then vd := st.kids[j];
        if opened then
        begin
          if vd <> nil then
          begin
            Err (st, 'EXCEPT and FINALLY on one block unsupported yet');
            Exit;
          end;
          { handlers: raises inside the sequence jump to the dispatch;
            RETURNs bypass it (returns are not exceptions) }
          w := 'L_hdl_' + NewTmp;
          cnd := 'L_dn_' + NewTmp;
          tg := raiseLbl;
          raiseLbl := w;
          EmitSeq (st.kids[0], ind);
          raiseLbl := tg;
          Line (pbuf, ind, 'goto ' + cnd + ';');
          Line (pbuf, 0, w + ': ;');
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkHandler then
              EmitHandler (st.kids[j], cnd, ind);
          Line (pbuf, ind, 'goto ' + raiseLbl + ';');
          Line (pbuf, 0, cnd + ': ;');
          Exit;
        end;
        if vd = nil then
        begin
          EmitSeq (st.kids[0], ind);
          Exit;
        end;
        { FINALLY as a goto cleanup chain (par 11): raises and
          RETURNs inside the block land on the label; the cleanup
          runs; then whatever was pending continues outward }
        w := NewTmp;
        l := 'L_fin_' + NewTmp;
        Line (pbuf, ind, 'bool ' + w + ' = false; (void) ' + w + ';');
        bname := exitLbl; fldn := curRetq; tg := raiseLbl;
        exitLbl := l; raiseLbl := l; curRetq := w;
        Inc (finDepth);
        EmitSeq (st.kids[0], ind);
        Dec (finDepth);
        Line (pbuf, 0, l + ': ;');
        exitLbl := bname; raiseLbl := tg; curRetq := fldn;
        EmitSeq (vd.kids[0], ind);
        if curRetq <> '' then
          Line (pbuf, ind, 'if (' + w + ') { ' + curRetq +
            ' = true; goto ' + exitLbl + '; }')
        else
          Line (pbuf, ind, 'if (' + w + ') goto ' + exitLbl + ';');
        Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
      end;
    nkCase :
      begin
        stRaise := False;
        cnd := EX (st.kids[0], '');
        tg := TagOfExpr (st.kids[0]);
        w := NewTmp;
        Line (pbuf, ind, '{ __typeof__(' + cnd + ') ' + w + ' = ' +
          cnd + ';');
        if stRaise then Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
        hadElse := False;
        if Copy (tg, 1, 3) = 'CR:' then
        begin
          l := CRPrefix (Copy (tg, 4, MaxInt)) + '_';
          vtN := CRNode (Copy (tg, 4, MaxInt));
          Line (pbuf, ind, 'switch (' + w + '.tag) {');
          Inc (inSwitch);
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkCaseArm then
            begin
              savedScope := scope.Count;
              opened := False;
              for i2 := 0 to High (st.kids[j].kids[0].kids) do
              begin
                lbl := st.kids[j].kids[0].kids[i2];
                if lbl.kind = nkLabelPattern then
                begin
                  Line (pbuf, ind, 'case ' + l + lbl.a + ': {');
                  opened := True;
                  { positional binders copy the payload fields }
                  vd := nil;
                  if vtN <> nil then
                    for j2 := 0 to High (vtN.kids) do
                      if vtN.kids[j2].a = lbl.a then vd := vtN.kids[j2];
                  if vd = nil then
                    Err (st, 'no variant ' + lbl.a)
                  else
                  begin
                    k2 := 0;
                    if vd.kids[0] <> nil then
                      for g2 := 0 to High (vd.kids[0].kids) do
                        for jj := 0 to
                            High (vd.kids[0].kids[g2].kids[0].kids) do
                        begin
                          if k2 <= High (lbl.kids[0].kids) then
                          begin
                            bname := CN (lbl.kids[0].kids[k2].a);
                            fldn :=
                              CN (vd.kids[0].kids[g2].kids[0].kids[jj].a);
                            Line (pbuf, ind + 1,
                              TyC (vd.kids[0].kids[g2].kids[1]) + ' ' +
                              bname + ' = ' + w + '.u.' + lbl.a + '.' +
                              fldn + '; (void) ' + bname + ';');
                            bpool.Add (lbl.kids[0].kids[k2].a + '=' +
                              OriginPool (st.kids[0]));
                            scope.AddObject (lbl.kids[0].kids[k2].a +
                              '=b', TObject (vd.kids[0].kids[g2].kids[1]));
                          end;
                          Inc (k2);
                        end;
                  end;
                end
                else if (lbl.kind = nkLabelRange) and
                        (LabelName (lbl.kids[0]) <> '') and
                        (lbl.kids[1] = nil) then
                  Line (pbuf, ind, 'case ' + l + LabelName (lbl.kids[0]) + ':')
                else
                  Err (st, 'CASE label form unsupported yet');
              end;
              if not opened then Line (pbuf, ind, '{');
              EmitSeq (st.kids[j].kids[1], ind + 1);
              Line (pbuf, ind, '} break;');
              while scope.Count > savedScope do
                scope.Delete (scope.Count - 1);
            end
            else
            begin
              hadElse := True;
              Line (pbuf, ind, 'default: {');
              EmitSeq (st.kids[j].kids[0], ind + 1);
              Line (pbuf, ind, '} break;');
            end;
          if not hadElse then
            Line (pbuf, ind, 'default: m9_trap_tag ();');
          Dec (inSwitch);
          Line (pbuf, ind, '} }');
        end
        else if (tg = 'CHAR') or (tg = 'I64') then
        begin
          Line (pbuf, ind, 'switch (' + w + ') {');
          Inc (inSwitch);
          for j := 1 to High (st.kids) do
            if st.kids[j].kind = nkCaseArm then
            begin
              for i2 := 0 to High (st.kids[j].kids[0].kids) do
              begin
                lbl := st.kids[j].kids[0].kids[i2];
                r := '';
                if (lbl.kind = nkLabelRange) and (lbl.kids[1] = nil) then
                begin
                  if (lbl.kids[0].kind = nkString) and
                     (Utf8Len (lbl.kids[0].a) = 1) then
                  begin
                    sv := 1;
                    r := IntToStr (Utf8Next (lbl.kids[0].a, sv)) + 'u';
                  end
                  else if lbl.kids[0].kind = nkChar then
                    r := IntToStr (CharVal (lbl.kids[0].a)) + 'u'
                  else if lbl.kids[0].kind = nkInt then
                    r := 'INT64_C(' + lbl.kids[0].a + ')'
                  else if lbl.kids[0].kind = nkDesignator then
                    r := ConstLbl (lbl.kids[0]);
                end;
                if r = '' then
                  Err (st, 'CASE label form unsupported yet')
                else
                  Line (pbuf, ind, 'case ' + r + ':');
              end;
              Line (pbuf, ind, '{');
              EmitSeq (st.kids[j].kids[1], ind + 1);
              Line (pbuf, ind, '} break;');
            end
            else
            begin
              hadElse := True;
              Line (pbuf, ind, 'default: {');
              EmitSeq (st.kids[j].kids[0], ind + 1);
              Line (pbuf, ind, '} break;');
            end;
          if not hadElse then
            Err (st, 'scalar CASE without ELSE unsupported yet ' +
              '(unmatched-label semantics undecided in the report)');
          Dec (inSwitch);
          Line (pbuf, ind, '} }');
        end
        else
          Err (st, 'CASE selector type unsupported yet: ' + tg);
      end;
    { ---- par 6: the monitor statements ----

      WAIT and SIGNAL name the MONITOR, not a field of it: there is
      one condition variable per monitor, so the monitor is the
      condition.  A WAIT is written as a loop around its predicate,
      which is why SIGNAL broadcasts -- see m9rt.h. }
    nkWait, nkSignal :
      begin
        stRaise := False;
        l := DES (st.kids[0], tg);
        vtN := Resolve (DesigDecl (st.kids[0]));
        if (vtN = nil) or (vtN.kind <> nkMonitorType) then
          Err (st, 'WAIT/SIGNAL needs a MONITOR')
        else if st.kind = nkWait then
          Line (pbuf, ind, 'm9_mon_wait (&(' + l + ').m9mon);')
        else
          Line (pbuf, ind, 'm9_mon_signal (&(' + l + ').m9mon);');
      end;

    { THREAD (P, arg).  ONE TRAMPOLINE PER PROCEDURE, not per site:
      par 6's SHARABLE argument is a MONITOR or an owned value moved
      in, both pointer-shaped, so the argument goes through void*
      with no allocation.  The trampoline carries its own error slot
      because a thread has no caller to check one -- and an unhandled
      raise there is fatal and says so, rather than becoming the one
      silence in this language. }
    nkThread :
      begin
        stRaise := True;
        if (st.kids[0] = nil) or (st.kids[0].kind <> nkDesignator) then
          Err (st, 'THREAD needs a procedure name')
        else
        begin
          bname := st.kids[0].a;
          l := DES (st.kids[1], tg);
          vd := DesigDecl (st.kids[1]);      { the DECLARED type node }
          vtN := Resolve (vd);               { what it resolves to }
          { par 6: the argument must be SHARABLE -- immutable, a
            MONITOR, or an owned value moved in.  A MONITOR is shared
            BY REFERENCE (its whole point is that one lock guards one
            record), and M9 gives no way to take its address outside
            UNSAFE, so the generator passes it: THREAD (P, gate) with
            `gate : Gate` hands &gate to a P declared VAR g: Gate.
            Anything else must already be pointer-shaped. }
          if vtN = nil then
            Err (st, 'THREAD argument type unresolvable')
          else if (vtN.kind <> nkMonitorType) and
                  (Pos ('*', TyC (vd)) = 0) then
            Err (st, 'THREAD argument must be a MONITOR or ' +
                     'pointer-shaped (par 6: SHARABLE)')
          else
          begin
            { TyC wants the DECLARED type -- a qualident it can name --
              not the resolved node: a bare MONITOR node has no name
              to emit, exactly as a bare RECORD node has none. }
            if vtN.kind = nkMonitorType then
            begin
              l := '&(' + l + ')';
              w := TyC (vd) + ' *';
            end
            else
              w := TyC (vd);
            if thrSeen.IndexOf (bname) < 0 then
            begin
              thrSeen.Add (bname);
              { rule 2: the thunk takes the pool the argument lives in
                as well, and hands it on when the target's first
                parameter carries one (mirrors Gen.EmitStmt) }
              thrWants := False;
              thrPi := FindProc (bname);
              if (thrPi >= 0) and (procs[thrPi].node <> nil) and
                 (procs[thrPi].node.kids[0] <> nil) and
                 (Length (procs[thrPi].node.kids[0].kids) > 0) and
                 (procs[thrPi].node.kids[0].kids[0] <> nil) then
                thrWants := procs[thrPi].node.kids[0].kids[0].f1 and
                  PoolParamTy (procs[thrPi].node.kids[0].kids[0].kids[1]);
              thrBuf.Add ('static void *m9_thr_' + modName + '_' + bname +
                ' (void *p, m9_pool *pool)');
              thrBuf.Add ('{');
              thrBuf.Add ('  m9_state e = { 0 };');
              if thrWants then
                thrBuf.Add ('  ' + modName + '_' + bname + ' ((' +
                  w + ') p, pool, &e);')
              else
              begin
                thrBuf.Add ('  (void) pool;');
                thrBuf.Add ('  ' + modName + '_' + bname + ' ((' +
                  w + ') p, &e);');
              end;
              thrBuf.Add ('  if (e.exc) m9_thread_died (e.exc->name);');
              thrBuf.Add ('  return NULL;');
              thrBuf.Add ('}');
              thrBuf.Add ('');
            end;
            Line (pbuf, ind, 'm9_thread_start2 (m9_thr_' + modName + '_' +
              bname + ', (void *) ' + l + ', ' + ObjPoolC (st.kids[1]) +
              ', err);');
            Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
          end;
        end;
      end;

    nkDispose :
      begin
        stRaise := False;
        l := DES (st.kids[0], tg);
        { interior pools die with their record (par 4.3) and interior
          SHARED handles are released -- but only when THIS is the
          last handle: a shared object's interior outlives any one
          Close (found by the bench driver closing the store first) }
        opened := False;
        vtN := Resolve (DesigDecl (st.kids[0]));
        if (vtN <> nil) and (vtN.kind in [nkPtrType, nkSharedType]) then
        begin
          vd := Resolve (vtN.kids[0]);
          if (vd <> nil) and (vd.kind = nkRecordType) and
             (vd.kids[1] <> nil) then
            for j := 0 to High (vd.kids[1].kids) do
            begin
              lbl := Resolve (vd.kids[1].kids[j].kids[1]);
              if lbl = nil then Continue;
              if ((lbl.kind = nkQualident) and (lbl.a = 'POOL')) or
                 (lbl.kind = nkSharedType) then
              begin
                if not opened then
                begin
                  Line (pbuf, ind, 'if (m9_rc_last (' + l + ')) {');
                  opened := True;
                end;
                if lbl.kind = nkSharedType then
                  for i2 := 0 to High (vd.kids[1].kids[j].kids[0].kids) do
                    Line (pbuf, ind + 1, 'm9_dispose (' + l + '->' +
                      CN (vd.kids[1].kids[j].kids[0].kids[i2].a) + ');')
                else
                  for i2 := 0 to High (vd.kids[1].kids[j].kids[0].kids) do
                    Line (pbuf, ind + 1, 'm9_pool_free (&' + l + '->' +
                      CN (vd.kids[1].kids[j].kids[0].kids[i2].a) + ');');
              end;
            end;
        end;
        if opened then Line (pbuf, ind, '}');
        Line (pbuf, ind, 'm9_dispose (' + l + ');');
        if stRaise then
          Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
      end;
    nkRaiseStmt :
      begin
        stRaise := False;
        l := st.kids[0].a; l2 := '';
        if st.kids[0].b <> '' then
        begin
          l2 := st.kids[0].a;
          l := st.kids[0].b;
        end;
        r := ExcRef (l2, l, vd);
        if r = '' then
        begin
          Err (st, 'RAISE of unknown exception: ' + l);
          Exit;
        end;
        r := '&' + r;
        { payload: I64-class into i[], F64 into d[], slices into s[] }
        if st.kids[1] <> nil then
        begin
          i2 := 0; j2 := 0; k2 := 0;
          for j := 0 to High (st.kids[1].kids) do
          begin
            tg := TagOfExpr (st.kids[1].kids[j]);
            cnd := EX (st.kids[1].kids[j], '');
            if (tg = 'F64') or (tg = 'F32') then
            begin
              { THE SLOTS ARE FINITE AND OVERFLOWING THEM IS SILENT.
                m9_state carries i[4], d[2], s[2]; before this check a
                seventh integer or a third real simply wrote past the
                end of the struct, and the generated C compiled.
                Found by declaring an exception with six F64 fields
                and reading the emitted code. }
              if j2 >= 2 then
              begin
                Err (st, 'RAISE payload: more than 2 real fields ' +
                  '(m9_state has d[2])');
                Exit;
              end;
              Line (pbuf, ind, 'err->d[' + IntToStr (j2) + '] = ' + cnd + ';');
              Inc (j2);
            end
            else if (tg = 'SLICE') then
            begin
              if k2 >= 3 then
              begin
                Err (st, 'RAISE payload: more than 3 slice fields ' +
                  '(m9_state has s[3])');
                Exit;
              end;
              w := NewTmp;
              { m9_pay_keep copies the octets out of the frame that built
                them, which the raise is about to leave (m9rt.h) }
              Line (pbuf, ind, '{ __typeof__(' + cnd + ') ' + w + ' = ' +
                cnd + '; err->s[' + IntToStr (k2) + '].p = ' + w +
                '.p; err->s[' + IntToStr (k2) + '].len = ' + w +
                '.len; m9_pay_keep (err, ' + IntToStr (k2) + ', sizeof (*' +
                w + '.p)); }');
              Inc (k2);
            end
            else
            begin
              if i2 >= 4 then
              begin
                Err (st, 'RAISE payload: more than 4 integer fields ' +
                  '(m9_state has i[4])');
                Exit;
              end;
              Line (pbuf, ind, 'err->i[' + IntToStr (i2) + '] = ' + cnd + ';');
              Inc (i2);
            end;
          end;
        end;
        Line (pbuf, ind, 'm9_raise (err, ' + r + ');');
        Line (pbuf, ind, 'goto ' + raiseLbl + ';');
      end;
    nkReturn :
      begin
        if st.kids[0] <> nil then
        begin
          stRaise := False;
          { the answer outlives this frame, so it is built in the
            caller's arena.  Intermediates land there too -- generous,
            and the price of not tracking tail position through EX. }
          Line (pbuf, ind, 'err->res = m9res;');
          hoistOk := True;
          hoistInd := ind;
          r := EX (st.kids[0], curRetTag);
          Line (pbuf, ind, 'm9ret = ' + r + ';');
          if stRaise then Line (pbuf, ind, 'if (err->exc) goto ' + raiseLbl + ';');
          CloseHoists (ind);
        end;
        if curRetq <> '' then
          Line (pbuf, ind, curRetq + ' = true;');
        Line (pbuf, ind, 'goto ' + exitLbl + ';');
      end;
  else
    Err (st, 'statement kind unsupported yet');
  end;
end;

{ ---- procedures ---- }

procedure TGen.GenProc (const gp: TGProc);
var
  d, pl, grp, body, vt, r : TNode;
  g, j, i, k : Integer;
  ci2, cj2, svConsts : Integer;   { the procedure's own CONSTs }
  sig, retC, mode, cty, init : string;
  names : string;
  monPar : string;               { the monitor this proc is bound to }
  monN : TNode;
  outStr : array of string;      { the VAR/OWN STR parameters, whose
                                   targets are re-homed at L_ret }
  adoptN : array of string;      { the VAR/OWN parameters of a
                                   pointer-bearing type, whose targets
                                   are tested for adoption at L_ret }
  adoptT : array of TNode;
  adoptD : array of string;      { ... and the pool each is adopted
                                   into (rule 2) }
  dst : string;
begin
  d := gp.node;
  scope.Clear;
  SetLength (localPools, 0);
  SetLength (outStr, 0);
  SetLength (adoptN, 0);
  SetLength (adoptT, 0);
  SetLength (adoptD, 0);
  tmpN := 0;
  exitLbl := 'L_ret';
  raiseLbl := 'L_ret';
  curRetq := '';
  finDepth := 0;
  inSwitch := 0;
  if d.kids[1] <> nil then
  begin
    retC := TyC (d.kids[1]);
    curRetTag := TagOfType (d.kids[1]);
  end
  else
  begin
    retC := 'void';
    curRetTag := '';
  end;
  sig := retC + ' ' + modName + '_' + gp.name + ' (';
  monPar := '';
  pl := d.kids[0];
  if pl <> nil then
    for g := 0 to High (pl.kids) do
    begin
      grp := pl.kids[g];
      { RO is a read-only BINDING; the representation follows the
        type, as Ada's `in` does.  Every RO parameter in the corpus
        today is a slice, which is already a borrow, so RO emits
        exactly as a value parameter.  Records and arrays will want
        a pointer here; the checker already forbids the write, so
        that change is an ABI decision, not a semantic one. }
      if grp.f1 then mode := 'v'
      else if grp.f2 then mode := 'o'
      else mode := 'p';
      cty := TyC (grp.kids[1]);
      for j := 0 to High (grp.kids[0].kids) do
      begin
        { A BOUND PROCEDURE IS ONE WHOSE FIRST PARAMETER IS THE
          MONITOR TYPE -- M9 has no method syntax, so the parameter
          is the binding (docs/concurrency.md).  Its body is wrapped
          in enter/leave, which is how par 6's "all access to the
          record's fields is implicitly serialized" becomes a
          property of the emitted code rather than a rule to keep. }
        if (g = 0) and (j = 0) then
        begin
          monN := Resolve (grp.kids[1]);
          if (monN <> nil) and (monN.kind = nkMonitorType) then
          begin
            if mode = 'p' then
              Err (d, 'a MONITOR parameter must be VAR or OWN: ' +
                      'by value copies the lock')
            else
              monPar := CN (grp.kids[0].kids[j].a);
          end;
        end;
        scope.AddObject (grp.kids[0].kids[j].a + '=' + mode,
          TObject (grp.kids[1]));
        if mode = 'p' then
          sig := sig + cty + ' ' + CN (grp.kids[0].kids[j].a) + ', '
        else
        begin
          sig := sig + cty + ' *' + CN (grp.kids[0].kids[j].a) + ', ';
          { rule 2 of docs/pool-elision-plan.md: a VAR parameter of
            a pointer-bearing type carries the pool its object lives
            in, right behind it, and its target is adopted into THAT
            pool at exit (mirrors Gen.GenProc) }
          if (mode = 'v') and PoolParamTy (grp.kids[1]) then
          begin
            sig := sig + 'm9_pool *' + CN (grp.kids[0].kids[j].a) + '_pool, ';
            dst := CN (grp.kids[0].kids[j].a) + '_pool';
          end
          else
            dst := 'm9res';
          if cty = 'm9_sl_CHAR' then
          begin
            SetLength (outStr, Length (outStr) + 1);
            outStr[High (outStr)] := CN (grp.kids[0].kids[j].a);
          end
          else if HasPtr (grp.kids[1], 0) then
          begin
            SetLength (adoptN, Length (adoptN) + 1);
            adoptN[High (adoptN)] := CN (grp.kids[0].kids[j].a);
            SetLength (adoptT, Length (adoptT) + 1);
            adoptT[High (adoptT)] := grp.kids[1];
            SetLength (adoptD, Length (adoptD) + 1);
            adoptD[High (adoptD)] := dst;
          end;
        end;
      end;
    end;
  sig := sig + 'm9_state *err)';

  if not gp.exported then
  begin
    sig := 'static ' + sig;
    sprotos.Add (sig + ';');
  end
  else
    hdrProtos.Add (sig + ';');

  if gp.body = nil then Exit;

  pbuf.Add ('');
  pbuf.Add (sig);
  pbuf.Add ('{');
  { THE FRAME ARENA.  Empty costs nothing -- m9_pool is one NULL
    pointer and the first block is created lazily -- so a procedure
    that never concatenates pays for a zeroed word.  Registered like
    any local POOL, which frees it on EVERY exit: par 11 routes
    return, raise and FINALLY through L_ret alike.

    And the result slot: err->res is the CALLER's arena when we are
    entered, so it is captured before our own calls overwrite it, then
    claimed for them -- a callee's answer lands in OUR frame.  Each
    procedure restores it at L_ret, which is why a caller sets it once
    rather than around every call.  NULL means a caller that does not
    play (a hand-written C driver) and HEAP is the fallback, which is
    what `+` did before this. }
  Line (pbuf, 1, 'm9_pool m9frame = {0};');
  PoolReg ('m9frame');
  Line (pbuf, 1, 'm9_pool *m9res = err->res ? err->res : &m9_heap;');
  Line (pbuf, 1, '(void) m9res;');
  { a function whose answer carries a pointer builds in its CALLER's
    arena from the first statement (rule 1 of docs/pool-elision-
    plan.md): the slot is left as the caller's and the frame stays
    empty.  Mirrors Gen.GenProc, which says why. }
  if (d.kids[1] <> nil) and (retC <> 'm9_sl_CHAR') and
     HasPtr (d.kids[1], 0) then
    Line (pbuf, 1, 'err->res = m9res;')
  else
    Line (pbuf, 1, 'err->res = &m9frame;');
  if dbgSrc <> '' then
    Line (pbuf, 1, 'err->file = "' + dbgSrc + '";');
  { PROCEDURE-LOCAL CONSTs, in the same map the module's own use.  The
    map answers the first hit, so a local that shadowed a module CONST
    would lose silently -- the checker refuses that, which is what
    makes appending safe here.  Truncated when the procedure ends. }
  svConsts := consts.Count;
  if gp.body <> nil then
    for ci2 := 0 to High (gp.body.kids) do
      if (gp.body.kids[ci2] <> nil) and
         (gp.body.kids[ci2].kind = nkConstSection) then
        for cj2 := 0 to High (gp.body.kids[ci2].kids) do
          consts.AddObject (gp.body.kids[ci2].kids[cj2].a,
                            TObject (FoldStr (gp.body.kids[ci2].kids[cj2].kids[0])));
  if retC <> 'void' then
  begin
    if Pos ('*', retC) > 0 then init := ' = NULL'
    else if (retC = 'double') or (retC = 'float') then init := ' = 0'
    else if (retC = 'bool') then init := ' = false'
    else if Pos ('_t', retC) > 0 then init := ' = 0'
    else init := ' = {0}';
    Line (pbuf, 1, retC + ' m9ret' + init + ';');
  end;

  if monPar <> '' then
    Line (pbuf, 1, 'm9_mon_enter (&(*' + monPar + ').m9mon);');

  { locals: zero-initialized, pools registered for L_ret free }
  body := gp.body;
  for i := 0 to High (body.kids) - 1 do
    if (body.kids[i] <> nil) and (body.kids[i].kind = nkVarSection) then
      for g := 0 to High (body.kids[i].kids) do
      begin
        vt := body.kids[i].kids[g].kids[1];
        cty := TyC (vt);
        r := Resolve (vt);
        names := '';
        for j := 0 to High (body.kids[i].kids[g].kids[0].kids) do
        begin
          scope.AddObject (
            body.kids[i].kids[g].kids[0].kids[j].a + '=l', TObject (vt));
          { the structural test comes FIRST: a GRID of I64 is called
            m9_gd3_int64_t, which contains _t and is not a scalar --
            it emitted `= 0` and gcc refused it.  Found by the second
            kernel of the port; a SLICE OF I64 had the same defect and
            no corpus module had happened to declare one as a local }
          if Pos ('*', cty) > 0 then init := ' = NULL'
          else if (r <> nil) and
                  (r.kind in [nkGridType, nkSliceType, nkArrayType,
                              nkRecordType, nkCaseRecordType,
                              nkMonitorType, nkEnumType]) then
            init := ' = {0}'
          else if (cty = 'double') or (cty = 'float') then init := ' = 0'
          else if cty = 'bool' then init := ' = false'
          else if Pos ('_t', cty) > 0 then init := ' = 0'
          else init := ' = {0}';
          Line (pbuf, 1, cty + ' ' +
            CN (body.kids[i].kids[g].kids[0].kids[j].a) + init +
            '; (void) ' + CN (body.kids[i].kids[g].kids[0].kids[j].a) +
            ';');
          if (r <> nil) and (r.kind = nkQualident) and (r.a = 'POOL') then
          begin
            SetLength (localPools, Length (localPools) + 1);
            localPools[High (localPools)] :=
              CN (body.kids[i].kids[g].kids[0].kids[j].a);
          end;
        end;
      end;

  { module state, visible after params and locals (first hit wins) }
  ModuleScope;
  PushAggs;

  { the body's block goes through the statement emitter so a
    proc-level EXCEPT/FINALLY gets the full treatment }
  EmitStmt (body.kids[High (body.kids)], 1);

  Line (pbuf, 0, 'L_ret: ;');
  Line (pbuf, 1, 'err->res = m9res;');
  { par 2.3: a string leaving this frame -- the result, or a VAR/OWN
    STR parameter's target -- is copied into the caller's arena IF it
    lives in the frame that is about to be freed.  Asked of the
    address, at the exit: a `+`, a callee's re-homed answer, a view
    of either, are all caught; a literal, a borrow, or a string in a
    pool the caller named is not moved.  This is what lets a string
    procedure take no pool. }
  { ... and from every LOCAL named pool as well (the frame is
    localPools[0]); mirrors Gen.GenProc, which says why }
  if retC = 'm9_sl_CHAR' then
    for i := 0 to High (localPools) do
      Line (pbuf, 1, 'm9ret = m9_rehome (&' + localPools[i] +
        ', m9res, m9ret, err);');
  for i := 0 to High (outStr) do
    for k := 0 to High (localPools) do
      Line (pbuf, 1, '*' + outStr[i] + ' = m9_rehome (&' + localPools[k] +
        ', m9res, *' + outStr[i] + ', err);');
  { rule 1 of docs/pool-elision-plan.md: a frame allocation that
    leaves -- through the result, or a VAR/OWN parameter's target --
    takes the whole arena with it into the caller's, which a copy
    could not do for a graph.  Mirrors Gen.GenProc. }
  if (d.kids[1] <> nil) and (retC <> 'm9_sl_CHAR') and
     HasPtr (d.kids[1], 0) then
    AdoptEmit ('m9ret', d.kids[1], 'm9res', 1, 0);
  for i := 0 to High (adoptN) do
    AdoptEmit ('(*' + adoptN[i] + ')', adoptT[i], adoptD[i], 1, 0);
  { every exit passes through L_ret, so a RAISE drops the lock for
    the same reason a RETURN does }
  if monPar <> '' then
    Line (pbuf, 1, 'm9_mon_leave (&(*' + monPar + ').m9mon);');
  for i := 0 to High (localPools) do
    Line (pbuf, 1, 'm9_pool_free (&' + localPools[i] + ');');
  if retC <> 'void' then
    Line (pbuf, 1, 'return m9ret;')
  else
    Line (pbuf, 1, 'return;');
  pbuf.Add ('}');
  while consts.Count > svConsts do consts.Delete (consts.Count - 1);
end;

{ a program module's body becomes main ().  The err slot is declared
  here and nowhere else: it is the root of the ABI, so an exception
  that reaches this frame has escaped every handler in the program
  and must be REPORTED and exited on, never swallowed.  par 11's
  "flush before any exit" is why the message goes to stderr and the
  status is nonzero: the museum's HALT piece lost three diagnostics
  to an unflushed stdout. }
procedure TGen.GenMain;
var
  i : Integer;
begin
  scope.Clear;
  SetLength (localPools, 0);
  tmpN := 0;
  exitLbl := 'L_ret';
  raiseLbl := 'L_ret';
  curRetq := '';
  curRetTag := '';
  finDepth := 0;
  inSwitch := 0;
  ModuleScope;
  PushAggs;
  pbuf.Add ('');
  pbuf.Add ('int main (int argc, char **argv)');
  pbuf.Add ('{');
  Line (pbuf, 1, 'm9_state errv = {0};');
  Line (pbuf, 1, 'm9_state *err = &errv;');
  PoolReg ('m9mframe');
  Line (pbuf, 1, 'err->res = &m9mframe;');
  if dbgSrc <> '' then
    Line (pbuf, 1, 'err->file = "' + dbgSrc + '";');
  Line (pbuf, 1, 'm9_args (argc, argv);');
  for i := 0 to extMods.Count - 1 do
    Line (pbuf, 1, extMods[i] + '_m9init (err); if (err->exc) goto L_ret;');
  { the body is a BLOCK, so EXCEPT at the root goes through the same
    handler machinery every other frame uses }
  EmitStmt (mainBody, 1);
  Line (pbuf, 0, 'L_ret: ;');
  for i := 0 to High (localPools) do
    Line (pbuf, 1, 'm9_pool_free (&' + localPools[i] + ');');
  Line (pbuf, 1, 'return m9_exit (err);');
  pbuf.Add ('}');
end;

procedure TGen.GenInit (const forModule: string);
var
  i : Integer;
begin
  scope.Clear;
  SetLength (localPools, 0);
  tmpN := 0;
  exitLbl := 'L_ret';
  raiseLbl := 'L_ret';
  curRetq := '';
  curRetTag := '';
  finDepth := 0;
  inSwitch := 0;
  ModuleScope;
  PushAggs;
  pbuf.Add ('');
  pbuf.Add ('void ' + forModule + '_m9init (m9_state *err)');
  pbuf.Add ('{');
  Line (pbuf, 1, 'static int m9done = 0;');
  Line (pbuf, 1, 'if (m9done) return;');
  Line (pbuf, 1, 'm9done = 1;');
  { the init body's frame is the MODULE's lifetime (the checker
    exempts a store into a module variable here, par 2.3), so the
    arena is static and never freed -- mirrors Gen.GenInit }
  Line (pbuf, 1, 'm9_pool *m9prev = err->res;');
  Line (pbuf, 1, 'err->res = &m9mframe;');
  for i := 0 to extMods.Count - 1 do
    Line (pbuf, 1, extMods[i] + '_m9init (err); if (err->exc) goto L_ret;');
  if mainBody <> nil then EmitStmt (mainBody, 1);
  Line (pbuf, 0, 'L_ret: ;');
  for i := 0 to High (localPools) do
    Line (pbuf, 1, 'm9_pool_free (&' + localPools[i] + ');');
  Line (pbuf, 1, 'err->res = m9prev;');
  pbuf.Add ('}');
end;

{ the C typedef of a procedure type: `typedef R (*Mod_Name) (T1, T2 *,
  m9_state *err);` -- a value parameter is its C type, VAR and OWN a
  pointer to it, exactly the heading rule, so a procedure of the same
  head IS a value of the type in C.  Mirrors Gen.ProcTypedefC. }
function TGen.ProcTypedefC (const name: string; ptn: TNode): string;
var
  retC, ps, cty : string;
  g, j : Integer;
  pl, grp : TNode;
begin
  retC := 'void';
  if ptn.kids[1] <> nil then retC := TyC (ptn.kids[1]);
  ps := '';
  pl := ptn.kids[0];
  if pl <> nil then
    for g := 0 to High (pl.kids) do
    begin
      grp := pl.kids[g];
      if grp = nil then Continue;
      cty := TyC (grp.kids[1]);
      if grp.kids[0] <> nil then
        for j := 0 to High (grp.kids[0].kids) do
          if grp.f1 and PoolParamTy (grp.kids[1]) then
            ps := ps + cty + ' *, m9_pool *, '     { rule 2 }
          else if grp.f1 or grp.f2 then ps := ps + cty + ' *, '
          else ps := ps + cty + ', ';
    end;
  Result := 'typedef ' + retC + ' (*' + modName + '_' + name + ') (' + ps
    + 'm9_state *err);';
end;

procedure TGen.Emit (const forModule: string);
var
  i, ci, j2, i2 : Integer;
  d, e : TNode;
  cs, s : string;
  tgt, rec2, rec3 : TStringList;
  fseq : TNode;
begin
  hdr.Clear; src.Clear; tdefs.Clear; pbuf.Clear; sprotos.Clear;
  thrBuf.Clear; thrSeen.Clear; rec2Gates.Clear; gateSeen.Clear;
  bpool.Clear;
  arrSeen.Clear; litBuf.Clear; hdrRecs.Clear; hdrProtos.Clear;
  hdrConsts.Clear; rec2 := TStringList.Create;
  arrRec.Clear; hdrArrRec.Clear; rec3 := TStringList.Create;
  { Gen.ExportWalks: Mod.v... to the one name Mod.v, before anything
    is emitted }
  if extVars.Count > 0 then
  begin
    for i := 0 to High (procs) do ExportWalk (procs[i].node, nil);
    ExportWalk (mainBody, nil);
  end;
  hdr.Add ('/* generated by M9Gen from ' + forModule + '.m9 -- do not edit */');
  hdr.Add ('#ifndef M9G_' + forModule + '_H');
  hdr.Add ('#define M9G_' + forModule + '_H');
  hdr.Add ('#include "m9rt.h"');
  for i := 0 to extMods.Count - 1 do
    hdr.Add ('#include "' + extMods[i] + '.h"');
  hdr.Add ('');
  if not isProgram then
  begin
    hdr.Add ('void ' + forModule + '_m9init (m9_state *err);');
    hdr.Add ('');
  end;
  src.Add ('/* generated by M9Gen from ' + forModule + '.m9 -- do not edit */');
  src.Add ('#include "' + forModule + '.h"');
  for i := 0 to extMods.Count - 1 do
    src.Add ('#include "' + extMods[i] + '.h"');
  src.Add ('');

  { forward typedefs for every record type: slice typedefs and
    mutually recursive fields need the names before the structs
    (typedef redefinition is legal C11, so the transparent structs'
    own typedef lines are harmless duplicates) }
  for i := 0 to High (tyNames) do
    if tyOpaque[i] or
       ((tyNodes[i] <> nil) and
        (tyNodes[i].kind in [nkRecordType, nkMonitorType, nkCaseRecordType, nkEnumType])) then
      hdr.Add ('typedef struct ' + modName + '_' + tyNames[i] + ' ' +
        modName + '_' + tyNames[i] + ';');
  hdr.Add ('');

  { procedure types (par 2.2.3): a function-pointer typedef with the
    err slot last, the same C signature a procedure of that head
    gets.  Into the discovered-typedef stream, AFTER the slice
    typedefs its parameters register on the way and BEFORE the record
    bodies that may hold a field of it. }
  for i := 0 to High (tyNames) do
    if (tyNodes[i] <> nil) and (tyNodes[i].kind = nkProcType) then
      tdefs.Add (ProcTypedefC (tyNames[i], tyNodes[i]));

  { case records: tagged structs, tags from 0 in declaration order;
    variants with payload fields become union members named after
    the variant }
  for i := 0 to High (tyNames) do
    if (tyNodes[i] <> nil) and (tyNodes[i].kind in [nkCaseRecordType, nkEnumType]) then
    begin
      d := tyNodes[i];
      if tyFromDef[i] then tgt := hdr else tgt := src;
      cs := '';
      for ci := 0 to High (d.kids) do
        if (Length (d.kids[ci].kids) > 0) and (d.kids[ci].kids[0] <> nil) then cs := 'y';
      { a NAMED struct, like records: an anonymous typedef cannot be
        forward-declared, so a SLICE OF this variant put an undeclared
        name in the header (demo/functional/SliceVar.m9) }
      if not IsOpaque (tyNames[i]) then
        tgt.Add ('typedef struct ' + modName + '_' + tyNames[i] + ' ' +
          modName + '_' + tyNames[i] + ';');
      if cs = '' then
        tgt.Add ('struct ' + modName + '_' + tyNames[i] +
          ' { int32_t tag; };')
      else
      begin
        tgt.Add ('struct ' + modName + '_' + tyNames[i] + ' {');
        tgt.Add ('  int32_t tag;');
        tgt.Add ('  union {');
        for ci := 0 to High (d.kids) do
          if (Length (d.kids[ci].kids) > 0) and (d.kids[ci].kids[0] <> nil) then
          begin
            s := '    struct { ';
            for j2 := 0 to High (d.kids[ci].kids[0].kids) do
            begin
              e := d.kids[ci].kids[0].kids[j2];
              for i2 := 0 to High (e.kids[0].kids) do
                s := s + TyC (e.kids[1]) + ' ' +
                  CN (e.kids[0].kids[i2].a) + '; ';
            end;
            tgt.Add (s + '} ' + d.kids[ci].a + ';');
          end;
        tgt.Add ('  } u;');
        tgt.Add ('};');
      end;
      for ci := 0 to High (d.kids) do
      begin
        tgt.Add ('#define ' + modName + '_' + tyNames[i] + '_' +
          d.kids[ci].a + ' ' + IntToStr (ci));
        { NAME's food: one code-point array per member }
        tgt.Add ('static const uint32_t ' + modName + '_' + tyNames[i] +
          '_nm' + IntToStr (ci) + '[] = { ' +
          StrCodes (d.kids[ci].a, d.kids[ci]) + ' };');
      end;
      { and the table NAME indexes by tag }
      { __unused__: the table is dead when nobody calls NAME on this
        type, and -Werror=unused-const-variable would reject it }
      tgt.Add ('static const m9_sl_CHAR __attribute__((__unused__)) ' +
        modName + '_' + tyNames[i] + '_names[] = {');
      for ci := 0 to High (d.kids) do
        tgt.Add ('  { (uint32_t *) ' + modName + '_' + tyNames[i] +
          '_nm' + IntToStr (ci) + ', ' + IntToStr (Length (d.kids[ci].a)) +
          ' },');
      tgt.Add ('};');
      tgt.Add ('');
    end;

  { exceptions: static descriptors, identity by address (par 11) }
  for i := 0 to High (excN) do
    if excDef[i] then
    begin
      hdr.Add ('extern const m9_exc ' + modName + '_' + excN[i] + ';');
      src.Add ('const m9_exc ' + modName + '_' + excN[i] + ' = { "' +
        excN[i] + '" };');
    end
    else
      src.Add ('static const m9_exc ' + modName + '_' + excN[i] +
        ' = { "' + excN[i] + '" };');
  if Length (excN) > 0 then begin hdr.Add (''); src.Add (''); end;

  { record bodies -- into rec2 (spliced after the typedefs their
    field types register), except transparent DEFINITION records,
    which callers must see: those go to the header }
  for i := 0 to High (tyNames) do
    if (tyNodes[i] <> nil) and
       (tyNodes[i].kind in [nkRecordType, nkMonitorType]) then
    begin
      d := tyNodes[i];
      if tyFromDef[i] and not IsOpaque (tyNames[i]) then
        tgt := hdrRecs
      else
        tgt := rec2;
      if not IsOpaque (tyNames[i]) then
        tgt.Add ('typedef struct ' + modName + '_' + tyNames[i] + ' ' +
          modName + '_' + tyNames[i] + ';');
      tgt.Add ('struct ' + modName + '_' + tyNames[i] + ' {');
      { A MONITOR IS A RECORD WITH A LOCK AS ITS FIRST FIELD, so it
        is layout-compatible with the record it is and the lock needs
        no offset arithmetic.  It needs no constructor: M9 records
        arrive zeroed and a zeroed pthread_mutex_t is
        PTHREAD_MUTEX_INITIALIZER on glibc -- measured, see m9rt.h. }
      if tyNodes[i].kind = nkMonitorType then
        tgt.Add ('  m9_mon m9mon;');
      { one declarator per line: `T * a, b` is one pointer and one
        struct in C -- the star binds to the declarator, not the type }
      if d.kind = nkMonitorType then fseq := d.kids[0]
      else fseq := d.kids[1];
      if fseq <> nil then
        for ci := 0 to High (fseq.kids) do
        begin
          s := TyC (fseq.kids[ci].kids[1]);
          for j2 := 0 to High (fseq.kids[ci].kids[0].kids) do
            tgt.Add ('  ' + s + ' ' +
              CN (fseq.kids[ci].kids[0].kids[j2].a) + ';');
        end;
      tgt.Add ('};');
      tgt.Add ('');
    end;

  { module consts -- into the header, so importers see them }
  for ci := 0 to consts.Count - 1 do
  begin
    e := TNode (consts.Objects[ci]);
    if e.kind = nkInt then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] +
        ' INT64_C(' + e.a + ')')
    { a negated literal is a unary node, not a literal: Dict's
      Empty = -1 is the first const the corpus wrote that way }
    else if (e.kind = nkUn) and (e.a = '-') and (e.kids[0] <> nil) and
            (e.kids[0].kind = nkInt) then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] +
        ' INT64_C(-' + e.kids[0].a + ')')
    else if (e.kind = nkUn) and (e.a = '-') and (e.kids[0] <> nil) and
            (e.kids[0].kind = nkReal) then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] +
        ' (-' + e.kids[0].a + ')')
    else if e.kind = nkReal then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] + ' (' +
        e.a + ')')
    { a BOOLEAN constant.  the ported model's parameter module has four of them and
      Fortran calls them parameters, which is what they are: a switch
      a program cannot flip at run time }
    else if e.kind = nkTrue then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] + ' true')
    else if e.kind = nkFalse then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] + ' false')
    else if (e.kind = nkString) and (Length (e.a) > 0) then
    begin
      hdrConsts.Add ('static const uint32_t ' + modName + '_' +
        consts[ci] + '_d[' + IntToStr (Utf8Len (e.a)) + '] = { ' +
        StrCodes (e.a, e) + ' };');
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] +
        ' ((m9_sl_CHAR){ (uint32_t *) ' + modName + '_' + consts[ci] +
        '_d, ' + IntToStr (Utf8Len (e.a)) + ' })');
    end
    { a CHAR constant: one code point, emitted like the char literal it
      names -- <cp>u -- so `s + NL` joins it as a code point (par 2.2) }
    else if e.kind = nkChar then
      hdrConsts.Add ('#define ' + modName + '_' + consts[ci] +
        ' (' + IntToStr (CharVal (e.a)) + 'u)')
    else
      Err (e, 'const form unsupported yet: ' + consts[ci]);
  end;

  { foreign procedures: extern declarations against the C ABI, the
    names passing through verbatim (par 7) }
  for i := 0 to foreignProcs.Count - 1 do
  begin
    d := TNode (foreignProcs.Objects[i]);
    if d.kids[1] <> nil then s := TyC (d.kids[1]) else s := 'void';
    cs := '';
    if d.kids[0] <> nil then
      for ci := 0 to High (d.kids[0].kids) do
        for j2 := 0 to High (d.kids[0].kids[ci].kids[0].kids) do
        begin
          if cs <> '' then cs := cs + ', ';
          cs := cs + TyC (d.kids[0].kids[ci].kids[1]);
        end;
    if cs = '' then cs := 'void';
    src.Add ('extern ' + s + ' ' + d.b + ' (' + cs + ');');
  end;
  if foreignProcs.Count > 0 then src.Add ('');

  { STATEFUL module state: statics, zero like every C static --
    which is also M9's defined-zero story.  Emitted into rec2 now so
    their array typedefs register before tdefs is spliced. }
  for i := 0 to High (modVarN) do
    rec3.Add ('static ' + TyC (modVarT[i]) + ' ' + CN (modVarN[i]) + ';');
  EmitAggs (rec3);
  { the MODULE FRAME, static and at file scope, so that a module
    variable declared without a pool has one to be grown in (rule 2
    of docs/pool-elision-plan.md; mirrors Gen.Emit) }
  rec3.Add ('static m9_pool m9mframe = {0};');
  rec3.Add ('');
  ExportVars (rec3);

  { procedures emit into pbuf; typedefs, string literals, and static
    prototypes they discover along the way land before them }
  for i := 0 to High (procs) do
    GenProc (procs[i]);
  if isProgram then begin if mainBody <> nil then GenMain; end
  else GenInit (forModule);

  { header assembly: consts, discovered typedefs, transparent def
    records, prototypes -- in dependency order }
  hdr.AddStrings (hdrConsts);
  if hdrConsts.Count > 0 then hdr.Add ('');
  hdr.AddStrings (tdefs);
  if tdefs.Count > 0 then hdr.Add ('');
  hdr.AddStrings (hdrRecs);
  hdr.AddStrings (hdrArrRec);
  hdr.AddStrings (hdrProtos);
  hdr.Add ('');
  hdr.Add ('#endif');

  src.AddStrings (rec2);
  src.AddStrings (arrRec);
  src.AddStrings (rec3);
  src.AddStrings (litBuf);
  if litBuf.Count > 0 then src.Add ('');
  src.AddStrings (rec2Gates);
  if rec2Gates.Count > 0 then src.Add ('');
  src.AddStrings (sprotos);
  if sprotos.Count > 0 then src.Add ('');
  { the trampolines go AFTER the prototypes they call and before the
    bodies, which is the only place both are visible }
  src.AddStrings (thrBuf);
  if thrBuf.Count > 0 then src.Add ('');
  src.AddStrings (pbuf);
  rec2.Free;
  rec3.Free;

  HText := hdr.Text;
  CText := src.Text;
end;

end.
