#include <sys/socket.h>
#include <netdb.h>
#include <string.h>
#include <stdio.h>
int tcp_connect(const char *host, int port){
    char ps[16]; snprintf(ps, sizeof ps, "%d", port);
    struct addrinfo hints = {0}, *res;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, ps, &hints, &res)) return -1;
    int fd = socket(res->ai_family, res->ai_socktype, 0);
    if (fd >= 0 && connect(fd, res->ai_addr, res->ai_addrlen)) { fd = -1; }
    freeaddrinfo(res);
    return fd;
}
