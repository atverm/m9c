# Rdf

RDF 1.1 graphs read from N-Triples and Turtle and written as
N-Triples (docs/datalib-plan.md par 2).  What Sparql.Construct
answers is read here.

READING follows the W3C grammars production by production: IRIs
resolved against a base by RFC 3986 par 5.2; prefixed names,
`a', blank-node property lists, collections, the numeric and
boolean short forms and all four string forms of Turtle; UCHAR and
ECHAR escapes; blank-node labels scoped to the document.  A
document that is not in the language is a SyntaxError naming the
line and column where it stops being one -- nothing is guessed,
and nothing is half-read: the graph is answered whole or not at
all.  Held to the W3C's own suites, every positive document read
and every negative one refused (RdfTest), and every evaluation
document's graph isomorphic to the W3C's expected one, judged by
rdflib (runtime/test/rdf.sh).

WRITING is N-Triples, one triple a line in the order read, blank
nodes labelled _:b0, _:b1 ... in the order they were first seen;
a literal's quote, backslash and control characters escaped, every
other character as itself (UTF-8 when written to a file).

Out: JSON-LD, TriG and named graphs, Turtle as an OUTPUT, and any
inference.  Language tags are kept as written.

### TYPE Kind

_(documented with the group below)_

### TYPE Term

the IRI, a blank node's label, a
literal's lexical form

### TYPE Triple

_(undocumented)_

### TYPE Graph

opaque; lives in a POOL

### EXCEPTION SyntaxError

_(undocumented)_

### CONST XsdString

_(documented with the group below)_

### ParseNTriples (VAR pool: POOL ; RO text: STR) : PTR Graph IN pool RAISES SyntaxError, ValueRange

an N-Triples document: every IRI absolute, no base

### ParseTurtle (VAR pool: POOL ; RO text: STR ; RO base: STR) : PTR Graph IN pool RAISES SyntaxError, ValueRange

a Turtle document; base is the IRI relative references resolve
against until the document says @base or BASE ('' for none, and
then a relative reference is a SyntaxError)

### Count (g: PTR Graph) : I64

how many triples were read; a triple stated twice is there twice

### Get (g: PTR Graph ; i: I64) : Triple RAISES IndexError

_(documented with the group below)_

### NTriples (g: PTR Graph) : STR RAISES ValueRange

the graph as N-Triples text, a line feed after every triple;
characters, so written to a file as UTF-8 (DynStr.Utf8 and
Io.WriteFileBytes) -- Io.WriteFile's Latin-1 refuses most of
the world's scripts
