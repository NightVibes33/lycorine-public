#include "codesign_hooks.h"
#include "dyld_bypass_validation.h"
#include "sandbox_extension.h"
#include "tweaks.h"
#include "log.h"
#include "../Shared/Sandbox/Extensions.h"

__attribute__((constructor)) static void initialize_general_hook(void) {
    sandbox_consume_inherited_extensions();
    ghlog("meowmeow generalhook initialising");
    applySandboxExtensions(true);

    if (!init_bypassDyldLibValidation()) {
        ghlog("dyld bypass failed; skipping tweaks");
        return;
    }

    install_codesign_hooks();
    load_tweaks();
}
