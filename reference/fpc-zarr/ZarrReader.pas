unit ZarrReader;

{ Native Object Pascal reader for zarr v2 stores (read-only).
  No Python. Dependencies: FPC's own fpjson + fphttpclient, and libblosc
  for blosc-compressed chunks (the zarr-python default).

  Supports: consolidated (.zmetadata) and per-array (.zarray) metadata,
  local directory stores and HTTP(S) stores, C-order arrays,
  little-endian f4/f8/i1..i8/u1..u8 dtypes, blosc / zlib / raw chunks,
  missing chunks -> fill_value, "." or "/" dimension separators.

  Not supported (raise clear errors): zarr v3, F-order, big-endian,
  filters, object/string dtypes, writing. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser, fphttpclient;

type
  TZarrCompressor = (zcNone, zcBlosc, zcZlib);

  TZarrArrayMeta = record
    Shape:  array of Int64;
    Chunks: array of Int64;
    DtypeKind: Char;         // 'f' float, 'i' signed int, 'u' unsigned
    ItemSize:  Integer;      // bytes per element
    OrderC:    Boolean;
    FillValue: Double;       // for floats (NaN-capable)
    FillValueI: Int64;       // for integer dtypes, validated at open
    Compressor: TZarrCompressor;
    DimSep:    Char;         // '.' (default) or '/'
  end;

  TZarrStore = class;

  { One array within the store hierarchy. }
  TZarrArray = class
  private
    FStore: TZarrStore;
    FPath:  string;                    // e.g. 'co2' or 'group/sub'
    FMeta:  TZarrArrayMeta;
    // single-chunk cache: ideal for sequential scans, replace with a
    // hash map keyed by chunk key if you need random-access locality
    FCache: array of record        // small LRU of decompressed chunks
      CC: array of Int64;
      Buf: TBytes;
      Stamp: QWord;
    end;
    FCacheUsed: Integer;
    FLastHit: Integer;             // fast path: most chunks hit repeatedly
    FStamp: QWord;
    FCC, FInC: array of Int64;     // per-call scratch, allocated once
    function ChunkByteSize: Int64;
    function ChunkKey(const ChunkCoords: array of Int64): string;
    function Decompress(const Raw: TBytes): TBytes;
    function GetChunk(const ChunkCoords: array of Int64): TBytes;
    function ElementOffset(const Idx: array of Int64;
                           out Buf: TBytes): Int64;
    function CheckedOffset(const Idx: array of Int64;
                           out Buf: TBytes): Int64;
  public
    property Meta: TZarrArrayMeta read FMeta;
    property Path: string read FPath;
    { Element access; Idx has one entry per dimension. }
    function GetDouble(const Idx: array of Int64): Double;
    function GetInt(const Idx: array of Int64): Int64;
    { Raw decompressed chunk, length = prod(chunks)*itemsize.
      Edge chunks are full-size (zarr pads them). Zero-copy friendly:
      point a PDouble at @Result[0] and iterate natively. }
    function ReadChunk(const ChunkCoords: array of Int64): TBytes;
  end;

  { A zarr v2 store rooted at a local directory or an http(s) URL. }
  TZarrStore = class
  private
    FBase: string;
    FIsHttp: Boolean;
    FHttp: TFPHTTPClient;
    FMetaRoot: TJSONData;              // parsed .zmetadata document, or nil
    FConsolidated: TJSONObject;        // its "metadata" object, or nil
    function FetchRaw(const RelPath: string; out Data: TBytes): Boolean;
    function FetchJSON(const RelPath: string): TJSONObject;
    function MetaJSON(const RelPath: string): TJSONObject;
  public
    constructor Create(const BaseURLOrDir: string);
    destructor Destroy; override;
    function OpenArray(const ArrayPath: string): TZarrArray;
    function ArrayAttrs(const ArrayPath: string): TJSONObject; // may be nil
  end;

  EZarr = class(Exception);

implementation

uses
  ZStream; // zlib codec via FPC's paszlib

{ ---- libblosc: one function is all we need ---- }
function blosc_decompress(src, dest: Pointer;
  destsize: PtrUInt): LongInt; cdecl; external 'blosc';

{ ================= TZarrStore ================= }

constructor TZarrStore.Create(const BaseURLOrDir: string);
var
  Raw: TBytes;
begin
  FBase := ExcludeTrailingPathDelimiter(BaseURLOrDir);
  if (FBase <> '') and (FBase[Length(FBase)] = '/') then
    SetLength(FBase, Length(FBase) - 1);
  FIsHttp := (Pos('http://', LowerCase(FBase)) = 1) or
             (Pos('https://', LowerCase(FBase)) = 1);
  if FIsHttp then
  begin
    FHttp := TFPHTTPClient.Create(nil);
    FHttp.AllowRedirect := True;
    FHttp.AddHeader('User-Agent', 'ZarrReader-FPC/0.1');
  end;
  // consolidated metadata: one fetch describes the whole hierarchy
  if FetchRaw('.zmetadata', Raw) then
  begin
    FMetaRoot := GetJSON(TEncoding.UTF8.GetString(Raw));
    FConsolidated := TJSONObject(FMetaRoot.FindPath('metadata'));
  end;
end;

destructor TZarrStore.Destroy;
begin
  FHttp.Free;
  FMetaRoot.Free;   // owns FConsolidated
  inherited;
end;

function TZarrStore.FetchRaw(const RelPath: string; out Data: TBytes): Boolean;
var
  MS: TMemoryStream;
  FN: string;
  FS: TFileStream;
begin
  Result := False;
  Data := nil;
  if FIsHttp then
  begin
    MS := TMemoryStream.Create;
    try
      try
        FHttp.SimpleGet(FBase + '/' + RelPath, MS);
      except
        on E: EHTTPClient do Exit(False);   // 404 => missing (legit in zarr)
      end;
      if FHttp.ResponseStatusCode <> 200 then Exit(False);
      SetLength(Data, MS.Size);
      if MS.Size > 0 then Move(MS.Memory^, Data[0], MS.Size);
      Result := True;
    finally
      MS.Free;
    end;
  end
  else
  begin
    FN := FBase + DirectorySeparator +
          StringReplace(RelPath, '/', DirectorySeparator, [rfReplaceAll]);
    if not FileExists(FN) then Exit(False);
    FS := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Data, FS.Size);
      if FS.Size > 0 then FS.ReadBuffer(Data[0], FS.Size);
      Result := True;
    finally
      FS.Free;
    end;
  end;
