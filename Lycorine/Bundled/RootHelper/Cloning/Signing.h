#import <Foundation/Foundation.h>

NSDictionary *cloneEntitlements(NSString *source, NSString *delta, NSError **error);
int signClone(NSString *path, NSDictionary *entitlements, NSString *work);
int signCloneWithIdentifier(NSString *path, NSDictionary *entitlements,
    NSString *work, NSString *identifier);
NSString *cloneToolPath(NSString *name);
