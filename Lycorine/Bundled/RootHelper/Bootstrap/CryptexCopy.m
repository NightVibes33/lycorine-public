#import "Bootstrap.h"
#import "IPC/LycorineLog.h"
#import "../../Hooks/Shared/LaunchDaemon.h"
#include <errno.h>

int copyCryptex(NSString *sourcePath, NSString *destinationPath)
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;
    sourcePath = sourcePath.stringByResolvingSymlinksInPath;
    if (![fileManager copyItemAtPath:sourcePath toPath:destinationPath error:&error]) {
        lycorinedLog(@"Cannot copy cryptex to %@: %@", destinationPath, error);
        return EIO;
    }

    NSArray *requiredExecutables = @[
        @"usr/bin/cryptex-run", @"usr/bin/lycorined", @"usr/bin/jitterd",
        @"usr/bin/toybox", @"usr/bin/sh", @"usr/bin/untar", @"usr/bin/ssh-keygen",
        @"usr/sbin/sshd", @"usr/libexec/lycorine/ldid",
        @"usr/libexec/lycorine/cryptexctl", @"usr/libexec/lycorine/trustcachectl"
    ];
    for (NSString *relativePath in requiredExecutables) {
        NSString *executablePath = [destinationPath stringByAppendingPathComponent:relativePath];
        if (![fileManager isExecutableFileAtPath:executablePath]) {
            lycorinedLog(@"Copied cryptex is missing executable %@", relativePath);
            return ENOENT;
        }
    }

    NSArray *requiredFiles = @[
        @"etc/ssh/sshd_config", @"usr/libexec/lycorine/start-openssh.sh",
        @"Library/LaunchDaemons/com.saccharine.lycorine.daemon.plist",
        @"Library/LaunchDaemons/com.saccharine.lycorine.openssh.plist",
        @"Library/LaunchDaemons/com.hrtowii.jitterd.plist"
    ];
    for (NSString *relativePath in requiredFiles) {
        NSString *filePath = [destinationPath stringByAppendingPathComponent:relativePath];
        if (![fileManager fileExistsAtPath:filePath]) {
            lycorinedLog(@"Copied cryptex is missing %@", relativePath);
            return ENOENT;
        }
    }

    NSString *daemonDirectory = [destinationPath stringByAppendingPathComponent:@"Library/LaunchDaemons"];
    NSArray *filenames = [fileManager contentsOfDirectoryAtPath:daemonDirectory error:&error];
    if (!filenames) {
        lycorinedLog(@"Cannot read copied daemon directory: %@", error);
        return EIO;
    }

    NSString *persistentRoot = @"/var/jb/cryptex";
    NSString *persistentPrefix = [persistentRoot stringByAppendingString:@"/"];
    NSMutableSet *registeredLabels = [NSMutableSet set];
    for (NSString *filename in filenames) {
        if (![filename.pathExtension isEqualToString:@"plist"]) {
            continue;
        }

        NSString *plistPath = [daemonDirectory stringByAppendingPathComponent:filename];
        NSDictionary *sourceJob = [NSDictionary dictionaryWithContentsOfFile:plistPath];
        NSDictionary *job = normalizeLaunchDaemon(sourceJob, persistentRoot);
        if (!job) {
            lycorinedLog(@"Invalid copied daemon plist %@", plistPath);
            return EINVAL;
        }

        NSString *label = job[@"Label"];
        if ([registeredLabels containsObject:label]) {
            lycorinedLog(@"Duplicate copied daemon label %@", label);
            return EINVAL;
        }

        NSString *programPath = job[@"Program"];
        NSString *relativePath = [programPath substringFromIndex:persistentPrefix.length];
        NSString *copiedExecutable = [destinationPath stringByAppendingPathComponent:relativePath];
        if (![fileManager isExecutableFileAtPath:copiedExecutable]) {
            lycorinedLog(@"Copied daemon %@ has no executable %@", label, relativePath);
            return ENOENT;
        }
        if (![job writeToFile:plistPath atomically:YES]) {
            lycorinedLog(@"Cannot write copied daemon plist %@", plistPath);
            return EIO;
        }
        [registeredLabels addObject:label];
    }
    lycorinedLog(@"Copied cryptex to %@ with %lu daemon jobs", destinationPath, (unsigned long)registeredLabels.count);
    return 0;
}
