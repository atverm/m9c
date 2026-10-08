# Rdf

RDF 1.1 graphs read from N-Triples, Turtle and RDF/XML and written
as N-Triples or Turtle (docs/datalib-plan.md par 2; RDF/XML and the
Turtle writer from docs/library-plan-2.md).  What Sparql.Construct
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
nodes labelled _:b0, _:b1 ... in the order they were first seen,
or Turtle (Turtle below: grouped, prefixed, the short forms);
a literal's quote, backslash and control characters escaped, every
other character as itself (UTF-8 when written to a file).

Out: JSON-LD, TriG and named graphs, and any inference.  Language tags are kept as written.

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

### ParseRdfXml (VAR pool: POOL ; RO doc: SLICE OF BYTE ; RO base: STR) : PTR Graph IN pool RAISES SyntaxError, ValueRange

an RDF/XML document (octets: the XML says its encoding); base is
the document's IRI, which rdf:ID and a relative rdf:about resolve
against until the document says xml:base ('' for none).  A
document that is not well-formed XML, or not in the RDF/XML
grammar, is a SyntaxError -- the XML's with its line and column,
the grammar's without (the tree has no positions)

### ParseJsonLd (VAR pool: POOL ; RO text: STR ; RO base: STR ; context: OPT PTR Json.Node) : PTR Graph IN pool RAISES SyntaxError, ValueRange

a JSON-LD document (JSON-LD 1.0's expansion and conversion to
RDF; its default graph; named graphs read and dropped); base is
the document's IRI; context a context the caller hands in, as
Json.Parse read it, applied before the document's own -- NONE
for none.  A context given as a URL is refused by name: nothing
is fetched.  A refusal carries the JSON-LD API's error code

### JsonLd (g: PTR Graph ; context: OPT PTR Json.Node) : STR RAISES ValueRange

the graph as JSON-LD: the flattened form -- every node once, in
first-seen order, "@id", "@type", properties as arrays --
compacted against the context handed in (its terms, prefixes,
@vocab, @language and coercions), which is written as "@context";
"@graph" holds the nodes; a chain of rdf:first/rest cells nothing
else refers to is "@list".  Deterministic; ParseJsonLd reads it
back.  Characters, as NTriples

### Count (g: PTR Graph) : I64

how many triples were read; a triple stated twice is there twice

### Get (g: PTR Graph ; i: I64) : Triple RAISES IndexError

_(documented with the group below)_

### NTriples (g: PTR Graph) : STR RAISES ValueRange

the graph as N-Triples text, a line feed after every triple;
characters, so written to a file as UTF-8 (DynStr.Utf8 and
Io.WriteFileBytes) -- Io.WriteFile's Latin-1 refuses most of
the world's scripts

### Turtle (g: PTR Graph ; RO names: SLICE OF STR ; RO iris: SLICE OF STR) : STR RAISES ValueRange

the graph as Turtle (2026-10-07, docs/library-plan-2.md item 2):
triples grouped by subject in the order subjects were first seen,
a subject's predicates in the order first seen with `;', a
predicate's objects in insertion order with `,'; `a' for
rdf:type as a predicate; a prefixed name wherever one of the
prefixes applies -- names[i] abbreviates iris[i], and rdf, rdfs,
xsd and owl are known without being given -- and only the
prefixes USED are declared, in that order; the short forms for
an xsd:integer, decimal, double or boolean whose lexical form is
one Turtle reads back unchanged (a sign and digits; digits, a
dot, digits; a double with its exponent; true/false -- 01 and +1
included, since the grammar takes them and keeps the lexical
form), every other literal quoted with its type; a literal holding a line end as a long string.  Blank
nodes keep their labels.  Deterministic: the same graph is the
same text.  Characters, as NTriples.
