#import "Clone.h"
#import "Signing.h"
#import "TrustCache.h"
#import "Core/Spawn.h"
#import "IPC/LycorineLog.h"
#import "../../Hooks/Shared/ClonePaths.h"
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/loader.h>
#import <stddef.h>
#import <stdint.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <string.h>
#import <unistd.h>

//tested on my 15 Plus
//idk if it works on other devices
static const char launchdHookLoadPath[] = "/var/jb/h.dylib";
static const char launchdHookLinkTarget[] = "usr/lib/lycorine/launchdhook.dylib";
enum {
    launchdHookCommandSize = (sizeof(struct dylib_command) +
        sizeof(launchdHookLoadPath) + 7) & ~(size_t)7
};

static int writeAt(int fd, const void *bytes, size_t size, off_t offset) {
    const uint8_t *cursor = bytes;
    while (size) {
        ssize_t written = pwrite(fd, cursor, size, offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return written < 0 ? errno : EIO;
        cursor += written;
        size -= (size_t)written;
        offset += written;
    }
    return 0;
}

static int stripCloneCPUSubtype(NSString *path) {
    NSData *image = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (image.length < sizeof(struct mach_header_64)) return ENOEXEC;

    const struct mach_header_64 *header = image.bytes;
    if (header->magic != MH_MAGIC_64 || header->cputype != CPU_TYPE_ARM64 ||
        header->filetype != MH_EXECUTE ||
        header->sizeofcmds > image.length - sizeof(*header)) return ENOEXEC;

    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return errno;

    cpu_subtype_t subtype = CPU_SUBTYPE_ARM64_ALL;
    int result = writeAt(fd, &subtype, sizeof(subtype), offsetof(struct mach_header_64, cpusubtype));
    if (close(fd) != 0 && result == 0) result = errno;
    return result;
}

static int addLaunchdHookLoadCommand(NSString *path) {
    NSData *image = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (image.length < sizeof(struct mach_header_64)) return ENOEXEC;

    const uint8_t *bytes = image.bytes;
    const struct mach_header_64 *header = (const struct mach_header_64 *)bytes;
    if (header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE ||
        header->ncmds == UINT32_MAX ||
        header->sizeofcmds > image.length - sizeof(*header)) return ENOEXEC;

    size_t commandsEnd = sizeof(*header) + header->sizeofcmds;
    size_t firstSection = image.length;
    size_t offset = sizeof(*header);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        if (offset > commandsEnd || commandsEnd - offset < sizeof(struct load_command)) return ENOEXEC;
        const struct load_command *command = (const struct load_command *)(bytes + offset);
        if (command->cmdsize < sizeof(*command) || command->cmdsize > commandsEnd - offset) return ENOEXEC;

        if (command->cmd == LC_SEGMENT_64) {
            if (command->cmdsize < sizeof(struct segment_command_64)) return ENOEXEC;
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (segment->nsects > (command->cmdsize - sizeof(*segment)) / sizeof(struct section_64)) return ENOEXEC;
            const struct section_64 *sections = (const struct section_64 *)(segment + 1);
            for (uint32_t j = 0; j < segment->nsects; j++) {
                if (sections[j].offset && sections[j].offset < firstSection)
                    firstSection = sections[j].offset;
            }
        } else if (command->cmd == LC_LOAD_DYLIB) {
            if (command->cmdsize < sizeof(struct dylib_command)) return ENOEXEC;
            const struct dylib_command *dylib = (const struct dylib_command *)command;
            uint32_t nameOffset = dylib->dylib.name.offset;
            if (nameOffset < sizeof(*dylib) || nameOffset >= command->cmdsize) return ENOEXEC;
            const char *name = (const char *)command + nameOffset;
            size_t available = command->cmdsize - nameOffset;
            if (!memchr(name, '\0', available)) return ENOEXEC;
            if (strcmp(name, launchdHookLoadPath) == 0) return 0;
        }
        offset += command->cmdsize;
    }
    if (offset != commandsEnd || firstSection == image.length ||
        firstSection < commandsEnd) return ENOEXEC;

    const uint32_t commandSize = launchdHookCommandSize;
    if (commandSize > firstSection - commandsEnd ||
        commandSize > UINT32_MAX - header->sizeofcmds) return ENOSPC;
    for (size_t i = commandsEnd; i < commandsEnd + commandSize; i++) {
        if (bytes[i] != 0) return ENOSPC;
    }

    uint8_t loadCommand[launchdHookCommandSize];
    memset(loadCommand, 0, sizeof(loadCommand));
    struct dylib_command *dylib = (struct dylib_command *)loadCommand;
    dylib->cmd = LC_LOAD_DYLIB;
    dylib->cmdsize = commandSize;
    dylib->dylib.name.offset = sizeof(*dylib);
    memcpy(loadCommand + sizeof(*dylib), launchdHookLoadPath, sizeof(launchdHookLoadPath));

    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return errno;
    int result = writeAt(fd, loadCommand, sizeof(loadCommand), (off_t)commandsEnd);
    if (result == 0) {
        uint32_t counts[2] = {header->ncmds + 1, header->sizeofcmds + commandSize};
        result = writeAt(fd, counts, sizeof(counts), offsetof(struct mach_header_64, ncmds));
    }
    if (close(fd) != 0 && result == 0) result = errno;
    if (result == 0)
        lycorinedLog(@"launchd clone: added LC_LOAD_DYLIB %@ (%u bytes; %lu bytes headerpad left)",
            @(launchdHookLoadPath), commandSize,
            (unsigned long)(firstSection - commandsEnd - commandSize));
    return result;
}

