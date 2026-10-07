-- The table PgTest and tools/pggold.py both read: run by each, in its
-- own session, as one script.  TEMP, so a test leaves nothing behind
-- and two runs never meet.  Each row is there for a reason:
--   1  ordinary values, a fraction of a second, a zone of +02
--   2  empty text (not NULL), zero, negative zero, the epoch
--   3  every column NULL
--   4  blanks inside text, a long numeric, a subnormal-adjacent
--      double, a leap day at a half-hour zone, a NULL inside an array
--   5  text outside Latin-1, a 3-octet and a 4-octet code point,
--      NaN, a negative numeric
--   6  quotes of both kinds, an int8 a double cannot hold, +Infinity,
--      a zone of +14
--   7  a line feed and a tab inside text, the smallest int8 as
--      numeric, -Infinity, one microsecond
--   8  the smallest int8 as the key itself
CREATE TEMP TABLE m9t (
  id int8 PRIMARY KEY,
  txt text,
  num numeric,
  f8 double precision,
  b boolean,
  ts timestamptz,
  arr int4[]
);
INSERT INTO m9t VALUES
  (1, 'plain', 1.5, 1.5, true, '2026-10-06 21:26:48.123456+02', '{1,2,3}'),
  (2, '', 0, '-0', false, '1970-01-01 00:00:00+00', '{}'),
  (3, NULL, NULL, NULL, NULL, NULL, NULL),
  (4, 'a b  c', 123456789.123456789, 1e-300, true, '2000-02-29 23:59:59.5-05:30', '{1,NULL}'),
  (5, 'Zürich ✓ 𝄞', -42, 'NaN', false, '1999-12-31 23:59:59+00', '{-1}'),
  (6, 'it''s "quoted"', 9007199254740993, 'Infinity', true, '2026-01-01 00:00:00+14', '{}'),
  (7, E'line\nbreak\ttab', -9223372036854775808, '-Infinity', false, '2026-06-30 12:00:00.000001+00', '{}'),
  (-9223372036854775808, 'min', 0.1, 0.1, true, '1900-01-01 00:00:00+01', '{}');
