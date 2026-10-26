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

static inline void m9t_putc (uint32_t c)   /* inline: a dump that writes octets uses none */
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

/* a text the M9 side answers, written as UTF-8: a slice of CHARs
   encoded, a UTF's octets as they are.  Chosen by the slice's type
   (2026-10-23, Lex's texts became UTF): lib/gen.sh builds the dumps
   against the checked-in runtime/gen first, the previous generator's,
   so a helper must take both.  The escaped form is comdump's (newline,
   CR and backslash shown, so a comment stays one line) -- the three
   are ASCII, so a byte-wise escape of the octets is the same text */
static inline void m9t_put_chars (m9_sl_CHAR s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) m9t_putc (s.p[i]);
}
static inline void m9t_put_octets (m9_sl_UTF8 s)
{
  fwrite (s.p, 1, (size_t) s.len, stdout);
}
#define m9t_put_text(s) _Generic ((s), m9_sl_CHAR: m9t_put_chars, m9_sl_UTF8: m9t_put_octets) (s)

static inline void m9t_esc (uint32_t ch)
{
  if (ch == 10) { putchar ('\\'); putchar ('n'); }
  else if (ch == 13) { putchar ('\\'); putchar ('r'); }
  else if (ch == '\\') { putchar ('\\'); putchar ('\\'); }
  else m9t_putc (ch);
}
static inline void m9t_put_esc_chars (m9_sl_CHAR s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) m9t_esc (s.p[i]);
}
static inline void m9t_put_esc_octets (m9_sl_UTF8 s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) {
    if (s.p[i] < 0x80) m9t_esc (s.p[i]); else putchar (s.p[i]);
  }
}
#define m9t_put_esc_text(s) _Generic ((s), m9_sl_CHAR: m9t_put_esc_chars, m9_sl_UTF8: m9t_put_esc_octets) (s)
#endif
