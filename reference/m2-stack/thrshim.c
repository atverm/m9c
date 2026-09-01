#include <pthread.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>
typedef void (*m2worker)(void*);
static m2worker g_fn;
static long ids[64];
static void *tramp(void *a){ g_fn(a); return 0; }
int run_parallel(m2worker fn, long n){
    pthread_t t[64]; g_fn = fn;
    for (long i = 0; i < n; i++){ ids[i] = i; pthread_create(&t[i], 0, tramp, &ids[i]); }
    for (long i = 0; i < n; i++) pthread_join(t[i], 0);
    return 0;
}
double now_ms(void){
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec*1000.0 + ts.tv_nsec/1e6;
}
long slurp(const char *path, void *buf, long max){   /* thread-safe file read */
    int fd = open(path, O_RDONLY); if (fd < 0) return -1;
    long total = 0, n;
    while ((n = read(fd, (char*)buf + total, max - total)) > 0) total += n;
    close(fd); return total;
}
