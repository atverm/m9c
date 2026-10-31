/* gendump_m9.c is the M9-compiled generator side of the stage-2
   differential.  Its output is identical to host/fpc/gendump.
   Usage: gendump_m9 MODULE [DEP ...]                               */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Parse.h"
#include "Gen.h"
#include "Sem.h"
#include "utf8io.h"

static m9_pool pool = {0};

/* This reads corpus/<name>.m9 as its UTF-8 octets, the way
   parsedump_m9 reads it. */
static m9_sl_UTF8 read_unit (const char *name)
{
  char path[512];
  FILE *f;
  long len;
  char *bytes;

  snprintf (path, sizeof path, "../../corpus/%s.m9", name);
  f = fopen (path, "rb");
  if (!f) { perror (path); exit (2); }
  fseek (f, 0, SEEK_END); len = ftell (f); fseek (f, 0, SEEK_SET);
  bytes = malloc ((size_t) len + 1);
  if (fread (bytes, 1, (size_t) len, f) != (size_t) len) exit (2);
  fclose (f);
  return (m9_sl_UTF8){ (uint8_t *) bytes, len };   /* UTF-8, as m9c reads it */
}

static Ast_Node *parse_unit (const char *name, m9_state *err)
{
  Parse_Parser p;
  Ast_Node *root;

  memset (&p, 0, sizeof p);
  Parse_InitUtf (&p, &pool,read_unit (name), err);
  root = Parse_File (&pool, &p, &pool,err);
  if (err->exc) { fprintf (stderr, "%s: raised %s\n", name, err->exc->name);
                  exit (3); }
  if (p.nerr > 0) { fprintf (stderr, "%s: %lld parse errors\n", name,
                             (long long) p.nerr); exit (1); }
  return root;
}

/* Gen's text is UTF-8 octets since 2026-10-23 (HText, CText answer
   UTF), and was a slice of CHARs before.  This takes both, chosen by
   the type.  lib/gen.sh builds this helper against the checked-in
   runtime/gen first, the previous generator's, and then against the
   one it writes next. */
static inline void put_chars (m9_sl_CHAR s)
{
  int64_t i;
  for (i = 0; i < s.len; i++) m9t_putc (s.p[i]);
}

static inline void put_octets (m9_sl_UTF8 s)
{
  fwrite (s.p, 1, (size_t) s.len, stdout);
}

#define put_text(s) _Generic ((s), m9_sl_CHAR: put_chars, m9_sl_UTF8: put_octets) (s)

static void emit_utf (const char *s, size_t n, m9_state *err)
{
  void (* volatile fp) (void) = (void (*) (void)) Gen_Emit;
  ((void (*) (m9_sl_UTF8, m9_state *)) fp)
    ((m9_sl_UTF8){ (uint8_t *) s, (int64_t) n }, err);
}

static void emit_chars (const char *s, size_t n, m9_state *err)
{
  size_t i;
  uint32_t *nm = malloc (sizeof (uint32_t) * (n ? n : 1));
  for (i = 0; i < n; i++) nm[i] = (uint32_t) (unsigned char) s[i];
  void (* volatile fp) (void) = (void (*) (void)) Gen_Emit;
  ((void (*) (m9_sl_CHAR, m9_state *)) fp)
    ((m9_sl_CHAR){ nm, (int64_t) n }, err);
}

int main (int argc, char **argv)
{
  m9_state err = {0};
  Ast_Node *root, *droot;
  int k;
  int64_t i;

  if (argc < 2) { fprintf (stderr, "usage: gendump_m9 MODULE [DEP ...]\n");
                  return 2; }

  /* STR is the UTF-8 type (the switch, 2026-10-31).  The generator
     gen.sh builds first is the checked-in C's, from before the switch,
     which reads STR as CHARs unless it is told.  The ones after it
     default to UTF, and this changes nothing for them. */
  Sem_SetStrUtf (true, &err);
  Gen_SetStrUtf (true, &err);

  /* Load dependency definitions first, exactly as gendump loads
       them. */
  for (k = 2; k < argc; k++)
    {
      droot = parse_unit (argv[k], &err);
      /* The root goes by VAR, its pool beside it.  A binder on a value
         parameter's component named no pool (2026-10-10). */
      Sem_LoadFile (&droot, &pool, &err);
      for (i = 0; i < droot->nkids; i++)
        if (droot->kids.p[i])
          { Gen_LoadExtern (droot->kids.p[i], &err);
            if (err.exc) { fprintf (stderr, "LoadExtern raised %s\n",
                                    err.exc->name); return 3; } }
    }

  root = parse_unit (argv[1], &err);
  /* Run the checker first, as m9c runs it.  It records the types the
     generator reads (the typed tree, 2026-10-09).  Its diagnostics
     are not this tool's business: semdiff holds them. */
  Sem_LoadFile (&root, &pool, &err);
  Sem_CheckFile (&root, &pool, &err);
  if (err.exc) { fprintf (stderr, "the checker raised %s\n",
                          err.exc->name); return 3; }
  for (i = 0; i < root->nkids; i++)
    if (root->kids.p[i])
      { Ast_Node *u = root->kids.p[i];
        Gen_LoadUnit (&u, &pool, &err);
        if (err.exc) { fprintf (stderr, "LoadUnit raised %s\n",
                                err.exc->name); return 3; } }

  {
    size_t n = strlen (argv[1]);
    /* Gen.Emit takes a UTF since 2026-10-24.  gen.sh builds the stage-1
       generator from the CHECKED-IN C, whose Emit took a STR.  It
       builds the stage-2 one from what it wrote.  Emit's own type
       chooses the call, so one helper serves both passes.  The other
       branch is never called.  Its call goes through a volatile
       pointer, so the compiler cannot hold it to Emit's declared
       type. */
    _Generic ((Gen_Emit),
              void (*)(m9_sl_UTF8, m9_state *): emit_utf,
              default: emit_chars) (argv[1], n, &err);
    if (err.exc) { fprintf (stderr, "Emit raised %s\n", err.exc->name);
                   return 3; }
  }

  put_text (Gen_HText (&err));
  printf ("==== M9GEN SPLIT ====\n");
  put_text (Gen_CText (&err));
  if (Gen_Errs (&err) > 0)
    {
      fprintf (stderr, "%lld gen errors\n", (long long) Gen_Errs (&err));
      return 1;
    }
  return 0;
}
