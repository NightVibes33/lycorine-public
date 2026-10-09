//
//  utils.m
//  Lycorine
//
//  Created by LL on 9/23/26.
//

#include "utils.h"
#include <stdio.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

int get_boot_manifest_hash(char hash[97])
{
  const UInt8 *bytes;
  CFIndex length;
  io_registry_entry_t chosen = IORegistryEntryFromPath(0, "IODeviceTree:/chosen");
  if (!MACH_PORT_VALID(chosen)) return 1;
  CFDataRef manifestHash = (CFDataRef)IORegistryEntryCreateCFProperty(chosen, CFSTR("boot-manifest-hash"), kCFAllocatorDefault, 0);
  IOObjectRelease(chosen);
  if (manifestHash == NULL || CFGetTypeID(manifestHash) != CFDataGetTypeID())
  {
    if (manifestHash != NULL) CFRelease(manifestHash);
    return 1;
  }
  length = CFDataGetLength(manifestHash);
  if (length <= 0 || length > 48) {
    CFRelease(manifestHash);
    return 1;
  }
  bytes = CFDataGetBytePtr(manifestHash);
  for (int i = 0; i < length; i++)
  {
    snprintf(&hash[i * 2], 3, "%02X", bytes[i]);
  }
  hash[length * 2] = '\0';
  CFRelease(manifestHash);
  return 0;
}

const char *return_boot_manifest_hash_main(void) {
  static char hash[97];
  int ret = get_boot_manifest_hash(hash);
  if (ret != 0) {
    fprintf(stderr, "could not get boot manifest hash\n");
    return NULL;
  }
  static char result[115];
  snprintf(result, sizeof(result), "/private/preboot/%s", hash);
  return result;
}

const char *procursuspath(void) {
  const char *preboot = return_boot_manifest_hash_main();
  if (preboot == NULL) return NULL;
  static char target[160];
  int length = snprintf(target, sizeof(target), "%s/procursus", preboot);
  return length > 0 && (size_t)length < sizeof(target) ? target : NULL;
}
