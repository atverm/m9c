/* utf8io.h -- the dump drivers' view of a source file and of a CHAR
   slice, since 2026-10-09.  m9c reads a source as UTF-8 (Io.ReadFile
   decodes) and a literal's CHARs are Unicode scalars; the drivers used
   to widen each OCTET to a CHAR, so the M9 side emitted `195u, 169u'
   for an `é' the oracle emitted as `233u' and bootstrap diverged on
   ShareUse.Accents.  Decoding here is lenient, like M9AST.Utf8Next: a
   malformed byte counts as itself (nothing in the corpus is malformed,
   and the lexer never refuses one).  Printing encodes back, so the
   bytes compared by lexdiff/parsediff/comdiff are the file's own. */
#ifndef M9_UTF8IO_H
#define M9_UTF8IO_H
#include <stdint.h>
#include <stdio.h>

static int64_t m9t_decode (const unsigned char *b, int64_t len, uint32_t *out)
{
  int64_t i = 0, n = 0;
  while (i < len) {
    unsigned c = b[i];
    int k, extra;
    uint32_t v;
    if (c < 0x80) { out[n++] = c; i++; continue; }
    if ((c & 0xE0) == 0xC0) { v = c & 0x1F; extra = 1; }
    else if ((c & 0xF0) == 0xE0) { v = c & 0x0F; extra = 2; }
    else if ((c & 0xF8) == 0xF0) { v = c & 0x07; extra = 3; }
    else { out[n++] = c; i++; continue; }
    for (k = 1; k <= extra; k++)
      if (i + k >= len || (b[i + k] & 0xC0) != 0x80) { extra = -1; break; }
    if (extra < 0) { out[n++] = c; i++; continue; }
    for (k = 1; k <= extra; k++) v = (v << 6) | (b[i + k] & 0x3F);
    out[n++] = v;
    i += extra + 1;
  }
  return n;
}

static void m9t_putc (uint32_t c)
{
  if (c < 0x80) putchar ((int) c);
  else if (c < 0x800) { putchar (0xC0 | (int) (c >> 6)); putchar (0x80 | (int) (c & 0x3F)); }
  else if (c < 0x10000) {
    putchar (0xE0 | (int) (c >> 12)); putchar (0x80 | (int) ((c >> 6) & 0x3F));
    putchar (0x80 | (int) (c & 0x3F));
  } else {
    putchar (0xF0 | (int) (c >> 18)); putchar (0x80 | (int) ((c >> 12) & 0x3F));
    putchar (0x80 | (int) ((c >> 6) & 0x3F)); putchar (0x80 | (int) (c & 0x3F));
  }
}
#endif
