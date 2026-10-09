#include "spawn_environment.h"
#include "../JIT/protocol.h"
#include <stdbool.h>

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

char *sandbox_extension_issue_file(const char *extension_class, const char *path, uint32_t flags);
char *sandbox_extension_issue_mach(const char *extension_class, const char *name, uint32_t flags);

static bool colon_list_contains(const char *list, const char *value) {
    if (!list || !value)
        return false;
    size_t wanted = strlen(value);
    for (const char *item = list; *item;) {
        const char *end = strchr(item, ':');
        size_t length = end ? (size_t)(end - item) : strlen(item);
        if (length == wanted && memcmp(item, value, wanted) == 0)
            return true;
        if (!end)
            break;
        item = end + 1;
    }
    return false;
}

static char **insert_dyld_library(char *const envp[], const char *lib, char **added) {
    extern char **environ;
    char *const *source = envp ? envp : environ;
    size_t count = 0;
    const char *existing = NULL;
    while (source && source[count] && count < 4096) {
        if (!strncmp(source[count], "DYLD_INSERT_LIBRARIES=", 22))
            existing = source[count] + 22;
        ++count;
    }
    if (count == 4096)
        return NULL;
    if (colon_list_contains(existing, lib))
        return NULL;

    char **copy = calloc(count + 2, sizeof(*copy));
    size_t length = strlen("DYLD_INSERT_LIBRARIES=") + strlen(lib) +
                    (existing && *existing ? strlen(existing) + 1 : 0) + 1;
    char *entry = malloc(length);
    if (!copy || !entry) {
        free(copy);
        free(entry);
        return NULL;
    }
    snprintf(entry, length, "DYLD_INSERT_LIBRARIES=%s%s%s", lib, (existing && *existing) ? ":" : "",
             (existing && *existing) ? existing : "");
    size_t used = 0;
    for (size_t i = 0; i < count; ++i)
        if (strncmp(source[i], "DYLD_INSERT_LIBRARIES=", 22))
            copy[used++] = source[i];
    copy[used] = entry;
    *added = entry;
    return copy;
}

static char *issue_jb_read_extension(const char *lib) {
    struct stat hook;
    if (lstat(lib, &hook) != 0)
        return NULL;
    if (!S_ISREG(hook.st_mode) || hook.st_nlink != 1 || hook.st_uid != 0 ||
        (hook.st_mode & (S_IWGRP | S_IWOTH)) != 0)
        return NULL;
    char root[PATH_MAX];
    if (!realpath("/var/jb", root))
        return NULL;
    return sandbox_extension_issue_file("com.apple.app-sandbox.read", root, 0);
}

char **inject_env(char *const envp[], const char *replacement, char **added_lib,
                  char **added_sandbox) {
    if (added_lib)
        *added_lib = NULL;
    if (added_sandbox)
        *added_sandbox = NULL;
    if (!replacement)
        return NULL;

    const char *lib = strcmp(replacement, "/var/jb/usr/libexec/xpcproxy") != 0
                          ? "/var/jb/usr/lib/lycorine/generalhook.dylib"
                          : "/var/jb/usr/lib/lycorine/xpcproxyhook.dylib";

    char *lib_entry = NULL;
    char **env = insert_dyld_library(envp, lib, &lib_entry);
    if (!env)
        return NULL;
    if (added_lib)
        *added_lib = lib_entry;

    char *read_extension = issue_jb_read_extension(lib);
    char *mach_extension = sandbox_extension_issue_mach(
        "com.apple.security.exception.mach-lookup.global-name", JIT_SERVICE_NAME, 0);
    if (!read_extension && !mach_extension) {
        return env;
    }
    size_t token_length = (read_extension ? strlen(read_extension) : 0) +
                          (mach_extension ? strlen(mach_extension) : 0) + 2;
    char *extension = malloc(token_length);
    if (extension)
        snprintf(extension, token_length, "%s%s%s", read_extension ? read_extension : "",
                 read_extension && mach_extension ? "|" : "", mach_extension ? mach_extension : "");
    free(read_extension);
    free(mach_extension);
    if (!extension)
        return env;

    static const char sandbox_key[] = "SANDBOX_EXTENSION=";
    const char *existing_sandbox = NULL;
    size_t sandbox_index = SIZE_MAX, count = 0;
    while (env[count] && count < 4096) {
        if (!strncmp(env[count], sandbox_key, sizeof(sandbox_key) - 1)) {
            sandbox_index = count;
            existing_sandbox = env[count] + sizeof(sandbox_key) - 1;
        }
        ++count;
    }
    if (existing_sandbox && strstr(existing_sandbox, extension)) {
        free(extension);
        return env;
    }
    size_t sandbox_length =
        sizeof(sandbox_key) + strlen(extension) +
        (existing_sandbox && *existing_sandbox ? strlen(existing_sandbox) + 1 : 0);
    char *sandbox_value = malloc(sandbox_length);
    char **grown = calloc(count + 2, sizeof(*grown));
    if (!sandbox_value || !grown) {
        free(sandbox_value);
        free(grown);
        free(extension);
        return env;
    }
    snprintf(sandbox_value, sandbox_length, "%s%s%s%s", sandbox_key, extension,
             (existing_sandbox && *existing_sandbox) ? "|" : "",
             (existing_sandbox && *existing_sandbox) ? existing_sandbox : "");
    for (size_t i = 0; i < count; i++)
        grown[i] = env[i];
    if (sandbox_index == SIZE_MAX)
        grown[count] = sandbox_value;
    else
        grown[sandbox_index] = sandbox_value;
    free(env);
    free(extension);
    if (added_sandbox)
        *added_sandbox = sandbox_value;
    else
        free(sandbox_value);
    return grown;
}

void inject_free(char **env, char *added_lib, char *added_sandbox) {
    free(added_lib);
    free(added_sandbox);
    free(env);
}
