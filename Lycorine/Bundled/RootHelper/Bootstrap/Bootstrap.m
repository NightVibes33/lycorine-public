#import "Bootstrap.h"
#import "JailbreakLink.h"
#import "IPC/LycorineLog.h"
#import "Core/Paths.h"
#import "Core/Spawn.h"
#import "Core/utils.h"
#import "Cloning/Clone.h"
#import "Patching/DyldGen.h"
#import "Reboot/UserspaceReboot.h"
#import <Foundation/Foundation.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

int installBootstrap(NSString *archivePath)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *mount = NSProcessInfo.processInfo.environment[@"CRYPTEX_MOUNT_PATH"];
    NSString *jb = @"/var/jb";
    const char *targetPath = procursuspath();
    if (archivePath.length == 0 || mount.length == 0 || jb.length == 0 ||
        targetPath == NULL || geteuid() != 0)
        return EPERM;
    NSString *realTarget = [NSString stringWithUTF8String:targetPath];

    NSError *error = nil;
    if (![fm fileExistsAtPath:archivePath]) return ENOENT;

    NSString *parent = realTarget.stringByDeletingLastPathComponent;
    if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&error]) {
        lycorinedLog(@"Cannot create bootstrap parent %@: %@", parent, error);
        return EIO;
    }
    for (NSString *name in [fm contentsOfDirectoryAtPath:parent error:nil]) {
        if (![name hasPrefix:@".jb.lycorine-stage-"]) continue;
        NSString *oldStage = [parent stringByAppendingPathComponent:name];
        if (![fm removeItemAtPath:oldStage error:&error]) {
            lycorinedLog(@"Cannot remove interrupted bootstrap stage %@: %@", oldStage, error);
            return EIO;
        }
    }

    struct stat info;
    BOOL hadTarget = lstat(realTarget.fileSystemRepresentation, &info) == 0;
    if (hadTarget && !S_ISDIR(info.st_mode)) return EEXIST;
    if (!hadTarget && errno != ENOENT) return errno;
    BOOL ready = hadTarget && [fm fileExistsAtPath:[realTarget stringByAppendingPathComponent:@".lycorine-bootstrap-ready"]];
    if (hadTarget && !ready) {
        lycorinedLog(@"Removing interrupted initial bootstrap at %@", realTarget);
        if (![fm removeItemAtPath:realTarget error:&error]) return EIO;
        hadTarget = NO;
    }

    struct stat linkInfo;
    BOOL hadLink = lstat(jb.fileSystemRepresentation, &linkInfo) == 0;
    if (!hadLink && errno != ENOENT) return errno;
    if (!hadTarget) {
        if (![fm createDirectoryAtPath:realTarget withIntermediateDirectories:NO attributes:nil error:&error]) {
            lycorinedLog(@"Cannot create initial bootstrap: %@", error);
            return EIO;
        }
        int linkResult = unhideJailbreak();
        if (linkResult != 0) {
            lycorinedLog(@"Cannot expose initial /var/jb: %d", linkResult);
            [fm removeItemAtPath:realTarget error:nil];
            return linkResult;
        }
        lycorinedLog(@"Initial bootstrap linked at %@ before extraction", jb);
    }

    NSString *suffix = NSUUID.UUID.UUIDString;
    NSString *stage = hadTarget ? [parent stringByAppendingPathComponent:[@".jb.lycorine-stage-" stringByAppendingString:suffix]] : realTarget;
    NSString *backup = [parent stringByAppendingPathComponent:[@".jb.lycorine-backup-" stringByAppendingString:suffix]];
    if (hadTarget && ![fm createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:&error]) {
        lycorinedLog(@"Cannot create bootstrap stage: %@", error);
        return EIO;
    }

    NSString *out = nil, *err = nil;
    NSString *untar = [mount stringByAppendingPathComponent:@"usr/bin/untar"];
    int result = spawnRoot(untar, @[archivePath, stage, @"3"], &out, &err);
    if (result != 0) {
        lycorinedLog(@"Bootstrap extraction failed (%d): %@ %@", result, out, err);
        [fm removeItemAtPath:stage error:nil];
        if (!hadTarget && !hadLink) hideJailbreak();
        return result > 0 ? result : EIO;
    }
    if (![fm fileExistsAtPath:[stage stringByAppendingPathComponent:@"prep_bootstrap.sh"]] ||
        ![fm isExecutableFileAtPath:[stage stringByAppendingPathComponent:@"usr/bin/zsh"]] ||
        ![fm isExecutableFileAtPath:[stage stringByAppendingPathComponent:@"usr/bin/uicache"]]) {
        lycorinedLog(@"Staged bootstrap is missing preparation, zsh, or uicache");
        [fm removeItemAtPath:stage error:nil];
        if (!hadTarget && !hadLink) hideJailbreak();
        return ENOENT;
    }

    result = copyCryptex(mount, [stage stringByAppendingPathComponent:@"cryptex"]);
    if (result != 0) {
        [fm removeItemAtPath:stage error:nil];
        if (!hadTarget && !hadLink) hideJailbreak();
        return result;
    }

    if (hadTarget && ![fm moveItemAtPath:realTarget toPath:backup error:&error]) {
        lycorinedLog(@"Cannot back up existing bootstrap: %@", error);
        [fm removeItemAtPath:stage error:nil];
        return EIO;
    }
    if (hadTarget && ![fm moveItemAtPath:stage toPath:realTarget error:&error]) {
        lycorinedLog(@"Cannot activate staged bootstrap: %@", error);
        if (hadTarget) [fm moveItemAtPath:backup toPath:realTarget error:nil];
        [fm removeItemAtPath:stage error:nil];
        return EIO;
    }

    result = unhideJailbreak();
    if (result == 0) {
        NSString *prep = [jb stringByAppendingPathComponent:@"prep_bootstrap.sh"];
        NSString *sh = [jb stringByAppendingPathComponent:@"usr/bin/sh"];
        result = spawnRoot(sh, @[prep], &out, &err);
        if (result != 0)
            lycorinedLog(@"Bootstrap preparation failed (%d): %@ %@", result, out, err);
    } else {
        lycorinedLog(@"Cannot expose /var/jb: %d", result);
    }
    if (result == 0) result = installSystemClones();
    if (result == 0) {
        int dyldResult = installPatchedDyld();
        if (dyldResult != 0)
            lycorinedLog(@"dyld patch unavailable (%d); continuing without overlay", dyldResult);
    }
    if (result == 0) {
        NSString *opainject = [jb stringByAppendingPathComponent:@"usr/bin/opainject"];
        NSString *launchdHook = [jb stringByAppendingPathComponent:@"usr/lib/lycorine/launchdhook.dylib"];
        if (![fm isExecutableFileAtPath:opainject]) {
            lycorinedLog(@"opainject missing at %@", opainject);
            result = ENOENT;
        } else if (![fm fileExistsAtPath:launchdHook]) {
            lycorinedLog(@"launchdhook missing at %@", launchdHook);
            result = ENOENT;
        } else {
            lycorinedLog(@"injecting %@ into pid 1", launchdHook);
            result = spawnRoot(opainject, @[@"1", launchdHook], &out, &err);
            if (result != 0)
                lycorinedLog(@"opainject failed (%d): %@ %@", result, out, err);
            else
                lycorinedLog(@"opainject succeeded: %@ %@", out ?: @"", err ?: @"");
        }
    }
    // if (result == 0) {
    //     NSString *killall = [jb stringByAppendingPathComponent:@"usr/bin/killall"];
    //     lycorinedLog(@"kill lsd so launchdhook can load the registration hook");
    //     int killResult = spawnRoot(killall, @[@"-9", @"lsd"], &out, &err);
    //     if (killResult != 0 && killResult != 1) {
    //         lycorinedLog(@"Cannot restart lsd (%d): %@ %@", killResult, out, err);
    //         result = killResult;
    //     }
    // }
    if (result == 0) {
      NSString *uicache =
          [jb stringByAppendingPathComponent:@"usr/bin/uicache"];
      // do not fuck up my every app's uicache brah
      result = spawnRoot(uicache, @[@"-p", @"/var/jb/Applications/Sileo.app" ],
                         &out, &err);
      if (result != 0)
        lycorinedLog(@"uicache failed (%d): %@ %@", result, out, err);
    }
