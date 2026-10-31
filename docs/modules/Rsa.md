# Rsa

Rsa does RSA signature VERIFICATION (docs/library-plan-2.md, item
5).  It reads a public key from PEM or DER: SubjectPublicKeyInfo
(BEGIN PUBLIC KEY) or PKCS#1 (BEGIN RSA PUBLIC KEY).  It checks a
signature over SHA-256 under PKCS#1 v1.5 or PSS (MGF1 with SHA-256,
a 32-octet salt).  The purpose: a signed data passport or a signed
release receipt can be checked by a program, not only by a person
with openssl on the command line.

NO signing, NO key generation, NO decryption: those need a private
key in the process; verification handles only what is public.

THE ARITHMETIC IS OPENSSL'S (m9_rsa_verify in runtime/tlsshim.c,
the runtime's OpenSSL surface, which every M9 program links).  A
verifier written in M9 first, on 24-bit limbs with Montgomery
multiplication, passed the same test and measured 70 times slower:
0.55 ms against 8 us at 2048 bits.  It bought nothing, since the
runtime links libcrypto anyway; Alex: "why not call openssl?"  M9
keeps the key's reading (PEM, the DER walk to the modulus and
exponent, so Bits/ModulusHex/ExponentHex answer from what was
read) and the refusals by name.

RsaTest holds it against Python's cryptography: three key sizes, 240
signatures under both schemes, every signature verifying and every
tampering refused, nine of Bleichenbacher's 2006 forgeries against
an e = 3 key refused (tools/rsagold.py).

### EXCEPTION Error

Error reports a key that cannot be read, a digest that is not
32 octets, or a scheme that is not one of the two.

### CONST Pkcs1

PKCS#1 v1.5, RFC 8017 par 8.2

### CONST Pss

PSS, par 8.1: MGF1-SHA-256, salt 32

### TYPE Key

opaque; lives in a POOL

### PublicKey (VAR pool: POOL ; RO pem: STR) : PTR Key IN pool RAISES Error, ValueRange

PublicKey reads a PEM text: the first BEGIN ... END block whose
label holds PUBLIC KEY, base64 between them (line breaks
ignored).

### PublicKeyDer (VAR pool: POOL ; RO der: SLICE OF BYTE) : PTR Key IN pool RAISES Error, ValueRange

PublicKeyDer reads the DER: SubjectPublicKeyInfo with the
rsaEncryption OID, or a bare PKCS#1 RSAPublicKey (SEQUENCE of two
INTEGERs).

### Bits (k: PTR Key) : I64

Bits answers the modulus's length in bits.

### ModulusHex (k: PTR Key) : STR RAISES ValueRange

_(documented with the group below)_

### ExponentHex (k: PTR Key) : STR RAISES ValueRange

ModulusHex and ExponentHex answer lowercase, no leading zeros:
Python's %x.

### Verify (k: PTR Key ; RO digest: SLICE OF BYTE ; RO signature: SLICE OF BYTE ; scheme: I64) : BOOL RAISES Error, ValueRange

Verify takes digest, the SHA-256 of the message (32 octets).  It
answers TRUE when the signature is that digest's under the key
and scheme.  It answers FALSE, not an Error, for a signature of
the wrong length, out of the modulus's range, or wrong.

### VerifyMessage (k: PTR Key ; RO message: SLICE OF BYTE ; RO signature: SLICE OF BYTE ; scheme: I64) : BOOL RAISES Error, ValueRange

VerifyMessage is Verify of the message's SHA-256.

VerifyC binds runtime/tlsshim.c: m9_rsa_verify, OpenSSL's
EVP_PKEY_verify over a key parsed from DER per call.  It keeps no
state, so it is reentrant.

### VerifyC (der: C.ConstPtr ; dlen: C.SizeT ; pkcs1Key: C.Int ; digest: C.ConstPtr ; hlen: C.SizeT ; sig: C.ConstPtr ; slen: C.SizeT ; pss: C.Int) : C.Int [REENTRANT]

_(undocumented)_
