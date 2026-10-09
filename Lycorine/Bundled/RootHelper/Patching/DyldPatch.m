#import "DyldPatch.h"

#include <choma/MachO.h>
#include <mach-o/loader.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uuid/uuid.h>

static const uint32_t kGetAMFIPatch[] = { 0xd2801fe0, 0xd65f03c0 }; // mov x0, #0xff; ret
static const uint32_t kReturn1Patch[] = { 0xd2800020, 0xd65f03c0 }; // mov x0, #1; ret

typedef struct {
    const char *const *names;
    const uint32_t *patch;
} patch_site_t;

static const char *const kGetAMFI[] = {
    "__ZN5dyld413ProcessConfig8Security7getAMFIERKNS0_7ProcessERNS_15SyscallDelegateE",
    NULL
};
static const char *const kLoadable[] = {
    "__ZNK6mach_o6Header19loadableIntoProcessENS_8PlatformE7CStringb",
    "__ZNK5dyld39MachOFile19loadableIntoProcessENS_8PlatformEPKcb",
    NULL
};
static const char *const kOverridable[] = {
    "__ZNK5dyld413ProcessConfig9DyldCache17isOverridablePathEPKc",
    NULL
};
static const char *const kAlwaysOverridable[] = {
    "__ZN5dyld413ProcessConfig9DyldCache23isAlwaysOverridablePathE7CString",
    "__ZN5dyld413ProcessConfig9DyldCache23isAlwaysOverridablePathEPKc",
    NULL
};

static const patch_site_t kSites[] = {
    // getAMFI()                 -> mov x0, #0xff; ret
    { kGetAMFI,           kGetAMFIPatch },
    // loadableIntoProcess()     -> mov x0, #1; ret
    { kLoadable,          kReturn1Patch },
    // isOverridablePath()       -> mov x0, #1; ret
    { kOverridable,       kReturn1Patch },
    // isAlwaysOverridablePath() -> mov x0, #1; ret
    { kAlwaysOverridable, kReturn1Patch },
};
#define kSiteCount (sizeof(kSites) / sizeof(kSites[0]))

static uint64_t resolve_site(MachO *macho, const patch_site_t *site) {
    __block uint64_t found = 0;
    for (const char *const *name = site->names; *name && !found; name++) {
        const char *wanted = *name;
        macho_enumerate_symbols(macho, ^(const char *sym, uint8_t type, uint64_t vmaddr, bool *stop) {
            (void)type;
            if (!strcmp(sym, wanted)) { found = vmaddr; *stop = true; }
        });
    }
    return found;
}

int apply_dyld_patch(const char *dyldPath, const char *uuidPrefix) {
    MachO *macho = macho_init_for_writing(dyldPath);
    if (!macho) return -1;

    uint64_t addrs[kSiteCount];
    for (size_t i = 0; i < kSiteCount; i++) {
        addrs[i] = resolve_site(macho, &kSites[i]);
        if (!addrs[i]) {
            macho_free(macho);
            return -1;
        }
    }

    for (size_t i = 0; i < kSiteCount; i++)
        macho_write_at_vmaddr(macho, addrs[i], sizeof(kGetAMFIPatch), (void *)kSites[i].patch);

    __block int r = 0;
    __block bool sawUUID = false;
    size_t prefixLen = strlen(uuidPrefix) + 1;
    macho_enumerate_load_commands(macho, ^(struct load_command lc, uint64_t offset, void *cmd, bool *stop) {
        (void)cmd;
        if (lc.cmd == LC_UUID) {
            sawUUID = true;
            if (prefixLen <= sizeof(uuid_t)) {
                macho_write_at_offset(macho, offset + offsetof(struct uuid_command, uuid), prefixLen, (void *)uuidPrefix);
            } else {
                r = -1;
            }
            *stop = true;
        }
    });
    if (!sawUUID) r = -1;

    macho_free(macho);
    return r;
}
