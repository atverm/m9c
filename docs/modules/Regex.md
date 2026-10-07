# Regex

Regular expressions: the subset Python's re and RE2 share, matched
by a Pike VM -- the NFA simulation RE2 uses -- in time linear in
the subject whatever the pattern, so that no pattern can hang the
program that runs it (docs/datalib-plan.md par 3).

THE LANGUAGE is Python's, and a match is the one Python's re finds:
literals and escapes (\n \t \x41 é ...), . and classes with
ranges and negation, \d \w \s and their negations, \b \B ^ $ \A
\Z, groups capturing, non-capturing (?:...) and named (?P<n>...),
alternation, * + ? {m} {m,} {,n} {m,n} each greedy or lazy, and
the flags i m s and u -- as letters to Compile, inline at the
start (?ims), or scoped (?i:...) (?-i:...).  Leftmost-first, with
Python's rule for a loop whose body matched nothing: the loop ends
there.  Held to re on 3,135 searches, 845 find-alls, 645
substitutions and 445 splits, of generated patterns and written
ones (RegexTest).

REFUSED BY NAME, because each needs backtracking, which is exactly
what this engine exists not to do: backreferences, lookahead and
lookbehind, atomic groups, possessive quantifiers, conditional
groups.  Also refused: verbose patterns, \N{...}, a repetition
count above 1000, and case-insensitive matching under u.

ASCII BY DEFAULT: \d \w \s \b and the i flag know ASCII only, RE2's
choice and Python's re.ASCII.  The flag u gives Python's Unicode
classes (from tables in this module, tools/regexucd.py); every
other character matches as itself in either mode, since a CHAR is
a code point.

A match is a Found: the span of each group, start and end, in
characters of the subject; -1 for a group that took no part.  The
procedures answering text answer VIEWS of the subject.

### TYPE Re

a compiled pattern; lives in a POOL

### TYPE Found

start and end of group 0, 1, ...;
-1 and -1 for one that took no part

### EXCEPTION BadPattern

msg says what; pos is the index in the pattern where it was
seen, or -1 for the flags or a replacement template

### Compile (VAR pool: POOL ; RO pattern: STR ; RO flags: STR) : PTR Re IN pool RAISES BadPattern

pattern compiled; flags is letters from imsu, '' for none:
i caseless, m ^ and $ at every line, s . matches a line feed
too, u Unicode classes

### Groups (re: PTR Re) : I64

how many capturing groups the pattern has

### GroupIndex (re: PTR Re ; RO name: STR) : I64

the number of the group named so, or -1

### Search (re: PTR Re ; RO s: STR ; from: I64) : OPT PTR Found

the first match at or after from (clamped to 0 .. LEN (s))

### Match (re: PTR Re ; RO s: STR ; from: I64) : OPT PTR Found

a match that starts at from

### FullMatch (re: PTR Re ; RO s: STR) : OPT PTR Found

a match of the whole of s

### Start (m: PTR Found ; k: I64) : I64 RAISES IndexError

_(documented with the group below)_

### End (m: PTR Found ; k: I64) : I64 RAISES IndexError

_(documented with the group below)_

### Took (m: PTR Found ; k: I64) : BOOL RAISES IndexError

group k's start, end, and whether it took part

### Group (RO s: STR ; m: PTR Found ; k: I64) : STR RAISES IndexError

the text group k matched in s, the subject m was found in; '' for
a group that took no part (Took says which)

### FindAll (re: PTR Re ; RO s: STR) : SLICE OF PTR Found

every match, left to right, as Python's finditer: an empty match
may follow a non-empty one where it ends, never another empty one

### Sub (re: PTR Re ; RO s: STR ; RO repl: STR ; count: I64) : STR RAISES BadPattern

s with the first count matches (0 for all) replaced by repl, in
which \g<0> \g<name> \g<n> and \1 .. \99 name a group's text ('' if
it took no part), and \n \t \r \\ are escapes

### Split (re: PTR Re ; RO s: STR ; maxsplit: I64) : SLICE OF STR

s cut at the first maxsplit matches (0 for all), each match's
groups between the pieces -- '' for one that took no part, where
Python says None
