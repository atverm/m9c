#!/usr/bin/env python3
"""listdiff -- the hand-maintained module lists must agree.

A corpus module is named in several places by hand, and until this
gate nothing checked that they said the same thing.  Every drift so
far was found by something else failing later:

  * 2026-08-24  gentest.pas, gendiff.sh, bootstrap.sh, build.sh
                LIBRARY, m9c.sh -- "every one was found by something
                failing"
  * 2026-08-29  Mat gained a Math import; bootstrap.sh's deps_of did
                not, and stage2 broke
  * 2026-09-11  ApiSpec, Arrow, Delim, Zip and Zarr joined gentest.pas
                and not gendiff.sh or bootstrap.sh; Http gained an Io
                import in gentest alone.  CI never saw it because the
                lexer golden was stale too and every later job waits on
                that one.

What is checked, each rule stated with the reason it is the rule:

  1. gentest.pas, gendiff.sh and bootstrap.sh name the SAME modules
     with the SAME dependency lists, in the same order.  gendiff.sh's
     own header says "the dep lists must match gentest.pas exactly";
     bootstrap.sh emits every module from every stage with those deps.
     (LibmGate is a gendiff-only fixture and says so; it is excluded.)

  2. Every module in corpus/ is in gentest.pas, except the ones named
     in NOT_GENERATED with a reason each.  A module the FPC generator
     never sees is a module runtime/gen does not hold and the bootstrap
     cannot build.

  3. A module's DIRECT imports are a subset of its gentest deps.  The
     deps are what LoadExtern registers, so an import missing from
     them is an unknown callee -- the 2026-09-11 failure exactly.  Not
     equality: some lists carry the transitive closure, HttpServer
     names Http for the foreign unit declared there, and changing any
     of them moves the emitted #includes.

  4. build.sh's LIBRARY is every corpus module except those named in
     NOT_INSTALLED with a reason each.  That list is what docgen and
     docdiff iterate and what the package installs to /usr/lib/m9.

  5. tools/tutor/setup.sh's LIB is a subset of LIBRARY and is closed
     under direct imports: a cell that compiles against a hermetic
     copy of the library cannot reach a module that is not in it.

  6. build.sh's COMPILER is closed under direct imports, for the same
     reason at link time.

Exit status 1 with every disagreement named; 0 when all agree.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')

# a corpus module gentest.pas deliberately does not generate
NOT_GENERATED = {
    'LibmGate': 'gendiff-only fixture (96 libm-named locals)',
    'Lsp':      'program module built by m9c --make from the library',
    'M9fmt':    'program module built by m9c --make from the library',
}
# a corpus module build.sh deliberately does not install
NOT_INSTALLED = {
    'LibmGate': 'gendiff-only fixture',
    'Hello':    'demo program',
    'Concat':   'demo program (the executable half of the + decision)',
    'M9c':      'the compiler itself, installed as a binary',
}


def rd(path):
    with open(os.path.join(ROOT, path), encoding='utf-8', errors='replace') as f:
        return f.read()


def corpus_modules():
    return sorted(os.path.basename(p)[:-3]
                  for p in glob.glob(os.path.join(ROOT, 'corpus', '*.m9')))


def direct_imports(m):
    """IMPORT A, B ; lines of both halves.  FROM u IMPORT names a
    foreign C unit, never an .m9, and is not an import here."""
    s = set()
    for line in rd(f'corpus/{m}.m9').splitlines():
        mm = re.match(r'\s*IMPORT\s+(.*?)\s*;', line)
        if mm:
            s |= {x.strip() for x in mm.group(1).split(',') if x.strip()}
    return s


def gentest():
    out = {}
    for mm in re.finditer(r"GenModule \('(\w+)', \[([^\]]*)\]", rd('host/fpc/gentest.pas')):
        out[mm.group(1)] = [x.strip("' ") for x in mm.group(2).split(',') if x.strip()]
    return out


def gendiff():
    out = {}
    for line in rd('runtime/test/gendiff.sh').splitlines():
        mm = re.match(r'run\s+(\w+)((?:\s+\w+)*)\s*$', line)
        if mm and mm.group(1) != 'LibmGate':
            out[mm.group(1)] = mm.group(2).split()
    return out


def bootstrap():
    text = rd('runtime/test/bootstrap.sh')
    mods = re.search(r'^MODS="([^"]*)"', text, re.M).group(1).split()
    body = re.search(r'^deps_of \(\) \{\n(.*?)^\}', text, re.M | re.S).group(1)
    deps = {}
    for mm in re.finditer(r'^\s*([\w|]+)\)\s*echo\s*([^;]*);;', body, re.M):
        for name in mm.group(1).split('|'):
            if name != '*':
                deps[name] = mm.group(2).split()
    return {m: deps.get(m, []) for m in mods}


def shell_list(path, var):
    """VAR="a b \\\n c" in a shell script, the range closing on the quote."""
    mm = re.search(r'^' + var + r'="([^"]*)"', rd(path), re.M)
    return mm.group(1).replace('\\\n', ' ').split()


def main():
    bad = []

    def fail(msg):
        bad.append(msg)

    corpus = corpus_modules()
    gt, gd, bs = gentest(), gendiff(), bootstrap()

    # 1. the three generator lists are one list
    for name, other in (('gendiff.sh', gd), ('bootstrap.sh', bs)):
        for m in sorted(set(gt) | set(other)):
            if m not in other:
                fail(f'{name}: {m} is in gentest.pas and not here')
            elif m not in gt:
                fail(f'{name}: {m} is here and not in gentest.pas')
            elif gt[m] != other[m]:
                fail(f'{name}: {m} deps {other[m]} != gentest.pas {gt[m]}')

    # 2. every corpus module is generated, or excused by name
    for m in corpus:
        if m not in gt and m not in NOT_GENERATED:
            fail(f'gentest.pas: corpus/{m}.m9 is not generated '
                 f'(add it, or name it in runtime/test/listdiff.py NOT_GENERATED with a reason)')
    for m in NOT_GENERATED:
        if m in gt:
            fail(f'listdiff.py: {m} is excused from gentest.pas but is in it')
        if m not in corpus:
            fail(f'listdiff.py: {m} is excused from gentest.pas but is not in corpus/')

    # 3. deps cover the direct imports
    for m, deps in gt.items():
        missing = direct_imports(m) - set(deps)
        if missing:
            fail(f'gentest.pas: {m} imports {sorted(missing)} but its deps are {deps}')

    # 4. LIBRARY is the corpus minus the excused
    lib = shell_list('build.sh', 'LIBRARY')
    for m in corpus:
        if m not in lib and m not in NOT_INSTALLED:
            fail(f'build.sh LIBRARY: corpus/{m}.m9 is not installed '
                 f'(add it, or name it in runtime/test/listdiff.py NOT_INSTALLED with a reason)')
    for m in lib:
        if m not in corpus:
            fail(f'build.sh LIBRARY: {m} has no corpus/{m}.m9')
        if m in NOT_INSTALLED:
            fail(f'listdiff.py: {m} is excused from LIBRARY but is in it')

    # 5. the tutor's library is a closed subset of LIBRARY
    tut = shell_list('tools/tutor/setup.sh', 'LIB')
    for m in tut:
        if m not in lib:
            fail(f'tools/tutor/setup.sh LIB: {m} is not in build.sh LIBRARY')
        for d in sorted(direct_imports(m) - set(tut)) if m in corpus else []:
            fail(f'tools/tutor/setup.sh LIB: {m} imports {d}, which is not in LIB')

    # 6. the compiler's closure is closed
    comp = shell_list('build.sh', 'COMPILER')
    for m in comp:
        for d in sorted(direct_imports(m) - set(comp)):
            fail(f'build.sh COMPILER: {m} imports {d}, which is not in COMPILER')

    if bad:
        for b in bad:
            print('listdiff: ' + b)
        print(f'listdiff: {len(bad)} disagreement(s)')
        return 1
    print(f'listdiff: {len(corpus)} corpus modules; gentest.pas, gendiff.sh, '
          f'bootstrap.sh ({len(gt)} entries), build.sh LIBRARY ({len(lib)}), '
          f'COMPILER ({len(comp)}) and the tutor LIB ({len(tut)}) agree')
    return 0


if __name__ == '__main__':
    sys.exit(main())
