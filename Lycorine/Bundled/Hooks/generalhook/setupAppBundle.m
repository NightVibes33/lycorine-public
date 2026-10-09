#import "setupAppBundle.h"
#include "../Shared/litehook.h"
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

char gFakeExecutablePath[PATH_MAX];
int (*orig_NSGetExecutablePath)(char *buf, uint32_t *bufsize);
int (*orig_proc_pidpath)(int pid, void *buffer, uint32_t buffersize);
const char *(*orig_dyld_get_image_name)(uint32_t image_index);
uint32_t gMainImageIndex = UINT32_MAX;

void find_main_image(void) {
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const struct mach_header *header = _dyld_get_image_header(i);

    if (header != NULL && header->filetype == MH_EXECUTE) {
      gMainImageIndex = i;
      return;
    }
  }
}

int hook_NSGetExecutablePath(char *buffer, uint32_t *size) {
  if (size == NULL)
    return -1;

  uint32_t needed = (uint32_t)strlen(gFakeExecutablePath) + 1;

  if (*size < needed) {
    *size = needed;
    return -1;
  }

  if (buffer == NULL)
    return -1;

  strlcpy(buffer, gFakeExecutablePath, *size);

  return 0;
}

int hook_proc_pidpath(int pid, void *buffer, uint32_t size) {

  if (pid != getpid() || gFakeExecutablePath[0] == '\0') {
    return orig_proc_pidpath(pid, buffer, size);
  }

  size_t length = strlen(gFakeExecutablePath);

  if (buffer == NULL || size <= length) {
    errno = ENOMEM;
    return 0;
  }

  memcpy(buffer, gFakeExecutablePath, length + 1);

  return (int)length;
}

const char *hook_dyld_get_image_name(uint32_t index) {
  if (index == gMainImageIndex && gFakeExecutablePath[0] != '\0') {
    return gFakeExecutablePath;
  }

  return orig_dyld_get_image_name(index);
}

void exec_pathspoof(const char *fakePath) {
  if (fakePath == NULL)
    return;

  if (strlcpy(gFakeExecutablePath, fakePath, sizeof(gFakeExecutablePath)) >=
      sizeof(gFakeExecutablePath)) {

    NSLog(@"fake executable path too long");
    gFakeExecutablePath[0] = '\0';
    return;
  }

  orig_NSGetExecutablePath = dlsym(RTLD_DEFAULT, "_NSGetExecutablePath");

  orig_proc_pidpath = dlsym(RTLD_DEFAULT, "proc_pidpath");

  orig_dyld_get_image_name = dlsym(RTLD_DEFAULT, "_dyld_get_image_name");

  find_main_image();

  if (orig_NSGetExecutablePath != NULL) {
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, orig_NSGetExecutablePath,
                           hook_NSGetExecutablePath, NULL);
  }

  if (orig_proc_pidpath != NULL) {
    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, orig_proc_pidpath,
                           hook_proc_pidpath, NULL);
  }

  if (orig_dyld_get_image_name != NULL && gMainImageIndex != UINT32_MAX) {

    litehook_rebind_symbol(LITEHOOK_REBIND_GLOBAL, orig_dyld_get_image_name,
                           hook_dyld_get_image_name, NULL);
  }
}

extern const char **_CFGetProgname(void);

@interface NSBundle (private)
- (id)_cfBundle;
@end

@implementation NSBundle (Loaded)

- (BOOL)isLoaded {
  return YES;
}

@end

void setupAppBundle(const char *bundlePathC, const char *fakeExecutablePath) {
  NSString *bundlePath = [NSString stringWithUTF8String:bundlePathC];
  NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
  exec_pathspoof(fakeExecutablePath);

  NSMutableArray<NSString *> *objcArgv =
      NSProcessInfo.processInfo.arguments.mutableCopy;

  if (objcArgv.count != 0) {
    objcArgv[0] = [NSString stringWithUTF8String:fakeExecutablePath];
    [NSProcessInfo.processInfo performSelector:@selector(setArguments:)
                                    withObject:objcArgv];
  }
  NSString *processName = appBundle.infoDictionary[@"CFBundleExecutable"];

  if (processName != nil) {
    NSProcessInfo.processInfo.processName = processName;
    *_CFGetProgname() = processName.UTF8String;
  }
}
