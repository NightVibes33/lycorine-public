#include "hook_install.h"
#include "../Shared/litehook.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <string.h>

void install_uspreboot(FILE *log, hook_t *hooks, size_t count) {
    hook_t *table = hooks;

    // USP path uses MH_EXECUTE scan (not index 0): SETEXEC re-exec
    // does not guarantee main is at index 0.
    const struct mach_header_64 *header = NULL;
    uint32_t main_idx = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *h =
            (const struct mach_header_64 *)_dyld_get_image_header(i);
        if (h && h->magic == MH_MAGIC_64 && h->filetype == MH_EXECUTE) {
            header = h;
            main_idx = i;
            break;
        }
    }
    if (!header) {
        header = (const struct mach_header_64 *)_dyld_get_image_header(0);
        if (log) {
            fprintf(log, "[launchd-usp] no MH_EXECUTE found, fallback to index 0\n");
            fflush(log);
        }
    }
    if (log) {
        fprintf(log, "[launchd-usp] mode=userspace-reboot main_idx=%u nimages=%u\n",
                main_idx, _dyld_image_count());
        fflush(log);
    }
    for (size_t i = 0; i < count; i++) {
        const char *prev_img = NULL;
        Dl_info ri = {0};
        if (table[i].resolved && dladdr(table[i].resolved, &ri) != 0)
            prev_img = ri.dli_fname;
        litehook_usp_result_t r = litehook_usp_rebind_image(
            (const mach_header_u *)header,
            table[i].resolved, table[i].replacement,
            prev_img, log, table[i].name);
        if (log) {
            fprintf(log, "[launchd-usp] rebind %s resolved=%p prev=%s matches=%u writes=%u protectFails=%u tproWrites=%u err=%d\n",
                    table[i].name, table[i].resolved,
                    prev_img ? prev_img : "(none)",
                    r.matches, r.writes, r.protectFails, r.tproWrites, r.firstErr);
            fflush(log);
        }
    }
}
