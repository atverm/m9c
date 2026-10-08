#!/usr/bin/env python3
"""The other half of runtime/test/deflate.sh.

    deflatecheck.py make DIR     write the inputs: DIR/NAME.in
    deflatecheck.py check DIR    read what deflateout wrote beside them
    deflatecheck.py png DIR      take apart the pictures pngout wrote
    deflatecheck.py svg DIR GOLD svg2png's figures against Chrome's in GOLD
    deflatecheck.py zip DIR ZIPOUT  archives zipout writes of DIR's inputs, read by zipfile

A compressor is right when somebody else's inflate reads back what went
in.  The somebody else is zlib, through Python: gzip.decompress for
NAME.gz, zlib.decompress for NAME.zz, and a raw inflate for NAME.raw.
`check` prints one line per file and the worst ratio against zlib's own
level 6, and exits 1 if anything is not read back whole."""
import gzip
import os
import random
import struct
import subprocess
import sys
import zipfile
import zlib


def inputs():
    random.seed(20261002)
    rows = "".join("HTM,2024-%02d-%02d,%8.3f,%d\n" % (i % 12 + 1, i % 28 + 1,
                                                    400.0 + random.random() * 30,
                                                    random.randint(0, 9))
                   for i in range(8000)).encode()
    noise = bytes(random.randrange(256) for _ in range(70000))
    far = bytes(random.randrange(256) for _ in range(30000))
    # an image as a PNG holds it: mostly one colour, a few lines
    image = bytearray(b"\xff" * (600 * 400 * 3))
    for k in range(0, len(image), 3 * 601):
        image[k:k + 3] = b"\x1f\x77\xb4"
    out = {
        "empty": b"", "one": b"a", "two": b"ab", "three": b"abc",
        "run": b"z" * 100000,                 # distance one, the longest lengths
        "table": rows, "noise": noise,        # noise: stored blocks
        "far": far * 3,                       # matches 30000 back
        "edge": far + far[:2768] + far,       # a match exactly 32768 back
        "ab": bytes(random.choice(b"ab") for _ in range(50000)),
        "image": bytes(image),
        "big": rows * 40,                     # 9 MB: the window slides many times
    }
    for n in (257, 258, 259, 65535, 65536):
        out["len%d" % n] = bytes([random.randrange(256)]) * n
    return out


def busy(w, h):
    return bytes(v for y in range(h) for x in range(w)
                 for v in ((x * 5 + y) % 256, (y * 9 + x * x) % 256,
                           ((x + y) % 7) * 30))


def figure(w, h):
    out = bytearray()
    for y in range(h):
        for x in range(w):
            if y % 40 == 7 or x % 50 == 9:
                out += b"\x1f\x77\xb4"
            elif y < 4:
                out += bytes([x % 256]) * 3
            else:
                out += b"\xff\xff\xff"
    return bytes(out)


def read_png(raw):
    """a PNG taken apart with nothing but zlib: (width, height, pixels a
    metre or None, the pixels as RGB bytes).  Every chunk's CRC is checked,
    and all five filters are undone -- a reader does not get to choose which
    ones a writer used."""
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG signature"
    at, kinds, idat, head, phys = 8, [], b"", None, None
    while at < len(raw):
        n = int.from_bytes(raw[at:at + 4], "big")
        kind = raw[at + 4:at + 8]
        data = raw[at + 8:at + 8 + n]
        crc = int.from_bytes(raw[at + 8 + n:at + 12 + n], "big")
        assert zlib.crc32(kind + data) == crc, "the CRC of %r" % kind
        kinds.append(kind)
        if kind == b"IHDR":
            head = data
        elif kind == b"pHYs":
            assert not idat, "pHYs after the image data"
            assert data[8] == 1 and data[:4] == data[4:8]
            phys = int.from_bytes(data[:4], "big")
        elif kind == b"IDAT":
            idat += data
        at += 12 + n
    assert at == len(raw) and kinds[0] == b"IHDR" and kinds[-1] == b"IEND"
    w = int.from_bytes(head[:4], "big")
    h = int.from_bytes(head[4:8], "big")
    assert tuple(head[8:13]) == (8, 2, 0, 0, 0), "not 8-bit RGB, plain"
    rows = zlib.decompress(idat)
    step = 3 * w + 1
    assert len(rows) == h * step
    out = bytearray()
    prior = bytes(3 * w)
    for y in range(h):
        kind = rows[y * step]
        line = bytearray(rows[y * step + 1:(y + 1) * step])
        for x in range(3 * w):
            a = line[x - 3] if x >= 3 else 0
            b = prior[x]
            c = prior[x - 3] if x >= 3 else 0
            if kind == 1:
                line[x] = (line[x] + a) % 256
            elif kind == 2:
                line[x] = (line[x] + b) % 256
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) % 256
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc
                                      else b if pb <= pc else c)) % 256
            else:
                assert kind == 0, "filter %d" % kind
        out += line
        prior = bytes(line)
    return w, h, phys, bytes(out)