static int installLaunchdHookLink(void) {
    struct stat info;
    if (lstat(launchdHookLoadPath, &info) == 0) {
        if (!S_ISLNK(info.st_mode)) return EEXIST;
        char target[PATH_MAX];
        ssize_t length = readlink(launchdHookLoadPath, target, sizeof(target) - 1);
        if (length < 0) return errno;
        target[length] = '\0';
        return strcmp(target, launchdHookLinkTarget) == 0 ? 0 : EEXIST;
    }
    if (errno != ENOENT) return errno;
    return symlink(launchdHookLinkTarget, launchdHookLoadPath) == 0 ? 0 : errno;
}

@interface NSObject (CloneApplicationProxy)
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
- (NSURL *)bundleURL;
@end

@interface LycorineStagedClone : NSObject
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *originalName;
@property (nonatomic) BOOL bundle;
@property (nonatomic, assign) clone_paths_t paths;
@property (nonatomic, copy) NSString *payload;
@property (nonatomic, copy) NSString *container;
@property (nonatomic, copy) NSString *executable;
@property (nonatomic, copy) NSString *loader;
@property (nonatomic, copy) NSString *fallbackName;
@property (nonatomic, copy) NSString *fallbackLoader;
@property (nonatomic, copy) NSString *stagedFallback;
@property (nonatomic) BOOL usedFallback;
@end

@implementation LycorineStagedClone
@end

static NSArray<NSString *> *systemCloneSources(void) {
  return @[
    @"/usr/libexec/xpcproxy",
    @"/usr/libexec/lsd",
    @"/usr/libexec/installd",
    @"/System/Library/CoreServices/iconservicesagent",
    // @"/System/Library/CoreServices/SpringBoard.app/SpringBoard",
    // TODO figure out why this resets home screen layout and notification settings
    @"/sbin/launchd",
    // @"/Applications/Preferences.app/Preferences"
    // TODO figure out how to fucking fix ldid ugh whatever
    ];
}

static NSString *sourceExecutable(NSString *target) {
    for (NSString *source in systemCloneSources())
        if ([target isEqualToString:source.lastPathComponent]) return source;
    NSString *path = target;
    if (!path.isAbsolutePath) {
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
        id proxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:target];
        path = [[proxy bundleURL] path];
    }
    if ([path.pathExtension isEqualToString:@"app"]) path = [NSBundle bundleWithPath:path].executablePath;
    path = path.stringByStandardizingPath;
    if ([path hasPrefix:@"/private/var/"]) path = [path substringFromIndex:8];
    if (!path.isAbsolutePath || [path hasPrefix:@"/var/jb/"] || [path hasPrefix:@"/private/var/jb/"]) return nil;
    return path;
}

