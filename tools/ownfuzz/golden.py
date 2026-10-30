"""The translator's and the model's golden suite.

golden/NAME.ops    a sequence, hand written
golden/NAME.m9     its translation as reviewed, held byte for byte
golden/NAME.want   the model's verdict, output line and trace, as reviewed

  python3 -I golden.py            translation and model against the files
  python3 -I golden.py --record   (re)write .m9 and .want -- then READ the diff
  python3 -I golden.py --compile [LABEL=M9C ...]
                                  also: each case checked by each compiler
                                  named (default: this tree's, harness.
                                  default_m9c); an accepted one is built and
                                  run under the sanitizers, and what it does
                                  must be what the model says -- a fault
                                  where the model says unsafe, the exact
                                  printed line where it says safe or raises.

The --compile half is what makes the translation trustworthy: the
golden cases cover every operation, and each one that some compiler
accepts is run and held to the model, so a translation that does
something else to memory than the operation says shows as a
disagreement here, before any fuzzing result depends on it.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ir  # noqa: E402

def compilers():
    named = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    if named:
        return named
    import harness
    return {"tree": harness.default_m9c()}


def want_text(verdict, reason, trace, output):
    return (f"verdict: {verdict}\nreason: {reason}\noutput: {output}\ntrace:\n"
            + "".join(f"  {t}\n" for t in trace))


def main():
    record = "--record" in sys.argv
    compile_ = "--compile" in sys.argv
    bad = 0
    cases = sorted((HERE / "golden").glob("*.ops"))
    for ops in cases:
        stem = ops.stem
        mod = "Golden" + "".join(p.capitalize() for p in stem.replace("-", " ").split())
        seq = ir.parse(ops.read_text())
        src = ir.to_m9(mod, seq)
        verdict, reason, trace, output = ir.run(seq)
        want = want_text(verdict, reason, trace, output)
        m9f, wantf = ops.with_suffix(".m9"), ops.with_suffix(".want")
        if record:
            m9f.write_text(src)
            wantf.write_text(want)
            continue
        if not m9f.exists() or m9f.read_text() != src:
            print(f"{stem}: TRANSLATION differs from {m9f.name}"); bad += 1
        if not wantf.exists() or wantf.read_text() != want:
            print(f"{stem}: MODEL differs from {wantf.name}"); bad += 1
        if not compile_:
            continue
        import harness
        for label, m9c in compilers().items():
            ok, diag = harness.check(m9c, src, mod)
            if not ok:
                print(f"{stem} [{label}]: refused -- {diag[:110]}")
                continue
            kind, what = harness.sanrun(m9c, src, mod)
            if verdict == "unsafe":
                agree = kind == "unsafe"
            else:
                agree = kind == "ran" and what == output
            print(f"{stem} [{label}]: accepted, run: {kind} {what[:70]!r}"
                  f" -- model {verdict} {output!r}: {'agrees' if agree else 'DISAGREES'}")
            bad += 0 if agree else 1
    if record:
        print(f"recorded {len(cases)} cases: read golden/*.m9 and golden/*.want before trusting them")
        return 0
    print(f"golden: {len(cases)} cases, {bad} failures")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
