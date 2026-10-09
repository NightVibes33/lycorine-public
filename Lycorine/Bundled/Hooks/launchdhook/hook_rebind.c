#include "hook_install.h"
#include "../Shared/litehook.h"
#include <mach-o/dyld.h>

void install_rebind(FILE *log, hook_t *hooks, size_t count) {
    hook_t *table = hooks;
    const struct mach_header_64 *header =
        (const struct mach_header_64 *)_dyld_get_image_header(0);
    for (size_t i = 0; i < count; i++) {
        litehook_rebind_symbol(header, table[i].resolved,
                               table[i].replacement, NULL);
        if (log) {
            fprintf(log, "[launchd] rebind %s resolved=%p\n", table[i].name,
                    table[i].resolved);
            fflush(log);
        }
    }
}
