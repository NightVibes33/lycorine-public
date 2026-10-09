#pragma once
#include "../Shared/Spawn/spawn.h"

extern spawn_function_t orig_posix_spawn;
extern spawn_function_t orig_posix_spawnp;

int hook_posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                     const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]);

int hook_posix_spawnp(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                      const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]);
