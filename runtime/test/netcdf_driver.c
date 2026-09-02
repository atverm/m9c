/* netcdf_driver.c -- NetCDF.m9 against libnetcdf, and against the
   round trip.

   Two kinds of check.  The ROUND TRIP writes a file with the M9
   write path and reads it back with the M9 read path, comparing
   every value with memcmp: a binding that loses a bit is a binding
   that will lose a field.  The DIFFERENTIAL then opens the same file
   with the raw C API in this driver and compares what the two see --
   because a round trip through one binding proves only that it is
   self-consistent, which a binding that swapped two axes would also
   be.

   The refusals are checked too.  A missing file, a wrong-sized
   buffer and a negative extent are all things a caller will do, and
   the C API's answer to two of them is undefined behaviour. */
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <netcdf.h>
#include "NetCDF.h"

static int checks = 0, failed = 0;

static void ok (const char *what, int cond)
{
  checks++;
  if (!cond) { failed++; printf ("FAIL: %s\n", what); }
}

static uint32_t sbuf[8192];
static size_t sused = 0;

static m9_sl_CHAR S (const char *s)
{
  size_t i, n = strlen (s);
  uint32_t *p = sbuf + sused;
  sused += n;
  for (i = 0; i < n; i++) p[i] = (uint32_t) (unsigned char) s[i];
  return (m9_sl_CHAR){ p, (int64_t) n };
}

static char *C (m9_sl_CHAR s, char *out, size_t cap)
{
  size_t i, n = (size_t) s.len < cap - 1 ? (size_t) s.len : cap - 1;
  for (i = 0; i < n; i++) out[i] = (char) s.p[i];
  out[n] = 0;
  return out;
}

#define NLAT 4
#define NLON 5
#define PATH "/tmp/m9_netcdf_test.nc"