//    if (result == 0) {
//        NSString *sbreload = [jb stringByAppendingPathComponent:@"usr/bin/sbreload"];
//        if (![fm isExecutableFileAtPath:sbreload]) {
//            lycorinedLog(@"sbreload missing at %@; skipping respring", sbreload);
//        } else {
//            NSString *sbOut = nil, *sbErr = nil;
//            int sbResult = spawnRoot(sbreload, @[], &sbOut, &sbErr);
//            if (sbResult != 0)
//                lycorinedLog(@"sbreload failed (%d): %@ %@; respring manually", sbResult, sbOut, sbErr);
//            else
//                lycorinedLog(@"sbreload succeeded");
//        }
//    }
    if (result == 0) {
        NSString *ready = [jb stringByAppendingPathComponent:@".lycorine-bootstrap-ready"];
        if (![@"ready\n" writeToFile:ready atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
            lycorinedLog(@"Cannot write bootstrap marker: %@", error);
            result = EIO;
        }
    }
    if (result != 0) {
        if (!hadLink) hideJailbreak();
        if (![fm removeItemAtPath:realTarget error:&error])
            lycorinedLog(@"Cannot remove failed bootstrap: %@", error);
        if (hadTarget && ![fm moveItemAtPath:backup toPath:realTarget error:&error])
            lycorinedLog(@"Cannot restore previous bootstrap: %@", error);
        else if (hadTarget)
            lycorinedLog(@"Restored previous bootstrap after failed install");
        else
            lycorinedLog(@"Removed failed initial bootstrap; /var/jb is absent until install succeeds");
        return result > 0 ? result : EIO;
    }
    if (hadTarget && ![fm removeItemAtPath:backup error:&error])
        lycorinedLog(@"Cannot remove previous bootstrap backup: %@", error);

    // lycorinedLog(@"install complete, userspace rebooting");
    // int rebootResult = userspace_reboot();
    // if (rebootResult != 0)
    //     lycorinedLog(@"userspace reboot failed (%d); reboot manually", rebootResult);
    return 0;
}

