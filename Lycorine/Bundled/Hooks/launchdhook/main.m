#include "hooks.h"
#include "hook_install.h"
#include "launch_daemons.h"
#include "../Shared/litehook.h"
#include "spawn.h"
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// argv[0] is spoofed, only the executable path counts.
static bool is_reboot(void) {
    char path[PATH_MAX] = {0};
    uint32_t length = sizeof(path);
    bool have_path = _NSGetExecutablePath(path, &length) == 0 && path[0];
    const char *rebooted = getenv("XPC_USERSPACE_REBOOTED");
    if (rebooted && *rebooted)
        return true;
    return have_path && strcmp(path, "/var/jb/sbin/launchd") == 0;
}

__attribute__((constructor)) static void initialize_launchd_hook(void) {
    FILE *file = fopen("/var/jb/launchd.log", "a");
    if (file) {
        fputs("[launchd] What makes a picture perfect? (Let's make a scene so worth it)\n", file);
        fflush(file);
    }

    hook_t hooks[] = {
        {"csops", (void *)hooked_csops, &orig_csops, NULL},
        {"csops_audittoken", (void *)hooked_csops_audittoken, &orig_csops_audittoken, NULL},
        {"posix_spawn", (void *)hook_posix_spawn, &orig_posix_spawn, NULL},
        {"posix_spawnp", (void *)hook_posix_spawnp, &orig_posix_spawnp, NULL},
        {"amfi_launch_constraint_set_spawnattr",
         (void *)hooked_amfi_launch_constraint_set_spawnattr,
         &orig_amfi_launch_constraint_set_spawnattr, NULL},
        {"xpc_dictionary_get_bool", (void *)hook_xpc_dictionary_get_bool,
         &xpc_dictionary_get_bool_orig, NULL},
        {"memorystatus_control", (void *)memorystatus_control_hook, &memorystatus_control_orig,
         NULL},
    };

    const size_t hook_count = sizeof(hooks) / sizeof(hooks[0]);
    for (size_t i = 0; i < hook_count; i++) {
        hooks[i].resolved = dlsym(RTLD_DEFAULT, hooks[i].name);
        memcpy(hooks[i].original_storage, &hooks[i].resolved, sizeof(hooks[i].resolved));
    }

    orig_xpc_dictionary_get_value = dlsym(RTLD_DEFAULT, "xpc_dictionary_get_value");

    bool reboot = is_reboot();
    if (file) {
        fprintf(file, "[launchd] mode=%s\n", reboot ? "userspace-reboot" : "initial-inject");
        fflush(file);
    }
    // Daemon configuration is also read from other images. Install globally
    // in both modes, after every original pointer has been initialized.
    if (getpid() == 1 && orig_xpc_dictionary_get_value) {
        litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, (void *)orig_xpc_dictionary_get_value,
                               (void *)hook_xpc_dictionary_get_value, NULL);
    }
    if (file) {
        fprintf(file, "[launchd] daemon hook scope=global resolved=%p requested=%d\n",
                (void *)orig_xpc_dictionary_get_value,
                getpid() == 1 && orig_xpc_dictionary_get_value != NULL);
        fflush(file);
    }
    if (reboot) {
        install_uspreboot(file, hooks, hook_count);
    } else {
        install_rebind(file, hooks, hook_count);
    }
    if (file)
        fclose(file);
}
