#!/usr/bin/env python3
"""Install the M9 kernel for Jupyter, on Linux, macOS or Windows.

    python3 install.py              say what it found, ask, install
    python3 install.py -y           the same, without asking
    python3 install.py --check      ... and then run one cell through it
    python3 install.py --uninstall  remove it again

    --uv            the kernel runs under `uv run --with ipykernel`:
                    no Python environment to prepare (the default when
                    uv is on PATH and this Python has no ipykernel)
    --python PY     the kernel runs under PY, which needs ipykernel
    --pip           install ipykernel with pip when PY lacks it (asked
                    for interactively; under -y only with --pip)
    --m9c PATH      this compiler (else $M9C, PATH, the usual places)
    --highlight     also install the JupyterLab highlighting extension
                    into THIS Python -- the one that runs JupyterLab
    --data-dir DIR  register under DIR/kernels/m9 (else
                    $JUPYTER_DATA_DIR, else Jupyter's own)

Why Python and not M9: Jupyter and the kernel are Python, so whoever
installs a Jupyter kernel already has it, on every platform the same
way.  What it writes is one directory, <data dir>/kernels/m9, holding
kernel.json; removing that directory uninstalls, and so does
--uninstall.  The kernel itself stays where this file is.

On Linux and macOS a library cell keeps its state in a session
(m9c --cell); on Windows every cell runs as its own program -- the
kernel decides that itself, nothing here differs.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
KERNEL = os.path.join(HERE, "m9kernel.py")
WINDOWS = os.name == "nt"
MAC = sys.platform == "darwin"
EXE = ".exe" if WINDOWS else ""


# ---- saying things ---------------------------------------------------------

QUIET = False


def say(msg=""):
    if not QUIET:
        print(msg, flush=True)


def step(what, result):
    say("  %-22s %s" % (what, result))


def fail(msg, hint=None):
    say()
    say("install: " + msg)
    if hint:
        for line in hint.splitlines():
            say("         " + line)
    sys.exit(1)


def ask(question, assume_yes):
    if assume_yes:
        return True
    try:
        answer = input("  %s [Y/n] " % question).strip().lower()
    except EOFError:
        return False
    return answer in ("", "y", "yes")


def run(argv, **kw):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, **kw)


# ---- the compiler ----------------------------------------------------------

def m9c_candidates(given):
    """where an m9c may be, in the order they are tried"""
    if given:
        yield given
    if os.environ.get("M9C"):
        yield os.environ["M9C"]
    found = shutil.which("m9c")
    if found:
        yield found
    # beside this kernel: a source tree (out/m9c), the Windows zip
    # (bin\\m9c.exe two levels up), a package (/usr/share/m9/jupyter ->
    # /usr/bin/m9c)
    up2 = os.path.dirname(os.path.dirname(HERE))
    yield os.path.join(up2, "out", "m9c" + EXE)
    yield os.path.join(up2, "bin", "m9c" + EXE)
    yield os.path.join(up2, "runtime", "test", "m9c" + EXE)
    up3 = os.path.dirname(up2)
    yield os.path.join(up3, "bin", "m9c" + EXE)
    if MAC:
        yield "/usr/local/m9/usr/bin/m9c"
        yield "/opt/homebrew/bin/m9c"
    if not WINDOWS:
        yield "/usr/local/bin/m9c"
        yield "/usr/bin/m9c"


def find_m9c(given):
    """the first m9c that answers --version and knows --run"""
    tried = []
    for c in m9c_candidates(given):
        c = os.path.abspath(os.path.expanduser(c))
        if c in tried or not os.path.isfile(c):
            continue
        tried.append(c)
        try:
            ver = run([c, "--version"]).stdout.strip()
            usage = run([c, "--help"]).stdout
        except OSError:
            continue
        if "--run" not in usage:
            step("m9c", "%s is %s: too old, the kernel needs 0.15 or later" % (c, ver))
            continue
        return c, ver, "--cell" in usage
    fail("no m9c 0.15 or later was found.",
         "Install M9 (https://github.com/atverm/m9c/releases), or say where\n"
         "it is: --m9c PATH, or set $M9C.")


# ---- the Python the kernel runs under --------------------------------------

def has_ipykernel(py):
    try:
        return run([py, "-c", "import ipykernel"]).returncode == 0
    except OSError:
        return False


def choose_runner(args):
    """('uv', argv-prefix, label) or ('python', argv-prefix, label)"""
    uv = shutil.which("uv")
    if args.uv:
        if not uv:
            fail("--uv was asked for and there is no uv on PATH.",
                 "Install it (https://docs.astral.sh/uv/), or leave --uv out.")
        return "uv", [uv, "run", "-q", "--no-project", "--with", "ipykernel", "python"], \
            "uv run --with ipykernel (uv makes the environment)"
    py = args.python or sys.executable
    if not args.python and not has_ipykernel(py) and uv:
        return "uv", [uv, "run", "-q", "--no-project", "--with", "ipykernel", "python"], \
            "uv run --with ipykernel (this Python has no ipykernel; uv makes one)"
    resolved = shutil.which(py) or py
    if not has_ipykernel(resolved):
        step("ipykernel", "missing in %s" % resolved)
        if args.yes and not args.pip or            not args.yes and not ask("Install ipykernel into it with pip?", False):
            fail("the kernel needs ipykernel.",
                 "pip install ipykernel, or install uv and use --uv.")
        r = run([resolved, "-m", "pip", "install", "--user", "ipykernel"])
        if r.returncode != 0:
            fail("pip could not install ipykernel:\n" + (r.stderr or r.stdout).strip()[-800:],
                 "This Python may be managed by the system (PEP 668): make a\n"
                 "virtual environment and pass --python, or install uv and use --uv.")
    return "python", [resolved], resolved


def data_dir(args, kind, runner_argv):
    if args.data_dir:
        return os.path.abspath(args.data_dir)
    if os.environ.get("JUPYTER_DATA_DIR"):
        return os.environ["JUPYTER_DATA_DIR"]
    # Jupyter's own answer, asked of the Python the kernel runs under
    probe = "from jupyter_core.paths import jupyter_data_dir; print(jupyter_data_dir())"
    argv = list(runner_argv)
    if kind == "uv":
        argv = argv[:-1] + ["--with", "jupyter-core", "python"]
    try:
        r = run(argv + ["-c", probe])
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip().splitlines()[-1]
    except OSError:
        pass
    # jupyter_core's defaults, when it cannot be asked
    home = os.path.expanduser("~")
    if WINDOWS:
        return os.path.join(os.environ.get("APPDATA", home), "jupyter")
    if MAC:
        return os.path.join(home, "Library", "Jupyter")
    return os.path.join(os.environ.get("XDG_DATA_HOME", os.path.join(home, ".local", "share")),
                        "jupyter")


# ---- install, check, uninstall ---------------------------------------------

def kernel_json(runner_argv, m9c):
    spec = {
        "argv": list(runner_argv) + [KERNEL, "-f", "{connection_file}"],
        "display_name": "M9",
        "language": "m9",
        # the compiler this was installed with, whatever PATH the
        # notebook server happens to have
        "env": {"M9C": m9c},
        "metadata": {"debugger": False},
    }
    if not WINDOWS:
        spec["interrupt_mode"] = "signal"
    return spec


CHECK_CELL = "MODULE InstallCheck ;\nIMPORT Io ;\nBEGIN\n  Io.WriteLine ('the M9 kernel answers')\nEND InstallCheck.\n"

CHECK_SCRIPT = r"""
import sys
from jupyter_client.manager import start_new_kernel
km, kc = start_new_kernel(kernel_name="m9")
try:
    msg_id = kc.execute(sys.argv[1])
    out = []
    while True:
        m = kc.get_iopub_msg(timeout=300)
        if m["parent_header"].get("msg_id") != msg_id:
            continue
        if m["msg_type"] == "stream":
            out.append(m["content"]["text"])
        elif m["msg_type"] == "error":
            out.append("ERROR " + m["content"]["evalue"])
        elif m["msg_type"] == "status" and m["content"]["execution_state"] == "idle":
            break
    print("".join(out), end="")
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)
"""


def check(kind, runner_argv, data):
    argv = list(runner_argv)
    if kind == "uv":
        argv = argv[:-1] + ["--with", "jupyter-client", "python"]
    env = dict(os.environ, JUPYTER_DATA_DIR=data)
    with tempfile.TemporaryDirectory() as tmp:
        try:
            r = run(argv + ["-c", CHECK_SCRIPT, CHECK_CELL], cwd=tmp, env=env, timeout=600)
        except (OSError, subprocess.TimeoutExpired) as e:
            return False, str(e)
    return "the M9 kernel answers" in r.stdout, (r.stdout + r.stderr).strip()[-1200:]


def install_highlight():
    src = os.path.join(HERE, "highlight")
    if not os.path.isdir(src):
        return False, "no highlight/ beside the kernel"
    r = run([sys.executable, "-m", "pip", "install", src])
    if r.returncode != 0:
        r = run([sys.executable, "-m", "pip", "install", "--user", src])
    return r.returncode == 0, (r.stderr or r.stdout).strip()[-600:]


def main():
    ap = argparse.ArgumentParser(description="Install the M9 kernel for Jupyter.")
    ap.add_argument("-y", "--yes", action="store_true", help="do not ask")
    ap.add_argument("--uv", action="store_true")
    ap.add_argument("--python")
    ap.add_argument("--pip", action="store_true")
    ap.add_argument("--m9c")
    ap.add_argument("--highlight", action="store_true")
    ap.add_argument("--data-dir")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--uninstall", action="store_true")
    ap.add_argument("-q", "--quiet", action="store_true", help="only errors")
    args = ap.parse_args()
    global QUIET
    QUIET = args.quiet

    platform = "Windows" if WINDOWS else "macOS" if MAC else "Linux"
    say("M9 kernel for Jupyter -- %s" % platform)
    say()

    if args.uninstall:
        data = data_dir(args, "python", [sys.executable])
        target = os.path.join(data, "kernels", "m9")
        spec = os.path.join(target, "kernel.json")
        if not os.path.isfile(spec):
            say("  nothing to remove: no %s" % spec)
            return
        with open(spec, encoding="utf-8") as f:
            if json.load(f).get("display_name") != "M9":
                fail("%s is not the M9 kernel; left alone." % spec)
        shutil.rmtree(target)
        say("  removed %s" % target)
        return

    m9c, ver, session = find_m9c(args.m9c)
    step("compiler", "%s (%s)" % (m9c, ver))
    if WINDOWS:
        step("cells", "each runs as its own program (no session on Windows)")
    else:
        step("cells", "library cells keep their state in a session"
             if session else "each runs as its own program (this m9c has no --cell)")
    kind, runner, label = choose_runner(args)
    step("kernel runs under", label)
    data = data_dir(args, kind, runner)
    target = os.path.join(data, "kernels", "m9")
    step("registered in", target)
    say()
    if not ask("Install the M9 kernel there?", args.yes):
        say("  nothing was installed")
        return

    os.makedirs(target, exist_ok=True)
    with open(os.path.join(target, "kernel.json"), "w", encoding="utf-8") as f:
        json.dump(kernel_json(runner, m9c), f, indent=2)
        f.write("\n")
    say("  installed: %s" % os.path.join(target, "kernel.json"))

    if args.highlight:
        ok, why = install_highlight()
        say("  highlighting: %s" % ("installed into %s" % sys.executable if ok else "NOT installed\n" + why))

    if args.check:
        say("  checking: one cell through the kernel (the first build takes a while) ...")
        ok, why = check(kind, runner, data)
        if not ok:
            fail("the kernel was installed but did not answer a cell:\n" + why)
        say("  checked: a cell ran and printed its line")

    say()
    say("Start JupyterLab and choose the M9 kernel, for example:")
    say("    uvx --from jupyterlab jupyter lab %s" % os.path.join(HERE, "M9Notebook.ipynb"))
    if not args.highlight:
        say("With highlighting:")
        say("    uvx --from jupyterlab --with %s jupyter lab" % os.path.join(HERE, "highlight"))


if __name__ == "__main__":
    main()
