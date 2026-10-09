#pragma once

// launchd and xpcproxy spawn routes use this to inject hooks and sandbox extensions.

char **inject_env(char *const envp[], const char *replacement, char **added_lib,
                  char **added_sandbox);
void inject_free(char **env, char *added_lib, char *added_sandbox);
