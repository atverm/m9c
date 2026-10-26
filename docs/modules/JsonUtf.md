# JsonUtf

Json over UTF text (docs/utf8-plan.md, stage 2; Alex, 2026-10-23:
"create the modules and test them, add UTF to the module name, swap
the names when STR becomes UTF").  The same tree, the same API and
the same contracts as Json -- read Json's comments for each procedure
-- with every piece of text a UTF: the document parsed, the payloads
and member names it keeps (views of the document, as Json's are), the
texts answered and the renderings produced.  A document is held at
its UTF-8 size, where Json's STR tree holds four octets a character.

What differs, and why:
  - positions in a ParseError are lines and columns of CHARACTERS, as
    Json's are; the scanner steps one code point at a time over byte
    offsets (Text.NextCp);
  - escape decoding and the renderings are built through STR and
    converted once at the end: transient text, where the tree is what
    lives on, and the switch at stage 3 makes the detour go away;
  - AppendJString and AppendF64 append to a DynStr, which is STR, so
    their text argument is converted;
  - the exceptions' messages stay STR: they are ASCII, and a RAISE's
    string payload is copied as a STR.

At the end of the transition this module becomes Json, and Json
goes.

### TYPE Node

opaque; lives in a POOL

### TYPE Value

_(undocumented)_

### EXCEPTION ParseError

_(undocumented)_

### EXCEPTION TypeMismatch

_(undocumented)_

### Parse (RO src: UTF) : PTR Node RAISES ParseError

_(undocumented)_

### ParseIn (VAR pool: POOL ; RO src: UTF) : PTR Node IN pool RAISES ParseError

_(undocumented)_

### Field (obj: PTR Node ; RO name: UTF) : OPT PTR Node

_(undocumented)_

### Item (arr: PTR Node ; i: I64) : PTR Node RAISES TypeMismatch, IndexError

_(undocumented)_

### Count (arr: PTR Node) : I64 RAISES TypeMismatch

_(undocumented)_

### MemberCount (obj: PTR Node) : I64 RAISES TypeMismatch

_(undocumented)_

### NameAt (obj: PTR Node ; i: I64) : UTF RAISES TypeMismatch, IndexError

_(undocumented)_

### MemberAt (obj: PTR Node ; i: I64) : PTR Node RAISES TypeMismatch, IndexError

_(undocumented)_

### AsI64 (n: PTR Node) : I64 RAISES TypeMismatch, ValueRange

_(undocumented)_

### AsF64 (n: PTR Node) : F64 RAISES TypeMismatch

_(undocumented)_

### AsBool (n: PTR Node) : BOOL RAISES TypeMismatch

_(undocumented)_

### AsStr (n: PTR Node) : UTF RAISES TypeMismatch

_(undocumented)_

### Text (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange

_(undocumented)_

### StrIs (n: PTR Node ; RO s: UTF) : BOOL

_(undocumented)_

### IsNull (n: PTR Node) : BOOL

_(undocumented)_

### Compact (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange

_(undocumented)_

### Spaced (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange

_(undocumented)_

### CompactSorted (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange, IndexError

_(undocumented)_

### Pretty (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange

_(undocumented)_

### ReprText (r: F64) : UTF RAISES ValueRange

_(undocumented)_

### NumText (n: PTR Node) : UTF RAISES TypeMismatch, ValueRange

_(undocumented)_

### AppendF64 (VAR d: PTR DynStr.DString ; r: F64) RAISES ValueRange

_(undocumented)_

### AppendJString (VAR d: PTR DynStr.DString ; RO t: UTF) RAISES ValueRange

_(undocumented)_

### NewObj () : PTR Node

_(undocumented)_

### NewArr () : PTR Node

_(undocumented)_

### NewStr (RO s: UTF) : PTR Node RAISES ValueRange

_(undocumented)_

### NewI64 (v: I64) : PTR Node

_(undocumented)_

### NewF64 (r: F64) : PTR Node

_(undocumented)_

### NewBool (b: BOOL) : PTR Node

_(undocumented)_

### NewNull () : PTR Node

_(undocumented)_

### NewRaw (RO text: UTF) : PTR Node RAISES ParseError, TypeMismatch

_(undocumented)_

### NewObjIn (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### NewArrIn (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### NewStrIn (VAR pool: POOL ; RO s: UTF) : PTR Node IN pool RAISES ValueRange

_(undocumented)_

### NewI64In (VAR pool: POOL ; v: I64) : PTR Node IN pool

_(undocumented)_

### NewF64In (VAR pool: POOL ; r: F64) : PTR Node IN pool

_(undocumented)_

### NewRawIn (VAR pool: POOL ; RO text: UTF) : PTR Node IN pool RAISES ParseError, TypeMismatch

_(undocumented)_

### NewBoolIn (VAR pool: POOL ; b: BOOL) : PTR Node IN pool

_(undocumented)_

### NewNullIn (VAR pool: POOL) : PTR Node IN pool

_(undocumented)_

### Name (RO s: UTF) : UTF RAISES ValueRange

_(undocumented)_

### Set (VAR KEPT obj: PTR Node ; RO KEPT name: UTF ; VAR KEPT v: PTR Node) RAISES TypeMismatch

_(undocumented)_

### Add (VAR arr: PTR Node ; VAR KEPT v: PTR Node) RAISES TypeMismatch

_(undocumented)_

### CloneIn (VAR pool: POOL ; n: PTR Node) : PTR Node IN pool RAISES TypeMismatch

_(undocumented)_

### Clone (n: PTR Node) : PTR Node RAISES TypeMismatch

_(undocumented)_

the float printer and reader Json binds (cjrepr), bound again here so
that JsonUtf stands alone

### ReprF64 (v: C.Double ; buf: C.MutPtr) : C.SSizeT [REENTRANT]

_(undocumented)_

### StrToD (s: C.ConstPtr) : C.Double [REENTRANT]

_(undocumented)_
