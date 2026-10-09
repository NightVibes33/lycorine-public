#import <Foundation/Foundation.h>
#import <errno.h>
#import <sys/stat.h>
#import <unistd.h>

#import "Bootstrap/Bootstrap.h"
#import "IPC/Inbox.h"
#import "Bootstrap/JailbreakLink.h"
#import "IPC/LycorineLog.h"
#import "Cloning/Clone.h"
#import "Reboot/UserspaceReboot.h"

static int cleanupIncompleteCryptex(void)
{
    NSString *path = @"/private/var/db/com.apple.security.cryptexd/codex.system/cryptex/com.saccharine.lycorine.recovery";
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0)
        return errno == ENOENT ? 0 : errno;
    if (!S_ISDIR(info.st_mode)) return ENOTDIR;

    for (NSString *name in @[@"cx1p", @"gdmg", @"ginf", @"gtcd", @"gtgv", @"im4m"]) {
        NSString *item = [path stringByAppendingPathComponent:name];
        if (lstat(item.fileSystemRepresentation, &info) == 0 && S_ISREG(info.st_mode) && info.st_size > 0)
            continue;
        lycorinedLog(@"Incomplete cryptex: %@ is missing or empty; removing %@", name, path);
        NSError *error = nil;
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
            lycorinedLog(@"Cannot remove incomplete cryptex: %@", error);
            return EIO;
        }
        return 0;
    }
    return 0;
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        lycorinedLog(@"lycorined spawn pid %d uid %d", getpid(), getuid());
        if (geteuid() != 0) {
            lycorinedLog(@"lycorined must be launched as root");
            return EPERM;
        }
        int cleanupResult = cleanupIncompleteCryptex();
        if (cleanupResult != 0) return cleanupResult;
        if (argc == 1) return watchInbox();

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"install"]) {
            if (argc < 3) return EINVAL;
            return installBootstrap([NSString stringWithUTF8String:argv[2]]);
        }
        if ([command isEqualToString:@"hide_jb"])
            return hideJailbreak();
        if ([command isEqualToString:@"unhide_jb"])
            return unhideJailbreak();
        if ([command isEqualToString:@"uninstall"])
            return uninstallBootstrap();
        if ([command isEqualToString:@"tweak_app"]) {
            return argc == 3 ? installClone(@(argv[2])) : EINVAL;
        }
        if ([command isEqualToString:@"disable_app"]) return argc == 3 ? disableClone(@(argv[2])) : EINVAL;
        if ([command isEqualToString:@"userspace-reboot"]) return userspace_reboot();
        lycorinedLog(@"usage: lycorined [install ARCHIVE|uninstall|hide_jb|unhide_jb|tweak_app TARGET|disable_app TARGET|userspace-reboot]");
        return EINVAL;
    }
}
