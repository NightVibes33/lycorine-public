#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <os/log.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

extern void lycorine_preference_loader27_start(void);

static bool is_replacement_preferences(void) {
    char path[PATH_MAX];
    uint32_t length = sizeof(path);
    return _NSGetExecutablePath(path, &length) == 0 &&
        strcmp(path, "/var/jb/Applications/Preferences.app/Preferences") == 0;
}

__attribute__((constructor)) static void load_preference_loader(void) {
    if (!is_replacement_preferences()) return;
    static const char *const candidates[] = {
        "/var/jb/Library/MobileSubstrate/DynamicLibraries/PreferenceLoader.dylib",
        "/var/jb/usr/lib/TweakInject/PreferenceLoader.dylib",
    };
    for (unsigned index = 0; index < sizeof(candidates) / sizeof(candidates[0]); ++index) {
        if (access(candidates[index], R_OK) != 0) continue;
        if (dlopen(candidates[index], RTLD_NOW | RTLD_LOCAL) != NULL) {
            os_log(OS_LOG_DEFAULT, "Lycorine: PreferenceLoader ready");
            lycorine_preference_loader27_start();
            return;
        }
        os_log_error(OS_LOG_DEFAULT, "Lycorine: PreferenceLoader load failed: %{public}s", dlerror());
    }
}
