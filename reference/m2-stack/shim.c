#include <stdio.h>
void printd(const char *label, double v){ printf("%s%.13g\n", label, v); }
void printn(const char *label, long n){ printf("%s%ld\n", label, n); }
#include <stdio.h>
int fmt_g(char *dst, double v){ return sprintf(dst, "%.4g", v); }
