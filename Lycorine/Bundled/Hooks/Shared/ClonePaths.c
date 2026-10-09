#include "ClonePaths.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

bool clone_paths(const char *source, clone_paths_t *paths) {
    if (!source || source[0] != '/') return false;

    // Treat /private/var/... as /var/... do not clone again
    if (!strncmp(source, "/private/var/", 13)) source += 8;
    if (!strncmp(source, "/var/jb/", 8)) return false;

    const char *last_slash = strrchr(source, '/');
    const char *filename = last_slash + 1;
    if (!*filename) return false;
    size_t directory_length = (size_t)(last_slash - source);
    bool in_app_bundle = directory_length >= 4 &&
        strncmp(last_slash - 4, ".app", 4) == 0;

    // The executable keeps its original path beneath /var/jb.
    int executable_length = snprintf(paths->executable, sizeof(paths->executable),
        "/var/jb%s", source);
    int loader_length;
    int disabled_length;
    if (in_app_bundle) {
        // Foo.app/Foo uses Foo.app/g and Foo.app/g-disabled.dylib.
        loader_length = snprintf(paths->loader, sizeof(paths->loader),
            "/var/jb%.*s/g", (int)directory_length, source);
        disabled_length = snprintf(paths->disabled, sizeof(paths->disabled),
            "/var/jb%.*s/g-disabled.dylib", (int)directory_length, source);
    } else {
        // /usr/bin/foo uses /var/jb/usr/bin/foo.dylib and foo-disabled.dylib.
        loader_length = snprintf(paths->loader, sizeof(paths->loader),
            "/var/jb%s.dylib", source);
        disabled_length = snprintf(paths->disabled, sizeof(paths->disabled),
            "/var/jb%s-disabled.dylib", source);
    }

    return executable_length > 0 && executable_length < PATH_MAX &&
        loader_length > 0 && loader_length < PATH_MAX &&
        disabled_length > 0 && disabled_length < PATH_MAX;
}

char *varjb_redirect(const char *source) {
    clone_paths_t paths;
    if (!clone_paths(source, &paths) || access(paths.disabled, F_OK) == 0 ||
        access(paths.executable, X_OK) != 0) return NULL;
    return strdup(paths.executable);
}

char *varjb_spawnp_redirect(const char *file, char *const envp[]) {
    if (!file || strchr(file, '/')) return varjb_redirect(file);

    const char *search = NULL;
    for (size_t i = 0; envp && envp[i]; i++) {
        if (!strncmp(envp[i], "PATH=", 5)) {
            search = envp[i] + 5;
            break;
        }
    }
    if (!search) search = getenv("PATH");
    if (!search) search = "/usr/bin:/bin:/usr/sbin:/sbin";

    for (const char *directory = search; ; ) {
        const char *end = strchr(directory, ':');
        size_t length = end ? (size_t)(end - directory) : strlen(directory);
        char source[PATH_MAX];
        int written = snprintf(source, sizeof(source), "%.*s%s%s",
            (int)length, directory, length ? "/" : "./", file);
        if (written > 0 && written < (int)sizeof(source)) {
            char *redirect = varjb_redirect(source);
            if (redirect) return redirect;
        }
        if (!end) break;
        directory = end + 1;
    }
    return NULL;
}
