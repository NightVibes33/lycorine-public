#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <spawn.h>
#include <stdint.h>

typedef int (*spawn_function_t)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                                const posix_spawnattr_t *, char *const[], char *const[]);

// Returns -1 when no route applies; the hook owns the final fallback.
int spawn_dispatch(spawn_function_t original, pid_t *pid, const char *path, bool search_path,
                   const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                   char *const argv[], char *const envp[]);
