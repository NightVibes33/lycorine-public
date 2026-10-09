#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>
#include "spawn.h"
#include "../Shared/Sandbox/Extensions.h"
#include "../Shared/JIT/client.h"
#include "../Shared/litehook.h"

__attribute__((constructor)) static void initialize_xpcproxy_hook(void) {
    jit_inherit();
    sandbox_consume_inherited_extensions();
    int saved_errno = errno;
    orig_posix_spawn = dlsym(RTLD_DEFAULT, "posix_spawn");
    orig_posix_spawnp = dlsym(RTLD_DEFAULT, "posix_spawnp");
    const struct mach_header_64 *header = NULL;
    uint32_t image_count = _dyld_image_count();
    // Inserted dylibs can precede the executable in dyld's image list.
    for (uint32_t i = 0; i < image_count; ++i) {
        const struct mach_header *candidate = _dyld_get_image_header(i);
        if (candidate && candidate->magic == MH_MAGIC_64 && candidate->filetype == MH_EXECUTE) {
            header = (const struct mach_header_64 *)candidate;
            break;
        }
    }
    struct {
        const char *name;
        void *original;
        void *replacement;
    } hooks[] = {
        {"posix_spawn", orig_posix_spawn, hook_posix_spawn},
        {"posix_spawnp", orig_posix_spawnp, hook_posix_spawnp},
    };
    if (!header) {
        errno = saved_errno;
        return;
    }
    for (size_t i = 0; i < sizeof(hooks) / sizeof(hooks[0]); ++i) {
        // The checked rebinder supports both PAC slots and current TPRO pages.
        litehook_usp_rebind_image(header, hooks[i].original, hooks[i].replacement, NULL, NULL,
                                  hooks[i].name);
    }
    errno = saved_errno;
}