end;

function TZarrStore.FetchJSON(const RelPath: string): TJSONObject;
var
  Raw: TBytes;
begin
  if not FetchRaw(RelPath, Raw) then Exit(nil);
  Result := TJSONObject(GetJSON(TEncoding.UTF8.GetString(Raw)));
end;

function TZarrStore.MetaJSON(const RelPath: string): TJSONObject;
begin
  // consolidated first (keys inside .zmetadata use '/' separators),
  // fall back to fetching the individual file
  Result := nil;
  if FConsolidated <> nil then
    Result := TJSONObject(FConsolidated.FindPath(RelPath));
  if Result = nil then
    Result := FetchJSON(RelPath);
end;

function ParseFillValue(V: TJSONData; out IsNull: Boolean): Double;
begin
  IsNull := (V = nil) or V.IsNull;
  if IsNull then Exit(Double.NaN);
  case V.JSONType of
    jtNumber: Result := V.AsFloat;
    jtString:
      case LowerCase(V.AsString) of
        'nan':               Result := Double.NaN;
        'infinity', 'inf':   Result := Double.PositiveInfinity;
        '-infinity', '-inf': Result := Double.NegativeInfinity;
      else
        raise EZarr.CreateFmt('Unsupported fill_value "%s"', [V.AsString]);
      end;
  else
    raise EZarr.Create('Unsupported fill_value type');
  end;
end;

function TZarrStore.OpenArray(const ArrayPath: string): TZarrArray;
var
  J, C: TJSONObject;
  A: TJSONArray;
  M: TZarrArrayMeta;
  Dt, CName: string;
  i: Integer;
  FillIsNull: Boolean;
