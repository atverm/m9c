/* gendump_m9.c -- the M9-compiled generator side of the stage-2
   differential: identical output to host/fpc/gendump.
   Usage: gendump_m9 MODULE [DEP ...]                               */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Parse.h"
#include "Gen.h"

static m9_pool pool = {0};

/* corpus/<name>.m9 -> a CHAR slice, the way parsedump_m9 reads it */
static m9_sl_CHAR read_unit (const char *name)
{
  char path[512];
  FILE *f;
  long len, i;
  char *bytes;
  uint32_t *chars;

  snprintf (path, sizeof path, "../../corpus/%s.m9", name);
  f = fopen (path, "rb");
  if (!f) { perror (path); exit (2); }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) exit (2);
  fclose (f);
  chars = malloc (sizeof (uint32_t) * (size_t) len);
  for (i = 0; i < len; i++) chars[i] = (uint32_t) (unsigned char) bytes[i];
  free (bytes);
  return (m9_sl_CHAR){ chars, len };
}

static Ast_Node *parse_unit (const char *name, m9_state *err)
{
  Parse_Parser p;
  Ast_Node *root;

  memset (&p, 0, sizeof p);
  Parse_Init (&p, read_unit (name), err);
  root = Parse_File (&pool, &p, err);
  if (err->exc) { fprintf (stderr, "%s: raised %s\n", name, err->exc->name);
                  exit (3); }
  if (p.nerr > 0) { fprintf (stderr, "%s: %lld parse errors\n", name,
                             (long long) p.nerr); exit (1); }
  return root;
}

static void put_slice (m9_sl_CHAR s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) putchar ((int) (s.p[i] & 0xff));
}

int main (int argc, char **argv)
{
  m9_state err = {0};
  Ast_Node *root, *droot;
  int k;
  int64_t i;

  if (argc < 2) { fprintf (stderr, "usage: gendump_m9 MODULE [DEP ...]\n");
                  return 2; }

  /* dependency definitions first, exactly as gendump loads them */
  for (k = 2; k < argc; k++)
    {
      droot = parse_unit (argv[k], &err);
      for (i = 0; i < droot->nkids; i++)
        if (droot->kids.p[i])
          { Gen_LoadExtern (droot->kids.p[i], &err);
            if (err.exc) { fprintf (stderr, "LoadExtern raised %s\n",
                                    err.exc->name); return 3; } }
    }

  root = parse_unit (argv[1], &err);
  for (i = 0; i < root->nkids; i++)
    if (root->kids.p[i])
      { Gen_LoadUnit (root->kids.p[i], &err);
        if (err.exc) { fprintf (stderr, "LoadUnit raised %s\n",
                                err.exc->name); return 3; } }

  {
    size_t n = strlen (argv[1]);
    uint32_t *nm = malloc (sizeof (uint32_t) * (n ? n : 1));
    for (i = 0; i < (int64_t) n; i++)
      nm[i] = (uint32_t) (unsigned char) argv[1][i];
    Gen_Emit ((m9_sl_CHAR){ nm, (int64_t) n }, &err);
    if (err.exc) { fprintf (stderr, "Emit raised %s\n", err.exc->name);
                   return 3; }
  }

  put_slice (Gen_HText (&err));
  printf ("==== M9GEN SPLIT ====\n");
  put_slice (Gen_CText (&err));
  if (Gen_Errs (&err) > 0)
    {
      fprintf (stderr, "%lld gen errors\n", (long long) Gen_Errs (&err));
      return 1;
    }
  return 0;
}
