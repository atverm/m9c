# Zarr

WRITING a zarr v2 store: groups, attributes, chunked arrays and the
consolidated index.

The corpus could already READ one -- ZarrStore over HTTP, and the
zarr proxy's own Zread over local files -- and nothing anywhere could
write one.  That was the single prerequisite standing between the
ICOS store builders (about 10,000 lines of Python) and one M9
program, so the subset here is chosen to be exactly what Zread
ACCEPTS, no wider: a store this module writes is a store that module
opens, and the two are gated against each other.

The subset, and everything outside it is refused BY NAME:
  * zarr v2 only.  v3 keeps its metadata in zarr.json and no
    deployed ICOS client opens it.
  * C order, rank 0..5, little-endian, and the '.' chunk-key
    separator -- which every ICOS store already uses, whether it
    spells the default out or leaves it out.
  * dtypes  <f4 <f8  <i8 <i4 <i2  |i1  |u1  <u2  |b1  <M8[ns],
    and the THREE string forms  |S<n>,  <U<n>  and
    |O + vlen-utf8.  Single-byte
    types take '|' because they have no byte order; the rest '<'.
  * blosc with the shuffle filter -- lz4 or zstd -- or no
    compressor at all.

FILL VALUES ARE NOT A PARAMETER on the plain writers, and that is
deliberate.  A float array gets NaN and an integer array gets null,
because a zarr fill_value of 0 on an integer column makes xarray
mask real zeros, and a fill_value of 0.0 on a coordinate once put
1.3 million phantom positions on Null Island in a live ICOS store.
The rule is in the code so it cannot be forgotten at a call site.

THE `Fill` TWINS ARE THE ONE EXCEPTION, and it is a different JOB
rather than a weaker rule.  The writers above INVENT an array, and
for an invented array a fill nobody chose is the right answer.  A
builder TRANSCRIBING a CF variable is not inventing: the netCDF
file already declares `_FillValue`, xarray carries it into the
zarr `fill_value`, and a reader masks on it -- so an ICOS ObsPack
`nvalue`'s -9 and `icos_datalevel`'s 127 MUST be written, or the
store says those observations are real.  The twins take the fill
the SOURCE declares, and they are spelled differently so a call
site inventing an array cannot reach one by accident.

### EXCEPTION Error

_(undocumented)_

### CONST NoCompress

the chunk is stored raw

### Lz4 (clevel: I64) : I64 RAISES Error, ValueRange

clevel 1..9

### Zstd (clevel: I64) : I64 RAISES Error, ValueRange

clevel 1..9

### CreateGroup (VAR pool: POOL ; RO dir: STR) RAISES Error, ValueRange

dir and every parent, then its .zgroup.  Exist-ok: a builder
re-running over a half-written store must not fail here.

### WriteAttrs (VAR pool: POOL ; RO dir: STR ; RO json: STR) RAISES Error, ValueRange

dir/.zattrs, the document written VERBATIM.  The caller owns the
JSON -- this module does not compose it, because the attributes a
store needs are the domain's business and not the format's.

### WriteF32 (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF F32 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

adir/.zarray plus every chunk file.  `data` is C-order and must be
the product of `shape`; `dims` names the axes for
_ARRAY_DIMENSIONS and may be empty.  comp 0 stores raw.

### WriteF64 (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF F64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

_(undocumented)_

### WriteInt (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF I64 ; width: I64 ; signed: BOOL ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

width 1, 2, 4 or 8 bytes.  `signed` FALSE is offered at widths 1
and 2 -- |u1 and <u2, the only unsigned dtypes the ICOS stores
carry: the flag columns and NOAA ObsPack's obspack_id_src, which
indexes a short list of source-dataset prefixes.

### WriteTimeNs (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF I64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

<M8[ns]: epoch NANOSECONDS, the only datetime64 unit Zread reads.

### WriteBool (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF BOOL ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

|b1: one octet per value, 0 or 1, fill_value null.  numpy's own
bool_ dtype, and the ICOS ocean store's `fixed` column -- a
per-cruise flag saying whether the platform is a buoy or a ship
-- is written by numpy exactly this way.  It is a dtype of its
own rather than |u1 because numpy reads |u1 back as an integer
and a caller comparing `fixed == True` would then get an array
of numbers.

### GuessChunks (VAR pool: POOL ; RO shape: SLICE OF I64 ; typesize: I64) : SLICE OF I64 RAISES Error, ValueRange

ZARR'S OWN `guess_chunks`, transcribed: halve along successive
axes until a chunk is near a target that itself scales with the
array's size.  It is here rather than in a builder because it is
the FORMAT's rule and not a domain one -- xarray passes an
encoding for a data variable and none for a coordinate, so any
array written without one gets this, and two builders in this
family already need it.

