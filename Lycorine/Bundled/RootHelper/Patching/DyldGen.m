#import "DyldGen.h"
#import "DyldPatch.h"
#import "Cloning/Signing.h"
#import "Cloning/TrustCache.h"
#import "IPC/LycorineLog.h"
#import <Foundation/Foundation.h>
#import <errno.h>
#import <sys/stat.h>
#import <unistd.h>

NSString *lycorineBasebinPath(void) { return @"/var/jb/basebin"; }
const char *lycorineDyldUUIDPrefix(void) { return "LYCO1.0.0"; }

int installPatchedDyld(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    NSString *base = lycorineBasebinPath();
    NSString *gen = [base stringByAppendingPathComponent:@"gen"];
    NSString *fakelib = [base stringByAppendingPathComponent:@".fakelib"];
    NSString *dyldOrig = [gen stringByAppendingPathComponent:@"dyld.orig"];
    NSString *dyldPatched = [gen stringByAppendingPathComponent:@"dyld"];
    NSString *dyldInflight = [gen stringByAppendingPathComponent:@"dyld.inflight"];
    const char *prefix = lycorineDyldUUIDPrefix();

    if ([fm fileExistsAtPath:dyldPatched]) {
        lycorinedLog(@"dyld: patched dyld already exists, skipping");
        return 0;
    }
    if (![fm createDirectoryAtPath:gen withIntermediateDirectories:YES attributes:nil error:&error]) {
        lycorinedLog(@"dyld: cannot create gen dir: %@", error);
        return EIO;
    }
    [fm removeItemAtPath:fakelib error:nil];
    if (![fm copyItemAtPath:@"/usr/lib" toPath:fakelib error:&error]) {
        lycorinedLog(@"dyld: cannot stage fakelib: %@", error);
        return EIO;
    }
    [fm removeItemAtPath:[fakelib stringByAppendingPathComponent:@"dyld"] error:nil];
    if (![fm createSymbolicLinkAtPath:[fakelib stringByAppendingPathComponent:@"dyld"]
                  withDestinationPath:dyldPatched error:&error]) {
        lycorinedLog(@"dyld: cannot link fakelib dyld: %@", error);
        return EIO;
    }
    if (![fm fileExistsAtPath:dyldOrig]) {
        if (![fm copyItemAtPath:@"/usr/lib/dyld" toPath:dyldOrig error:&error]) {
            lycorinedLog(@"dyld: cannot back up stock dyld: %@", error);
            return EIO;
        }
        lycorinedLog(@"dyld: stock dyld backed up");
    }
    [fm removeItemAtPath:dyldInflight error:nil];
    if (![fm copyItemAtPath:dyldOrig toPath:dyldInflight error:&error]) {
        lycorinedLog(@"dyld: cannot stage inflight copy: %@", error);
        return EIO;
    }
    if (apply_dyld_patch(dyldInflight.fileSystemRepresentation, prefix) != 0) {
        lycorinedLog(@"dyld: patch failed, writing nothing");
        [fm removeItemAtPath:dyldInflight error:nil];
        return EIO;
    }
    NSString *scratch = [gen stringByAppendingPathComponent:@"tmp"];
    [fm removeItemAtPath:scratch error:nil];
    [fm createDirectoryAtPath:scratch withIntermediateDirectories:YES attributes:nil error:nil];
    int signResult = signClone(dyldInflight, @{@"com.apple.darwin.ignition": @YES}, scratch);
    [fm removeItemAtPath:scratch error:nil];
    if (signResult != 0) {
        lycorinedLog(@"dyld: resign failed (%d)", signResult);
        [fm removeItemAtPath:dyldInflight error:nil];
        return signResult;
    }
    if (![fm moveItemAtPath:dyldInflight toPath:dyldPatched error:&error]) {
        lycorinedLog(@"dyld: cannot publish patched dyld: %@", error);
        return EIO;
    }
    chmod(dyldPatched.fileSystemRepresentation, 0755);
    lchown(dyldPatched.fileSystemRepresentation, 0, 0);
    NSString *tcWork = [base stringByAppendingPathComponent:@"tcwork"];
    [fm removeItemAtPath:tcWork error:nil];
    [fm createDirectoryAtPath:tcWork withIntermediateDirectories:YES attributes:nil error:nil];
    int trustResult = trustCloneDirectory(gen, tcWork);
    [fm removeItemAtPath:tcWork error:nil];
    if (trustResult != 0) {
        lycorinedLog(@"dyld: trust-cache failed (%d)", trustResult);
        return trustResult;
    }
    lycorinedLog(@"dyld: patched dyld installed + trusted");
    return 0;
}