begin
  J := MetaJSON(ArrayPath + '/.zarray');
  if J = nil then
    raise EZarr.CreateFmt('Array "%s" not found (no .zarray)', [ArrayPath]);

  if J.Get('zarr_format', 2) <> 2 then
    raise EZarr.Create('Only zarr v2 supported (v3 has zarr.json metadata)');

  A := J.Arrays['shape'];
  SetLength(M.Shape, A.Count);
  for i := 0 to A.Count - 1 do M.Shape[i] := A.Int64s[i];

  A := J.Arrays['chunks'];
  SetLength(M.Chunks, A.Count);
  for i := 0 to A.Count - 1 do M.Chunks[i] := A.Int64s[i];

  if Length(M.Shape) <> Length(M.Chunks) then
    raise EZarr.Create('shape/chunks rank mismatch');

  Dt := J.Get('dtype', '');                  // e.g. "<f8", "|i1"
  if Length(Dt) < 3 then
    raise EZarr.CreateFmt('Bad dtype "%s"', [Dt]);
  if not (Dt[1] in ['<', '|']) then
    raise EZarr.CreateFmt('Big-endian dtype "%s" not supported', [Dt]);
  M.DtypeKind := Dt[2];
  if not (M.DtypeKind in ['f', 'i', 'u']) then
    raise EZarr.CreateFmt('Dtype kind "%s" not supported (numeric only)',
      [M.DtypeKind]);
  M.ItemSize := StrToInt(Copy(Dt, 3, MaxInt));
  if not (M.ItemSize in [1, 2, 4, 8]) then
    raise EZarr.CreateFmt('Item size %d not supported', [M.ItemSize]);
  if (M.DtypeKind = 'f') and not (M.ItemSize in [4, 8]) then
    raise EZarr.Create('Only f4/f8 floats supported');

  M.OrderC := J.Get('order', 'C') = 'C';
  if not M.OrderC then
    raise EZarr.Create('F-order arrays not supported');

  if J.FindPath('filters') <> nil then
    if not J.FindPath('filters').IsNull then
      raise EZarr.Create('Filter pipelines not supported');

  M.FillValue := ParseFillValue(J.FindPath('fill_value'), FillIsNull);
  M.FillValueI := 0;
  if M.DtypeKind in ['i', 'u'] then
  begin
    if FillIsNull then
      M.FillValueI := 0
    else if IsNan(M.FillValue) or IsInfinite(M.FillValue) or
            (Frac(M.FillValue) <> 0) then
      raise EZarr.Create('Non-integer fill_value on integer dtype')
    else
      M.FillValueI := Trunc(M.FillValue);
  end;

  if (J.FindPath('compressor') = nil) or J.FindPath('compressor').IsNull then
    M.Compressor := zcNone
  else
  begin
    C := J.Objects['compressor'];
    CName := C.Get('id', '');
    case CName of
      'blosc': M.Compressor := zcBlosc;
      'zlib':  M.Compressor := zcZlib;
    else
      raise EZarr.CreateFmt('Compressor "%s" not supported ' +
        '(blosc, zlib, none)', [CName]);
    end;
  end;

  M.DimSep := '.';
  if J.Get('dimension_separator', '.') = '/' then M.DimSep := '/';

  Result := TZarrArray.Create;
  Result.FStore := Self;
  Result.FPath := ArrayPath;
  Result.FMeta := M;
  SetLength(Result.FCC, Length(M.Shape));
  SetLength(Result.FInC, Length(M.Shape));
  // capacity: one row of chunks along the fastest-varying dim, min 4 --
  // makes plain row-major element scans decompress each chunk exactly once
  i := 4;
  if Length(M.Shape) >= 1 then
    i := Max(4, Integer((M.Shape[High(M.Shape)] +
         M.Chunks[High(M.Chunks)] - 1) div M.Chunks[High(M.Chunks)]));
  SetLength(Result.FCache, Min(i, 64));   // cap memory: 64 chunks max
  Result.FCacheUsed := 0;
  Result.FLastHit := -1;
end;

function TZarrStore.ArrayAttrs(const ArrayPath: string): TJSONObject;
begin
  Result := MetaJSON(ArrayPath + '/.zattrs');
end;

{ ================= TZarrArray ================= }

function TZarrArray.ChunkByteSize: Int64;
var
  d: Integer;
begin
  Result := FMeta.ItemSize;
  for d := 0 to High(FMeta.Chunks) do
    Result := Result * FMeta.Chunks[d];
end;

function TZarrArray.ChunkKey(const ChunkCoords: array of Int64): string;
var
  d: Integer;
begin
  Result := '';
  for d := 0 to High(ChunkCoords) do
  begin
    if d > 0 then Result := Result + FMeta.DimSep;
    Result := Result + IntToStr(ChunkCoords[d]);
  end;
end;

function TZarrArray.Decompress(const Raw: TBytes): TBytes;
var
  n: LongInt;
  DS: TDecompressionStream;
  SS: TBytesStream;
