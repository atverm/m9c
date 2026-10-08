#!/usr/bin/env python3
"""smtpfix -- the SMTP server runtime/test/smtp.sh's driver sends to,
and the judge of what arrived (docs/library-plan-2.md, item 6).

    smtpfix.py serve PLAIN_PORT LOGIN_PORT TLS_PORT STARTTLS_PORT CERT KEY OUTDIR
    smtpfix.py judge OUTDIR SENT

serve: four aiosmtpd servers -- plain with AUTH (PLAIN and LOGIN
offered, the account m9 / secret), plain offering LOGIN only,
implicit TLS, and plain with STARTTLS required -- each writing every message it accepts as
OUTDIR/NNN.eml with its envelope in OUTDIR/NNN.env; until SIGTERM.
The plain server also REFUSES a recipient named reject@ with 550 and
answers 451 to a MAIL FROM temp@, so the driver meets a 5xx and a 4xx.

judge: SENT is what the driver says it sent (smtpfix/SmtpFix.m9 prints
a line per message: `sent TAG N from to,... | subject | body | attach |
auth`), and
the .eml files are parsed by Python's email: the subject decoded, the
text body, every attachment's octets, the recipients, the dot-stuffed
line -- each must be what was sent."""
import email
import email.policy
import os
import signal
import ssl
import sys
import threading

from aiosmtpd.controller import Controller
from aiosmtpd.smtp import AuthResult, LoginPassword


class Recorder:
    def __init__(self, out, tag, reject):
        self.out, self.tag, self.reject = out, tag, reject
        self.n = 0

    async def handle_MAIL(self, server, session, envelope, address, mail_options):
        if self.reject and address.startswith("temp@"):
            return "451 try again later"
        envelope.mail_from = address
        envelope.mail_options.extend(mail_options)
        return "250 OK"

    async def handle_RCPT(self, server, session, envelope, address, rcpt_options):
        if self.reject and address.startswith("reject@"):
            return "550 no such user"
        envelope.rcpt_tos.append(address)
        return "250 OK"

    async def handle_DATA(self, server, session, envelope):
        self.n += 1
        base = os.path.join(self.out, f"{self.tag}{self.n:03d}")
        with open(base + ".eml", "wb") as f:
            f.write(envelope.content)
        with open(base + ".env", "w") as f:
            f.write(envelope.mail_from + "\n" + " ".join(envelope.rcpt_tos) + "\n" +
                    ("auth" if session.authenticated else "noauth") + "\n")
        return "250 Message accepted for delivery"


def authenticator(server, session, envelope, mechanism, auth_data):
    if isinstance(auth_data, LoginPassword) and auth_data.login == b"m9" and auth_data.password == b"secret":
        return AuthResult(success=True)
    return AuthResult(success=False, handled=False)


def serve(args):
    plain, login, tls, starttls = int(args[0]), int(args[1]), int(args[2]), int(args[3])
    cert, key, out = args[4], args[5], args[6]
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(cert, key)
    c1 = Controller(Recorder(out, "p", True), hostname="127.0.0.1", port=plain,
                    authenticator=authenticator, auth_require_tls=False, auth_required=False)
    c2 = Controller(Recorder(out, "l", False), hostname="127.0.0.1", port=login,
                    authenticator=authenticator, auth_require_tls=False, auth_required=False,
                    auth_exclude_mechanism=["PLAIN"])
    # auth_require_tls=False: aiosmtpd 1.4 does not read an implicit-TLS
    # transport as encrypted and would answer AUTH with 538
    c3 = Controller(Recorder(out, "t", False), hostname="127.0.0.1", port=tls, ssl_context=ctx,
                    authenticator=authenticator, auth_require_tls=False, auth_required=False)
    c4 = Controller(Recorder(out, "s", False), hostname="127.0.0.1", port=starttls, tls_context=ctx,
                    require_starttls=True, authenticator=authenticator, auth_required=False)
    for c in (c1, c2, c3, c4):
        c.start()
    print("smtpfix: serving", flush=True)
    stop = threading.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *a: stop.set())
    stop.wait()
    for c in (c1, c2, c3, c4):
        c.stop()


def judge(args):
    out, sent = args[0], args[1]
    fails = 0
    checks = 0

    def ck(ok, what):
        nonlocal fails, checks
        checks += 1
        if not ok:
            fails += 1
            print("FAIL:", what)

    expected = {}
    for line in open(sent, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.startswith("sent "):
            continue
        head, subject, body, attach, auth = line[5:].split(" | ")
        tag, n, frm, rcpts = head.split(" ", 3)
        expected[tag + n.zfill(3)] = (frm, rcpts.split(","), subject, body.replace("\\n", "\n"), attach, auth)
    names = sorted(f[:-4] for f in os.listdir(out) if f.endswith(".eml"))
    ck(sorted(expected) == names, f"the messages that arrived are the ones sent: {names} vs {sorted(expected)}")
    for name in names:
        if name not in expected:
            continue
        frm, rcpts, subject, body, attach, auth = expected[name]
        msg = email.message_from_bytes(open(os.path.join(out, name + ".eml"), "rb").read(), policy=email.policy.default)
        env = open(os.path.join(out, name + ".env")).read().split("\n")
        ck(env[0] == frm, f"{name}: envelope from {env[0]!r}, sent {frm!r}")
        ck(env[1].split() == rcpts, f"{name}: envelope recipients {env[1]!r}, sent {rcpts}")
        ck(env[2] == auth, f"{name}: the session was {env[2]}, the driver said {auth}")
        ck(msg["Subject"] == subject, f"{name}: subject {msg['Subject']!r}, sent {subject!r}")
        ck(msg["From"] == frm, f"{name}: From {msg['From']!r}")
        ck(msg["Date"] is not None and msg["Message-ID"] is not None, f"{name}: Date and Message-ID present")
        raw = open(os.path.join(out, name + ".eml"), "rb").read()
        head = raw.split(b"\r\n\r\n", 1)[0].split(b"\r\n")
        long_ = [l for l in head if len(l) > 78]
        ck(not long_, f"{name}: a header line over 78 (RFC 5322 par 2.1.1): {long_[:1]}")
        text = msg.get_body(preferencelist=("plain",))
        got = text.get_content() if text is not None else None
        ck(got == body, f"{name}: body {got!r}, sent {body!r}")
        atts = [(p.get_filename(), p.get_content_type(), p.get_payload(decode=True))
                for p in msg.iter_attachments()]
        if attach == "-":
            ck(not atts, f"{name}: no attachment, got {[a[0] for a in atts]}")
        else:
            aname, actype, asize = attach.split(":")
            ck(len(atts) == 1 and atts[0][0] == aname and atts[0][1] == actype and
               len(atts[0][2]) == int(asize) and all(atts[0][2][i] == (i * 7 + 3) % 256 for i in range(int(asize))),
               f"{name}: the attachment {aname} of {asize} octets as sent: got {[(a[0], a[1], len(a[2])) for a in atts]}")
        for r in rcpts:
            if r.startswith("bcc"):
                ck("Bcc" not in msg and r not in (msg["To"] or "") and r not in (msg["Cc"] or ""),
                   f"{name}: {r} in the envelope only")
    print(f"smtpfix: {'PASS' if not fails else 'FAIL'} ({checks} checks{'' if not fails else ', ' + str(fails) + ' failed'})")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    {"serve": serve, "judge": judge}[sys.argv[1]](sys.argv[2:])
