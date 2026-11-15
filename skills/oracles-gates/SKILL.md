---
name: oracles-gates
description: Proving that a port, migration, refactor or new feature is right with evidence that can say no -- an independent oracle, a gate that exits 0 or 1, recorded goldens, sabotage that shows the gate can fail, and fuzzing judged by an oracle, a model or the sanitizers. Load before porting code from another language or version, before claiming a change is done, correct, equivalent or faster, before writing or changing a test or gate, and when asked to verify, compare against a reference, or fuzz.
---

# Oracles, gates and goldens

A change is done when evidence says so, not when the code looks right.
You write fast and report fluently, in the same voice whether the work
is right or wrong, and asked to confirm a hypothesis you tend to
confirm it.  So nothing rests on your word.  Every claim you make --
correct, equivalent, faster, done -- becomes a check a machine runs and
that can fail, and you report what that check printed.

## The pieces

| Piece | What it is |
|---|---|
| Oracle | An independent source of the right answer: the original program, a reference library (numpy, scipy, a standard library module), a standard's test vectors, the production service. Independent of the code under test, and of you. |
| Gate | A script that runs the code against the oracle or a golden and exits 0 or 1. |
| Golden | A recorded expected output (bytes, a page, JSON, a list of diagnostics), compared byte for byte. |
| Fixpoint | A tagged state of the application with its toolchain and dependencies pinned. |
| Sabotage | One small break of a copy of the code, naming the property it breaks. The gate must go red on it. |
| Fuzzer | A generator of inputs nobody wrote, run against a judge: an oracle, an independent model, or an invariant such as "no sanitizer report". |
| Reproduction | A minimal program that shows a fault in a tool or library, with the expected and the actual result. |

## Before you write code

1. **Name the oracle, and check it is fit.** An original with too many
   known faults is not one: then gate against analytic cases, synthetic
   truths (data made from known parameters, then recovered) and
   independent implementations.  Write down which oracle and why.
2. **Keep the oracle in its own language.**  A Python oracle stays
   Python.  Rewriting it in the language under test, or writing code
   and oracle yourself, holds the code to itself.
3. **Fix a point**: tag the application and record the toolchain.
   Build a newer toolchain in a scratch location, never over the one
   in use.
4. **Write the gate first, and see it red** before the code is done.
   A gate that has never been red is untested.

## While you change code

- **Small steps, each gated.**  Put the counts in the commit message:
  checks passed, files matched, requests compared.
- **Byte for byte where it means something**: generated files, pages,
  JSON, exports.  Mask only what must differ (timestamps, build ids,
  timings) and list what you masked.
- **Show the comparison exercised what changed.**  For an encoding
  change, show the compared data holds non-ASCII text; for an edge
  case, show it is in the sample.
- **Run the new build beside the live one**, as a separate service on
  another port under a memory cap, and diff the answers.  Never send a
  heavy request to production "to see": a request the client gives up
  on keeps running on the server.
- **Check every consumer** of a change: logs, databases, indexes,
  exports, downstream jobs.
- **Watch what you start until it ends, and read the output.**  Two
  runs that both died agree.
- **Never re-record a golden to make a gate green.**  Re-record only on
  purpose, and say why in the commit.  A golden changed to pass has
  stopped being a golden.
- **A gate that regenerates what it compares against cannot fail.**
  Generating the expectation and comparing against it are two scripts.

## Sabotage: show what a gate holds

One red run shows a gate can fail.  It does not show the gate holds
each property it claims.

1. **List one sabotage per property**: the property, the file, the
   exact text to replace (it must occur exactly once, so a stale entry
   is refused rather than counted), and its replacement.  Keep the
   list beside the gate.
2. **Apply each to a copy**, run the gate on the copy, require red.
   Never break the working tree.
3. **A sabotage the gate passes names a missing check.**  Write that
   check before going on, and run the list again.  Report it as
   "18 sabotages, 18 red".
4. **Put a control inside the gate**, a known-bad case reported on
   every run: a planted data race the race detector must see, an
   output with a line cut out that the comparison must notice.  A gate
   whose control passes is blind, and must say so instead of passing.
5. **Sabotage the harness too.**  A translator or model that turns
   test cases into runs is code: give it goldens, and check that a
   planted fault in it is reported.

Mutation-testing tools (PIT on the JVM, mutmut or cosmic-ray for
Python) automate part of this; read their surviving mutants as
sabotages the tests pass.

## Fuzzing: inputs nobody wrote

Choose the judge first: an **oracle** (the same input to old and new,
outputs compared -- the strongest), an **independent model** that knows
the semantics and nothing of the implementation, or an **invariant**
(no crash, no ASan/UBSan/TSan report, a round trip that gives the input
back -- the weakest, and always available).

- **Mutate valid inputs** where the input has structure: seeds from the
  test suite, one edit at a time.
- **Classify every result**: refused, clean, finding, timeout.  A
  timeout is a verdict.
- **A fixed sample with a fixed seed in CI**, large campaigns offline;
  every finding becomes a fixed case.  Shrink a finding before you
  report it.
- **Keep an owed list** of known findings by an identity that survives
  renumbering (seed and mutation).  Red on a new finding, and red on an
  owed one that no longer happens: the list can only shrink.
- **Show the fuzzer can find**: run it on an older version with known
  faults and record how many it found.
- **Check the judge on this machine.**  A sanitizer broken on a
  toolchain reports nothing or fails everything.  Give it a clean
  control that must pass and a faulty one that must be reported; skip
  out loud where the control fails, and fail in CI.
- **Gate only what the design promises.**  A conservative checker
  refuses some valid inputs: print those, do not gate them.

## How you report

- **Give the gate's own output**: counts of checks, bytes compared,
  requests made, what differed, what was masked.  "All tests pass"
  without numbers is a claim.
- **Say what was not run, and why.**
- **When delegating, hand over the gate, not the conclusion**: "make
  this gate pass and show its output", never "check that this works".
- **Report a tool's fault upstream with a reproduction**, keep a
  commented workaround, and remove it when the fix lands.
- **Measure pace in gated output** (lines, files, checks gated per
  day), not in estimates.

## Habits that bite

- Kill processes by PID or port (`fuser -k PORT/tcp`), never by a name
  pattern: it matches other sessions' servers, or your own shell.
- Write source files with the file-writing tool, not heredocs or
  string literals, where escapes are mangled.
- Short timeouts for anything expected within a second.
- Read a stricter checker's refusals: they often find real bugs.
- Review a codemod's list of sites it could not prove: it can change
  the meaning of a few silently.
- Floats: compare with stated tolerances and say why, or byte for byte
  only when both sides format the same way.  Sort unordered
  collections and JSON keys before comparing.  Pin the oracle's
  versions: a minor numpy or pandas release can move a last digit.
- A test runner can be green without testing: count the tests it ran
  and hold the count.

## Before you say "done"

- [ ] The oracle is named, independent, and its versions recorded.
- [ ] The gate ran; its counts are in the report; it was seen red.
- [ ] Each property the gate claims has a sabotage, and each turned it red.
- [ ] Where a fuzzer guards the change: its fixed sample ran, its owed
      list matches, its judge's control passed.
- [ ] The comparison ran on a copy, with its masks listed, and is shown
      to have exercised what changed.
- [ ] Every consumer was checked.
- [ ] Everything started was stopped, and its output read.
- [ ] What was not run is said, with the reason.