static int setDisabled(NSString *source, BOOL disabled) {
    clone_paths_t paths;
    if (!clone_paths(source.fileSystemRepresentation, &paths)) return EINVAL;
    NSString *marker = @(paths.disabled);
    if (!disabled) return unlink(paths.disabled) == 0 || errno == ENOENT ? 0 : errno;
    [NSFileManager.defaultManager createDirectoryAtPath:marker.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    return [[NSData data] writeToFile:marker atomically:YES] ? 0 : EIO;
}

static int cloneLock(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:@"/var/jb/etc/lycorine" withIntermediateDirectories:YES attributes:nil error:nil];
    int fd = open("/var/jb/etc/lycorine/clone.lock", O_CREAT | O_RDWR, 0600);
    if (fd >= 0 && flock(fd, LOCK_EX) != 0) { close(fd); return -1; }
    return fd;
}

int disableClone(NSString *target) {
    NSString *source = sourceExecutable(target);
    if (!source) return EINVAL;
    lycorinedLog(@"disable clone: %@", source);
    int lock = cloneLock();
    if (lock < 0) return errno;
    int result = setDisabled(source, YES);
    close(lock);
    lycorinedLog(@"disable clone %@: %d", source, result);
    return result;
}

int installSystemHooks(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    NSString *support = @"/var/jb/usr/lib/lycorine";
    lycorinedLog(@"installing system hooks to %@", support);
    if (![fm createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:&error]) {
        lycorinedLog(@"cannot create %@: %@", support, error.localizedDescription);
        return EIO;
    }
    for (NSString *hook in @[@"safemode.dylib", @"PreferenceLoader27.dylib", @"generalhook.dylib", @"xpcproxyhook.dylib", @"launchdhook.dylib", @"lsdhook.dylib"]) {
        NSString *path = [support stringByAppendingPathComponent:hook];
        [fm removeItemAtPath:path error:nil];
        if (![fm copyItemAtPath:cloneToolPath([@"Hooks/" stringByAppendingString:hook]) toPath:path error:&error]) {
            lycorinedLog(@"install hook %@: %@", hook, error.localizedDescription);
            return EIO;
        }
        [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:path error:nil];
        lchown(path.fileSystemRepresentation, 0, 0);
        lycorinedLog(@"installed hook %@", path);
    }
    NSString *loaderDirectory = @"/var/jb/usr/libexec/lycorine";
    if (![fm createDirectoryAtPath:loaderDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        lycorinedLog(@"create loader directory %@: %@", loaderDirectory, error.localizedDescription);
        return EIO;
    }
    NSString *loader = [loaderDirectory stringByAppendingPathComponent:@"ExecMainBinary"];
    NSString *loaderSource = [cloneToolPath(@"../../bin/ExecMainBinary") stringByStandardizingPath];
    [fm removeItemAtPath:loader error:nil];
    if (![fm copyItemAtPath:loaderSource toPath:loader error:&error]) {
        lycorinedLog(@"install loader %@: %@", loader, error.localizedDescription);
        return EIO;
    }
    [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:loader error:nil];
    lchown(loader.fileSystemRepresentation, 0, 0);
    NSString *faked = [loaderDirectory stringByAppendingPathComponent:@"faked"];
    [fm removeItemAtPath:faked error:nil];
    if (![fm copyItemAtPath:cloneToolPath(@"faked") toPath:faked error:&error]) {
        lycorinedLog(@"install faked %@: %@", faked, error.localizedDescription);
        return EIO;
    }
    [fm setAttributes:@{NSFilePosixPermissions: @0755} ofItemAtPath:faked error:nil];
    lchown(faked.fileSystemRepresentation, 0, 0);
    lycorinedLog(@"installed faked %@", faked);
    int linkResult = installLaunchdHookLink();
    if (linkResult != 0) {
        lycorinedLog(@"cannot install launchd hook link %s: %s", launchdHookLoadPath, strerror(linkResult));
        return linkResult;
    }
    return 0;
}

static int stageClone(NSString *source, NSString *payload, NSString *scratch, LycorineStagedClone **stagedOut) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    BOOL bundle = [source.stringByDeletingLastPathComponent.pathExtension isEqualToString:@"app"];
    NSString *originalName = source.lastPathComponent;
    clone_paths_t paths;
    if (!clone_paths(source.fileSystemRepresentation, &paths)) return EINVAL;

    NSString *name = @(paths.executable).lastPathComponent;
    NSString *container = bundle ? [payload stringByAppendingPathComponent:source.stringByDeletingLastPathComponent.lastPathComponent] : payload;
    NSString *executable = [container stringByAppendingPathComponent:name];

    [fm createDirectoryAtPath:payload withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:nil];

    lycorinedLog(@"clone %@: copying to %@", source, executable);
    if (bundle) {
        if (![fm copyItemAtPath:source.stringByDeletingLastPathComponent toPath:container error:&error]) goto failed;
    } else if (![fm copyItemAtPath:source toPath:executable error:&error]) goto failed;

    {
        NSString *delta = cloneToolPath([originalName isEqualToString:@"launchd"] ? @"Entitlements/launchdentitlements.plist" : @"Entitlements/extraents.plist");
        // Read original entitlements before changing the private executable's signature.
        NSDictionary *entitlements = cloneEntitlements(source, delta, &error);
        if (!entitlements) goto failed;
        lycorinedLog(@"clone %@: merged entitlements", source);
        BOOL isLaunchd = [source isEqualToString:@"/sbin/launchd"];
        if (isLaunchd) {
            int patchResult = addLaunchdHookLoadCommand(executable);
            if (patchResult != 0) {
                lycorinedLog(@"clone %@: cannot add hook load command (%d)", source, patchResult);
                return patchResult;
            }
        }
        int result = stripCloneCPUSubtype(executable);
        if (result != 0) {
            lycorinedLog(@"clone %@: cannot strip CPU subtype (%d)", source, result);
            return result;
        }
        lycorinedLog(@"clone %@: stripped CPU subtype to arm64", source);
        result = isLaunchd ? signCloneWithIdentifier(executable,
            entitlements, scratch, @"com.apple.xpc.launchd") :
            signClone(executable, entitlements, scratch);
        if (result == 0) lycorinedLog(@"clone %@: signed executable", source);
        if (result != 0) return result;

// to move to notxx
        // NSString *renamedName = [@"not" stringByAppendingString:name];
        // NSString *renamedExecutable = [container stringByAppendingPathComponent:renamedName];
        // if (![fm moveItemAtPath:executable toPath:renamedExecutable error:&error]) goto failed;
        // if (bundle && ![fm createSymbolicLinkAtPath:executable
        //     withDestinationPath:renamedName error:&error]) goto failed;
        // executable = renamedExecutable;

        LycorineStagedClone *staged = [LycorineStagedClone new];
        staged.source = source;
        staged.originalName = originalName;
        staged.bundle = bundle;
        staged.paths = paths;
        staged.payload = payload;
        staged.container = container;
        staged.executable = executable;
        staged.loader = nil;
        staged.fallbackName = nil;
        staged.fallbackLoader = nil;
        staged.stagedFallback = nil;
        staged.usedFallback = false;

        if (stagedOut) *stagedOut = staged;
        return 0;
    }
failed:
    lycorinedLog(@"clone %@: %@", source, error.localizedDescription ?: @"could not stage clone");
    return EIO;
}

