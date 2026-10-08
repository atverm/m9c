#!/usr/bin/env python3
"""sabotage M9C PYTHON -- shows the smtp gate able to fail.

Each entry below is one small edit to a COPY of corpus/Smtp.m9 that
breaks one property the gate claims to hold.  For each: run smtp.sh
with the copy as the library, and require it to FAIL.  A sabotage the
gate passes is a property the gate does not hold, and this script
exits 1 naming it.

Not run by CI; run it after changing Smtp or the fixture, from
runtime/test/smtpfix:

    ./sabotage.py ../../../out/m9c PYTHON-WITH-AIOSMTPD [NAME-PART]

docs/library-plan-2.md, item 6.                                     """
import os
import shutil
import subprocess
import sys
import tempfile

M9C = os.path.abspath(sys.argv[1])
PY = sys.argv[2]
ONLY = sys.argv[3] if len(sys.argv) > 3 else ""
HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.abspath(os.path.join(HERE, "../../../corpus"))
GATE = os.path.abspath(os.path.join(HERE, "../smtp.sh"))

SABOTAGES = [
    ("Bcc written in the headers",
     "  Addresses (d, 'Cc', m.cc, m.ncc) ;\n",
     "  Addresses (d, 'Cc', m.cc, m.ncc) ;\n  Addresses (d, 'Bcc', m.bcc, m.nbcc) ;\n"),
    ("Bcc left out of the envelope",
     "    FOR i := 0 TO m.nbcc - 1 DO\n      Cmd (c, 'RCPT TO:<' + m.bcc[i] + '>') ;",
     "    FOR i := 0 TO -1 DO\n      Cmd (c, 'RCPT TO:<' + m.bcc[i] + '>') ;"),
    # not here: dot-stuffing -- every part is base64 and no header
    # begins with a dot, so the wire never carries a line to stuff;
    # SmtpTest holds Stuffed on text directly
    ("the subject's non-ASCII sent raw",
     "  IF IsAscii (m.subject) THEN DynStr.Append (d, m.subject)",
     "  IF TRUE THEN DynStr.Append (d, m.subject)"),
    ("a folded subject word over the line",
     "  room := 63 - LEN ('Subject: ') + 1 ;", "  room := 63 ;"),
    ("the attachment's octets shifted",
     "  FOR i := 0 TO LEN (data) - 1 DO copy[i] := data[i] END ;",
     "  FOR i := 0 TO LEN (data) - 2 DO copy[i] := data[i + 1] END ;"),
    ("the text part not base64",
     "  DynStr.Append (d, 'Content-Transfer-Encoding: base64') ;\n  CrLf (d) ;\n  CrLf (d) ;\n  Lines (d, Text.ToBase64 (DynStr.Utf8 (scratch, text)))",
     "  CrLf (d) ;\n  Lines (d, Text.ToBase64 (DynStr.Utf8 (scratch, text)))"),
    ("AUTH PLAIN's identity without its first NUL",
     "    ident := NEW (scratch, BYTE, LEN (u) + LEN (p) + 2) ;\n    ident[0] := 0 ;",
     "    ident := NEW (scratch, BYTE, LEN (u) + LEN (p) + 1) ;\n    ident := SLICE (ident, 0, LEN (ident)) ;"),
    ("LOGIN's user and password swapped",
     "    Cmd (c, Text.ToBase64 (u)) ;\n    Need (c, 334, 'AUTH LOGIN, the user', text) ;\n    Cmd (c, Text.ToBase64 (p)) ;",
     "    Cmd (c, Text.ToBase64 (p)) ;\n    Need (c, 334, 'AUTH LOGIN, the user', text) ;\n    Cmd (c, Text.ToBase64 (u)) ;"),
    ("a 4xx taken for success",
     "  IF (want = 2 AND code DIV 100 # 2) OR (want # 2 AND code # want) THEN",
     "  IF (want = 2 AND code DIV 100 = 5) OR (want # 2 AND code # want) THEN"),
    ("STARTTLS not offered, sent plain anyway",
     "      IF NOT Offers (ehlo, 'STARTTLS') THEN",
     "      IF FALSE THEN"),
    ("STARTTLS's handshake skipped",
     "      h := I64 (TlsWrap (C.Int (c.fd), ADR (hz))) ;",
     "      h := -1 ;"),
    ("the second EHLO after STARTTLS skipped",
     "      Cmd (c, Ehlo) ;\n      Need (c, 250, 'EHLO after STARTTLS', ehlo)\n",
     "      ehlo := ehlo\n"),
    ("a reply read only to its first line",
     "           IsDigit (buf[ls + 2]) AND I64 (buf[ls + 3]) = 32 THEN",
     "           IsDigit (buf[ls + 2]) THEN"),
    ("the reply code not reported",
     "    RAISE Error ('smtp: ' + stage + ': ' + Text.Trim (text), code)",
     "    RAISE Error ('smtp: ' + stage + ': ' + Text.Trim (text), 0)"),
]


def run(name, old, new):
    src = open(os.path.join(CORPUS, "Smtp.m9")).read()
    if src.count(old) != 1:
        print(f"sabotage '{name}': the text to break occurs {src.count(old)} times; the list is stale")
        return False
    lib = tempfile.mkdtemp(prefix="m9smtp-sab-")
    for f in os.listdir(CORPUS):
        if f.endswith(".m9"):
            shutil.copy(os.path.join(CORPUS, f), lib)
    open(os.path.join(lib, "Smtp.m9"), "w").write(src.replace(old, new))
    env = dict(os.environ, M9C=M9C, SMTPFIX_PY=PY, M9LIBRARY_OVERRIDE=lib)
    r = subprocess.run([GATE], env=env, capture_output=True, text=True)
    shutil.rmtree(lib)
    ok = r.returncode != 0
    print(f"{'red' if ok else 'STILL GREEN'}: {name}")
    if not ok:
        print(r.stdout[-2000:])
    return ok


if __name__ == "__main__":
    bad = 0
    n = 0
    for name, old, new in SABOTAGES:
        if ONLY and ONLY not in name:
            continue
        n += 1
        if not run(name, old, new):
            bad += 1
    print(f"sabotage: {n - bad} of {n} red")
    sys.exit(1 if bad else 0)
