#import "Signing.h"
#import "Core/Spawn.h"
#import "IPC/LycorineLog.h"
#import <mach-o/dyld.h>

NSString *cloneToolPath(NSString *name) {
    char path[PATH_MAX];
    uint32_t length = sizeof(path);
    if (_NSGetExecutablePath(path, &length) != 0) return nil;
    NSString *root = [[@(path) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    return [[root stringByAppendingPathComponent:@"libexec/lycorine"] stringByAppendingPathComponent:name];
}

static id mergeEntitlements(id stock, id extra) {
    if ([stock isKindOfClass:NSDictionary.class] && [extra isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *result = [stock mutableCopy];
        for (NSString *key in extra) result[key] = mergeEntitlements(result[key], extra[key]);
        return result;
    }
    if ([stock isKindOfClass:NSArray.class] && [extra isKindOfClass:NSArray.class]) {
        NSMutableArray *result = [stock mutableCopy];
        for (id value in extra) if (![result containsObject:value]) [result addObject:value];
        return result;
    }
    return extra;
}

NSDictionary *cloneEntitlements(NSString *source, NSString *delta, NSError **error) {
    NSString *out = nil, *err = nil;
    int status = spawnRoot(cloneToolPath(@"ldid"), @[@"-e", source], &out, &err);
    if (status != 0) {
        if (error) *error = [NSError errorWithDomain:@"Lycorine.Signing" code:status
            userInfo:@{NSLocalizedDescriptionKey:err ?: @"ldid could not read entitlements"}];
        return nil;
    }
    NSDictionary *stock = out.length ? [NSPropertyListSerialization propertyListWithData:
        [out dataUsingEncoding:NSUTF8StringEncoding] options:0 format:nil error:error] : @{};
    NSDictionary *extra = [NSDictionary dictionaryWithContentsOfFile:delta];
    if (!stock || !extra) return nil;
    return mergeEntitlements(stock, extra);
}

int signCloneWithIdentifier(NSString *path, NSDictionary *entitlements,
    NSString *work, NSString *identifier) {
    NSString *plist = [work stringByAppendingPathComponent:@"entitlements.plist"];
    NSString *requirements = [work stringByAppendingPathComponent:@"requirements.blob"];
    // Empty CSMAGIC_REQUIREMENTS superblob. ldid otherwise generates a
    // certificate-based requirement that an ad-hoc signature cannot satisfy.
    static const uint8_t emptyRequirements[] = {
        0xfa, 0xde, 0x0c, 0x01, 0, 0, 0, 12, 0, 0, 0, 0
    };
    if (![entitlements writeToFile:plist atomically:YES]) return EIO;
    if (![[NSData dataWithBytes:emptyRequirements length:sizeof(emptyRequirements)]
          writeToFile:requirements atomically:YES]) return EIO;
    NSString *out = nil, *err = nil;
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        @"-Cadhoc", [@"-Q" stringByAppendingString:requirements],
        [@"-S" stringByAppendingString:plist]]];
    if (identifier.length)
        [arguments addObject:[@"-I" stringByAppendingString:identifier]];
    [arguments addObject:path];
    int status = spawnRoot(cloneToolPath(@"ldid"), arguments, &out, &err);
    if (status) lycorinedLog(@"sign %@: %@ %@", path, out ?: @"", err ?: @"");
    return status;
}

int signClone(NSString *path, NSDictionary *entitlements, NSString *work) {
    return signCloneWithIdentifier(path, entitlements, work, nil);
}
