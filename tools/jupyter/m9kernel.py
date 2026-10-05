"""M9 for Jupyter: a wrapper kernel around `m9c --run`.

EVERY CELL IS A WHOLE MODULE, and that is the design, not a gap.  A
cell that begins `MODULE Name` is a program: it is written to the
notebook's module directory, checked, compiled and run by
`m9c --run`, and what it prints is the cell's output.  A cell that
begins `DEFINITION MODULE Name` is a library: it is written beside
the programs, CHECKED, and from then on any later cell can IMPORT it
-- code is shared between cells by the language's own means.  Values
are not: nothing a program computed survives it.  Data travels
between cells through files, as it does between the steps of any
pipeline M9 is written for (a Frame to Parquet or Arrow, a figure to
SVG), and every dependency of a cell is in its text.  That is the
stateless mode (Windows, or M9KERNEL_STATELESS=1).  On Linux and
macOS a library cell is a STATE cell instead: its module lives in a
session process and later cells read its exported variables in
memory (see Session below).

A FIGURE IS A FILE.  Any .svg or .png the cell wrote, in the working
directory or one directory below it, during the run, is shown under
the cell -- Plot writes SVG, Png writes PNG, nothing in M9 needs to
know about Jupyter.

The checker's diagnostics come back with the cell's own line numbers:
the cell is written verbatim, so line N of the file is line N of the
cell.  This file is glue -- it carries a cell to m9c and the answer
back -- and computes nothing.  Gate: runtime/test/jupyter.sh.
"""

import base64
import hashlib
import json
import os
import queue
import re
import shutil
import signal
import subprocess
import tempfile
import threading

from ipykernel.kernelbase import Kernel

__version__ = "0.1.0"

HEAD = re.compile(
    r"\b(DEFINITION\s+MODULE|IMPLEMENTATION\s+MODULE|MODULE)\s+([A-Za-z][A-Za-z0-9]*)")


def strip_comments(src):
    """The text with M9 comments (nested) and strings blanked, so that
    the heading is found where the lexer would find it."""
    out = []
    i, depth, n = 0, 0, len(src)
    if src.startswith("#!"):
        j = src.find("\n")
        i = n if j < 0 else j
    while i < n:
        c = src[i]
        if depth == 0 and c in "'\"":
            j = src.find(c, i + 1)
            j = n if j < 0 else j + 1
            out.append(" " * (j - i))
            i = j
        elif src.startswith("(*", i):
            depth += 1
            out.append("  ")
            i += 2
        elif depth > 0 and src.startswith("*)", i):
            depth -= 1
            out.append("  ")
            i += 2
        else:
            out.append(c if depth == 0 or c == "\n" else " ")
            i += 1
    return "".join(out)


def heading(src):
    """('program' | 'library', Name) or None"""
    m = HEAD.search(strip_comments(src))
    if m is None:
        return None
    kind = "program" if m.group(1) == "MODULE" else "library"
    return kind, m.group(2)


def figures(root):
    """{path: mtime} of the .svg and .png files under root and one
    directory below it (hidden directories skipped)"""
    found = {}
    for dirpath, dirs, files in os.walk(root):
        depth = os.path.relpath(dirpath, root).count(os.sep)
        dirs[:] = [d for d in dirs if not d.startswith(".")] if depth < 1 else []
        for f in files:
            if f.lower().endswith((".svg", ".png")):
                p = os.path.join(dirpath, f)
                try:
                    found[p] = os.stat(p).st_mtime_ns
                except OSError:
                    pass
    return found


def stored(cells):
    """{name: (kind, mtime)} of what NbCells holds in `cells`: its files
    are NAME.KIND.parquet (corpus/NbCells.m9)"""
    found = {}
    try:
        entries = os.listdir(cells)
    except OSError:
        return found
    for f in entries:
        parts = f.split(".")
        if len(parts) == 3 and parts[2] == "parquet":
            try:
                found[parts[0]] = (parts[1], os.stat(os.path.join(cells, f)).st_mtime_ns)
            except OSError:
                pass
    return found


END = b"\x01M9 END\x01\n"


