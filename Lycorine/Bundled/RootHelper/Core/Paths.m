#import "Paths.h"
#import "IPC/LycorineLog.h"
#import <dlfcn.h>

@interface MCMAppDataContainer : NSObject
@property (nonatomic, readonly) NSURL *url;
+ (instancetype)containerWithIdentifier:(NSString *)identifier
                      createIfNecessary:(BOOL)create
                                 existed:(BOOL *)existed
                                   error:(NSError **)error;
@end

NSString *lycorineInboxPath(void)
{
    Class containerClass = NSClassFromString(@"MCMAppDataContainer");
    if (containerClass == Nil) {
        dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_NOW);
        containerClass = NSClassFromString(@"MCMAppDataContainer");
    }
    if (containerClass == Nil) {
        lycorinedLog(@"MobileContainerManager unavailable: %s", dlerror());
        return nil;
    }

    NSError *error = nil;
    MCMAppDataContainer *container = [containerClass containerWithIdentifier:@"com.saccade.Lycorine"
                                                        createIfNecessary:NO
                                                                   existed:NULL
                                                                     error:&error];
    if (container == nil) {
        lycorinedLog(@"Cannot locate Lycorine container: %@", error);
        return nil;
    }
    return [container.url.path stringByAppendingPathComponent:@"Documents/lycorined"];
}
