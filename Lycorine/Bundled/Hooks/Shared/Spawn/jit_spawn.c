#include "jit_spawn.h"
#include "../JIT/client.h"
#include <errno.h>
#include <limits.h>
#include <malloc/malloc.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *, uint8_t);

extern int posix_spawnattr_getmacpolicyinfo_np(const posix_spawnattr_t *, const char *, void **,
                                              size_t *);
extern int posix_spawnattr_setmacpolicyinfo_np(posix_spawnattr_t *, const char *, void *, size_t);

struct spawn_mac_policy {
    char name[128];
    uint64_t data, length;
};

struct spawn_mac_policies {
    int capacity, count;
    struct spawn_mac_policy entries[];
};

static int remove_amfi_constraint(posix_spawnattr_t *attributes, void **owned_table) {
    void *data = NULL;
    size_t length = 0;
    int error = posix_spawnattr_getmacpolicyinfo_np(attributes, "AMFI", &data, &length);
    if (error)
        return error == ESRCH ? 0 : error;

    posix_spawnattr_t probe = NULL;
    error = posix_spawnattr_init(&probe);
    if (error)
        return error;
    size_t size = malloc_size(probe);
    unsigned char *before = malloc(size);
    if (!before) {
        posix_spawnattr_destroy(&probe);
        return ENOMEM;
    }
    memcpy(before, probe, size);
    error = posix_spawnattr_setmacpolicyinfo_np(&probe, "AMFI", data, length);
    size_t offset = SIZE_MAX;
    if (!error) {
        for (size_t i = 0; i + sizeof(void *) <= size; i += sizeof(void *)) {
            if (!memcmp(before + i, (unsigned char *)probe + i, sizeof(void *)))
                continue;
            if (offset != SIZE_MAX) {
                error = ENOTSUP;
                break;
            }
            offset = i;
        }
    }
    free(before);
    posix_spawnattr_destroy(&probe);
    if (error)
        return error;
    if (offset == SIZE_MAX || offset + sizeof(void *) > malloc_size(*attributes))
        return ENOTSUP;

    struct spawn_mac_policies *table = NULL;
    unsigned char *slot = (unsigned char *)*attributes + offset;
    memcpy(&table, slot, sizeof(table));
    size = table ? malloc_size(table) : 0;
    if (size < sizeof(*table) || table->count < 1 || table->count > table->capacity ||
        (size_t)table->capacity > (size - sizeof(*table)) / sizeof(table->entries[0]))
        return EINVAL;
    int index = 0;
    while (index < table->count &&
           strncmp(table->entries[index].name, "AMFI", sizeof(table->entries[index].name)))
        ++index;
    if (index == table->count || table->entries[index].data != (uintptr_t)data ||
        table->entries[index].length != length)
        return ENOTSUP;

    struct spawn_mac_policies *filtered = NULL;
    if (table->count > 1) {
        filtered = malloc(size);
        if (!filtered)
            return ENOMEM;
        memcpy(filtered, table, size);
        --filtered->count;
        memmove(&filtered->entries[index], &filtered->entries[index + 1],
                (filtered->count - index) * sizeof(filtered->entries[0]));
    }
    memcpy(slot, &filtered, sizeof(filtered));
    *owned_table = filtered;
    return 0;
}