static int publishStaged(LycorineStagedClone *staged) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    if (staged.usedFallback && rename(staged.stagedFallback.fileSystemRepresentation, staged.fallbackLoader.fileSystemRepresentation) != 0)
        return errno;
    NSString *destination = @(staged.paths.executable);

    lycorinedLog(@"clone %@: publishing to %@", staged.source, destination);
    NSString *parent = destination.stringByDeletingLastPathComponent;

    [fm createDirectoryAtPath:staged.bundle ? parent.stringByDeletingLastPathComponent : parent
        withIntermediateDirectories:YES attributes:nil error:&error];

    if (staged.bundle) {
        [fm removeItemAtPath:parent error:nil];
        if (![fm moveItemAtPath:staged.container toPath:parent error:&error]) goto failed;
    } else {
        [fm removeItemAtPath:destination error:nil];
        if (![fm copyItemAtPath:staged.executable toPath:destination error:&error]) goto failed;
        if (staged.loader) {
            NSString *installedLoader = @(staged.paths.loader);
            [fm removeItemAtPath:installedLoader error:nil];
            if (![fm moveItemAtPath:staged.loader toPath:installedLoader error:&error]) goto failed;
        }
    }
    if ([staged.source isEqualToString:@"/sbin/launchd"])
        return 0;
    int enabled = setDisabled(staged.source, NO);
    if (enabled == 0) lycorinedLog(@"clone %@: redirect enabled", staged.source);

    return enabled;
