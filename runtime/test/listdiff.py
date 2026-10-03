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

  3. A module's DIRECT imports are a subset of its gentest deps, and
     every dep is inside the module's import CLOSURE.  The deps are
     what LoadExtern registers and what the generator #includes: an
     import missing from them is an unknown callee (the 2026-09-11
     failure), and a dep the module can never reach is a dead include
     (Sem carried Fmt, Fmt carried DynStr, neither used -- removed the
     same day).  Not equality with either the direct set or the
     closure: some lists carry the closure and some the direct
     imports, and changing one moves the emitted #includes.  A dep
     outside the closure is excused BY NAME in EXTRA_DEPS with the
     reason: HttpServer names Http because `FROM csock IMPORT` needs
     the foreign unit declared in Http.m9.

  4. build.sh's LIBRARY is every corpus module except those named in
     NOT_INSTALLED with a reason each.  That list is what docgen and
     docdiff iterate and what the package installs to /usr/lib/m9.

  5. tools/tutor/setup.sh's LIB is a subset of LIBRARY and is closed
     under direct imports: a cell that compiles against a hermetic
     copy of the library cannot reach a module that is not in it.

  6. build.sh's COMPILER is closed under direct imports, for the same
     reason at link time.

  7. m9c.sh's `check M deps...` lines carry gentest.pas's deps for M.
     They compile M with NAMED deps and compare the bytes with the
     oracle's, and named deps win, so a stale line there emits an
     #include the oracle does not and the gate diverges for a reason
     that is not the compiler's.

  8. Every gate that links an m9c of its own (`... -o m9c` or
     `-o "$W/m9c"` in runtime/test/*.sh) links exactly build.sh's
     COMPILER modules.  Twelve scripts carry that line by hand; ten
     still linked Fmt.c and three Time.c after nothing in the compiler
     imported either (2026-09-11) -- dead under LTO, but a module
     MISSING from one of them is a link error only that gate sees.

  9. Every battery in runtime/test/build.sh links a set of generated
     modules that is CLOSED under direct imports.  The driver lines
     name their `../gen/M.c` by hand -- the script's own comment
     counts three times one of them missed Json -- and a missing one
     is a link error in one battery of thirty-eight; here it is one
     line naming the module and the import.

 10. Every module gentest.pas generates is linked by at least one
     battery of build.sh, or is named in NO_BATTERY with what holds
     it instead.  A library module that lands without a driver is a
     module nothing runs (2026-10-01, written before the library
     backlog adds six or more).

 11. The tutorial's hand link lines (runtime/test/lib/tutcommon.sh,
     the examples that need a C library) are closed the same way:
     the objects they name cover the example's imports and each
     other's.  When Stats gained Bits on 2026-09-27 only tutgen
     failing to link C14Flux said so.

 12. The link lines of every OTHER gate over runtime/gen, and
     bootstrap.sh's TOOLC, are closed under direct imports as rule 9
     holds build.sh's.  When Gen gained Text on 2026-10-01 the first
     three rules named gentest, gendiff's run line and deps_of; the
     helper both gendiff and bootstrap LINK was left to the linker,
     once in each gate, the second after a ten-minute run.

 13. corpus/NAMETest.m9 is the test of corpus/NAME.m9 (m9test.sh
     builds and runs it): excused from gentest and from LIBRARY by
     its name, so the name must have a module behind it.

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
    'KindUse':  'gendiff-only fixture (a case record used across a module)',
    'EnumUse':  'gendiff-only fixture (an enumeration used across a module)',
    'Palette':  'gendiff-only fixture (an enumeration declaration)',
    'Lsp':      'program module built by m9c --make from the library',
    'M9fmt':    'program module built by m9c --make from the library',
    'M9elide':  'program module built by m9c --make from the library',
}
# a gentest dep outside the module's import closure, and why it is there
EXTRA_DEPS = {
    'HttpServer': {'Http': 'FROM csock IMPORT: the foreign unit is declared in Http.m9'},
}
# a corpus module build.sh deliberately does not install
NOT_INSTALLED = {
    'LibmGate': 'gendiff-only fixture',
    'KindUse':  'gendiff-only fixture',
    'EnumUse':  'gendiff-only fixture',
    'Palette':  'gendiff-only fixture',
    'Hello':    'demo program',
    'Concat':   'demo program (the executable half of the + decision)',
    'Narrow':   'test program (every integer width traps on overflow)',
    'ProcUse':  'test program (procedure types, par 2.2.3)',
    'AggUse':   'test program (constant tables, par 2.2.4)',
    'ShareUse': 'test program (a call that raised answered nothing, par 5)',
    'M9c':      'the compiler itself, installed as a binary',
}
# a generated module no battery of runtime/test/build.sh links, and
# the gate that holds it instead
NO_BATTERY = {
    'Lex':   'lexdiff, comdiff and the token-count golden',
    'Ast':   'parsediff (every node kind printed back)',
    'Parse': 'parsediff and the parse probes',
    'Print': 'parsediff (print (parse ()) is the fixpoint)',
    'Sem':   'semdiff and probediff',
    'Gen':   'gendiff and bootstrap',
    'Doc':   'docdiff',
    'Diag':  'diagdiff and the tutor gate',
    'M9c':   'm9c.sh, the compiler as a program',
    'Review': 'reviewdiff (one recorded page per corpus module)',
    'Check': 'm9test (CheckTest holds it to its own recorded output)',
    'Arrays': 'm9test (ArraysTest, against numpy goldens)',
    'Numeric': 'm9test (NumericTest, against scipy goldens)',
    'Png': 'm9test (PngTest, read back through Zip.Decompress) and deflate.sh (Python reads the files)',
}


def rd(path):
    with open(os.path.join(ROOT, path), encoding='utf-8', errors='replace') as f:
        return f.read()


def corpus_modules():
    return sorted(os.path.basename(p)[:-3]
                  for p in glob.glob(os.path.join(ROOT, 'corpus', '*.m9')))


def no_comments(text):
    """the source with every (* ... *) blanked, nesting honoured and
    the line breaks kept.  Check.m9's documentation shows a test,
    IMPORT line and all, and was read as importing itself."""
    out, depth, i = [], 0, 0
    while i < len(text):
        if text.startswith('(*', i):
            depth += 1
            i += 2
        elif depth and text.startswith('*)', i):
            depth -= 1
            i += 2
        else:
            if depth == 0 or text[i] == '\n':
                out.append(text[i])
            i += 1
    return ''.join(out)


def direct_imports(m):
    """IMPORT A, B ; lines of both halves.  FROM u IMPORT names a
    foreign C unit, never an .m9, and is not an import here."""
    s = set()
    for line in no_comments(rd(f'corpus/{m}.m9')).splitlines():
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
        if mm and mm.group(1) not in ('LibmGate', 'KindUse', 'EnumUse', 'Palette'):
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

    # 13. corpus/NAMETest.m9 is the test of corpus/NAME.m9, a program
    # m9test.sh builds and runs: excused from the generated and the
    # installed lists as a CLASS, by its name -- which is why the
    # name must be honest
    for m in corpus:
        if m.endswith('Test') and len(m) > 4:
            if m[:-4] not in corpus:
                fail(f'corpus/{m}.m9 is named as a test and there is no corpus/{m[:-4]}.m9')
            NOT_GENERATED[m] = 'a test in M9, built and run by m9test.sh'
            NOT_INSTALLED[m] = 'a test in M9, built and run by m9test.sh'

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

    # 3. deps cover the direct imports, and reach no further than the closure
    def closure(m, seen=None):
        seen = set() if seen is None else seen
        for d in direct_imports(m) if m in corpus else ():
            if d not in seen:
                seen.add(d)
                closure(d, seen)
        return seen
    for m, deps in gt.items():
        missing = direct_imports(m) - set(deps)
        if missing:
            fail(f'gentest.pas: {m} imports {sorted(missing)} but its deps are {deps}')
        dead = set(deps) - closure(m) - set(EXTRA_DEPS.get(m, {}))
        if dead:
            fail(f'gentest.pas: {m} names {sorted(dead)} in its deps but never imports '
                 f'{"it" if len(dead) == 1 else "them"}, directly or through another module '
                 f'(remove, or excuse in EXTRA_DEPS with a reason)')
    for m, extra in EXTRA_DEPS.items():
        for d in extra:
            if m not in gt or d not in gt[m]:
                fail(f'listdiff.py: EXTRA_DEPS excuses {m} -> {d}, which gentest.pas does not list')
            elif d in closure(m):
                fail(f'listdiff.py: EXTRA_DEPS excuses {m} -> {d}, but {m} does import it')

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

    # 7. m9c.sh's named-dep checks are gentest's entries
    for line in rd('runtime/test/m9c.sh').splitlines():
        mm = re.match(r'check\s+(\w+)((?:\s+\w+)*)\s*$', line)
        if mm:
            m, deps = mm.group(1), mm.group(2).split()
            if m not in gt:
                fail(f'm9c.sh: check {m} names a module gentest.pas does not generate')
            elif deps != gt[m]:
                fail(f'm9c.sh: check {m} {deps} != gentest.pas {gt[m]}')

    # 8. every hand-linked m9c is the COMPILER set
    for path in sorted(glob.glob(os.path.join(ROOT, 'runtime', 'test', '*.sh'))):
        text = rd(os.path.relpath(path, ROOT)).replace('\\\n', ' ')
        for line in text.splitlines():
            if re.search(r'-o\s+"?(\$\w+/)?m9c"?(\s|$)', line) and 'gen/' in line:
                linked = set(re.findall(r'gen/(\w+)\.c', line))
                if linked != set(comp):
                    name = os.path.basename(path)
                    extra, missing = sorted(linked - set(comp)), sorted(set(comp) - linked)
                    fail(f'{name}: the m9c it links differs from build.sh COMPILER'
                         f'{" -- extra " + str(extra) if extra else ""}'
                         f'{" -- missing " + str(missing) if missing else ""}')

    # 9. every battery's link line is closed under direct imports
    drivers = rd('runtime/test/build.sh').replace('\\\n', ' ')
    battery_mods = set()
    nlines = 0
    for line in drivers.splitlines():
        if not (line.lstrip().startswith('gcc') and 'gen/' in line):
            continue
        nlines += 1
        mods = set(re.findall(r'gen/(\w+)\.c', line))
        battery_mods |= mods
        out = re.search(r'-o\s+(\S+)', line)
        what = out.group(1) if out else '?'
        for m in sorted(mods):
            for d in sorted(direct_imports(m) - mods) if m in corpus else []:
                fail(f'runtime/test/build.sh: {what} links {m} and not {d}, which {m} imports')

    # 10. every generated module has a battery, or is held elsewhere by name
    for m in sorted(gt):
        if m not in battery_mods and m not in NO_BATTERY:
            fail(f'runtime/test/build.sh: no battery links {m} '
                 f'(give it a driver, or name it in runtime/test/listdiff.py NO_BATTERY with the gate that holds it)')
    for m in NO_BATTERY:
        if m in battery_mods:
            fail(f'listdiff.py: {m} is excused from build.sh but a battery links it')
        if m not in gt:
            fail(f'listdiff.py: {m} is excused from build.sh but gentest.pas does not generate it')

    # 12. every OTHER gate's link line over runtime/gen is closed too,
    # and bootstrap's TOOLC, which is a list of names and not a line
    ngate = 0
    for path in sorted(glob.glob(os.path.join(ROOT, 'runtime', 'test', '*.sh'))):
        base = os.path.basename(path)
        if base == 'build.sh':
            continue
        text = rd('runtime/test/' + base).replace('\\\n', ' ')
        for line in text.splitlines():
            if not (line.lstrip().startswith('gcc') and 'gen/' in line):
                continue
            ngate += 1
            mods = set(re.findall(r'gen/(\w+)\.c', line))
            out = re.search(r'-o\s+(\S+)', line)
            what = out.group(1) if out else '?'
            for m in sorted(mods):
                for d in sorted(direct_imports(m) - mods) if m in corpus else []:
                    fail(f'runtime/test/{base}: {what} links {m} and not {d}, which {m} imports')
    tc = re.search(r'^TOOLC="([^"]*)"', rd('runtime/test/bootstrap.sh'), re.M)
    if not tc:
        fail('runtime/test/bootstrap.sh: no TOOLC line to read')
    else:
        mods = set(tc.group(1).split())
        for m in sorted(mods):
            for d in sorted(direct_imports(m) - mods) if m in corpus else []:
                fail(f'runtime/test/bootstrap.sh: TOOLC has {m} and not {d}, which {m} imports')

    # 11. the tutorial's hand link lines are closed too
    tutc = rd('runtime/test/lib/tutcommon.sh').replace('\\\n', ' ')
    ntut = 0
    for mm in re.finditer(r'^\s*(\w+)\)\n(.*?);;', tutc, re.M | re.S):
        name, body = mm.group(1), mm.group(2)
        g = re.search(r'gcc[^\n]*', body)
        if not g:
            continue
        ntut += 1
        objs = set(re.findall(r'\b(\w+)\.o\b', g.group(0)))
        src = os.path.join(ROOT, 'docs', 'tutorial', 'examples', name + '.m9')
        if not os.path.exists(src):
            fail(f'tutcommon.sh: {name} has a link line and no docs/tutorial/examples/{name}.m9')
            continue
        need = set()
        with open(src, encoding='utf-8') as f:
            for line in f:
                im = re.match(r'\s*IMPORT\s+(.*?)\s*;', line)
                if im:
                    need |= {x.strip() for x in im.group(1).split(',') if x.strip()}
        for d in sorted(need - objs):
            if d in corpus:
                fail(f'tutcommon.sh: {name} imports {d} and its link line has no {d}.o')
        for o in sorted(objs):
            for d in sorted(direct_imports(o) - objs) if o in corpus else []:
                fail(f'tutcommon.sh: {name} links {o}.o and not {d}.o, which {o} imports')

    if bad:
        for b in bad:
            print('listdiff: ' + b)
        print(f'listdiff: {len(bad)} disagreement(s)')
        return 1
    print(f'listdiff: {len(corpus)} corpus modules; gentest.pas, gendiff.sh, '
          f'bootstrap.sh ({len(gt)} entries), build.sh LIBRARY ({len(lib)}), '
          f'COMPILER ({len(comp)}) and the tutor LIB ({len(tut)}) agree; '
          f'{nlines} driver link lines, {ngate} gate ones and {ntut} '
          f'tutorial ones are closed, '
          f'{len(gt) - len(NO_BATTERY)} modules have a battery')
    return 0


if __name__ == '__main__':
    sys.exit(main())
