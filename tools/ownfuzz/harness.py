"""The compiler side: check a program, and build and run an accepted one
under ASan + UBSan with the runtime's M9_ASAN arenas (lib/sancc: no
block cache, released arenas poisoned), the way runtime/test/regions.sh
runs its repros.  Nothing here reads M9 source; it reads exit codes,
sanitizer reports and the program's printed line."""
import os
import subprocess
import tempfile
from pathlib import Path

# the tree whose runtime and library the programs build against: this
# file's own (tools/ownfuzz -> the root), or $OWNFUZZ_TREE
TREE = Path(os.environ.get("OWNFUZZ_TREE", Path(__file__).resolve().parents[2]))


def default_m9c():
    """runtime/test/m9c when a gate built one, else out/m9c"""
    for p in (TREE / "runtime/test/m9c", TREE / "out/m9c"):
        if p.exists():
            return str(p)
    return "m9c"


def _env(tmp):
    e = dict(os.environ)
    e.update(M9RUNTIME=str(TREE / "runtime"), M9LIBRARY=str(TREE / "corpus"),
             M9CACHE=str(Path(tmp) / "cache"),
             ASAN_OPTIONS="detect_leaks=0:abort_on_error=0",
             UBSAN_OPTIONS="print_stacktrace=1")
    e.setdefault("SANCC_REAL", "gcc")
    return e


def check(m9c, src, name):
    """(accepted, first diagnostic)"""
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / f"{name}.m9"
        f.write_text(src)
        r = subprocess.run([m9c, "--check", f.name], cwd=tmp, env=_env(tmp),
                           capture_output=True, text=True, timeout=120)
        if r.returncode == 0:
            return True, ""
        lines = [l for l in (r.stdout + r.stderr).splitlines() if not l.startswith("m9c:")]
        first = lines[0] if lines else (r.stdout + r.stderr).strip()
        return False, first.split(": ", 2)[-1] if first.count(": ") >= 2 else first


def sanrun(m9c, src, name):
    """('unsafe', report) or ('ran', printed line) or ('build', error)"""
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / f"{name}.m9"
        f.write_text(src)
        env = _env(tmp)
        env["CC"] = str(TREE / "runtime/test/lib/sancc")
        try:
            r = subprocess.run([m9c, "--run", f.name], cwd=tmp, env=env, stdin=subprocess.DEVNULL,
                               capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired:
            return "build", "timeout"
        out = r.stdout + r.stderr
        for l in out.splitlines():
            if "ERROR: AddressSanitizer" in l or "runtime error:" in l:
                return "unsafe", l.strip()
        if r.returncode < 0 or r.returncode > 128:
            return "unsafe", f"signal / exit {r.returncode}"
        printed = [l for l in r.stdout.splitlines() if l.startswith(("total ", "raised"))]
        if r.returncode == 0 and printed:
            return "ran", printed[-1]
        return "build", out.strip().splitlines()[-1] if out.strip() else f"exit {r.returncode}"
