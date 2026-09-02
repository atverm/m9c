# Ast

M9 abstract syntax, in M9 -- restated from host/fpc/M9AST.pas for
the P5 self-hosted parser.  One homogeneous node: kind codes
mirror the FPC TNodeKind order (0 File .. 80 ArgList); fixed child
slots may be NONE and print as absence; a and b carry ident and
literal text verbatim.  Nodes and their kid vectors live in the
caller's pool: free the pool, free the tree -- the Json story.

### CONST NFile

_(documented with the group below)_

### CONST NDefinition

_(documented with the group below)_

### CONST NImplementation

_(documented with the group below)_

### CONST NProgram

_(documented with the group below)_

### CONST NModBody

_(documented with the group below)_

### CONST NFromImport

_(documented with the group below)_

### CONST NImportList

_(documented with the group below)_

### CONST NConstSection

_(documented with the group below)_

### CONST NTypeSection

_(documented with the group below)_

### CONST NVarSection

_(documented with the group below)_

### CONST NExcSection

_(documented with the group below)_

### CONST NConstDecl

_(documented with the group below)_

### CONST NTypeDecl

_(documented with the group below)_

### CONST NVarDecl

_(documented with the group below)_

### CONST NExcDecl

_(documented with the group below)_

### CONST NProcDecl

_(documented with the group below)_

### CONST NParamList

_(documented with the group below)_

### CONST NParam

_(documented with the group below)_

### CONST NRaises

_(documented with the group below)_

### CONST NAttrib

_(documented with the group below)_

### CONST NProcBody

_(documented with the group below)_

### CONST NBlock

_(documented with the group below)_

### CONST NHandler

_(documented with the group below)_

### CONST NFinally

_(documented with the group below)_

### CONST NIdentList

_(documented with the group below)_

### CONST NIdent

_(documented with the group below)_

### CONST NQualident

_(documented with the group below)_

### CONST NArrayType

_(documented with the group below)_

### CONST NSliceType

_(documented with the group below)_

### CONST NRecordType

_(documented with the group below)_

### CONST NCaseRecordType

_(documented with the group below)_

### CONST NVariant

_(documented with the group below)_

### CONST NMonitorType

_(documented with the group below)_

### CONST NFieldSeq

_(documented with the group below)_

### CONST NFieldGroup

_(documented with the group below)_

### CONST NPtrType

_(documented with the group below)_

### CONST NOptType

_(documented with the group below)_

### CONST NSharedType

_(documented with the group below)_

### CONST NStmtSeq

_(documented with the group below)_

### CONST NAssign

_(documented with the group below)_

### CONST NCallStmt

_(documented with the group below)_

### CONST NIf

_(documented with the group below)_

### CONST NElsif

_(documented with the group below)_

### CONST NWhile

_(documented with the group below)_

### CONST NElse

_(documented with the group below)_

### CONST NFor

_(documented with the group below)_

### CONST NLoop

_(documented with the group below)_

### CONST NExit

_(documented with the group below)_

### CONST NCase

_(documented with the group below)_

### CONST NCaseArm

_(documented with the group below)_

### CONST NLabelList

_(documented with the group below)_

### CONST NLabelRange

_(documented with the group below)_

### CONST NLabelPattern

_(documented with the group below)_

### CONST NReturn

_(documented with the group below)_

### CONST NRaiseStmt

_(documented with the group below)_

### CONST NDispose

_(documented with the group below)_

### CONST NThread

_(documented with the group below)_

### CONST NTransfer

_(documented with the group below)_

### CONST NWait

_(documented with the group below)_

### CONST NSignal

_(documented with the group below)_

### CONST NBin

_(documented with the group below)_

### CONST NUn

_(documented with the group below)_

### CONST NIs

_(documented with the group below)_

### CONST NIsSome

_(documented with the group below)_

### CONST NParen

_(documented with the group below)_

### CONST NInt

_(documented with the group below)_

### CONST NReal

_(documented with the group below)_

### CONST NChar

_(documented with the group below)_

### CONST NString

_(documented with the group below)_

### CONST NTrue

_(documented with the group below)_

### CONST NFalse

_(documented with the group below)_

### CONST NNoneLit

_(documented with the group below)_

### CONST NSomeExpr

_(documented with the group below)_

### CONST NSharedExpr

_(documented with the group below)_

### CONST NNewExpr

_(documented with the group below)_

### CONST NSliceOf3

_(documented with the group below)_

### CONST NCallExpr

_(documented with the group below)_

### CONST NDesignator

_(documented with the group below)_

### CONST NSelField

_(documented with the group below)_

### CONST NSelIndex

_(documented with the group below)_

### CONST NArgList

Appended, not inserted.  The FPC enum grew nkGridType next to
nkArrayType, but a code that MOVES is a code no one can rely on
-- the rule Lex already states for keywords -- and nothing
compares these numbers across the two implementations:
parsediff compares printed text and gendiff compares emitted C.

### CONST NGridType

_(undocumented)_

### TYPE Kid

named so NEW can say it;
Node resolves lazily below

### TYPE Node

f3: the RO mode on a binding;
f4: KEPT, which composes with any
of the modes rather than replacing
one -- a kept parameter is usually
also RO

### NewNode (VAR pool: POOL ; kind, line, col: I64) : PTR Node IN pool

a node with no children and empty a/b, ready for Add.

kind      -- one of the N* constants above.  They are
             EXPORTED CONSTS with fixed values, not an
             enumeration, because both generators and both
             checkers agree on them by number: a code that
             moves is a code nobody can rely on, which is why
             NGridType was appended at 81 rather than
             inserted where it belonged alphabetically.
line, col -- where the construct STARTS.  There is no end
             position on a node, which is worth knowing
             before writing anything that wants to know how
             far a declaration reached.

### Add (VAR pool: POOL ; VAR n: PTR Node ; KEPT kid: Kid)

NONE is a legal child: absence with a position
