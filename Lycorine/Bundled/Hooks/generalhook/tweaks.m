#include "tweaks.h"
#include "log.h"
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static bool executable_is(const char *expected) {
    char path[PATH_MAX];
    char resolved[PATH_MAX], expected_path[PATH_MAX];
    uint32_t length = sizeof(path);
    return _NSGetExecutablePath(path, &length) == 0 &&
        realpath(path, resolved) && realpath(expected, expected_path) &&
        strcmp(resolved, expected_path) == 0;
}

void load_tweaks(void) {
    ghlog("loading tweaks");
    if (executable_is("/var/jb/usr/libexec/lsd")) {
        if (!dlopen("/var/jb/usr/lib/lycorine/lsdhook.dylib", RTLD_NOW | RTLD_LOCAL))
            ghlog("lsd hook unavailable: %s", dlerror());
    }
    if (executable_is("/var/jb/System/Library/CoreServices/"
                      "SpringBoard.app/SpringBoard")) {
        void *safe_mode = dlopen("/var/jb/usr/lib/lycorine/safemode.dylib", RTLD_NOW | RTLD_LOCAL);
        if (safe_mode) {
            bool (*active)(void) = dlsym(safe_mode, "lycorine_safemode_active");
            if (active && active())
                return;
        } else {
            ghlog("SafeMode hook unavailable: %s", dlerror());
        }
    }

    dlopen("/var/jb/usr/lib/ellekit/libinjector.dylib", RTLD_NOW);

    if (executable_is("/var/jb/Applications/Preferences.app/Preferences")) {
        if (!dlopen("/var/jb/usr/lib/lycorine/PreferenceLoader27.dylib", RTLD_NOW | RTLD_LOCAL)) {
            ghlog("PreferenceLoader27 unavailable: %s", dlerror());
        }
    }
}
