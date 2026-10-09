#import "Inbox.h"
#import "Bootstrap/Bootstrap.h"
#import "Bootstrap/JailbreakLink.h"
#import "LycorineLog.h"
#import "Core/Paths.h"
#import "Cloning/Clone.h"
#import "Cloning/Apps/Apps.h"
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *readAction(NSString *path)
{
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (file == nil) return nil;
    NSData *data = [file readDataOfLength:128];
    [file closeFile];
    const char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        if (bytes[i] == '\n' && i > 0)
            return [[NSString alloc] initWithBytes:bytes length:i encoding:NSUTF8StringEncoding];
    }
    return nil;
}

static void processInbox(NSString *inbox)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *listError = nil;
    NSArray<NSString *> *names = [[fm contentsOfDirectoryAtPath:inbox error:&listError] sortedArrayUsingSelector:@selector(compare:)];
    if (names == nil) {
        lycorinedLog(@"[Inbox] processInbox: failed to list %@: %@", inbox, listError);
        return;
    }
    for (NSString *name in names) {
        BOOL pending = [name hasSuffix:@".request"];
        BOOL interrupted = [name hasSuffix:@".processing"];
        if (!pending && !interrupted) continue;
        NSString *identifier = [name stringByDeletingPathExtension];
        NSString *request = [inbox stringByAppendingPathComponent:name];
        NSString *processing = [inbox stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"processing"]];
        NSString *resultPath = [inbox stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"result.plist"]];
        if ([fm fileExistsAtPath:resultPath]) continue;
        if (pending && [fm fileExistsAtPath:processing]) continue;
        if (pending && ![fm moveItemAtPath:request toPath:processing error:nil]) {
            lycorinedLog(@"[Inbox] processInbox: %@ could not move %@ -> %@, skipping", identifier, request, processing);
            continue;
        }

        lycorinedSetProcessingPath(processing);
        NSString *action = readAction(processing);
        lycorinedLog(@"[Inbox] %@ action=%@", identifier, action ?: @"invalid");
        int result = EINVAL;
        NSArray<NSDictionary *> *apps = nil;
        if ([action isEqualToString:@"install"]) {
            NSString *archive = [inbox stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"bootstrap.tar.zst"]];
            result = installBootstrap(archive);
        }
        else if ([action isEqualToString:@"uninstall"]) result = uninstallBootstrap();
        else if ([action isEqualToString:@"hide_jb"]) result = hideJailbreak();
        else if ([action isEqualToString:@"unhide_jb"]) result = unhideJailbreak();
        else if ([action isEqualToString:@"list_apps"]) {
            apps = lycorineInstalledApps();
            result = apps ? 0 : ENOSYS;
        }
        else if ([action isEqualToString:@"tweak_app"] || [action isEqualToString:@"disable_app"]) {
            NSString *targetPath = [inbox stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"target.plist"]];
            NSString *target = [NSDictionary dictionaryWithContentsOfFile:targetPath][@"target"];
            if ([target isKindOfClass:NSString.class])
                result = [action isEqualToString:@"tweak_app"] ? installClone(target) : disableClone(target);
        }
        else lycorinedLog(@"[Inbox] %@ invalid request", identifier);
        lycorinedLog(@"[Inbox] processInbox: %@ action '%@' finished with result=%d (%s)", identifier, action, result, strerror(result));
        NSMutableDictionary *response = [@{@"action": action ?: @"", @"status": @(result)} mutableCopy];
        if (apps) response[@"apps"] = apps;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:response
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0 error:nil];
        if (![data writeToFile:resultPath options:NSDataWritingAtomic error:nil]) {
            lycorinedLog(@"[Inbox] could not write result for %@", identifier);
            lycorinedClearProcessingPath();
            continue;
        }
        if (result == 0 && [action isEqualToString:@"install"]) {
            NSString *archive = [inbox stringByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"bootstrap.tar.zst"]];
            [fm removeItemAtPath:archive error:nil];
        }
        lycorinedClearProcessingPath();
    }
}

static int ensureAppDirectory(NSString *path)
{
    struct stat parent, directory;
    NSString *parentPath = [path stringByDeletingLastPathComponent];
    if (stat(parentPath.fileSystemRepresentation, &parent) != 0) return errno;
    if (mkdir(path.fileSystemRepresentation, 0700) != 0 && errno != EEXIST)
        return errno;
    if (stat(path.fileSystemRepresentation, &directory) != 0) return errno;
    if (!S_ISDIR(directory.st_mode)) return ENOTDIR;
    if (directory.st_uid != parent.st_uid || directory.st_gid != parent.st_gid) {
        if (chown(path.fileSystemRepresentation, parent.st_uid, parent.st_gid) != 0)
            return errno;
    }
    return 0;
}

int watchInbox(void)
{
    NSString *inbox = lycorineInboxPath();
    if (inbox == nil) {
        lycorinedLog(@"Cannot locate Lycorine inbox");
        return ENOENT;
    }
    NSString *documents = [inbox stringByDeletingLastPathComponent];
    lycorinedLog(@"Lycorine documents folder: %@ (resolved: %@)", documents, [documents stringByResolvingSymlinksInPath]);
    lycorinedLog(@"Lycorine inbox folder: %@ (resolved: %@)", inbox, [inbox stringByResolvingSymlinksInPath]);
    int result = ensureAppDirectory(documents);
    if (result == 0) result = ensureAppDirectory(inbox);
    if (result != 0) {
        lycorinedLog(@"Cannot prepare Lycorine inbox %@: %s", inbox, strerror(result));
        return result;
    }
    int fd = open(inbox.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) {
        lycorinedLog(@"Cannot watch %@: %s", inbox, strerror(errno));
        return errno;
    }
    dispatch_queue_t queue = dispatch_queue_create("com.saccharine.lycorine.inbox", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
                                                      DISPATCH_VNODE_WRITE | DISPATCH_VNODE_RENAME |
                                                      DISPATCH_VNODE_DELETE, queue);
    dispatch_source_set_event_handler(source, ^{
        unsigned long flags = dispatch_source_get_data(source);
        if (flags & (DISPATCH_VNODE_RENAME | DISPATCH_VNODE_DELETE)) exit(1);
        processInbox(inbox);
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    dispatch_async(queue, ^{ processInbox(inbox); });
    dispatch_main();
}
