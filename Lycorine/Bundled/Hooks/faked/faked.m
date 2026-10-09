#include "../Shared/ClonePaths.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <unistd.h>

int main(int argc, char *argv[], char *envp[]) {
    FILE *file = fopen("/var/jb/faked.log", "a");
    if (getpid() == 1) {
        if (file) {
          fputs("[faked] You're closed in, I'm awake / I'm open, you're asleep\n",
                file);
          fflush(file);
        }
    }
    clone_paths_t launchd_paths;
    if (!clone_paths("/sbin/launchd", &launchd_paths)) {
        if (file) fclose(file);
        return 127;
    }

    size_t count = 0;
    while (envp && envp[count]) ++count;
    char **envc = calloc(count + 2, sizeof(*envc));
    if (!envc) {
        if (file) fclose(file);
        return 127;
    }
    size_t used = 0;
    for (size_t i = 0; i < count; ++i) {
        if (strncmp(envp[i], "DYLD_INSERT_LIBRARIES=", 22) == 0 ||
            strncmp(envp[i], "XPC_USERSPACE_REBOOTED=", 23) == 0)
            continue;
        envc[used++] = envp[i];
    }
    envc[used] = "XPC_USERSPACE_REBOOTED=1";
    mount("bindfs", "/usr/lib", MNT_RDONLY, "/var/jb/basebin/.fakelib");
    if (file) {
        fputs("[faked] executing launchd clone\n", file);
        fflush(file);
    }

    argv[0] = "/sbin/launchd";
    posix_spawnattr_t attr;
    int r = posix_spawnattr_init(&attr);
    if (r == 0)
        r = posix_spawnattr_setflags(&attr,
            POSIX_SPAWN_SETEXEC | POSIX_SPAWN_CLOEXEC_DEFAULT);
    pid_t pid = 0;
    if (r == 0)
        r = posix_spawn(&pid, launchd_paths.executable, NULL, &attr, argv,
                        envc);
    if (file) {
        fprintf(file, "[faked] launchd clone exec failed: %d (%s)\n", r,
                strerror(r));
        fclose(file);
    }
    return 127;
}
