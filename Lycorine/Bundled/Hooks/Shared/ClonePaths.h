#pragma once
#include <limits.h>
#include <stdbool.h>

typedef struct {
    char executable[PATH_MAX];
    char loader[PATH_MAX];
    char disabled[PATH_MAX];
} clone_paths_t;

bool clone_paths(const char *source, clone_paths_t *paths);
char *varjb_redirect(const char *source);
char *varjb_spawnp_redirect(const char *file, char *const envp[]);
