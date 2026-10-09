#include "hooks.h"
#include <string.h>
#include <unistd.h>

#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT 6

int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
int csops_audittoken(pid_t pid, unsigned int ops, void *useraddr, size_t usersize,
                     audit_token_t *token);
int64_t amfi_launch_constraint_set_spawnattr(posix_spawnattr_t *attr, char *bytes, int64_t length);
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer,
                         size_t buffersize);

int (*orig_csops)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
int (*orig_csops_audittoken)(pid_t pid, unsigned int ops, void *useraddr, size_t usersize,
                             audit_token_t *token);
int (*memorystatus_control_orig)(uint32_t command, int32_t pid, uint32_t flags, void *buffer,
                                 size_t buffersize);
bool (*xpc_dictionary_get_bool_orig)(xpc_object_t dictionary, const char *key);

int64_t (*orig_amfi_launch_constraint_set_spawnattr)(posix_spawnattr_t *attr, char *bytes,
                                                     int64_t length);

int64_t hooked_amfi_launch_constraint_set_spawnattr(posix_spawnattr_t *attr, char *bytes,
                                                    int64_t length) {
    short flags = 0;
    if (getpid() == 1 && attr && posix_spawnattr_getflags(attr, &flags) == 0 &&
        (flags & POSIX_SPAWN_SETEXEC)) {
        return 0;
    }
    return orig_amfi_launch_constraint_set_spawnattr(attr, bytes, length);
}

int hooked_csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int result = orig_csops(pid, ops, useraddr, usersize);
    if (result != 0)
        return result;
    if (ops == 0) {
        *((uint32_t *)useraddr) |= 0x4000001;
    }
    return result;
}

int hooked_csops_audittoken(pid_t pid, unsigned int ops, void *useraddr, size_t usersize,
                            audit_token_t *token) {
    int result = orig_csops_audittoken(pid, ops, useraddr, usersize, token);
    if (result != 0)
        return result;
    if (ops == 0) {
        *((uint32_t *)useraddr) |= 0x4000001;
    }
    return result;
}

bool hook_xpc_dictionary_get_bool(xpc_object_t dictionary, const char *key) {
    if (!strcmp(key, "LogPerformanceStatistics"))
        return true;
    else
        return xpc_dictionary_get_bool_orig(dictionary, key);
}

int memorystatus_control_hook(uint32_t command, int32_t pid, uint32_t flags, void *buffer,
                              size_t buffersize) {
    if (command == MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT) {
        return 0;
    }
    return memorystatus_control_orig(command, pid, flags, buffer, buffersize);
}