int spawn_jit(spawn_function_t original, pid_t *pid, const char *path,
              const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
              char *const argv[], char *const envp[], bool redirect) {
    // Copy the opaque attributes so launchd's flags and private fields stay intact.
    posix_spawnattr_t copy = NULL;
    if (attributes) {
        if (!*attributes)
            return EINVAL;
        size_t size = malloc_size(*attributes);
        if (!size)
            return EINVAL;
        copy = malloc(size);
        if (!copy)
            return ENOMEM;
        memcpy(copy, *attributes, size);
    } else {
        int error = posix_spawnattr_init(&copy);
        if (error)
            return error;
    }

    int result = 0;
    mach_port_t service = MACH_PORT_NULL;
    char **proxy_env = NULL;
    void *policy_copy = NULL;
    bool loader = !strcmp(path, "/var/jb/usr/libexec/lycorine/ExecMainBinary");
    if (redirect || loader) {
        result = posix_spawnattr_set_launch_type_np(&copy, 0);
        if (result)
            goto cleanup;
    }
    if (loader) {
        result = remove_amfi_constraint(&copy, &policy_copy);
        if (result)
            goto cleanup;
    }
    short flags = 0;
    result = posix_spawnattr_getflags(&copy, &flags);
    if (result)
        goto cleanup;
    bool setexec = (flags & POSIX_SPAWN_SETEXEC) != 0;
    bool resume = (flags & POSIX_SPAWN_START_SUSPENDED) == 0;
    char resolved[PATH_MAX];
    pid_t child = -1;
    pid_t *result_pid = pid;
    if (!result_pid)
        result_pid = &child;

    // Before jitterd publishes, the proxy must start independently to launch it.
    if (!strcmp(path, "/var/jb/usr/libexec/xpcproxy")) {
        if (getpid() == 1 && !setexec)
            service = jit_service();
        if (MACH_PORT_VALID(service)) {
            result = posix_spawnattr_setflags(&copy, flags | POSIX_SPAWN_START_SUSPENDED);
            if (result)
                goto cleanup;
            extern char **environ;
            char *const *source = envp ? envp : environ;
            size_t count = 0;
            while (source && source[count] && count < 4096)
                ++count;
            if (count == 4096) {
                result = E2BIG;
                goto cleanup;
            }
            proxy_env = calloc(count + 2, sizeof(*proxy_env));
            if (!proxy_env) {
                result = ENOMEM;
                goto cleanup;
            }
            size_t used = 0;
            for (size_t i = 0; i < count; ++i)
                if (strncmp(source[i], "LYCORINE_JIT_PORT=", 18))
                    proxy_env[used++] = source[i];
            proxy_env[used] = "LYCORINE_JIT_PORT=2";
            envp = proxy_env;
        }
        result = original(result_pid, path, actions, &copy, argv, envp);
        if (!result && MACH_PORT_VALID(service)) {
            result = jit_pass(*result_pid, service);
            if (result)
                kill(*result_pid, SIGKILL);
            else if (resume)
                kill(*result_pid, SIGCONT);
        }
        goto cleanup;
    }
    if (realpath(path, resolved))
        service = jit_service();

    // Without jitterd, spawn normally and leave the caller's suspension alone.
    if (!MACH_PORT_VALID(service)) {
        result = original(result_pid, path, actions, &copy, argv, envp);
        goto cleanup;
    }
    result = posix_spawnattr_setflags(&copy, flags | POSIX_SPAWN_START_SUSPENDED);
    if (result)
        goto cleanup;

    // SETEXEC replaces this process: send first, then execute the new image.
    if (setexec) {
        int error = jit_send(service, getpid(), resolved, JIT_SETEXEC, resume);
        if (error) {
            result = posix_spawnattr_setflags(&copy, flags);
            if (result)
                goto cleanup;
        }
        result = original(result_pid, path, actions, &copy, argv, envp);
        goto cleanup;
    }

    // A normal spawn gives us a stopped child to send to jitterd.
    result = original(result_pid, path, actions, &copy, argv, envp);
    if (result)
        goto cleanup;
    child = *result_pid;
    int error = jit_send(service, child, resolved, JIT_CHILD, resume);
    // Successful send: jitterd resumes. Failed send: release our stop here.
    if (error && resume)
        kill(child, SIGCONT);

cleanup:
    free(proxy_env);
    if (MACH_PORT_VALID(service))
        mach_port_deallocate(mach_task_self(), service);
    if (attributes) {
        free(policy_copy);
        free(copy);
    }
    else
        posix_spawnattr_destroy(&copy);
    return result;
}
