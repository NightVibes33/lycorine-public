#include "routes.h"
#include "../Injection/spawn_environment.h"
#include "jit_spawn.h"
#include "../ClonePaths.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *attr, uint8_t launch_type);

int spawn_clone(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                char *const argv[], char *const envp[]) {
    if (path && strcmp(path, "/sbin/launchd") == 0)
        return -1;
    char *replacement = search_path ? varjb_spawnp_redirect(path, envp) : varjb_redirect(path);
    if (!replacement)
        return -1;

    char **copy = NULL;
    if (argv) {
        size_t count = 0;
        while (argv[count])
            ++count;
        copy = calloc(count + 1, sizeof(*copy));
        if (!copy) {
            free(replacement);
            return original(pid, path, actions, attributes, argv, envp);
        }
        if (count)
            copy[0] = replacement;
        for (size_t i = 1; i < count; ++i)
            copy[i] = argv[i];
    }

    char *added_lib = NULL, *added_sandbox = NULL;
    char **environment = inject_env(envp, replacement, &added_lib, &added_sandbox);
    char *const *spawn_env = environment ? (char *const *)environment : envp;
    int result = spawn_jit(original, pid, replacement, actions, attributes, copy ? copy : argv,
                           (char *const *)spawn_env, true);
    inject_free(environment, added_lib, added_sandbox);
    free(copy);
    free(replacement);
    if (result != 0)
        result = original(pid, path, actions, attributes, argv, envp);
    return result;
}
