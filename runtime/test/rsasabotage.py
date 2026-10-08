#!/usr/bin/env python3
"""rsasabotage REPO [NAME-PART] -- shows RsaTest able to fail.

Each entry is one small break of a COPY of corpus/Rsa.m9 or of the
shim in runtime/tlsshim.c (m9_rsa_verify); RsaTest is built against the
copies with REPO/out/m9c and must go red.  A test that stays green on a
break is a property the test does not hold; the script says which.  A
test that does not finish in two minutes is HUNG and said so -- the
first run found one (a loop on a zero top octet, now a refusal).
Not run by CI; run it after changing Rsa, the shim or RsaTest.

    runtime/test/rsasabotage.py . ["shim"]

docs/library-plan-2.md, section 13.                                   """
H = sys.argv[1]
SAB = [
 ("runtime/tlsshim.c", "shim: PSS verified as PKCS#1", "pss ? RSA_PKCS1_PSS_PADDING : RSA_PKCS1_PADDING", "RSA_PKCS1_PADDING"),
 ("runtime/tlsshim.c", "shim: a 20-octet salt", "EVP_PKEY_CTX_set_rsa_pss_saltlen (ctx, 32)", "EVP_PKEY_CTX_set_rsa_pss_saltlen (ctx, 20)"),
 ("runtime/tlsshim.c", "shim: MGF1 over SHA-1", "EVP_PKEY_CTX_set_rsa_mgf1_md (ctx, EVP_sha256 ())", "EVP_PKEY_CTX_set_rsa_mgf1_md (ctx, EVP_sha1 ())"),
 ("runtime/tlsshim.c", "shim: the signature digest said to be SHA-1", "EVP_PKEY_CTX_set_signature_md (ctx, EVP_sha256 ())", "EVP_PKEY_CTX_set_signature_md (ctx, EVP_sha1 ())"),
 ("runtime/tlsshim.c", "shim: any answer of OpenSSL's taken as verified", "rc = EVP_PKEY_verify (ctx, sig, slen, digest, hlen) == 1 ? 1 : 0;", "rc = EVP_PKEY_verify (ctx, sig, slen, digest, hlen) >= 0 ? 1 : 0;"),
 ("corpus/Rsa.m9", "the OID not checked", "    IF NOT RsaOid (der, at) THEN RAISE Error ('not an rsaEncryption key') END ;", ""),
 ("corpus/Rsa.m9", "the bit count off by one", "  k.bits := LEN (n) * 8 ;\n  WHILE top", "  k.bits := LEN (n) * 8 - 1 ;\n  WHILE top"),
 ("corpus/Rsa.m9", "the key's form told wrong to OpenSSL", "  IF k.pkcs1 THEN pk := 1 ELSE pk := 0 END ;", "  IF k.pkcs1 THEN pk := 0 ELSE pk := 1 END ;"),
 ("corpus/Rsa.m9", "the scheme told wrong to OpenSSL", "  IF scheme = Pss THEN pss := 1 ELSE pss := 0 END ;", "  IF scheme = Pss THEN pss := 0 ELSE pss := 1 END ;"),
 ("corpus/Rsa.m9", "the modulus's leading zero kept", "  WHILE i < len - 1 AND I64 (d[start + i]) = 0 DO i := i + 1 END ;", "  i := 0 ;"),
]
red = 0
ONLY = sys.argv[2] if len(sys.argv) > 2 else ""
for path, name, old, new in SAB:
    if ONLY and ONLY not in name: continue
    src = open(os.path.join(H, path)).read()
    assert src.count(old) == 1, name
    tmp = tempfile.mkdtemp(prefix="rsasab-")
    lib = os.path.join(tmp, "corpus"); rt = os.path.join(tmp, "runtime")
    os.mkdir(lib); os.mkdir(rt)
    for f in os.listdir(os.path.join(H, "corpus")):
        if f.endswith(".m9"): shutil.copy(os.path.join(H, "corpus", f), lib)
    for f in os.listdir(os.path.join(H, "runtime")):
        if f.endswith(".c") or f.endswith(".h"): shutil.copy(os.path.join(H, "runtime", f), rt)
    open(os.path.join(tmp, path), "w").write(src.replace(old, new))
    b = os.path.join(tmp, "b"); os.mkdir(b)
    e = dict(os.environ, M9LIBRARY=lib, M9RUNTIME=rt)
    r = subprocess.run([os.path.join(H, "out/m9c"), "--make", "-o", "t", os.path.join(lib, "RsaTest.m9")], cwd=b, env=e, capture_output=True, text=True)
    if r.returncode: print("BUILD FAIL", name, r.stderr[-300:]); continue
    try:
        r = subprocess.run([os.path.join(b, "t")], cwd=H, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        print("HUNG (two minutes): " + name); continue
    ok = r.returncode != 0
    red += ok
    print(("red: " if ok else "STILL GREEN: ") + name + ("" if ok else "\n" + r.stdout[-300:]))
    shutil.rmtree(tmp)
print(f"{red} of {len(SAB)} red")
