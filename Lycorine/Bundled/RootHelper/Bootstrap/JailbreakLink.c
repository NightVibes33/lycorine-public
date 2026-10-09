#include "JailbreakLink.h"
#include "../Core/utils.h"
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *link_path = "/var/jb";

static int link_state(void)
{
    struct stat info;
    char target[PATH_MAX];
    ssize_t length;
    const char *target_path = procursuspath();
    if (target_path == NULL) return -EIO;

    if (lstat(link_path, &info) != 0)
        return errno == ENOENT ? 0 : -errno;
    if (!S_ISLNK(info.st_mode))
        return -EEXIST;
    length = readlink(link_path, target, sizeof(target) - 1);
    if (length < 0)
        return -errno;
    target[length] = '\0';
    return strcmp(target, target_path) == 0 ? 1 : -EEXIST;
}

int hideJailbreak(void)
{
    int state = link_state();
    if (state < 0) return -state;
    if (state == 0) return 0;
    return unlink(link_path) == 0 ? 0 : errno;
}

int unhideJailbreak(void)
{
    struct stat info;
    const char *target_path = procursuspath();
    if (target_path == NULL) return EIO;
    int state = link_state();
    if (state < 0) return -state;
    if (state == 1) return 0;
    if (stat(target_path, &info) != 0) return errno;
    if (!S_ISDIR(info.st_mode)) return ENOTDIR;
    if (symlink(target_path, link_path) == 0) return 0;
    if (errno == EEXIST && link_state() == 1) return 0;
    return errno;
}