static int removeItemAtPathRecursively(NSString *path)
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0)
        return errno == ENOENT ? 0 : errno;
    // Never traverse a symlink, including one that points to a directory.
    if (!S_ISDIR(info.st_mode)) {
        if (unlink(path.fileSystemRepresentation) == 0 || errno == ENOENT) return 0;
        lycorinedLog(@"Cannot unlink %@: %s", path, strerror(errno));
        return errno;
    }
    NSError *error = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:&error];
    if (contents == nil) {
        lycorinedLog(@"Error reading contents of directory %@: %@", path, error);
        return EIO;
    }
    int result = 0;
    for (NSString *item in contents) {
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        int itemResult = removeItemAtPathRecursively(itemPath);
        if (itemResult != 0 && result == 0) result = itemResult;
    }
    if (rmdir(path.fileSystemRepresentation) != 0 && errno != ENOENT) {
        lycorinedLog(@"Cannot remove directory %@: %s", path, strerror(errno));
        if (result == 0) result = errno;
    }
    return result;
}

int uninstallBootstrap(void)
{
    if (geteuid() != 0) return EPERM;
    NSString *jb = @"/var/jb";
    const char *targetPath = procursuspath();
    if (targetPath == NULL) return EIO;
    NSString *realTarget = [NSString stringWithUTF8String:targetPath];
    struct stat info;
    if (lstat(jb.fileSystemRepresentation, &info) == 0) {
        if (S_ISLNK(info.st_mode)) {
            if (unlink(jb.fileSystemRepresentation) != 0 && errno != ENOENT) {
                lycorinedLog(@"Cannot remove /var/jb symlink: %s", strerror(errno));
                return errno;
            }
            lycorinedLog(@"Removed /var/jb symlink");
        } else {
            lycorinedLog(@"Refusing to uninstall unexpected %@ (not a symlink)", jb);
            return EEXIST;
        }
    }
    int result = removeItemAtPathRecursively(realTarget);
    if (result != 0) {
        lycorinedLog(@"Uninstall failed: %d", result);
        return result;
    }
    lycorinedLog(@"Uninstalled %@", realTarget);
    return 0;
}
