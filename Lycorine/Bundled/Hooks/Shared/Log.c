#include "Log.h"
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>

void hook_log(const char *component, const char *path, const char *format, ...) {
    int saved_errno = errno;
    char message[2048];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(message, sizeof(message), format, arguments);
    va_end(arguments);

    int fd = path ? open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0600) : -1;
    if (fd >= 0) {
        dprintf(fd, "[%s pid=%d] %s\n", component, getpid(), message);
        close(fd);
    } else {
        fprintf(stderr, "[%s pid=%d] %s\n", component, getpid(), message);
    }
    errno = saved_errno;
}