begin
  SetLength(Result, ChunkByteSize);
  case FMeta.Compressor of
    zcNone:
      begin
        if Length(Raw) <> Length(Result) then
          raise EZarr.Create('Raw chunk size mismatch');
        Move(Raw[0], Result[0], Length(Raw));
      end;
    zcBlosc:
      begin
        n := blosc_decompress(@Raw[0], @Result[0], Length(Result));
        if n < 0 then
          raise EZarr.CreateFmt('blosc_decompress error %d', [n]);
        if n <> Length(Result) then
          raise EZarr.Create('blosc: unexpected decompressed size');
      end;
    zcZlib:
      begin
        SS := TBytesStream.Create(Raw);
        try
          DS := TDecompressionStream.Create(SS); // zlib-wrapped deflate
          try
            DS.ReadBuffer(Result[0], Length(Result));
          finally
            DS.Free;
          end;
        finally
          SS.Free;
        end;
      end;
  end;
end;

function TZarrArray.GetChunk(const ChunkCoords: array of Int64): TBytes;
var
  Raw: TBytes;
  d: Int64;
  P: PDouble;
  PS: PSingle;
  i, NElems: Int64;
  Slot, e: Integer;

  function SameCC(const E: array of Int64): Boolean;
  var k: Integer;
  begin
    for k := 0 to High(E) do
      if E[k] <> ChunkCoords[k] then Exit(False);
    Result := True;
  end;

begin
  Inc(FStamp);
  // fast path: same chunk as last time (dominant in any local scan)
  if (FLastHit >= 0) and SameCC(FCache[FLastHit].CC) then
  begin
    FCache[FLastHit].Stamp := FStamp;
    Exit(FCache[FLastHit].Buf);
  end;
  // linear search of the small LRU
  for e := 0 to FCacheUsed - 1 do
    if SameCC(FCache[e].CC) then
    begin
      FCache[e].Stamp := FStamp;
      FLastHit := e;
      Exit(FCache[e].Buf);
    end;

  if FStore.FetchRaw(FPath + '/' + ChunkKey(ChunkCoords), Raw) then
    Result := Decompress(Raw)
  else
  begin
    // missing chunk is legitimate: means "entirely fill_value"
    SetLength(Result, ChunkByteSize);
    NElems := ChunkByteSize div FMeta.ItemSize;
    if (FMeta.DtypeKind = 'f') and (FMeta.ItemSize = 8) then
    begin
      P := PDouble(@Result[0]);
      for i := 0 to NElems - 1 do P[i] := FMeta.FillValue;
    end
    else if (FMeta.DtypeKind = 'f') and (FMeta.ItemSize = 4) then
    begin
      PS := PSingle(@Result[0]);
      for i := 0 to NElems - 1 do PS[i] := FMeta.FillValue;
    end
    else
    begin
      d := FMeta.FillValueI;                     // validated at OpenArray
      if d = 0 then
        FillChar(Result[0], Length(Result), 0)
      else
        for i := 0 to NElems - 1 do
          Move(d, Result[i * FMeta.ItemSize], FMeta.ItemSize); // LE only
    end;
  end;

  // insert into LRU: free slot if any, else evict oldest stamp
  if FCacheUsed < Length(FCache) then
  begin
    Slot := FCacheUsed;
    Inc(FCacheUsed);
    SetLength(FCache[Slot].CC, Length(ChunkCoords));
  end
  else
  begin
    Slot := 0;
    for e := 1 to FCacheUsed - 1 do
      if FCache[e].Stamp < FCache[Slot].Stamp then Slot := e;
  end;
  for e := 0 to High(ChunkCoords) do FCache[Slot].CC[e] := ChunkCoords[e];
  FCache[Slot].Buf := Result;
  FCache[Slot].Stamp := FStamp;
  FLastHit := Slot;
end;

function TZarrArray.ReadChunk(const ChunkCoords: array of Int64): TBytes;
begin
  Result := GetChunk(ChunkCoords);
end;

{ Locate element: which chunk, and byte offset inside it (C-order). }
function TZarrArray.ElementOffset(const Idx: array of Int64;
  out Buf: TBytes): Int64;
var
  d: Integer;
  Stride: Int64;
