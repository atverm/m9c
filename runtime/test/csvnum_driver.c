/* csvnum_driver.c -- m9_csv_number and m9_field_f64 (m9rt.h), Csv's
   IsNumber grammar in one pass in the runtime, held to a table of
   verdicts read off that grammar -- every shape it names: blanks and
   tabs trimmed, a sign, nan/inf/infinity in any case, digits with one
   point among them, an exponent with a sign, and the shapes it refuses:
   nothing, a sign alone, a point alone, 1e, 0x10, a blank inside, a
   second point, text, a trailing letter -- and the parser's value to
   strtod on the trimmed field for every accepted one plus 200,000
   random fields of digits and padding.  Under M9_CSV_PORTABLE both
   answer -1 for every field (the battery's second run, the control).
   Shown able to fail: the exponent's digit count not reset fails "1e"
   and "1e+" (2026-10-25). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "m9rt.h"

static long bad = 0, checks = 0;
static int portable;

static void verdict (const char *s, int want)
{
  int got = m9_csv_number (s, (int64_t) strlen (s));
  double d = 0;
  int got2 = m9_field_f64 (s, (int64_t) strlen (s), &d);
  checks++;
  if (portable) { if (got != -1 || got2 != -1) { bad++; printf ("FAIL \"%s\": %d %d under M9_CSV_PORTABLE\n", s, got, got2); } return; }
  if (got != want || got2 != want) { bad++; printf ("FAIL \"%s\": number %d, field %d, wanted %d\n", s, got, got2, want); return; }
  if (want == 1) {
    /* the value: strtod on the trimmed field */
    const char *p = s;
    while (*p == ' ' || *p == '\t') p++;
    double w = strtod (p, NULL);
    uint64_t a, b;
    memcpy (&a, &d, 8); memcpy (&b, &w, 8);
    if (a != b && !(isnan (d) && isnan (w))) { bad++; printf ("FAIL \"%s\": value %.17g, strtod %.17g\n", s, d, w); }
  }
}

int main (void)
{
  portable = getenv ("M9_CSV_PORTABLE") != NULL;
  static const struct { const char *s; int want; } tab[] = {
    { "0", 1 }, { "1", 1 }, { "-1", 1 }, { "+1", 1 }, { "1.5", 1 }, { "-1.5", 1 }, { ".5", 1 }, { "+.5", 1 }, { "5.", 1 },
    { "1e5", 1 }, { "1E5", 1 }, { "1e+5", 1 }, { "1e-5", 1 }, { "1.5e-7", 1 }, { ".5e3", 1 }, { "5.e3", 1 },
    { " 1", 1 }, { "1 ", 1 }, { "\t1\t", 1 }, { "  -2.5e+3  ", 1 }, { "000.000", 1 }, { "123456789012345678901234567890", 1 },
    { "nan", 1 }, { "NaN", 1 }, { "NAN", 1 }, { "-nan", 1 }, { "inf", 1 }, { "Inf", 1 }, { "-INF", 1 }, { "+inf", 1 },
    { "infinity", 1 }, { "Infinity", 1 }, { "-infinity", 1 }, { " inf ", 1 },
    { "", 0 }, { " ", 0 }, { "\t", 0 }, { "-", 0 }, { "+", 0 }, { ".", 0 }, { "-.", 0 }, { "e5", 0 }, { "1e", 0 }, { "1e+", 0 },
    { "1e-", 0 }, { "1ee5", 0 }, { "1.2.3", 0 }, { "1 2", 0 }, { "1,5", 0 }, { "0x10", 0 }, { "0x1p3", 0 }, { "1.5x", 0 },
    { "x1.5", 0 }, { "abc", 0 }, { "nan1", 0 }, { "infin", 0 }, { "infinit", 0 }, { "infinityy", 0 }, { "in f", 0 },
    { "1e5.5", 0 }, { "--1", 0 }, { "+-1", 0 }, { "1-", 0 }, { "1+", 0 }, { "1.5e", 0 }, { "NA", 0 }, { "null", 0 },
    { "1_000", 0 }, { "１", 0 }, { "1\n", 0 }, { "1\r", 0 } };
  for (unsigned i = 0; i < sizeof tab / sizeof tab[0]; i++) verdict (tab[i].s, tab[i].want);
  /* random fields: digits, a point somewhere or not, an exponent or not, padding */
  srand (5);
  char buf[96];
  for (int i = 0; i < 200000; i++) {
    int k = 0, nd = 1 + rand () % 20, pt = rand () % (nd + 2);
    int pad = rand () % 3;
    for (int j = 0; j < pad; j++) buf[k++] = ' ';
    if (rand () % 3 == 0) buf[k++] = rand () % 2 ? '-' : '+';
    for (int j = 0; j < nd; j++) { if (j == pt) buf[k++] = '.'; buf[k++] = (char) ('0' + rand () % 10); }
    if (rand () % 2 == 0) k += snprintf (buf + k, sizeof buf - k, "e%d", rand () % 600 - 300);
    for (int j = 0; j < pad; j++) buf[k++] = ' ';
    buf[k] = 0;
    verdict (buf, 1);
  }
  if (bad) { printf ("csvnum_driver: %ld of %ld checks FAIL\n", bad, checks); return 1; }
  printf ("csvnum_driver: %ld checks ok%s\n", checks, portable ? " (M9_CSV_PORTABLE: declined every field)" : "");
  return 0;
}
