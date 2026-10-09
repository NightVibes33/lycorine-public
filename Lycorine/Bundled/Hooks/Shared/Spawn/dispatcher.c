#include "routes.h"

int spawn_dispatch(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                   const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                   char *const argv[], char *const envp[]) {
    int result = spawn_clone(original, pid, path, search_path, actions, attributes, argv, envp);
    if (result == -1)
        result = spawn_loader(original, pid, path, search_path, actions, attributes, argv, envp);

    return result;
}
