"""Shrink a sequence while a discrepancy holds: delete one operation at
a time, keep a deletion that preserves the predicate, until no single
deletion does (1-minimal).  The predicate sees only the sequence."""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ir  # noqa: E402
import harness  # noqa: E402


def shrink(seq, holds):
    seq = list(seq)
    changed = True
    while changed:
        changed = False
        for i in range(len(seq)):
            cand = seq[:i] + seq[i + 1:]
            if cand and holds(cand):
                seq = cand
                changed = True
                break
    return seq


def hole_predicate(m9c):
    """the checker accepts, and the run faults -- the model's verdict
    first, as a cheap filter, the sanitizers as the judge"""
    def holds(seq):
        if ir.run(seq)[0] != "unsafe":
            return False
        src = ir.to_m9("Shrunk", seq)
        ok, _ = harness.check(m9c, src, "Shrunk")
        return ok and harness.sanrun(m9c, src, "Shrunk")[0] == "unsafe"
    return holds


def mismatch_predicate(m9c):
    """the checker accepts and the run does not do what the model says"""
    def holds(seq):
        verdict, _, _, output = ir.run(seq)
        src = ir.to_m9("Shrunk", seq)
        ok, _ = harness.check(m9c, src, "Shrunk")
        if not ok:
            return False
        kind, what = harness.sanrun(m9c, src, "Shrunk")
        return (kind == "unsafe") != (verdict == "unsafe") or (kind == "ran" and what != output)
    return holds


if __name__ == "__main__":
    # shrink.py M9C FILE.ops [mismatch]
    m9c, path = sys.argv[1], sys.argv[2]
    pred = mismatch_predicate(m9c) if sys.argv[3:] == ["mismatch"] else hole_predicate(m9c)
    seq = ir.parse(Path(path).read_text())
    if not pred(seq):
        print("the predicate does not hold for the input")
        sys.exit(1)
    print(ir.show(shrink(seq, pred)), end="")