class Session:
    """The session host (runtime/m9session.c): state cells live in it,
    program cells run in a fork of it.  Commands go to its stdin; each answer comes on a pipe of
    its own; a cell's stdout and stderr stream as they arrive and end
    at a marker line the host writes after every command."""

    def __init__(self, host):
        r, w = os.pipe()
        self.proc = subprocess.Popen([host, str(w)], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     pass_fds=(w,), bufsize=0)
        os.close(w)
        self.q = queue.Queue()
        for f, tag in ((os.fdopen(r, "rb", 0), "ctl"), (self.proc.stdout, "stdout"),
                       (self.proc.stderr, "stderr")):
            threading.Thread(target=self._pump, args=(f, tag), daemon=True).start()
        self.loaded = set()

    def _pump(self, f, tag):
        for line in iter(f.readline, b""):
            self.q.put((tag, line))
        self.q.put((tag, None))

    def command(self, words, emit):
        """send one command; emit (stream, text) for the cell's output;
        answer the host's answer line"""
        self.proc.stdin.write(("\t".join(words) + "\n").encode("utf-8"))
        self.proc.stdin.flush()
        answer, ends = None, 0
        while answer is None or ends < 2:
            try:
                tag, line = self.q.get()
            except KeyboardInterrupt:
                self.proc.send_signal(signal.SIGINT)
                continue
            if line is None:
                raise RuntimeError("the session host ended")
            if tag == "ctl":
                answer = line.decode("utf-8", "replace").rstrip("\n")
            elif line == END:
                ends += 1
            else:
                emit(tag, line.decode("utf-8", "replace"))
        return answer

    def close(self):
        try:
            self.proc.stdin.write(b"QUIT\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


class M9Kernel(Kernel):
    implementation = "m9kernel"
    implementation_version = __version__
    language = "m9"
    language_version = "0.15"
    language_info = {
        "name": "m9",
        "mimetype": "text/x-m9",
        "file_extension": ".m9",
        "pygments_lexer": "modula2",
        "codemirror_mode": "m9",
    }
    banner = ("M9 -- every cell is a whole module: MODULE runs, "
              "DEFINITION MODULE defines what later cells import")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.m9c = os.environ.get("M9C") or shutil.which("m9c") or "m9c"
        self.moddir = tempfile.mkdtemp(prefix="m9kernel-")
        # WHERE NbCells KEEPS WHAT CELLS HAND ON: NOTEBOOK.m9data beside
        # the notebook.  Jupyter's server tells a kernel which notebook
        # it serves in JPY_SESSION_NAME; a client that does not (nbclient
        # running a file) gets notebook.m9data.  A $M9CELLS the notebook
        # was started with wins, as it does for any M9 program.
        if not os.environ.get("M9CELLS"):
            stem = os.path.splitext(os.path.basename(
                os.environ.get("JPY_SESSION_NAME", "") or "notebook"))[0]
            os.environ["M9CELLS"] = os.path.join(os.getcwd(), stem + ".m9data")
        self.cells = os.environ["M9CELLS"]
        self.silent = False
        self.decls = {}       # module name -> (source mtime, declarations)
        # in-memory state needs fork and dlopen; elsewhere, or when asked,
        # every cell is a separate program as before (decision 4)
        self.stateful = os.name == "posix" and not os.environ.get("M9KERNEL_STATELESS")
        self.m9session = None
        self.inited = {}      # state cell module -> its shared object
        self.closure = {}     # state cell module -> the modules its list loads
        self.gens = {}        # state cell module -> its generation, past 1
        self.ran = {}         # program module -> (its cell's execution
                              # count, {state module: generation it read})
        self.labels = {}      # expression cell's program -> its text, short
        self.showbuf = None   # an expression cell's stdout, while it runs

    # ---- what a module exports: m9c --json, never a second parser ---------
    #
    # Completion and inspection answer from the compiler's own account of
    # a module -- `m9c --json`, the data docs/modules is rendered from and
    # the VS Code extension reads -- so they cannot disagree with what the
    # checker will accept.  Cached per module by its source's mtime; a
    # library cell run again rewrites its file, and so its entry.

    def _libdirs(self):
        """where m9c would look for a module, in its order: the cells'
        own modules first, then $M9LIBRARY, then the library installed
        beside this m9c (its lib/m9), else the package's"""
        dirs = [self.moddir]
        dirs += [d for d in os.environ.get("M9LIBRARY", "").split(os.pathsep) if d]
        exe = shutil.which(self.m9c) or self.m9c
        own = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(exe))),
                           "lib", "m9")
        dirs.append(own if os.path.isdir(own) else "/usr/lib/m9")
        return dirs

    def _source(self, name):
        for d in self._libdirs():
            p = os.path.join(d, name + ".m9")
            if os.path.isfile(p):
                return p
        return None

    def _modules(self):
        """every module with a DEFINITION part on the search path"""
        names = set()
        for d in self._libdirs():
            try:
                entries = os.listdir(d)
            except OSError:
                continue
            for f in entries:
                if f.endswith(".m9") and not f.endswith("Test.m9"):
                    try:
                        with open(os.path.join(d, f), encoding="utf-8",
                                  errors="replace") as h:
                            head = heading(h.read(8192))
                    except OSError:
                        continue
                    if head is not None and head[0] == "library":
                        names.add(f[:-3])
        return sorted(names)

    def _declarations(self, name):
        path = self._source(name)
        if path is None:
            return None
        mtime = os.stat(path).st_mtime_ns
        hit = self.decls.get(name)
        if hit is not None and hit[0] == mtime:
            return hit[1]
        work = tempfile.mkdtemp(prefix="m9kernel-json-")
        try:
            r = subprocess.run([self.m9c, "--json", "-I", self.moddir, path],
                               cwd=work, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode != 0:
                return None
            with open(os.path.join(work, name + ".json"), encoding="utf-8") as f:
                doc = json.load(f)
        except (OSError, ValueError):
            return None
        finally:
            shutil.rmtree(work, ignore_errors=True)
        self.decls[name] = (mtime, doc)
        return doc

    @staticmethod
    def _heading_of(decl):
        """the declaration as its DEFINITION spells it"""
        if decl.get("signature"):
            return decl["signature"]
        kind = decl.get("kind", "")
        if kind == "exception":
            return "EXCEPTION " + decl["name"]
        if kind == "var" and decl.get("type"):
            return "VAR %s%s : %s" % ("RO " if decl.get("ro") else "",
                                      decl["name"], decl["type"])
        return "%s %s" % (kind.upper(), decl["name"])

    def do_complete(self, code, cursor_pos):
        text = code[:cursor_pos]
        matches, start, types = [], cursor_pos, []
        m = re.search(r"([A-Za-z][A-Za-z0-9]*)\.([A-Za-z0-9]*)$", text)
        if m:
            doc = self._declarations(m.group(1))
            prefix = m.group(2)
            start = cursor_pos - len(prefix)
            if doc is not None:
                for d in sorted(doc.get("declarations", []), key=lambda d: d["name"]):
                    if d["name"].startswith(prefix) and d["name"] not in matches:
                        matches.append(d["name"])
                        types.append({"start": start, "end": cursor_pos,
                                      "text": d["name"], "type": d.get("kind", ""),
                                      "signature": self._heading_of(d)})
        else:
            m = re.search(r"([A-Za-z][A-Za-z0-9]*)$", text)
            if m:
                start = cursor_pos - len(m.group(1))
                matches = [n for n in self._modules() if n.startswith(m.group(1))]
                types = [{"start": start, "end": cursor_pos, "text": n,
                          "type": "module"} for n in matches]
        return {"status": "ok", "matches": matches, "cursor_start": start,
                "cursor_end": cursor_pos,
                "metadata": {"_jupyter_types_experimental": types}}

    def do_inspect(self, code, cursor_pos, detail_level=0, omit_sections=()):
        """Module.Name under or just before the cursor: its heading, its
        RAISES and its doc comment; a bare Module: its own doc and what
        it exports"""
        left = cursor_pos
        while left > 0 and (code[left - 1].isalnum() or code[left - 1] == "."):
            left -= 1
        right = cursor_pos
        while right < len(code) and code[right].isalnum():
            right += 1
        word = code[left:right].strip(".")
        found = False
        text = ""
        parts = word.split(".")
        if len(parts) >= 1 and parts[0]:
            doc = self._declarations(parts[0])
            if doc is not None and len(parts) >= 2:
                for d in doc.get("declarations", []):
                    if d["name"] == parts[1]:
                        found = True
                        text = "%s.%s\n\n%s" % (parts[0], self._heading_of(d),
                                                d.get("doc") or "(undocumented)")
                        text += "\n\n-- %s, line %s" % (parts[0], d.get("line"))
                        break
            elif doc is not None:
                found = True
                names = ", ".join(d["name"] for d in doc.get("declarations", []))
                text = "MODULE %s\n\n%s\n\nexports: %s" % (
                    parts[0], doc.get("doc") or "(undocumented)", names)
        return {"status": "ok", "found": found,
                "data": {"text/plain": text} if found else {}, "metadata": {}}

    # ---- output -------------------------------------------------------

    def _showing(self):
        """collect the program's stdout instead of streaming it"""
        self.showbuf = []

    def _shown(self):
        """the collected stdout as the cell's output: a table's HTML,
        between NbShow's marker lines, becomes one display_data with the
        text beside it as text/plain; anything else is a stream"""
        out, self.showbuf = "".join(self.showbuf), None
        start, end = "\x01M9 HTML\x01\n", "\x01M9 /HTML\x01\n"
        i = out.find(start)
        j = out.find(end, i + 1) if i >= 0 else -1
        if i < 0 or j < 0:
            self._stream("stdout", out)
            return
        text, html = out[:i], out[i + len(start):j]
        if not self.silent:
            self.send_response(self.iopub_socket, "display_data",
                               {"data": {"text/plain": text.rstrip("\n"),
                                         "text/html": html},
                                "metadata": {}})
        self._stream("stdout", out[j + len(end):])

    def _stream(self, name, text):
        if name == "stdout" and self.showbuf is not None:
            self.showbuf.append(text)
            return
        if text and not self.silent:
            self.send_response(self.iopub_socket, "stream",
                               {"name": name, "text": text})

    def _show(self, path):
        if self.silent:
            return
        try:
            if path.lower().endswith(".svg"):
                with open(path, encoding="utf-8") as f:
                    data = {"image/svg+xml": f.read()}
            else:
                with open(path, "rb") as f:
                    data = {"image/png": base64.b64encode(f.read()).decode("ascii")}
        except OSError as e:
            self._stream("stderr", "m9kernel: could not read %s: %s\n" % (path, e))
            return
        data["text/plain"] = os.path.relpath(path)
        self.send_response(self.iopub_socket, "display_data",
                           {"data": data, "metadata": {}})

    def _tidy(self, text):
        # the module directory is the kernel's business, not the reader's,
        # and so is the name of the program around an expression cell
        text = text.replace(self.moddir + os.sep, "")
        return re.sub(r"Show[0-9a-f]{10} body: ", "", text)

    # ---- running m9c ----------------------------------------------------

    def _run(self, argv):
        """run argv, streaming both streams as they arrive; the status"""
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                bufsize=0)
        q = queue.Queue()

        def pump(f, name):
            for line in iter(f.readline, b""):
                q.put((name, line.decode("utf-8", "replace")))
            q.put((name, None))

        for f, name in ((proc.stdout, "stdout"), (proc.stderr, "stderr")):
            threading.Thread(target=pump, args=(f, name), daemon=True).start()
        open_streams = 2
        try:
            while open_streams:
                name, text = q.get()
                if text is None:
                    open_streams -= 1
                else:
                    self._stream(name, self._tidy(text))
            return proc.wait()
        except KeyboardInterrupt:
            proc.send_signal(signal.SIGINT)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            self._stream("stderr", "m9kernel: interrupted\n")
            return -signal.SIGINT

    def do_execute(self, code, silent, store_history=True, user_expressions=None,
                   allow_stdin=False):
        self.silent = silent
        if not code.strip():
            return self._ok()
        head = heading(code)
        if head is None:
            # no MODULE heading: an EXPRESSION cell, shown by the NbShow
            # procedure for its type (m9c --show).
            # Named from its text, so the same cell run again is the same
            # program to the cache and to the out-of-date notice.
            kind = "show"
            name = "Show" + hashlib.sha1(code.strip().encode("utf-8")).hexdigest()[:10]
            first = code.strip().splitlines()[0]
            self.labels[name] = first if len(first) <= 40 else first[:37] + "..."
        else:
            kind, name = head
        if self.stateful:
            return self._execute_in_session(code, kind, name)
        path = os.path.join(self.moddir, name + ".m9")
        with open(path, "w", encoding="utf-8") as f:
            f.write(code if code.endswith("\n") else code + "\n")
        if kind == "show":
            self._showing()
            rc = self._run([self.m9c, "--show", "--run", path])
            self._shown()
            return self._ok() if rc == 0 else self._error("the expression was not shown")
        if kind == "library":
            rc = self._run([self.m9c, "--check", path])
            if rc == 0:
                self._stream("stdout", "module %s checked; later cells may IMPORT it\n" % name)
                return self._ok()
            return self._error("%s refused" % name)
        # a figure is a file this run WROTE: new, or with another mtime
        # than before it -- not one an earlier cell left behind
        before = figures(os.getcwd())
        held = stored(self.cells)
        rc = self._run([self.m9c, "--run", path])
        after = figures(os.getcwd())
        for p in sorted(after, key=lambda q: (after[q], q)):
            if before.get(p) != after[p]:
                self._show(p)
        # and what it handed on through NbCells, by name and kind
        now = stored(self.cells)
        put = [n for n in sorted(now) if held.get(n) != now[n]]
        if put:
            self._stream("stdout", "stored: %s\n" % ", ".join(
                "%s (%s)" % (n, now[n][0]) for n in put))
        if rc == 0:
            return self._ok()
        return self._error("%s exited with status %d" % (name, rc))

    # ---- the session: state cells and program cells (phase 1) ---------

    def _emit(self, tag, text):
        self._stream(tag, self._tidy(text))

    def _prefixes(self):
        """--prefix MOD=MOD_gN for every state cell past its first run"""
        args = []
        for m, n in self.gens.items():
            if n > 1:
                args += ["--prefix", "%s=%s_g%d" % (m, m, n)]
        return args

    def _build(self, name, show=False):
        """m9c --cell for the module file `name` (an expression with
        --show): the load list, or None having said why"""
        path = os.path.join(self.moddir, name + ".m9")
        try:
            r = subprocess.run([self.m9c] + self._prefixes() +
                               (["--show"] if show else []) + ["--cell", path],
                               stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except KeyboardInterrupt:
            # interrupted while m9c was still building the cell: nothing
            # ran, the session is untouched (seen on CI's cold cache)
            self._stream("stderr", "m9kernel: interrupted while building %s\n" % name)
            return None
        if r.stderr:
            self._stream("stderr", self._tidy(r.stderr.decode("utf-8", "replace")))
        if r.returncode != 0:
            return None
        return [l.split("\t") for l in r.stdout.decode("utf-8").splitlines() if l]

    def _load_libs(self, lines):
        """the session started, and every library of the list loaded;
        None, or why not"""
        if self.m9session is None:
            self.m9session = Session(lines[0][1])
        for fields in lines[1:]:
            if fields[0] == "LIB" and fields[1] not in self.m9session.loaded:
                ans = self.m9session.command(["LOAD", fields[1]], self._emit)
                if ans != "OK":
                    return "could not load %s: %s" % (fields[1], ans)
                self.m9session.loaded.add(fields[1])
        return None

    def _run_state(self, name):
        """build the state cell `name` at its current generation, load it
        and run its body; None, or why not"""
        lines = self._build(name)
        if lines is None:
            return "%s refused" % name
        why = self._load_libs(lines)
        if why is not None:
            return why
        last = lines[-1]
        ans = self.m9session.command(["INIT", last[1], last[2]], self._emit)
        self.m9session.loaded.add(last[1])
        if ans != "OK":
            return "the body of %s raised %s" % (name, ans[4:])
        self.inited[name] = last[1]
        self.closure[name] = {os.path.basename(f[1])[3:-3] for f in lines[1:-1]
                              if f[0] == "LIB"}
        return None

    def _execute_in_session(self, code, kind, name):
        """A library cell is a STATE cell: built as a shared object,
        loaded into the session, its body run there once.  A program
        cell runs in a fork of the session and sees every state cell's
        values as they are.

        RUN AGAIN, a state cell becomes a new GENERATION (C names
        Mod_gN, m9c --prefix), and so does every loaded state cell that
        imports it, re-run after it in the order they were first run
        (Alex, 2026-10-04: "rerun dependents" -- the notebook mistake of
        a cell computed from a dependency that has since changed is the
        one this makes impossible).  Old generations stay loaded and
        nothing compiled later refers to them."""
        path = os.path.join(self.moddir, name + ".m9")
        try:
            if kind == "library":
                rerun = name in self.inited
                with open(path, "w", encoding="utf-8") as f:
                    f.write(code if code.endswith("\n") else code + "\n")
                if not rerun:
                    why = self._run_state(name)
                    if why is not None:
                        return self._error(why)
                    self._stream("stdout", "module %s loaded; its body ran once in "
                                 "this session, and later cells may IMPORT it\n" % name)
                    return self._ok()
                deps = [m for m in self.inited if m != name and name in self.closure[m]]
                for m in [name] + deps:
                    self.gens[m] = self.gens.get(m, 1) + 1
                for m in [name] + deps:
                    why = self._run_state(m)
                    if why is not None:
                        return self._error(why)
                    if m == name:
                        self._stream("stdout", "module %s ran again (generation %d)\n"
                                     % (m, self.gens[m]))
                    else:
                        self._stream("stdout", "re-ran %s (generation %d), which imports "
                                     "%s\n" % (m, self.gens[m], name))
                # program cells are not re-run, but each one that read
                # what has just changed is named, with its cell number:
                # its output is from the old values
                stale = sorted((n, c) for n, (c, read) in self.ran.items()
                               if any(read.get(m, self.gens[m]) < self.gens[m]
                                      for m in [name] + deps))
                if stale:
                    self._stream("stdout", "out of date, they read the old values -- run "
                                 "them again: %s\n" % ", ".join(
                                     "%s [%d]" % (self.labels.get(n, n), c)
                                     for n, c in stale))
                return self._ok()
            with open(path, "w", encoding="utf-8") as f:
                f.write(code if code.endswith("\n") else code + "\n")
            lines = self._build(name, show=(kind == "show"))
            if lines is None:
                return self._error("the expression was not shown" if kind == "show"
                                   else "%s refused" % name)
            why = self._load_libs(lines)
            if why is not None:
                return self._error(why)
            last = lines[-1]
            before = figures(os.getcwd())
            held = stored(self.cells)
            if kind == "show":
                self._showing()
            ans = self.m9session.command(["RUN", last[1], last[2]], self._emit)
            if kind == "show":
                self._shown()
            read = {os.path.basename(f[1])[3:-3] for f in lines[1:-1] if f[0] == "LIB"}
            self.ran[name] = (self.execution_count,
                              {m: self.gens.get(m, 1) for m in read if m in self.inited})
        except RuntimeError as e:
            self.m9session = None
            self.inited = {}
            self.closure = {}
            self.gens = {}
            self.ran = {}
            return self._error("%s -- the session is gone; restart the kernel" % e)
        after = figures(os.getcwd())
        for p in sorted(after, key=lambda q: (after[q], q)):
            if before.get(p) != after[p]:
                self._show(p)
        now = stored(self.cells)
        put = [n for n in sorted(now) if held.get(n) != now[n]]
        if put:
            self._stream("stdout", "stored: %s\n" % ", ".join(
                "%s (%s)" % (n, now[n][0]) for n in put))
        rc = int(ans.split()[1]) if ans.startswith("STATUS") else -1
        if rc == 0:
            return self._ok()
        if kind == "show":
            return self._error("the expression was not shown")
        return self._error("%s exited with status %d" % (name, rc))

    def _ok(self):
        return {"status": "ok", "execution_count": self.execution_count,
                "payload": [], "user_expressions": {}}

    def _error(self, why):
        # said on iopub as well as in the reply: the front end marks the
        # cell failed from the message, and "run all" stops on it
        content = {"ename": "M9", "evalue": why, "traceback": ["M9: " + why]}
        if not self.silent:
            self.send_response(self.iopub_socket, "error", content)
        content.update({"status": "error",
                        "execution_count": self.execution_count})
        return content

    def do_shutdown(self, restart):
        if self.m9session is not None:
            self.m9session.close()
            self.m9session = None
        shutil.rmtree(self.moddir, ignore_errors=True)
        return {"status": "ok", "restart": restart}


if __name__ == "__main__":
    from ipykernel.kernelapp import IPKernelApp
    IPKernelApp.launch_instance(kernel_class=M9Kernel)
