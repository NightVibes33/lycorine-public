#import <Foundation/Foundation.h>
#import "../Shared/LaunchDaemon.h"
#include <xpc/xpc.h>
#include <errno.h>
#include "launch_daemons.h"
#include "../Shared/Log.h"
#include <string.h>
#include <unistd.h>

xpc_object_t (*orig_xpc_dictionary_get_value)(xpc_object_t, const char *);
extern xpc_object_t xpc_create_from_plist(const void *, size_t);
static __thread bool importing;

#define daemon_log(...) hook_log("launchd", "/var/jb/launchd.log", __VA_ARGS__)

static NSString *find_daemon_root(void) {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *persistentRoot = @"/var/jb/cryptex";
    NSString *daemonPlist =
        [persistentRoot stringByAppendingPathComponent:
                            @"Library/LaunchDaemons/com.saccharine.lycorine.daemon.plist"];
    NSString *launcherPath = [persistentRoot stringByAppendingPathComponent:@"usr/bin/cryptex-run"];
    if ([fileManager fileExistsAtPath:daemonPlist] &&
        [fileManager isExecutableFileAtPath:launcherPath]) {
        return persistentRoot;
    }

    NSString *mountDirectory = @"/private/var/run/com.apple.security.cryptexd/mnt";
    NSArray *mountNames = [fileManager contentsOfDirectoryAtPath:mountDirectory error:nil];
    for (NSString *mountName in mountNames) {
        if (![mountName hasPrefix:@"com.saccharine.lycorine.recovery"]) {
            continue;
        }
        NSString *mountPath = [mountDirectory stringByAppendingPathComponent:mountName];
        NSString *plistPath =
            [mountPath stringByAppendingPathComponent:
                           @"Library/LaunchDaemons/com.saccharine.lycorine.daemon.plist"];
        if ([fileManager fileExistsAtPath:plistPath]) {
            return mountPath;
        }
    }
    return nil;
}

static void import_daemon_jobs(xpc_object_t value, NSString *daemonDirectory, NSString *rootPath) {
    if (xpc_get_type(value) != XPC_TYPE_DICTIONARY) {
        daemon_log("daemon request skipped: expected dictionary");
        return;
    }

    NSMutableSet *registeredLabels = [NSMutableSet set];
    xpc_dictionary_apply(value, ^bool(const char *path, xpc_object_t job) {
      if (xpc_get_type(job) == XPC_TYPE_DICTIONARY) {
          const char *label = xpc_dictionary_get_string(job, "Label");
          if (label) {
              [registeredLabels addObject:@(label)];
          }
      }
      return true;
    });

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *directoryError = nil;
    NSArray *filenames = [fileManager contentsOfDirectoryAtPath:daemonDirectory
                                                          error:&directoryError];
    if (!filenames) {
        daemon_log("cannot read daemon directory %s: %s", daemonDirectory.fileSystemRepresentation,
                   directoryError.localizedDescription.UTF8String);
        return;
    }
    size_t added = 0;
    for (NSString *filename in filenames) {
        if (![filename.pathExtension isEqualToString:@"plist"]) {
            continue;
        }

        NSString *plistPath = [daemonDirectory stringByAppendingPathComponent:filename];
        NSDictionary *sourceJob = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSDictionary *job = normalizeLaunchDaemon(sourceJob, rootPath);
        if (!job) {
            daemon_log("invalid daemon job %s", plistPath.fileSystemRepresentation);
            continue;
        }
        NSString *programPath = job[@"Program"];
        if (access(programPath.fileSystemRepresentation, X_OK) != 0) {
            daemon_log("missing daemon executable %s error=%d",
                       programPath.fileSystemRepresentation, errno);
            continue;
        }
        NSString *label = job[@"Label"];
        if ([registeredLabels containsObject:label]) {
            daemon_log("duplicate daemon label skipped %s", label.UTF8String);
            continue;
        }

        NSData *plistData =
            [NSPropertyListSerialization dataWithPropertyList:job
                                                       format:NSPropertyListBinaryFormat_v1_0
                                                      options:0
                                                        error:nil];
        if (!plistData) {
            daemon_log("cannot serialize job %s", plistPath.fileSystemRepresentation);
            continue;
        }
        xpc_object_t parsedJob = xpc_create_from_plist(plistData.bytes, plistData.length);
        if (!parsedJob) {
            daemon_log("cannot parse job %s", plistPath.fileSystemRepresentation);
            continue;
        }

        xpc_dictionary_set_value(value, plistPath.UTF8String, parsedJob);
        [registeredLabels addObject:label];
        added++;
        daemon_log("registered daemon job %s program=%s", label.UTF8String,
                   programPath.fileSystemRepresentation);
    }
    daemon_log("daemon import complete count=%zu", added);
}

static void append_daemon_directory(xpc_object_t value, NSString *daemonDirectory) {
    if (xpc_get_type(value) != XPC_TYPE_ARRAY) {
        daemon_log("daemon request skipped: expected array");
        return;
    }
    __block bool alreadyPresent = false;
    xpc_array_apply(value, ^bool(size_t index, xpc_object_t entry) {
      if (xpc_get_type(entry) != XPC_TYPE_STRING) {
          return true;
      }
      NSString *existingPath = @(xpc_string_get_string_ptr(entry));
      if ([existingPath isEqualToString:daemonDirectory]) {
          alreadyPresent = true;
      }
      return true;
    });
    if (!alreadyPresent) {
        xpc_array_set_string(value, XPC_ARRAY_APPEND, daemonDirectory.UTF8String);
    }
    daemon_log("daemon directory %s %s", alreadyPresent ? "already present" : "added",
               daemonDirectory.fileSystemRepresentation);
}

xpc_object_t hook_xpc_dictionary_get_value(xpc_object_t dictionary, const char *key) {
    xpc_object_t value = orig_xpc_dictionary_get_value(dictionary, key);
    if (getpid() != 1 || importing || !key) {
        return value;
    }

    bool isDaemonRequest = strcmp(key, "LaunchDaemons") == 0;
    bool isPathRequest = strcmp(key, "Paths") == 0;
    if (!isDaemonRequest && !isPathRequest) {
        return value;
    }

    importing = true;
    @autoreleasepool {
        @try {
            const char *type = !value                                       ? "missing"
                               : xpc_get_type(value) == XPC_TYPE_DICTIONARY ? "dictionary"
                               : xpc_get_type(value) == XPC_TYPE_ARRAY      ? "array"
                                                                            : "other";
            daemon_log("daemon request key=%s type=%s", key, type);
            if (!value)
                return value;
            NSString *rootPath = find_daemon_root();
            if (!rootPath) {
                daemon_log("no daemon root available");
                return value;
            }
            daemon_log("daemon root %s", rootPath.fileSystemRepresentation);
            NSString *daemonDirectory =
                [rootPath stringByAppendingPathComponent:@"Library/LaunchDaemons"];

            if (isDaemonRequest) {
                import_daemon_jobs(value, daemonDirectory, rootPath);
            } else {
                append_daemon_directory(value, daemonDirectory);
            }
        } @catch (NSException *exception) {
            daemon_log("daemon import failed: %s", exception.reason.UTF8String);
        } @finally {
            importing = false;
        }
    }
    return value;
}
