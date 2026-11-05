/* yk.h says what YieldMark's mark becomes in each variant of the
   yield probe (bench/yieldprobe.sh; docs/task-plan.md, sections
   "Yield checks, priced" and "Preemption").  Every loop's head holds

     M9_YCHK(K, LOOP, CALL, NONLEAF, NESTED)

   with four facts, each 0 or 1: its body holds a loop; it calls an M9
   procedure; it calls one that is not a leaf procedure (no loop, only
   leaf calls); the loop is inside another loop of its procedure.
   M9_YIELD picks the variant:

     0  nothing: the base
     1  a relaxed load of one global int at every loop's head, and a
        call when it is set
     2  the same on a _Thread_local int, a per-carrier flag
     3  option 2: variant 1's check where the body holds a loop or a
        call
     4  option 3: a counter per loop, the flag read every 1,024 turns
     5  options 2 and 3: the counted check where variant 3 checks
     6  option 2 with leaf procedures: the check where the body holds
        a loop or calls a procedure that is not a leaf
     7  the outermost loop of a procedure, and any loop that calls a
        procedure that is not a leaf
     8  the outermost loop of a nest (a loop that holds a loop, in no
        other), and any loop that calls a procedure that is not a
        leaf: a leaf loop never, and an inner loop only for its calls
     9  the outermost loop of a procedure, when it holds a loop or calls
        a procedure that is not a leaf: one check a procedure's loop
        nest at most

   The condition is made of constants, and the compiler folds it.  The
   flag stays 0 unless M9_YFLAG is set (ykslow.c), so the slow call
   never runs. */
#if M9_YIELD >= 1
extern int m9_yflag;
extern _Thread_local int m9_yflag_t;
void m9_yslow (void);
#define M9_YG do { if (__builtin_expect (__atomic_load_n (&m9_yflag, __ATOMIC_RELAXED), 0)) m9_yslow (); } while (0)
#define M9_YT do { if (__builtin_expect (__atomic_load_n (&m9_yflag_t, __ATOMIC_RELAXED), 0)) m9_yslow (); } while (0)
#define M9_YC(K) do { if (__builtin_expect (--m9_yc##K == 0, 0)) { m9_yc##K = 1024; M9_YG; } } while (0)
#endif

#if M9_YIELD == 1
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) M9_YG
#elif M9_YIELD == 2
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) M9_YT
#elif M9_YIELD == 3
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { if ((A) || (C)) M9_YG; } while (0)
#elif M9_YIELD == 4
#define M9_YDECL(K) int m9_yc##K = 1024;
#define M9_YCHK(K, A, C, N, D) M9_YC(K)
#elif M9_YIELD == 5
#define M9_YDECL(K) __attribute__ ((unused)) int m9_yc##K = 1024;
#define M9_YCHK(K, A, C, N, D) do { if ((A) || (C)) M9_YC(K); } while (0)
#elif M9_YIELD == 6
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { if ((A) || (N)) M9_YG; } while (0)
#elif M9_YIELD == 7
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { if (!(D) || (N)) M9_YG; } while (0)
#elif M9_YIELD == 8
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { if (((A) && !(D)) || (N)) M9_YG; } while (0)
#elif M9_YIELD == 9
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { if (((A) || (N)) && !(D)) M9_YG; } while (0)
#else
#define M9_YDECL(K)
#define M9_YCHK(K, A, C, N, D) do { } while (0)
#endif
