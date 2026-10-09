#pragma once
#include <bsm/audit.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <xpc/xpc.h>

extern int (*orig_csops)(pid_t, unsigned int, void *, size_t);
extern int (*orig_csops_audittoken)(pid_t, unsigned int, void *, size_t, audit_token_t *);
extern int (*memorystatus_control_orig)(uint32_t, int32_t, uint32_t, void *, size_t);
extern bool (*xpc_dictionary_get_bool_orig)(xpc_object_t, const char *);
extern int64_t (*orig_amfi_launch_constraint_set_spawnattr)(posix_spawnattr_t *, char *, int64_t);

int hooked_csops(pid_t, unsigned int, void *, size_t);
int hooked_csops_audittoken(pid_t, unsigned int, void *, size_t, audit_token_t *);
int memorystatus_control_hook(uint32_t, int32_t, uint32_t, void *, size_t);
bool hook_xpc_dictionary_get_bool(xpc_object_t, const char *);
int64_t hooked_amfi_launch_constraint_set_spawnattr(posix_spawnattr_t *, char *, int64_t);