Worth transcribing rather than approximating: 500 of the NOAA
ObsPack store's 971 time axes are neither the whole array nor
the 50,000 its data columns take.

### WriteIntFill (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF I64 ; width: I64 ; signed: BOOL ; hasFill: BOOL ; fill: I64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

WriteInt, with the fill the SOURCE declares: `hasFill` FALSE
writes `null` exactly as WriteInt does, and TRUE writes the
value -- which must fit the width, and is refused by name when
it does not.  An ABSENT chunk then reads back as that fill,
which is the whole point of writing it.

### WriteF32Fill (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF F32 ; hasFill: BOOL ; fill: F64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

WriteF32, with a declared fill.  `hasFill` FALSE is NaN, which is
what WriteF32 writes, so the two agree where they overlap.

### WriteF64Fill (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF F64 ; hasFill: BOOL ; fill: F64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

the same for `<f8`.

### WriteStrFixedFill (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF STR ; width: I64 ; hasFill: BOOL ; RO fill: STR ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

WriteStrFixed, with a declared fill.  zarr spells a `|S` fill as
the BASE64 of its padded octets -- which is what zarr-python
writes and a reader decodes -- and this writes that spelling;
`hasFill` FALSE writes `null`.

### WriteStrFixed (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF STR ; width: I64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

|S<width>: every element UTF-8 encoded into exactly `width`
octets and NUL-padded on the right, chunked like any other
fixed-width array.  A string whose encoding does not FIT is
refused BY NAME rather than truncated -- a shortened expocode is
a different cruise, not a shorter one, and numpy's own
assignment would have cut it silently.

PREFER THIS FORM, and the reason is measured on a live store:
one station's string QC series read back in 0.17 s as |S where
the vlen form took 3.3 s.  A fixed width is a stride; a vlen
table is a decode of the whole chunk to reach any of it.

BUT |S CARRIES OCTETS, NOT TEXT, and the two readers disagree
about what that means -- measured, not deduced.  The six
scalars B a r U+00E1 t h go in as the SEVEN octets
42 61 72 C3 A1 74 68.  numpy hands those octets back and a
caller who decodes UTF-8 recovers the six scalars; Zread turns
each octet into one scalar and answers SEVEN, the C3 arriving
as a character of its own.  That is the dtype's own property --
numpy will not build |S from a non-ASCII str at all -- so use
this form for what the live stores use it for (expocodes, flag
letters, ids) and reach for WriteStrVlen for anything that can
carry an accent.

### WriteOctets (VAR pool: POOL ; RO adir: STR ; RO raw: SLICE OF BYTE ; width: I64 ; hasFill: BOOL ; RO fill: STR ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

|S<width> straight from the OCTETS, already padded: LEN (raw)
must be the product of `shape` times `width`.

It exists because a TRANSCRIBED string column already has its
bytes.  WriteStrFixed takes a STR per element and re-encodes
each, which for one ICOS ObsPack station's 85,344 obspack_ids at
200 octets is 68 MB of CHARs to produce 17 MB of array -- and
the CHARs were made by decoding the very octets being rebuilt.

### WriteStrUcs4 (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF STR ; width: I64 ; RO shape: SLICE OF I64 ; RO chunks: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

`<U<width>`: numpy's OWN fixed-width string -- `width` UCS-4 code
points little-endian, NUL-padded, `fill_value` null.

THE THIRD STRING FORM, AND IT IS NOT A DUPLICATE OF THE OTHER
TWO.  `|S` carries OCTETS and numpy will not build one from a
non-ASCII `str` at all; `|O` carries UTF-8 behind a filter and
cannot be chunked.  `<U` is what xarray writes for a small
LABELLED COORDINATE -- the ICOS ecosystem store's
`nee_variant`, `ustar_threshold`, `partition_method`,
`corr_pct` and the 0-d `temporal_resolution` are all `<U` -- and
it is the only one of the three that is both chunkable and able
to hold a scalar past U+00FF.

Four bytes per code point whatever the text, so it is for SHORT
labels and the module says so: a `<U200` identity column would
be four times the `|S200` the same data fits in.  A value longer
than `width` is REFUSED, not truncated, for the reason
WriteStrFixed gives.

### WriteStrVlen (VAR pool: POOL ; RO adir: STR ; RO data: SLICE OF STR ; RO shape: SLICE OF I64 ; RO dims: SLICE OF STR ; comp: I64) RAISES Error, ValueRange

|O carrying the vlen-utf8 filter: a u32-LE item count, then per
item a u32-LE octet length and the UTF-8 octets.

