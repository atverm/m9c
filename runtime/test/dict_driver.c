/* dict_driver.c -- Dict.m9 through the generator, exercised from C.
   Four design decisions get tested, one per claim: the value is a
   VARIANT so heterogeneous tables need no second module, iteration
   is insertion-ordered across growth and rehash, keys are BORROWED
   (a mutated source shows through the table), and absence is an
   exception rather than a sentinel -- because with a variant value
   there is no spare bit pattern to reserve for "missing".          */
#include <stdio.h>
#include <string.h>
#include "Dict.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

/* A CHAR slice over a C string.  Dict BORROWS keys, so every key
   needs storage that outlives the table: this bumps through one
   arena and never recycles.  An earlier version of this driver
   rotated 64 buffers and watched the first keys rot out from under
   the table -- the contract doing exactly what it says.            */
static uint32_t arena[64 * 1024];
static size_t used = 0;

static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p = arena + used;
  used += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static int slice_is (m9_sl_CHAR a, const char *s)
{
  size_t n = strlen (s);
  int64_t i;
  if (a.len != (int64_t) n) return 0;
  for (i = 0; i < a.len; i++)
    if (a.p[i] != (uint32_t) (unsigned char) s[i]) return 0;
  return 1;
}

/* the variant constructors, as M9 writes Dict.Value.Int (n) */
static Dict_Value VInt (int64_t n)
{ Dict_Value v; v.tag = Dict_Value_Int; v.u.Int.i = n; return v; }
static Dict_Value VStr (const char *s)
{ Dict_Value v; v.tag = Dict_Value_Str; v.u.Str.s = S (s); return v; }
static Dict_Value VReal (double x)
{ Dict_Value v; v.tag = Dict_Value_Real; v.u.Real.x = x; return v; }
static Dict_Value VBool (bool b)
{ Dict_Value v; v.tag = Dict_Value_Bool; v.u.Bool.b = b; return v; }
static Dict_Value VNull (void)
{ Dict_Value v; memset (&v, 0, sizeof v); v.tag = Dict_Value_Null; return v; }

static int is_int (Dict_Value v, int64_t n)
{ return v.tag == Dict_Value_Int && v.u.Int.i == n; }

