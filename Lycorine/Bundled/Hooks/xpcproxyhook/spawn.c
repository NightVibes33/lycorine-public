#include "spawn.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>

static bool is_proxy_hook(const char *item, size_t length) {
    const char *paths[] = {"/var/jb/usr/lib/lycorine/xpcproxyhook.dylib",
                           "/private/var/jb/usr/lib/lycorine/xpcproxyhook.dylib"};
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i)
        if (strlen(paths[i]) == length && !memcmp(item, paths[i], length))
            return true;
    return false;
}

static int strip_hook(char *const envp[], char ***cleaned, char **entry) {
    extern char **environ;
    *cleaned = NULL;
    *entry = NULL;
    char *const *source = envp ? envp : environ;
    size_t count = 0;
    while (source && count < 4096 && source[count])
        ++count;
    if (count == 4096)
        return E2BIG;
    const char key[] = "DYLD_INSERT_LIBRARIES=";
    bool found = false;
    size_t capacity = sizeof(key);
    for (size_t i = 0; i < count; ++i) {
        if (strncmp(source[i], key, sizeof(key) - 1))
            continue;
        capacity += strlen(source[i]);
        const char *cursor = source[i] + sizeof(key) - 1;
        while (*cursor) {
            const char *end = strchr(cursor, ':');
            size_t length = end ? (size_t)(end - cursor) : strlen(cursor);
            if (is_proxy_hook(cursor, length))
                found = true;
            if (!end)
                break;
            cursor = end + 1;
        }
    }
    if (!found)
        return 0;
    char **copy = calloc(count + 1, sizeof(*copy));
    char *value = malloc(capacity);
    if (!copy || !value) {
        free(copy);
        free(value);
        return ENOMEM;
    }
    memcpy(value, key, sizeof(key));
    size_t used = sizeof(key) - 1, copied = 0;
    for (size_t i = 0; i < count; ++i) {
        if (strncmp(source[i], key, sizeof(key) - 1)) {
            copy[copied++] = source[i];
            continue;
        }
        const char *cursor = source[i] + sizeof(key) - 1;
        while (*cursor) {
            const char *end = strchr(cursor, ':');
            size_t length = end ? (size_t)(end - cursor) : strlen(cursor);
            if (length && !is_proxy_hook(cursor, length)) {
                if (used > sizeof(key) - 1)
                    value[used++] = ':';
                memcpy(value + used, cursor, length);
                used += length;
            }
            if (!end)
                break;
            cursor = end + 1;
        }
    }
    value[used] = '\0';
    if (used > sizeof(key) - 1)
        copy[copied++] = value;
    *cleaned = copy;
    *entry = value;
    return 0;
}

spawn_function_t orig_posix_spawn;
spawn_function_t orig_posix_spawnp;

static int dispatch_spawn(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                          const posix_spawn_file_actions_t *actions,
                          const posix_spawnattr_t *attributes, char *const argv[],
                          char *const envp[]) {
    char **cleaned = NULL;
    char *entry = NULL;
    int error = strip_hook(envp, &cleaned, &entry);
    if (error)
        return error;
    if (cleaned)
        envp = cleaned;
    int result = spawn_dispatch(original, pid, path, search_path, actions, attributes, argv, envp);
    if (result == -1)
        result = original(pid, path, actions, attributes, argv, envp);
    free(cleaned);
    free(entry);
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