THERE IS NO `chunks` PARAMETER because there is only one legal
grid: the whole shape in one chunk.  A vlen chunk declares its
own item count, and the readers this writes for check that count
against the SHAPE -- so a second chunk makes the store
unreadable rather than merely differently laid out.  That is no
narrowing in practice: this form carries identity lists (cruise
expocodes, station names, citations) and the live ICOS stores
hold them in a single chunk already.

### TYPE Sink

opaque; lives in a POOL

### SinkF32 (VAR pool: POOL ; RO KEPT adir: STR ; chunk: I64 ; RO KEPT dims: SLICE OF STR ; comp: I64) : PTR Sink IN pool RAISES Error, ValueRange

_(undocumented)_

### SinkF64 (VAR pool: POOL ; RO KEPT adir: STR ; chunk: I64 ; RO KEPT dims: SLICE OF STR ; comp: I64) : PTR Sink IN pool RAISES Error, ValueRange

_(undocumented)_

### SinkInt (VAR pool: POOL ; RO KEPT adir: STR ; width: I64 ; signed: BOOL ; chunk: I64 ; RO KEPT dims: SLICE OF STR ; comp: I64) : PTR Sink IN pool RAISES Error, ValueRange

_(undocumented)_

### SinkTimeNs (VAR pool: POOL ; RO KEPT adir: STR ; chunk: I64 ; RO KEPT dims: SLICE OF STR ; comp: I64) : PTR Sink IN pool RAISES Error, ValueRange

_(undocumented)_

### PutF32 (VAR s: PTR Sink ; v: F32) RAISES Error, ValueRange

_(documented with the group below)_

### PutF64 (VAR s: PTR Sink ; v: F64) RAISES Error, ValueRange

_(documented with the group below)_

### PutI64 (VAR s: PTR Sink ; v: I64) RAISES Error, ValueRange

the value goes in at the sink's own width, and a value that does
not fit is a CHECKED CONVERSION rather than a wrap -- an int8 QC
column handed 300 raises instead of storing 44.

### Rows (s: PTR Sink) : I64

_(documented with the group below)_

### Seal (VAR s: PTR Sink) RAISES Error, ValueRange

flush the partial chunk, then write .zarray and .zattrs.  A sink
is finished exactly once.

### Consolidate (VAR pool: POOL ; RO store: STR) RAISES Error, ValueRange

store/.zmetadata over the WHOLE tree: every .zgroup, .zattrs and
.zarray beneath it.  This is what `consolidated=True` opens, and
for a store of many small arrays it is the difference between one
request and tens of thousands.

IT REFUSES A SLIM STORE BY NAME, and that refusal is the point of
having two procedures rather than a flag: running this over a
shallow-root store is the foot-gun that re-bloated one ICOS root
from ~7 MB to ~1.2 GB and took the viewers down.  The marker in
the root .zattrs is what makes the refusal possible, which is why
ConsolidateSlim writes it.

### ConsolidateSlim (VAR pool: POOL ; RO store: STR) RAISES Error, ValueRange

the SHALLOW root: the store's own .zgroup and .zattrs, each
top-level entity's .zgroup and .zattrs, and the FULL subtree under
_combined -- and nothing else.

THIS IS NOT AN OPTIMISATION.  A full consolidate over a store with
hundreds of entities re-bloated one ICOS root from ~7 MB to
~1.2 GB and took the viewers down; the largest store on disk (82 GB
over 783 sites) is servable only because its root indexes 488
entries instead of hundreds of thousands.  THE MARKER IS WRITTEN
HERE, not left to the caller: this procedure puts
`"metadata_layout":"shallow-root"` into the root .zattrs before
indexing it, so a store is marked by the ACT of being
consolidated this way and cannot be left unmarked by a builder
that forgot.  Consolidate above keys its refusal off it.

`_`-prefixed top-level groups other than `_combined` are NOT
indexed at all, and a child without a .zgroup is skipped -- both
are the reference policy (icos_ingest.finalize), and both are
load-bearing rather than tidy: the whole point is that the root
stays small.

blosc's CONTEXT form only, as everywhere else in this tree: the
plain blosc_compress carries global state and would have to be
[SERIAL], which a THREAD root may not call.

### CompressCtx (comp: C.Int ; doshuffle: C.Int ; typesize: C.SizeT ; nbytes: C.SizeT ; src: C.ConstPtr ; dest: C.MutPtr ; destsize: C.SizeT ; compressor: C.ConstPtr ; blocksize: C.SizeT ; nthreads: C.Int) : C.Int [REENTRANT]

_(undocumented)_