begin
  if Length(Idx) <> Length(FMeta.Shape) then
    raise EZarr.Create('Index rank mismatch');
  for d := 0 to High(Idx) do
  begin
    if (Idx[d] < 0) or (Idx[d] >= FMeta.Shape[d]) then
      raise EZarr.CreateFmt('Index %d out of bounds in dim %d', [Idx[d], d]);
    FCC[d]  := Idx[d] div FMeta.Chunks[d];
    FInC[d] := Idx[d] mod FMeta.Chunks[d];
  end;
  Buf := GetChunk(FCC);
  Result := 0;
  Stride := 1;
  for d := High(Idx) downto 0 do
  begin
    Result := Result + FInC[d] * Stride;
    Stride := Stride * FMeta.Chunks[d];
  end;
  Result := Result * FMeta.ItemSize;
end;

function TZarrArray.CheckedOffset(const Idx: array of Int64;
  out Buf: TBytes): Int64;
begin
  Result := ElementOffset(Idx, Buf);
  if (Result < 0) or (Result + FMeta.ItemSize > Length(Buf)) then
    raise EZarr.CreateFmt('Internal error: offset %d outside chunk buffer ' +
      'of %d bytes', [Result, Length(Buf)]);
end;

function TZarrArray.GetDouble(const Idx: array of Int64): Double;
var
  Buf: TBytes;
  Ofs: Int64;
begin
  Ofs := CheckedOffset(Idx, Buf);
  case FMeta.DtypeKind of
    'f': case FMeta.ItemSize of
           4: Result := PSingle(@Buf[Ofs])^;
           8: Result := PDouble(@Buf[Ofs])^;
         else
           raise EZarr.Create('Internal error: bad float item size');
         end;
    'i': case FMeta.ItemSize of
           1: Result := PShortInt(@Buf[Ofs])^;
           2: Result := PSmallInt(@Buf[Ofs])^;
           4: Result := PLongInt(@Buf[Ofs])^;
           8: Result := PInt64(@Buf[Ofs])^;    // note: |v| > 2^53 loses
         else                                  // precision in Double
           raise EZarr.Create('Internal error: bad int item size');
         end;
    'u': case FMeta.ItemSize of
           1: Result := PByte(@Buf[Ofs])^;
           2: Result := PWord(@Buf[Ofs])^;
           4: Result := PLongWord(@Buf[Ofs])^;
           8: Result := PQWord(@Buf[Ofs])^;    // QWord->Double is correct,
         else                                  // same 2^53 caveat
           raise EZarr.Create('Internal error: bad uint item size');
         end;
  else
    raise EZarr.Create('Internal error: bad dtype kind');
  end;
end;

function TZarrArray.GetInt(const Idx: array of Int64): Int64;
var
  Buf: TBytes;
  Ofs: Int64;
  U: QWord;
  D: Double;
begin
  Ofs := CheckedOffset(Idx, Buf);
  case FMeta.DtypeKind of
    'i': case FMeta.ItemSize of
           1: Result := PShortInt(@Buf[Ofs])^;
           2: Result := PSmallInt(@Buf[Ofs])^;
           4: Result := PLongInt(@Buf[Ofs])^;
           8: Result := PInt64(@Buf[Ofs])^;
         else
           raise EZarr.Create('Internal error: bad int item size');
         end;
    'u': case FMeta.ItemSize of
           1: Result := PByte(@Buf[Ofs])^;
           2: Result := PWord(@Buf[Ofs])^;
           4: Result := PLongWord(@Buf[Ofs])^;
           8: begin
                U := PQWord(@Buf[Ofs])^;
                if U > QWord(High(Int64)) then
                  raise EZarr.CreateFmt('uint64 value %s does not fit in ' +
                    'Int64; read it via GetDouble or ReadChunk',
                    [UIntToStr(U)]);
                Result := Int64(U);
              end;
         else
           raise EZarr.Create('Internal error: bad uint item size');
         end;
    'f': begin
           case FMeta.ItemSize of
             4: D := PSingle(@Buf[Ofs])^;
             8: D := PDouble(@Buf[Ofs])^;
           else
             raise EZarr.Create('Internal error: bad float item size');
           end;
           if IsNan(D) or IsInfinite(D) then
             raise EZarr.CreateFmt('Cannot convert non-finite value (%s) ' +
               'to integer', [FloatToStr(D)]);
           if (D >= 9.2233720368547758E18) or (D <= -9.2233720368547758E18) then
             raise EZarr.CreateFmt('Float value %g out of Int64 range', [D]);
           Result := Trunc(D);
         end;
  else
    raise EZarr.Create('Internal error: bad dtype kind');
  end;
end;

end.