failed:
    lycorinedLog(@"clone %@: %@", staged.source, error.localizedDescription ?: @"could not publish clone");
    return EIO;
}

int installSystemClones(void)
{
    NSArray<NSString *> *sources = systemCloneSources();
    for (NSString *source in sources) {
        if (![NSFileManager.defaultManager isExecutableFileAtPath:source]) {
            lycorinedLog(@"clone source %@: missing or not executable", source);
            return ENOENT;
        }
    }

    int lock = cloneLock();
    if (lock < 0) return errno;

    char template[] = "/var/jb/etc/lycorine/clones.XXXXXX";
    char *batchDir = mkdtemp(template);
    int result = batchDir ? installSystemHooks() : errno;

    NSString *work = batchDir ? @(batchDir) : nil;
    NSMutableArray<LycorineStagedClone *> *staged = [NSMutableArray array];

    if (result == 0) {
        NSUInteger i = 0;
        for (NSString *source in sources) {
            lycorinedLog(@"Installing system clone: %@", source);
            result = [source isEqualToString:@"/sbin/launchd"] ?
                0 : setDisabled(source, YES);
            if (result != 0) break;
            NSString *tag = [NSString stringWithFormat:@"clone-%lu", (unsigned long)i++];
            NSString *payload = [[[work stringByAppendingPathComponent:@"scan"] stringByAppendingPathComponent:tag] copy];
            NSString *scratch = [[work stringByAppendingPathComponent:@"scratch"] stringByAppendingPathComponent:tag];
            LycorineStagedClone *clone = nil;
            result = stageClone(source, payload, scratch, &clone);
            if (result != 0) break;
            [staged addObject:clone];
        }
    }

    if (result == 0) {
        lycorinedLog(@"trusting %lu staged clones at once", (unsigned long)staged.count);
        result = trustCloneDirectory([work stringByAppendingPathComponent:@"scan"], work);
    }
    if (result == 0) {
        lycorinedLog(@"trusting faked install dir");
        result = trustCloneDirectory(@"/var/jb/usr/libexec/lycorine", work);
    }
    if (result == 0) {
        for (LycorineStagedClone *clone in staged) {
            result = publishStaged(clone);
            if (result != 0) break;
        }
    }
    if (batchDir) [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    close(lock);
    lycorinedLog(@"system clones finished: %d", result);
    return result;
}

int installClone(NSString *target) {
    NSString *source = sourceExecutable(target);
    if (!source) { lycorinedLog(@"clone target %@: source not found", target); return EINVAL; }
    lycorinedLog(@"clone %@: preparing %@", target, source);
    int lock = cloneLock();
    if (lock < 0) return errno;
    char template[] = "/var/jb/etc/lycorine/clone.XXXXXX";
    char *directory = mkdtemp(template);
    int result = directory ? setDisabled(source, YES) : errno;
    NSString *work = directory ? @(directory) : nil;

    if (result == 0) result = installSystemHooks();
    LycorineStagedClone *clone = nil;
    NSString *scan = work ? [work stringByAppendingPathComponent:@"scan"] : nil;

    if (result == 0) result = stageClone(source, scan, [work stringByAppendingPathComponent:@"scratch"], &clone);
    if (result == 0) result = trustCloneDirectory(scan, work);
    if (result == 0) result = publishStaged(clone);

    if (directory) [NSFileManager.defaultManager removeItemAtPath:work error:nil];
    close(lock);
    lycorinedLog(@"clone %@ finished: %d", target, result);
    return result;
}
