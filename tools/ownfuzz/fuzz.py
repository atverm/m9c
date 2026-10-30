"""Generate sequences, and judge each three ways.

  python3 -I fuzz.py OUTDIR N SEED [COMPILER=path ...]

For each sequence: the MODEL's verdict (ir.run); for each compiler the
CHECKER's (m9c --check of ir.to_m9); for an accepted program the RUN
under the sanitizers (harness.sanrun), which is the ground truth for the
programs it can be asked about.  Classes, per compiler:

  ok          accepted, the run does what the model says
  refused-ok  refused, the model says unsafe
  conservative refused, the model says safe (or raises)
  HOLE        accepted, and the run faults            -- shrunk
  MISMATCH    accepted, and the run and the model disagree on
              anything else: the model, the translator or the
              sanitizers is wrong                    -- shrunk
  BUILD       accepted by --check, refused by the build

A sequence is kept as OUTDIR/cases/NAME.ops; a shrunk one beside it as
NAME.min.ops.
"""
import os
import random
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ir  # noqa: E402
import harness  # noqa: E402
import shrink  # noqa: E402

OPS = list(ir.ARITY)


def random_seq(rng):
    """one or two NEWs, then 3 to 6 operations whose operands are names
    given a value so far, all but 3% of the time"""
    seq, assigned = [], set()
    for v in rng.sample(ir.VARS, rng.randint(1, 2)):
        seq.append(("NEW", v))
        assigned.add(v)
    for _ in range(rng.randint(3, 6)):
        op = rng.choice(OPS)
        args = []
        for k in ir.ARITY[op]:
            if k == "p":
                args.append(rng.choice(ir.POOLS))
            elif not args and op in ("NEW", "MOVE", "BORROW", "LOAD"):
                args.append(rng.choice(ir.VARS))          # the target
            else:
                pick = sorted(assigned) if rng.random() < 0.97 else list(ir.VARS)
                args.append(rng.choice(pick))
        if op in ("NEW", "MOVE", "BORROW", "LOAD"):
            assigned.add(args[0])
        seq.append((op, *args))
    return seq


def judge(m9c, name, seq):
    verdict, reason, _, output = ir.run(seq)
    src = ir.to_m9(name, seq)
    ok, diag = harness.check(m9c, src, name)
    if not ok:
        return ("refused-ok" if verdict == "unsafe" else "conservative"), verdict, diag
    kind, what = harness.sanrun(m9c, src, name)
    if kind == "build":
        return "BUILD", verdict, what
    if kind == "unsafe":
        return "HOLE", verdict, what
    if verdict == "unsafe" or what != output:
        return "MISMATCH", verdict, f"ran {what!r}, model {verdict} {output!r} ({reason})"
    return "ok", verdict, what


def main():
    out, n, seed = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    compilers = dict(a.split("=", 1) for a in sys.argv[4:]) or {"tree": harness.default_m9c()}
    jobs = int(os.environ.get("M9_JOBS", "8"))
    cases = out / "cases"
    cases.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)
    seen, seqs = set(), []
    while len(seqs) < n:
        s = random_seq(rng)
        if tuple(s) not in seen:
            seen.add(tuple(s))
            seqs.append((f"F{len(seqs) + 1:05d}", s))
    for name, s in seqs:
        (cases / f"{name}.ops").write_text(ir.show(s))
    failed = False
    for label, m9c in compilers.items():
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            res = list(ex.map(lambda ns: (ns[0], ns[1], judge(m9c, *ns)), seqs))
        counts = {}
        rows = []
        for name, s, (cls, verdict, note) in res:
            counts[cls] = counts.get(cls, 0) + 1
            rows.append(f"{name}\t{cls}\t{verdict}\t{note}")
        (out / f"{label}.tsv").write_text("\n".join(rows) + "\n")
        print(f"{label}: " + "  ".join(f"{k} {v}" for k, v in sorted(counts.items())))
        failed = failed or any(counts.get(k) for k in ("HOLE", "MISMATCH", "BUILD"))
        for name, s, (cls, _, note) in res:
            if cls in ("HOLE", "MISMATCH"):
                pred = shrink.hole_predicate(m9c) if cls == "HOLE" else shrink.mismatch_predicate(m9c)
                small = shrink.shrink(s, pred)
                (cases / f"{name}.{label}.min.ops").write_text(ir.show(small))
                print(f"  {cls} {name} ({len(s)} ops -> {len(small)}): " + " ; ".join(" ".join(o) for o in small))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