def check_pngs(where):
    want = {
        "busy.png": (64, 48, None, busy(64, 48)),
        "thin.png": (300, 5, round(72 / 0.0254), busy(300, 5)),
        "figure.png": (640, 400, round(300 / 0.0254), figure(640, 400)),
    }
    bad = 0
    for name in sorted(want):
        raw = open(os.path.join(where, name), "rb").read()
        try:
            got = read_png(raw)
            ok = got == want[name]
            why = "" if ok else "the picture read back is another one"
        except (AssertionError, zlib.error) as e:
            ok, why = False, str(e)
        # a second reader, where there is one
        try:
            from PIL import Image
            import io
            im = Image.open(io.BytesIO(raw))
            pil = im.convert("RGB").tobytes() == want[name][3]
            if want[name][2] is not None:
                pil = pil and round(im.info["dpi"][0]) == round(want[name][2] * 0.0254)
            second = "Pillow agrees" if pil else "PILLOW READS ANOTHER PICTURE"
            ok = ok and pil
        except ImportError:
            second = "no Pillow here"
        print("%s %-10s %7d bytes for %7d of pixels; %s%s"
              % ("ok  " if ok else "FAIL", name, len(raw), len(want[name][3]),
                 second, "" if not why else "; " + why))
        bad += 0 if ok else 1
    print("deflatecheck: %d pictures, %d failed" % (len(want), bad))
    return 1 if bad else 0


