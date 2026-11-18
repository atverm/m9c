# Explain

Explain finds the probe behind a refusal, so m9c can print the fix
under it and `m9c --explain' can print the whole entry (0.28.1).

Each probe in probes/ is the smallest program that earns one
refusal, and docs/diagnose.md gives each a cause and a fix.  An
agent asked for that table inside the compiler, where it cannot be
a version behind.  tools/MkDiagnose.m9 writes it as ExplainTab: the
probe's message, made a PATTERN, with its cause and fix.

A PATTERN is the message with every name that came from the probe's
own program and every number replaced by `~'.  So `module Lib is
named and not imported' becomes `module ~ is named and not
imported', and matches the same refusal in any program.  A `~'
stands for one character or more.  A builtin type stays as it is:
with the types made wildcards every `cannot assign X to Y' looked
alike, and the I32-to-I64 refusal was offered four probes about
handler binders and none about widening.  A refusal with other
types gets no line, which is better than a wrong one.

One refusal can have several probes: the same words are earned by
different programs, with different fixes.  So a message gets the
CANDIDATES, not one answer: every probe whose pattern matches with
a score close to the best.  The score is the pattern's length less
its wildcards, so a more literal pattern wins.  MkDiagnose refuses
to write the table unless every probe's own message has its own
probe among at most MaxCandidates.

### CONST Wild

_(documented with the group below)_

### CONST Slack

a candidate scores at least best - Slack

### CONST MaxCandidates

_(documented with the group below)_

### Template (RO msg: STR ; RO names: SLICE OF STR) : STR

Template answers msg as a pattern.  A word is a run of letters,
digits, `_' and `.' that starts with a letter or `_'; a number is
a run of digits.  A word is replaced by `~' when it, or its part
before the first `.', is in names and is not a builtin type;
every number is.  Runs of `~' collapse to one.

### Score (RO pat: STR) : I64

Score answers the octets of pat that are not `~'.

### Matches (RO pat: STR ; RO msg: STR) : BOOL

Matches asks whether pat occurs in msg, each `~' taking one
character or more.  The pattern may start anywhere in msg.

### Candidates (RO pats: SLICE OF STR ; RO msg: STR ; VAR out: SLICE OF I64) : I64

Candidates answers how many patterns of pats match msg with a
score of at least the best score less Slack, and puts their
indexes in out, best score first and then in index order, as many
as out holds.  It answers 0 when none matches.

### Nearest (VAR pool: POOL ; RO text: STR ; VAR out: SLICE OF I64) : I64

Nearest is for a refusal's text pasted in part, which no pattern
may match: `module Frob is named and not imported' stops before
the `: write IMPORT' the pattern needs.  It counts the words of
text that occur among the words of each ExplainTab message, and
answers the entries with the best count, if that count is at
least three and at least two thirds of text's words.  out is
filled as Candidates fills it.

### Patterns (VAR pool: POOL) : SLICE OF STR

Patterns answers ExplainTab's patterns in its order, in pool.

### Find (RO name: STR) : I64

Find answers the ExplainTab index of probe `name', or -1.

### Hint (VAR pool: POOL ; RO msg: STR) : STR

Hint answers the line m9c prints under refusal msg, or '' when
no probe matches.  One candidate gives its fix and its name for
`m9c --explain'; several give their names, best first.
