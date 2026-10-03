# Mat

Dense 2-D matrices of F64 with NaN-aware, loop-free operations.
The FOR loops have not gone anywhere: they moved in here, were
written once, and are auto-vectorised by the compiler.  This is
also all numpy ever promised.

### TYPE Matrix

opaque; lives in a POOL

### TYPE ReduceOp

the M2 enumeration: an empty-variant CASE RECORD is M9's
enumeration, and CASE over it must be total.  The first layout
of this declaration put the variants in a margin comment's
interior -- the lexer shrugged, the parser refused; P1 caught a
corpus bug on its first run.

### New (VAR pool: POOL ; rows, cols: I64) : PTR Matrix IN pool RAISES Faults.SizeError

nonpositive dimensions are Faults.SizeError at the door, not a zero-
element surprise later.  Storage is defined-zero (par 4.3): the
M2 version handed out uninitialized REALs.

### Rows (m: PTR Matrix) : I64

_(documented with the group below)_

### Cols (m: PTR Matrix) : I64

the two extents.  They are asked of the MATRIX and not carried
beside it by the caller, which is the whole reason this type
became a GRID 2 OF F64: when the shape lived in the caller's
head, Get (m, 0, 3) on a 2x3 matrix answered element (1,0) and
raised nothing, because index 3 is inside a 6-element flat
slice.  Now every axis is checked against its own extent.

### Get (m: PTR Matrix ; r, c: I64) : F64

_(documented with the group below)_

### Set (VAR m: PTR Matrix ; r, c: I64 ; v: F64)

r/c bounds are checked runtime errors like all indexing:
always on, undeclarable, catchable.

### ColReduce (m: PTR Matrix ; op: ReduceOp ; out: SLICE OF F64) RAISES Faults.SizeError

out[c] receives the NaN-aware statistic of column c.  The M2
version silently skipped columns beyond HIGH (out); here
LEN (out) # Cols (m) is Faults.SizeError, said out loud.

### SubRowVector (VAR pool: POOL ; m: PTR Matrix ; RO v: SLICE OF F64) : PTR Matrix IN pool RAISES Faults.SizeError

result[r,c] := m[r,c] - v[c], broadcast over rows

### MinMax (m: PTR Matrix ; VAR mn, mx: F64)

NaN-aware global range.  All-NaN input answers NaN twice --
the M2 version answered 0.0, which is a lie with digits.

### EXCEPTION NotSPD

Cholesky met a nonpositive pivot at this row: the matrix is not
symmetric positive definite.  For a covariance matrix that is a
data or modelling error worth a name, not a NaN worth nothing.

### MulM (VAR pool: POOL ; a, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

a (r x k) times b (k x c); Cols (a) # Rows (b) is Faults.SizeError

### MulV (VAR pool: POOL ; a: PTR Matrix ; RO x: SLICE OF F64) : PTR Matrix IN pool RAISES Faults.SizeError

a times a column vector, answered as an n x 1 matrix so it can
feed straight back into MulM/CholSolve

### Transpose (VAR pool: POOL ; m: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

_(undocumented)_

### AddM (VAR pool: POOL ; a, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

_(documented with the group below)_

### SubM (VAR pool: POOL ; a, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

_(documented with the group below)_

### Scale (VAR m: PTR Matrix ; s: F64)

in place, the one mutator: scaling allocates nothing

### Identity (VAR pool: POOL ; n: I64) : PTR Matrix IN pool RAISES Faults.SizeError

_(undocumented)_

### CopyM (VAR pool: POOL ; m: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

_(undocumented)_

### Cholesky (VAR pool: POOL ; a: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError, NotSPD, ValueRange

the lower-triangular L with L L^T = a.  Only the lower triangle
of a is read, which is the usual contract and means a matrix
that is SPD in its lower half is never betrayed by garbage in
its upper.

### CholSolve (VAR pool: POOL ; l, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError

solve A X = B given L = Cholesky (A); B may carry many columns,
which is how the Kalman-style gain is built in one call

### SpdInverse (VAR pool: POOL ; a: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError, NotSPD, ValueRange

CholSolve against the identity: the posterior covariance step

### CholeskyT (VAR pool: POOL ; a: PTR Matrix ; threads: I64) : PTR Matrix IN pool RAISES Faults.SizeError, NotSPD, ValueRange

Cholesky's factor, computed BLOCKED and on threads (2026-09-15):
the lower triangle of a is copied and factored in place, panel
by panel -- the diagonal block serially, the rows below it as
independent forward substitutions, the trailing lower triangle
updated a row at a time -- with the rows of the last two steps
claimed in bands by `threads` workers.  Every cell sees the
same subtractions in the same order the serial Cholesky applies
(k ascending, one running value, never a panel dot product
subtracted whole), so the factor is BIT-IDENTICAL to Cholesky's
at any thread count; the gate holds it so.  On 16 629 unknowns
the serial factorisation was the last single-threaded minutes
of a solve whose other stages were already banded.

### CholInverse (VAR pool: POOL ; KEPT l: PTR Matrix ; threads: I64) : PTR Matrix IN pool RAISES Faults.SizeError

