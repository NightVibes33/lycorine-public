#include "codesign_hooks.h"
#include "codesign.h"
#include "../Shared/litehook.h"
#include <bsm/audit.h>
#include <stdint.h>
#include <unistd.h>

#define SYSCALL_CSOPS 0xA9
#define SYSCALL_CSOPS_AUDITTOKEN 0xAA

extern int csops(pid_t, unsigned int, void *, size_t);
extern int csops_audittoken(pid_t, unsigned int, void *, size_t, audit_token_t *);

int csops_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize) {
    int rv = syscall(SYSCALL_CSOPS, pid, ops, useraddr, usersize);
    if (rv != 0)
        return rv;
    if (ops == CS_OPS_STATUS) {
        if (useraddr && usersize == sizeof(uint32_t)) {
            uint32_t *csflag = (uint32_t *)useraddr;
            *csflag |= CS_VALID;
            *csflag |= CS_PLATFORM_BINARY;
        }
    }
    return rv;
}

int csops_audittoken_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize,
                          audit_token_t *token) {
    int rv = syscall(SYSCALL_CSOPS_AUDITTOKEN, pid, ops, useraddr, usersize, token);
    if (rv != 0)
        return rv;
    if (ops == CS_OPS_STATUS) {
        if (useraddr && usersize == sizeof(uint32_t)) {
            uint32_t *csflag = (uint32_t *)useraddr;
            *csflag |= CS_VALID;
            *csflag |= CS_PLATFORM_BINARY;
        }
    }
    return rv;
}

void install_codesign_hooks(void) {
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, csops, csops_hook, NULL);
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, csops_audittoken, csops_audittoken_hook, NULL);
}
