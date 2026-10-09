#pragma once
#include "spawn.h"

// A route returns -1 when it does not handle this spawn.
int spawn_clone(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                char *const argv[], char *const envp[]);

int spawn_loader(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                 const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                 char *const argv[], char *const envp[]);