def check_svg(where, gold):
    """svg2png's pictures against Chrome's of the same SVG (gold/png/*.png),
    both read by this file's own PNG reader: the mean difference of 255
    and the share of pixels with a channel off by more than 96 -- a shift
    of one pixel triples both (measured 2026-10-03: 1.6 / 0.56% for the
    Taylor diagram, 4.9 / 2.8% shifted)."""
    bad = 0
    for name, ref in (("annual", "annual-chrome.png"),
                      ("columns", "columns-chrome.png"),
                      ("anomaly", "anomaly-chrome.png")):
        mine = read_png(open(os.path.join(where, name + ".png"), "rb").read())
        theirs = read_png(open(os.path.join(gold, ref), "rb").read())
        ok = mine[:2] == theirs[:2]
        why = "" if ok else "another size than Chrome's %dx%d" % theirs[:2]
        if ok:
            a, b = mine[3], theirs[3]
            n = len(a)
            total = sum(abs(a[i] - b[i]) for i in range(n))
            far = sum(1 for i in range(0, n, 3)
                      if max(abs(a[i] - b[i]), abs(a[i + 1] - b[i + 1]),
                             abs(a[i + 2] - b[i + 2])) > 96)
            mean = total / n
            share = far / (n // 3)
            ok = mean < 2.5 and share < 0.01
            why = "mean %.3f of 255, %.3f%% of pixels far off" % (mean, 100 * share)
        print("%s %-8s %s" % ("ok  " if ok else "FAIL", name, why))
        bad += 0 if ok else 1
    # twice the resolution is twice the size
    w2, h2, _, _ = read_png(open(os.path.join(where, "annual144.png"), "rb").read())
    w1, h1, _, _ = read_png(open(os.path.join(where, "annual.png"), "rb").read())
    ok = (w2, h2) == (2 * w1, 2 * h1)
    print("%s at 144 dpi: %dx%d for %dx%d at 72" % ("ok  " if ok else "FAIL", w2, h2, w1, h1))
    bad += 0 if ok else 1
    print("deflatecheck: 3 figures against Chrome, %d failed" % bad)
    return 1 if bad else 0


def check_zip(where, zipout):
    """Zip's writer: zipout packs every input of `where` twice, deflated
    and stored, under names with a directory and one beyond ASCII; zipfile
    reads each archive back -- testzip (every CRC), the names in order,
    method, the time stamped, the flag that says UTF-8, size, CRC, and
    the bytes -- and an empty archive opens with no member."""
    names = sorted(n[:-3] for n in os.listdir(where) if n.endswith(".in"))
    bad = 0
    members = []
    for i, name in enumerate(names):
        member = ("sub/dir/" if i % 3 == 0 else "") + name + (".\u00e9t\u00e9" if i % 4 == 1 else ".in")
        members.append((member, os.path.join(where, name + ".in")))
    for mode in ("deflate", "store", "none"):
        path = os.path.join(where, "zipout-%s.zip" % mode)
        args = [zipout, path, "deflate" if mode == "none" else mode]
        for member, src in ([] if mode == "none" else members):
            args += [member, src]
        r = subprocess.run(args, capture_output=True, text=True)
        if r.returncode != 0:
            print("FAIL zipout %s: %s" % (mode, r.stderr.strip()))
            bad += 1
            continue
        try:
            zf = zipfile.ZipFile(path)
            first = zf.testzip()
        except zipfile.BadZipFile as e:
            print("FAIL %s: zipfile refuses it: %s" % (path, e))
            bad += 1
            continue
        if first is not None:
            print("FAIL %s: testzip: %s" % (path, first))
            bad += 1
        raw = open(path, "rb").read()
        want_names = [m for m, _ in members] if mode != "none" else []
        if zf.namelist() != want_names:
            print("FAIL %s: names %r" % (path, zf.namelist()))
            bad += 1
        for member, src in ([] if mode == "none" else members):
            want = open(src, "rb").read()
            info = zf.getinfo(member)
            got = zf.read(member)
            problems = []
            if got != want:
                problems.append("the bytes differ")
            if info.compress_type != (zipfile.ZIP_DEFLATED if mode == "deflate" else zipfile.ZIP_STORED):
                problems.append("method %d" % info.compress_type)
            if info.date_time != (2026, 10, 7, 12, 34, 56):
                problems.append("time %r" % (info.date_time,))
            if not info.flag_bits & 0x800:
                problems.append("the UTF-8 flag is off")
            if info.file_size != len(want) or info.CRC != zlib.crc32(want):
                problems.append("size %d or CRC %08x" % (info.file_size, info.CRC))
            # the LOCAL header too: zipfile reads sizes from the central
            # directory only, so a wrong local field is seen by nobody else
            loc = raw[info.header_offset:info.header_offset + 30]
            sig, _, flags, method, t, d, crc, csize, usize, nlen, xlen = struct.unpack("<IHHHHHIIIHH", loc)
            lname = raw[info.header_offset + 30:info.header_offset + 30 + nlen]
            if (sig != 0x04034b50 or flags != info.flag_bits or method != info.compress_type or
                    crc != info.CRC or csize != info.compress_size or usize != info.file_size or
                    lname != member.encode() or xlen != 0):
                problems.append("the local header disagrees with the directory")
            if problems:
                print("FAIL %s %s: %s" % (path, member, ", ".join(problems)))
                bad += 1
        size = os.path.getsize(path)
        print("%s zip %-7s %3d members %9d bytes" % ("FAIL" if bad else "ok  ", mode, len(zf.namelist()), size))
    print("deflatecheck zip: %d archives, %d problems" % (3, bad))
    return 1 if bad else 0


def main():
    mode, where = sys.argv[1], sys.argv[2]
    if mode == "zip":
        return check_zip(where, sys.argv[3])
    if mode == "svg":
        return check_svg(where, sys.argv[3])
    if mode == "png":
        return check_pngs(where)
    if mode == "make":
        for name, data in inputs().items():
            with open(os.path.join(where, name + ".in"), "wb") as f:
                f.write(data)
        return 0
    bad = 0
    worst = 0.0
    names = sorted(n[:-3] for n in os.listdir(where) if n.endswith(".in"))
    for name in names:
        want = open(os.path.join(where, name + ".in"), "rb").read()
        got = {}
        for ext in ("gz", "zz", "raw"):
            raw = open(os.path.join(where, name + "." + ext), "rb").read()
            try:
                if ext == "gz":
                    got[ext] = gzip.decompress(raw)
                elif ext == "zz":
                    got[ext] = zlib.decompress(raw)
                else:
                    got[ext] = zlib.decompress(raw, -15)
            except (OSError, EOFError, zlib.error) as e:
                got[ext] = None
                print("FAIL %s.%s: %s" % (name, ext, e))
        ok = all(got[e] == want for e in got)
        size = os.path.getsize(os.path.join(where, name + ".gz"))
        theirs = len(gzip.compress(want, 6, mtime=0))
        ratio = size / theirs
        if len(want) >= 1000:
            worst = max(worst, ratio)
        # never much longer than what went in: stored blocks at worst
        grown = size - len(want)
        if grown > 18 + 5 * (len(want) // 65535 + 1):
            ok = False
            print("FAIL %s.gz is %d bytes longer than its input" % (name, grown))
        print("%s %-9s %9d -> %8d  (zlib's level 6: %8d)"
              % ("ok  " if ok else "FAIL", name, len(want), size, theirs))
        bad += 0 if ok else 1
    print("deflatecheck: %d files, %d failed; at worst %.2f times zlib's size"
          % (len(names), bad, worst))
    return 1 if bad or not names else 0


sys.exit(main())