int main (void)
{
  m9_pool pool = {0};
  m9_state err = {0};
  Dict_Dict *d;
  Dict_Value v;
  int64_t i;
  char name[32];

  d = Dict_New (&pool, &err);
  ok ("new is empty", Dict_Count (d, &err) == 0);

  Dict_Put (&pool, &d, S ("alpha"), VInt (10), &err);
  Dict_Put (&pool, &d, S ("beta"), VInt (20), &err);
  Dict_Put (&pool, &d, S ("gamma"), VInt (30), &err);
  ok ("three keys", Dict_Count (d, &err) == 3);
  ok ("get alpha", is_int (Dict_Get (d, S ("alpha"), &err), 10));
  ok ("get beta", is_int (Dict_Get (d, S ("beta"), &err), 20));
  ok ("get gamma", is_int (Dict_Get (d, S ("gamma"), &err), 30));
  ok ("no error so far", err.exc == NULL);

  ok ("has known", Dict_Has (d, S ("beta"), &err));
  ok ("has unknown", !Dict_Has (d, S ("delta"), &err));

  /* one table, mixed values: the whole reason the value is a variant.
     A config or a database row is heterogeneous by nature. */
  Dict_Put (&pool, &d, S ("host"), VStr ("localhost"), &err);
  Dict_Put (&pool, &d, S ("ratio"), VReal (0.25), &err);
  Dict_Put (&pool, &d, S ("debug"), VBool (true), &err);
  Dict_Put (&pool, &d, S ("absent"), VNull (), &err);
  v = Dict_Get (d, S ("host"), &err);
  ok ("string value tag", v.tag == Dict_Value_Str);
  ok ("string value bytes", slice_is (v.u.Str.s, "localhost"));
  v = Dict_Get (d, S ("ratio"), &err);
  ok ("real value", v.tag == Dict_Value_Real && v.u.Real.x == 0.25);
  v = Dict_Get (d, S ("debug"), &err);
  ok ("bool value", v.tag == Dict_Value_Bool && v.u.Bool.b);
  v = Dict_Get (d, S ("absent"), &err);
  ok ("null value", v.tag == Dict_Value_Null);
  ok ("mixed values raised nothing", err.exc == NULL);

  /* replacing keeps the value AND the original position, and may
     change the variant: a row's column can be re-typed */
  Dict_Put (&pool, &d, S ("alpha"), VStr ("eleven"), &err);
  v = Dict_Get (d, S ("alpha"), &err);
  ok ("replace changes variant", v.tag == Dict_Value_Str);
  ok ("replace does not grow", Dict_Count (d, &err) == 7);
  ok ("replace keeps position", slice_is (Dict_KeyAt (d, 0, &err), "alpha"));
  Dict_Put (&pool, &d, S ("alpha"), VInt (11), &err);

  /* every bit pattern is a value some caller meant to store, so
     absence cannot be a sentinel -- it is an exception carrying the
     key that was missing */
  ok ("find present", Dict_Find (d, S ("beta"), &v, &err) && is_int (v, 20));
  ok ("find absent is false", !Dict_Find (d, S ("nope"), &v, &err));
  ok ("find never raises", err.exc == NULL);
  Dict_Get (d, S ("nope"), &err);
  ok ("get absent raises", err.exc == &Dict_NotFound);
  {
    const uint32_t *kp = (const uint32_t *) err.s[0].p;
    ok ("payload is the key",
        err.s[0].len == 4 && kp[0] == 'n' && kp[3] == 'e');
  }
  err.exc = NULL;

  /* growth: 200 keys forces several rehashes of both arrays */
  for (i = 0; i < 200; i++)
    {
      snprintf (name, sizeof name, "k%lld", (long long) i);
      Dict_Put (&pool, &d, S (name), VInt (i * 7), &err);
    }
  ok ("count after growth", Dict_Count (d, &err) == 207);
  ok ("growth raised nothing", err.exc == NULL);

  for (i = 0; i < 200; i++)
    {
      snprintf (name, sizeof name, "k%lld", (long long) i);
      if (!is_int (Dict_Get (d, S (name), &err), i * 7)) break;
    }
  ok ("all 200 survive rehash", i == 200);
  ok ("earlier keys survive too", is_int (Dict_Get (d, S ("gamma"), &err), 30));
  v = Dict_Get (d, S ("host"), &err);
  ok ("string survives rehash", slice_is (v.u.Str.s, "localhost"));

  /* insertion order survives every rehash -- the whole point */
  ok ("order[0]", slice_is (Dict_KeyAt (d, 0, &err), "alpha"));
  ok ("order[1]", slice_is (Dict_KeyAt (d, 1, &err), "beta"));
  ok ("order[2]", slice_is (Dict_KeyAt (d, 2, &err), "gamma"));
  ok ("order[3]", slice_is (Dict_KeyAt (d, 3, &err), "host"));
  ok ("order[7]", slice_is (Dict_KeyAt (d, 7, &err), "k0"));
  ok ("order[206]", slice_is (Dict_KeyAt (d, 206, &err), "k199"));
  ok ("value at 206", is_int (Dict_ValAt (d, 206, &err), 199 * 7));
  ok ("ordered walk raised nothing", err.exc == NULL);

  Dict_KeyAt (d, 207, &err);
  ok ("KeyAt out of range raises", err.exc == &m9_exc_IndexError);
  ok ("IndexError payload", err.i[0] == 207 && err.i[1] == 207);
  err.exc = NULL;

  /* keys are borrowed, and that is a documented promise rather than
     an implementation detail: mutate the caller's storage and the
     table shows the change, because it never took a copy */
  {
    m9_sl_CHAR k = S ("mutable");
    Dict_Put (&pool, &d, k, VInt (99), &err);
    ok ("borrowed key found before",
        is_int (Dict_Get (d, S ("mutable"), &err), 99));
    ((uint32_t *) k.p)[0] = 'M';
    ok ("table sees the mutation",
        slice_is (Dict_KeyAt (d, Dict_Count (d, &err) - 1, &err), "Mutable"));
    ok ("old spelling no longer found", !Dict_Has (d, S ("mutable"), &err));
    ok ("borrow checks raised nothing", err.exc == NULL);
  }

  /* the hash is pinned, not just its effects: a polynomial mod a
     prime, so the value is reproducible by hand */
  {
    int64_t h = 0; const char *s = "alpha"; size_t k;
    for (k = 0; k < strlen (s); k++)
      h = (h * 33 + (unsigned char) s[k]) % 1000003;
    ok ("hash matches the stated recurrence",
        Dict_Hash (S ("alpha"), &err) == h);
    ok ("hash stays in range", h >= 0 && h < 1000003);
  }
  ok ("empty key hashes to zero", Dict_Hash (S (""), &err) == 0);

  m9_pool_free (&pool);
  if (failed == 0) printf ("PASS (%d checks)\n", checks);
  else printf ("FAILED %d of %d\n", failed, checks);
  return failed != 0;
}