(L L^T)^-1 from the factor Cholesky answered, in two contiguous
passes on `threads` threads (2026-09-15, the year inversion's
8-hour inverse):

  T = (L^-1)^T   row j of T is column j of L^-1: a forward
                 substitution against the identity's column j,
                 zero above j, reading row i of L along its
                 columns -- contiguous, and the zeros halve it;
  P = T T^T      P[a,b] = sum over k >= max(a,b) of T[a,k] T[b,k]
                 -- two rows read along their columns.

SpdInverse's back substitution read the factor DOWN a column for
each of n identity columns, a cache miss per multiply: n = 16 629
took 8 hours; this takes n^3/3 flops instead of n^3 and reads
memory the way it lies.  Columns of T and rows of P are
independent, so the work is claimed in bands by `threads`
workers, each writing only its own rows; the arithmetic of every
cell is the same in the same order whatever the thread count, so
the answer is bit-identical for 1 and for 32.  threads <= 1 runs
in the caller's thread.

### AddNormal (h: PTR Matrix ; RO w: SLICE OF F64 ; VAR k: PTR Matrix ; threads: I64) RAISES Faults.SizeError

k := k + H^T diag (w) H, the normal matrix of a weighted least
squares, accumulated where it lies: one pass over the rows of H
per band of columns, zeros of H skipped, the upper triangle
computed and the lower mirrored at the end.  A worker owns a band
of rows of k and reads every row of H, so nothing is written
twice; the per-cell sums run over the rows of H ascending in
every band, as the serial loop did, so the result does not depend
on the thread count.

### EXCEPTION Singular

no pivot at this column.  In Solve, Inverse and Det that is a
pivot EXACTLY zero, LAPACK's own test: the matrix has no
inverse.  A matrix that is merely close to singular raises
nothing there and answers with few digits, as it does
everywhere -- its condition number is the caller's to know.  In
LstSq it is a column that adds nothing to the columns before it
beyond rounding: the problem has no unique answer.

### EXCEPTION NoConverge

the Jacobi iteration of Svd or EigSym did not settle in this
many sweeps.  Not seen on a finite matrix; an infinity inside
one does it.

### Solve (VAR pool: POOL ; a, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError, Singular

the X with A X = B, A square, by LU with partial pivoting
(numpy.linalg.solve); B may carry many columns

### Det (a: PTR Matrix) : F64 RAISES Faults.SizeError

the determinant, from the same factorisation: the product of the
pivots, negated once for every row exchange.  0.0 for a matrix
whose elimination meets a zero pivot.

### Inverse (VAR pool: POOL ; a: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError, Singular

Solve against the identity (numpy.linalg.inv).  To solve a
system, Solve it: an inverse multiplied in costs three times
the work and loses digits.

### Qr (VAR pool: POOL ; a: PTR Matrix ; VAR q, r: PTR Matrix) RAISES Faults.SizeError, ValueRange

a = q r by Householder reflections, in the reduced form: for a
of m x n and k the smaller of the two, q is m x k with
orthonormal columns and r is k x n, zero below its diagonal
(numpy.linalg.qr, mode 'reduced').  THE DIAGONAL OF r IS NEVER
NEGATIVE: a factorisation is unique only up to the sign of each
column of q, and this is the one that is said.  ValueRange is a
NaN in a: it cannot travel through a square root.

### LstSq (VAR pool: POOL ; a, b: PTR Matrix) : PTR Matrix IN pool RAISES Faults.SizeError, Singular, ValueRange

the X that makes A X - B smallest, column by column, in the
least-squares sense: A of m x n with m >= n and full column
rank, B of m rows, X of n rows (numpy.linalg.lstsq).  Through
QR, never through the normal equations, which square the
condition number.  Fewer equations than unknowns is
Faults.SizeError, and a column that is a combination of earlier
ones is Singular: neither has ONE answer, and the smallest of
the many is Svd's to find.

### Svd (VAR pool: POOL ; a: PTR Matrix ; VAR u: PTR Matrix ; VAR s: SLICE OF F64 ; VAR vt: PTR Matrix) RAISES Faults.SizeError, NoConverge, ValueRange

a = u diag (s) vt, the singular value decomposition without the
full matrices: for a of m x n and k the smaller, u is m x k, s
has k values, vt is k x n (numpy.linalg.svd, full_matrices
False).  LEN (s) must be k.  The values DESCEND and are never
negative.  A pair of singular vectors is unique only up to one
sign, and this is the one that is said: the component of
largest magnitude of each row of vt is positive.

By one-sided Jacobi rotations, which find small singular values
to their own precision.  Where a value is exactly zero the
matrix does not determine its vector on the side that was
iterated, and that vector is answered as zeros.

### EigSym (VAR pool: POOL ; a: PTR Matrix ; VAR w: SLICE OF F64 ; VAR v: PTR Matrix) RAISES Faults.SizeError, NoConverge, ValueRange

the eigenvalues w, ASCENDING, and the eigenvectors, the COLUMNS
of v, of a symmetric matrix: a v = v diag (w) (numpy.linalg.eigh).
Only the lower triangle of a is read, as Cholesky reads it.
LEN (w) must be the matrix's order.  Each vector's component of
largest magnitude is positive.  By Jacobi rotations.  A general
matrix has complex eigenvalues and is not this procedure's.
