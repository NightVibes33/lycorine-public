#include "spawn.h"
#include "../Shared/ClonePaths.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static const char *own_executable(void) {
    static char cached[PATH_MAX];
    static bool resolved = false;
    if (!resolved) {
        uint32_t len = sizeof(cached);
        if (_NSGetExecutablePath(cached, &len) == 0) {
            resolved = true;
        } else {
            cached[0] = '\0';
        }
    }
    return cached;
}

static void log_faked(const char *event, int result) {
    int saved_errno = errno;
    int fd = open("/var/jb/lycorine-pid1.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        dprintf(fd, "[launchd] %s result=%d\n", event, result);
        fsync(fd);
        close(fd);
    }
    errno = saved_errno;
}

static int spawn_reboot(spawn_function_t original, pid_t *pid, const char *path,
                        const posix_spawn_file_actions_t *actions,
                        const posix_spawnattr_t *attributes, char *const argv[],
                        char *const envp[]) {
    if (path == NULL || strcmp(path, "/sbin/launchd") != 0) {
        return -1;
    }

    clone_paths_t launchd_paths;
    clone_paths_t faked_paths;
    if (!clone_paths(path, &launchd_paths) ||
        !clone_paths("/usr/libexec/lycorine/faked", &faked_paths)) {
        return -1;
    }

    const char *self = own_executable();
    bool stock_caller = strcmp(self, path) == 0;
    if (!stock_caller) {
        char actual[PATH_MAX];
        char clone[PATH_MAX];
        if (realpath(self, actual) == NULL || realpath(launchd_paths.executable, clone) == NULL) {
            return -1;
        }
        if (strcmp(actual, clone) != 0) {
            return -1;
        }
    }

    short flags = 0;
    if (attributes == NULL || posix_spawnattr_getflags(attributes, &flags) != 0) {
        return -1;
    }
    if ((flags & POSIX_SPAWN_SETEXEC) == 0) {
        return -1;
    }

    char **copy = NULL;
    if (argv) {
        size_t count = 0;
        while (argv[count]) {
            ++count;
        }
        copy = calloc(count + 1, sizeof(*copy));
        if (copy == NULL) {
            return -1;
        }
        if (count != 0) {
            copy[0] = faked_paths.executable;
        }
        for (size_t i = 1; i < count; ++i) {
            copy[i] = argv[i];
        }
    }

    int result =
        original(pid, faked_paths.executable, actions, attributes, copy ? copy : argv, envp);
    log_faked("self-spawn -> faked returned", result);
    free(copy);
    if (result != 0 && stock_caller) {
        return original(pid, path, actions, attributes, argv, envp);
    }
    return result;
}

spawn_function_t orig_posix_spawn;
spawn_function_t orig_posix_spawnp;

static int dispatch_spawn(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                          const posix_spawn_file_actions_t *actions,
                          const posix_spawnattr_t *attributes, char *const argv[],
                          char *const envp[]) {
    int result = spawn_dispatch(original, pid, path, search_path, actions, attributes, argv, envp);
    if (result == -1)
        result = spawn_reboot(original, pid, path, actions, attributes, argv, envp);
    if (result == -1)
        result = original(pid, path, actions, attributes, argv, envp);
    return result;
}

int hook_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                     const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
    return dispatch_spawn(orig_posix_spawn, pid, path, false, actions, attributes, argv, envp);
}

int hook_posix_spawnp(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                      const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
    return dispatch_spawn(orig_posix_spawnp, pid, path, true, actions, attributes, argv, envp);
}
