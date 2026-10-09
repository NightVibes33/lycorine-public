#import "Apps.h"
#import "IPC/LycorineLog.h"
#import "../../../Hooks/Shared/ClonePaths.h"
#import <dlfcn.h>
#import <unistd.h>
// thank you trolldecrypt
@interface LSApplicationRecord : NSObject
@property (nonatomic, readonly) NSArray *appTags;
@property (nonatomic, readonly, getter=isLaunchProhibited) BOOL launchProhibited;
@end

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationType;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *canonicalExecutablePath;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *shortVersionString;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSArray *appTags;
@property (nonatomic, readonly, getter=isLaunchProhibited) BOOL launchProhibited;
- (LSApplicationRecord *)correspondingApplicationRecord;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (void)enumerateApplicationsOfType:(NSUInteger)type block:(void (^)(LSApplicationProxy *))block;
@end

static BOOL containsHiddenTag(NSArray *tags) {
    for (id tag in tags) {
        if ([tag isKindOfClass:NSString.class] &&
            [tag rangeOfString:@"hidden" options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static BOOL isHidden(LSApplicationProxy *proxy, NSDictionary *info) {
    LSApplicationRecord *record = [proxy respondsToSelector:@selector(correspondingApplicationRecord)]
        ? proxy.correspondingApplicationRecord : nil;
    BOOL prohibited = [record respondsToSelector:@selector(isLaunchProhibited)] && record.launchProhibited;
    if (!prohibited && [proxy respondsToSelector:@selector(isLaunchProhibited)]) prohibited = proxy.launchProhibited;
    NSArray *recordTags = [record respondsToSelector:@selector(appTags)] ? record.appTags : nil;
    NSArray *proxyTags = [proxy respondsToSelector:@selector(appTags)] ? proxy.appTags : nil;
    return prohibited || containsHiddenTag(recordTags) || containsHiddenTag(proxyTags) ||
        containsHiddenTag(info[@"SBAppTags"]) ||
        [proxy.bundleIdentifier hasPrefix:@"com.apple.webapp"];
}

static NSString *displayName(LSApplicationProxy *proxy, NSDictionary *info) {
    for (id value in @[info[@"CFBundleDisplayName"] ?: @"", info[@"CFBundleName"] ?: @""]) {
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return proxy.localizedName.length ? proxy.localizedName : proxy.bundleIdentifier;
}

static NSString *cloneState(NSString *source) {
    clone_paths_t paths;
    if (!clone_paths(source.fileSystemRepresentation, &paths) ||
        access(paths.executable, F_OK) != 0) return @"available";
    return access(paths.disabled, F_OK) == 0 ? @"disabled" : @"enabled";
}

NSArray<NSDictionary *> *lycorineInstalledApps(void) {
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
    LSApplicationWorkspace *workspace = [NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
    if (!workspace) { lycorinedLog(@"list apps: LaunchServices unavailable"); return nil; }

    NSMutableArray<LSApplicationProxy *> *proxies = [NSMutableArray array];
    if ([workspace respondsToSelector:@selector(enumerateApplicationsOfType:block:)]) {
        for (NSUInteger type = 0; type <= 1; type++) {
            [workspace enumerateApplicationsOfType:type block:^(LSApplicationProxy *proxy) {
                [proxies addObject:proxy];
            }];
        }
    } else {
        [proxies addObjectsFromArray:workspace.allInstalledApplications ?: @[]];
    }

    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *apps = [NSMutableArray array];
    for (LSApplicationProxy *proxy in proxies) {
        NSString *bundleID = proxy.bundleIdentifier;
        NSString *type = proxy.applicationType;
        if (!bundleID.length || [seen containsObject:bundleID] ||
            !([type isEqualToString:@"User"] || [type isEqualToString:@"System"])) continue;

        NSString *bundlePath = proxy.bundleURL.path;
        if (!bundlePath.length) continue;
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [bundlePath stringByAppendingPathComponent:@"Info.plist"]] ?: @{};
        if (isHidden(proxy, info)) continue;

        NSString *executable = proxy.canonicalExecutablePath;
        if (!executable.length) executable = [NSBundle bundleWithPath:bundlePath].executablePath;
        if (!executable.length) continue;

        [seen addObject:bundleID];
        [apps addObject:@{
            @"bundleID": bundleID,
            @"name": displayName(proxy, info),
            @"type": type,
            @"version": proxy.shortVersionString ?: @"",
            @"executable": executable,
            @"cloneState": cloneState(executable)
        }];
    }
    [apps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    lycorinedLog(@"list apps: %lu visible applications", (unsigned long)apps.count);
    return apps;
}
