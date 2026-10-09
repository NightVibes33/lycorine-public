#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static BOOL allowEmbeddedRegistration(id client, SEL selector)
{
    (void)client;
    (void)selector;
    return YES;
}

__attribute__((constructor)) static void installRegistrationHook(void)
{
    Class client = objc_getClass("_LSDModifyClient");
    SEL selector = NSSelectorFromString(@"clientIsEntitledForEmbeddedRegistrationOperations");
    Method predicate = client ? class_getInstanceMethod(client, selector) : NULL;
    if (!predicate) {
        NSLog(@"Lycorine lsd: embedded registration predicate unavailable");
        return;
    }
    method_setImplementation(predicate, (IMP)allowEmbeddedRegistration);
    NSLog(@"Lycorine lsd: embedded registration enabled");
}