int main (void)
{
  m9_state e = { 0 };
  m9_pool pool = { 0 };
  double data[NLAT * NLON], back[NLAT * NLON];
  int i, j;
  char buf[256];

  for (i = 0; i < NLAT; i++)
    for (j = 0; j < NLON; j++)
      data[i * NLON + j] = 100.0 * (double) i + (double) j / 8.0;

  /* ---- write ---- */
  {
    NetCDF_File *f = NetCDF_Create (&pool, S (PATH), true, &e);
    int64_t dlat, dlon, v;
    int64_t dims[2];
    int64_t start[2] = { 0, 0 }, count[2] = { NLAT, NLON };
    ok ("Create", !e.exc);
    dlat = NetCDF_DefDim (f, S ("lat"), NLAT, &e);
    dlon = NetCDF_DefDim (f, S ("lon"), NLON, &e);
    ok ("DefDim", !e.exc);
    dims[0] = dlat; dims[1] = dlon;
    v = NetCDF_DefVar (f, S ("t2m"), NetCDF_TypeDouble,
                       (m9_sl_I64){ dims, 2 }, &e);
    ok ("DefVar", !e.exc);
    NetCDF_PutAttStr (f, v, S ("units"), S ("K"), &e);
    NetCDF_PutAttF64 (f, v, S ("scale_factor"), 0.5, &e);
    NetCDF_PutAttStr (f, NetCDF_Global, S ("title"),
                      S ("written by M9"), &e);
    ok ("attributes", !e.exc);
    NetCDF_EndDef (f, &e);
    ok ("EndDef", !e.exc);
    NetCDF_PutF64 (f, v, (m9_sl_I64){ start, 2 }, (m9_sl_I64){ count, 2 },
                   (m9_sl_F64){ data, NLAT * NLON }, &e);
    ok ("PutF64", !e.exc);
    NetCDF_Close (&f, &e);
    ok ("Close after write", !e.exc);
  }

  /* ---- read it back through M9 ---- */
  {
    NetCDF_File *f = NetCDF_Open (&pool, S (PATH), &e);
    int64_t v;
    int64_t start[2] = { 0, 0 }, count[2] = { NLAT, NLON };
    ok ("Open", !e.exc);
    ok ("DimLenOf lat", NetCDF_DimLenOf (f, S ("lat"), &e) == NLAT);
    ok ("DimLenOf lon", NetCDF_DimLenOf (f, S ("lon"), &e) == NLON);
    v = NetCDF_VarId (f, S ("t2m"), &e);
    ok ("VarId", !e.exc);
    ok ("VarRank", NetCDF_VarRank (f, v, &e) == 2);
    {
      m9_sl_I64 shape = NetCDF_VarShape (&pool, f, v, &e);
      ok ("VarShape", !e.exc && shape.len == 2 &&
          shape.p[0] == NLAT && shape.p[1] == NLON);
    }
    NetCDF_GetF64 (f, v, (m9_sl_I64){ start, 2 }, (m9_sl_I64){ count, 2 },
                   (m9_sl_F64){ back, NLAT * NLON }, &e);
    ok ("GetF64", !e.exc);
    ok ("every value survived the round trip, bit for bit",
        memcmp (data, back, sizeof data) == 0);

    ok ("GetAttF64", NetCDF_GetAttF64 (f, v, S ("scale_factor"), &e) == 0.5);
    ok ("GetAttStr",
        strcmp (C (NetCDF_GetAttStr (&pool, f, v, S ("units"), &e),
                   buf, sizeof buf), "K") == 0);
    ok ("global attribute",
        strcmp (C (NetCDF_GetAttStr (&pool, f, NetCDF_Global, S ("title"),
                                     &e), buf, sizeof buf),
                "written by M9") == 0);
    ok ("HasVar says yes", NetCDF_HasVar (f, S ("t2m"), &e));
    ok ("HasVar says no without raising",
        !NetCDF_HasVar (f, S ("nope"), &e) && !e.exc);

    /* a hyperslab: one row, offset */
    {
      double row[NLON];
      int64_t s2[2] = { 2, 0 }, c2[2] = { 1, NLON };
      NetCDF_GetF64 (f, v, (m9_sl_I64){ s2, 2 }, (m9_sl_I64){ c2, 2 },
                     (m9_sl_F64){ row, NLON }, &e);
      ok ("a hyperslab reads the row it names",
          !e.exc && memcmp (row, data + 2 * NLON, sizeof row) == 0);
    }

    /* ReadGrid2: shape and values, indexed per axis */
    {
      m9_gd2_double g = NetCDF_ReadGrid2 (&pool, f, S ("t2m"), &e);
      int bad = 0;
      ok ("ReadGrid2 shape", !e.exc && g.n[0] == NLAT && g.n[1] == NLON);
      for (i = 0; i < NLAT; i++)
        for (j = 0; j < NLON; j++)
          if (g.p[i * NLON + j] != data[i * NLON + j]) bad++;
      ok ("ReadGrid2 values", bad == 0);
      {
        int64_t idx[3] = { 0, NLON, 0 };
        (void) m9_gat (g.p, sizeof (double), g.n, g.s, idx, 2, &e);
        ok ("and the grid checks its own axes",
            e.exc == &m9_exc_IndexError);
        e.exc = NULL;
      }
    }

    /* the refusals */
    {
      double small[2];
      int64_t c3[2] = { NLAT, NLON };
      NetCDF_GetF64 (f, v, (m9_sl_I64){ start, 2 }, (m9_sl_I64){ c3, 2 },
                     (m9_sl_F64){ small, 2 }, &e);
      ok ("a buffer smaller than the slab raises SizeError",
          e.exc == &NetCDF_SizeError && e.i[0] == 2 &&
          e.i[1] == NLAT * NLON);
      e.exc = NULL;
    }
    {
      int64_t neg[2] = { -1, 0 };
      NetCDF_GetF64 (f, v, (m9_sl_I64){ neg, 2 }, (m9_sl_I64){ count, 2 },
                     (m9_sl_F64){ back, NLAT * NLON }, &e);
      ok ("a negative offset raises ValueRange, not a huge size_t",
          e.exc == &m9_exc_ValueRange);
      e.exc = NULL;
    }
    {
      NetCDF_VarId (f, S ("absent"), &e);
      ok ("a missing variable raises Error", e.exc == &NetCDF_Error);
      ok ("...carrying the operation",
          e.exc && strcmp (C ((m9_sl_CHAR){ (uint32_t *) e.s[0].p, e.s[0].len },
                              buf, sizeof buf), "nc_inq_varid") == 0);
      ok ("...and the library's own message",
          e.exc && strstr (C ((m9_sl_CHAR){ (uint32_t *) e.s[1].p, e.s[1].len },
                              buf, sizeof buf), "Variable not found"));
      e.exc = NULL;
    }
    NetCDF_Close (&f, &e);
    ok ("Close after read", !e.exc);
  }

  {
    NetCDF_Open (&pool, S ("/nonexistent/nope.nc"), &e);
    ok ("opening a missing file raises rather than halting",
        e.exc == &NetCDF_Error);
    e.exc = NULL;
  }

  /* ---- the differential: the same file, through the C API ---- */
  {
    int ncid, varid, status;
    double cdata[NLAT * NLON];
    size_t start[2] = { 0, 0 }, count[2] = { NLAT, NLON };
    status = nc_open (PATH, NC_NOWRITE, &ncid);
    ok ("the file M9 wrote opens with the C API", status == NC_NOERR);
    status = nc_inq_varid (ncid, "t2m", &varid);
    ok ("the variable is where the C API expects it", status == NC_NOERR);
    status = nc_get_vara_double (ncid, varid, start, count, cdata);
    ok ("the C API reads the same bytes",
        status == NC_NOERR && memcmp (cdata, data, sizeof data) == 0);
    {
      size_t alen = 0;
      char att[64] = { 0 };
      nc_inq_attlen (ncid, varid, "units", &alen);
      nc_get_att_text (ncid, varid, "units", att);
      ok ("the attribute is a real attribute",
          alen == 1 && att[0] == 'K');
    }
    {
      int ndims = 0;
      nc_inq_varndims (ncid, varid, &ndims);
      ok ("the rank agrees", ndims == 2);
    }
    nc_close (ncid);
  }

  m9_pool_free (&pool);
  printf (failed ? "FAIL (%d of %d checks)\n" : "PASS (%d checks)\n",
          failed ? failed : checks, checks);
  return failed != 0;
}
