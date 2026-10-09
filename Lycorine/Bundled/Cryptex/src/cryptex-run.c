#include <errno.h>
#include <os/log.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    os_log_t log = os_log_create("com.saccharine.lycorine.recovery", "cryptex-run");
    if (argc < 2) {
        os_log_error(log, "usage: cryptex-run PROGRAM [ARG ...]");
        return EXIT_FAILURE;
    }

    const char *root = getenv("CRYPTEX_MOUNT_PATH");
    if (root == NULL || root[0] != '/') {
        os_log_error(log, "CRYPTEX_MOUNT_PATH is missing or invalid");
        return EXIT_FAILURE;
    }

    const char *old_path = getenv("PATH");
    if (old_path == NULL) old_path = "/usr/bin:/bin:/usr/sbin:/sbin";

    char *path = NULL;
    if (asprintf(&path, "%s/usr/bin:%s/usr/sbin:%s/usr/libexec:%s",
                 root, root, root, old_path) < 0) {
        os_log_error(log, "could not construct PATH");
        return EXIT_FAILURE;
    }
    if (setenv("PATH", path, 1) != 0) {
        os_log_error(log, "setenv failed: %{public}s", strerror(errno));
        free(path);
        return EXIT_FAILURE;
    }

    execvP(argv[1], path, &argv[1]);
    os_log_error(log, "exec %{public}s failed: %{public}s", argv[1], strerror(errno));
    free(path);
    return EXIT_FAILURE;
}

