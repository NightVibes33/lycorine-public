#import "TrustCache.h"
#import "Signing.h"
#import "Core/Spawn.h"
#import "IPC/LycorineLog.h"


static NSString *installedCryptex(void) {
    NSString *database = @"/private/var/db/com.apple.security.cryptexd";
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *codex in [fm contentsOfDirectoryAtPath:database error:nil]) {
        NSString *path = [[database stringByAppendingPathComponent:codex]
            stringByAppendingPathComponent:@"cryptex/com.saccharine.lycorine.recovery"];
        if ([fm fileExistsAtPath:[path stringByAppendingPathComponent:@"im4m"]]) return path;
    }
    return nil;
}

int trustCloneDirectory(NSString *directory, NSString *work) {
    NSString *installed = installedCryptex();

    NSString *base = [installed stringByAppendingPathComponent:@"gtcd"];
    NSString *baseTicket = [installed stringByAppendingPathComponent:@"im4m"];
    NSString *cache = [work stringByAppendingPathComponent:@"gtcd"];
    NSString *ticket = [work stringByAppendingPathComponent:@"im4m"];
    NSString *image = [work stringByAppendingPathComponent:@"cache.img4"];
    NSString *out = nil, *err = nil;

    lycorinedLog(@"trust clone: generating cache for %@", directory);
    int result = spawnRoot(cloneToolPath(@"cryptexctl"), // not in the repo here either
        @[@"generate-trust-cache", @"-o", cache, @"-t", @"loadable", @"-b", base, directory], &out, &err);

    if (result == 0) lycorinedLog(@"trust clone: personalizing cache");
    // lalala too bad
    if (result == 0) lycorinedLog(@"trust clone: loading cache");
    if (result == 0) result = spawnRoot(cloneToolPath(@"trustcachectl"), @[@"load", image], &out, &err);

    if (result) lycorinedLog(@"trust clone failed (%d): %@ %@", result, out ?: @"", err ?: @"");
    else lycorinedLog(@"trust clone: cache loaded");
    return result;
}
