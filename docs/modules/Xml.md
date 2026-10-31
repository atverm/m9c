# Xml

Xml handles XML 1.0 (fifth edition) with Namespaces 1.0: a pull
reader, a small tree on it, and a writer (docs/datalib-plan.md
par 4).

READING is well-formedness, all of it, and nothing guessed: every
character checked against the Char and Name productions, line ends
normalised, attribute values normalised, the five predefined
entities and character references replaced, CDATA read as text,
comments and processing instructions reported, namespace prefixes
resolved and every namespace constraint held.  A document that is
not well-formed is a SyntaxError at its line and column.

Xml REFUSES BY NAME, as Unsupported, what a reader that takes
documents off the network must not do or cannot do without a DTD: an
ENTITY declaration (the billion-laughs and external-entity class), an
ATTLIST declaration (its defaults and normalisation would change the
data a reader without the DTD reports), a parameter entity, an entity
reference that only an external DTD could declare, any encoding but
UTF-8, and XML 1.1.  The rest of a DOCTYPE is read for
well-formedness and skipped.

XmlTest holds it to the W3C XML conformance suite (xmlconf): every
not-well-formed document refused, every well-formed one read the
way expat reads it (to the W3C's own canonical outputs, where it
gives them) or refused by name.

WRITING escapes what it must and refuses a name that is not one.

Strings are characters (code points); a document arrives as the
bytes of its file or HTTP body.

### TYPE Kind

_(documented with the group below)_

### TYPE Attr

as written, prefix:local

### TYPE Event

Start, End: as written; Pi: target

### TYPE Reader

opaque; lives in a POOL

### TYPE Element

character data before the first child

### TYPE Writer

opaque; lives in a POOL

### EXCEPTION SyntaxError

SyntaxError reports a document that is not well-formed.

### EXCEPTION Unsupported

Unsupported reports a document that is well-formed, perhaps,
but refused by name.

### EXCEPTION WriteError

_(documented with the group below)_

### Open (VAR pool: POOL ; RO doc: SLICE OF BYTE) : PTR Reader IN pool RAISES SyntaxError, Unsupported

Open answers a reader on doc: UTF-8, with or without a byte
order mark.

### Next (VAR r: PTR Reader) : Event RAISES SyntaxError, Unsupported

Next answers the next event; Eof once the root element and what
follows it are read, and again after that.  The event's strings
live in the reader's pool.

### Parse (VAR pool: POOL ; RO doc: SLICE OF BYTE) : PTR Element IN pool RAISES SyntaxError, Unsupported

Parse answers the root element; comments and processing
instructions are dropped.

### Child (e: PTR Element ; RO ns: STR ; RO local: STR) : OPT PTR Element

Child answers the first child of that name.

### HasAttr (e: PTR Element ; RO ns: STR ; RO local: STR) : BOOL

_(documented with the group below)_

### AttrValue (e: PTR Element ; RO ns: STR ; RO local: STR) : STR

AttrValue answers an attribute's value, '' when there is none
(HasAttr says).

### AllText (e: PTR Element) : STR

AllText answers the element's character data and its
descendants', in order.

### NewWriter (VAR pool: POOL) : PTR Writer IN pool

_(documented with the group below)_

### StartTag (VAR w: PTR Writer ; RO name: STR) RAISES WriteError

_(documented with the group below)_

### Attribute (VAR w: PTR Writer ; RO name: STR ; RO value: STR) RAISES WriteError

Attribute is allowed only straight after StartTag or another
Attribute.

### Chars (VAR w: PTR Writer ; RO s: STR) RAISES WriteError

_(documented with the group below)_

### EndTag (VAR w: PTR Writer) RAISES WriteError

_(documented with the group below)_

### Document (w: PTR Writer) : STR RAISES WriteError

Document answers the document so far, which must be one element,
closed: an XML declaration, then the element.  A character no XML
document may hold is refused where it is written.
