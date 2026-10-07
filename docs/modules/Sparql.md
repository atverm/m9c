# Sparql

A SPARQL 1.1 client: SELECT and ASK answered in the W3C JSON
results format and read into typed terms, CONSTRUCT answered as
N-Triples text for Rdf to read (docs/datalib-plan.md par 2).

The HTTP side is the protocol's (SPARQL 1.1 Protocol par 2.1): the
query goes as `query=` in the URL when the URL stays within GetMax
characters, and as a form-encoded POST body otherwise -- the
download statistics found an endpoint that refuses a GET of a
hundred URIs and takes it by POST.  An answer other than 200 is a
QueryError carrying the status and the start of what the endpoint
said.

Parse and ParseAsk read a results document without the network,
so a document read from a file is a Results too, and the test
holds the reading to rdflib's own answers offline.  Every string a
Results holds is copied into its pool: nothing points back into the
document.

### TYPE Kind

_(documented with the group below)_

### TYPE Term

the IRI, a literal's lexical form, a
blank node's label; '' when unbound

### TYPE Results

opaque; lives in a POOL

### EXCEPTION QueryError

the endpoint answered, but not 200: msg is the start of what it
said, status the HTTP status

### EXCEPTION FormatError

a document that is not the W3C SPARQL JSON results format

### CONST GetMax

a longer URL goes by POST

### CONST ResultCap

64 MB of answer, refused past it

### Select (VAR pool: POOL ; RO endpoint: STR ; RO query: STR) : PTR Results IN pool RAISES Http.TransportError, QueryError, FormatError, ValueRange

a SELECT, its rows read into pool

### Ask (RO endpoint: STR ; RO query: STR) : BOOL RAISES Http.TransportError, QueryError, FormatError, ValueRange

_(undocumented)_

### Construct (VAR pool: POOL ; RO endpoint: STR ; RO query: STR) : STR RAISES Http.TransportError, QueryError, ValueRange

a CONSTRUCT or DESCRIBE, the graph as N-Triples text in pool
(Accept: application/n-triples)

### Parse (VAR pool: POOL ; RO doc: STR) : PTR Results IN pool RAISES FormatError, ValueRange

a SELECT's JSON results document

### ParseAsk (RO doc: STR) : BOOL RAISES FormatError

an ASK's: its `boolean`

### Vars (r: PTR Results) : I64

how many variables the head names

### Var (r: PTR Results ; i: I64) : STR RAISES IndexError

the name of variable i, without its `?`

### Rows (r: PTR Results) : I64

_(documented with the group below)_

### Column (r: PTR Results ; RO name: STR) : I64

the index of the variable named name, or -1

### Get (r: PTR Results ; row, col: I64) : Term RAISES IndexError

the term bound to variable col in row, kind Unbound when the row
leaves it unbound (an OPTIONAL that did not match).  row and col
are each checked against their own extent.

### Value (r: PTR Results ; row, col: I64) : STR RAISES IndexError

Get's value: '' when unbound
