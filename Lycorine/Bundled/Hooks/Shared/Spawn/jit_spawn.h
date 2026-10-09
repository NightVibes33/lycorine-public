#pragma once
#include "spawn.h"

int spawn_jit(spawn_function_t original, pid_t *pid, const char *path,
              const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
              char *const argv[], char *const envp[], bool redirect);
