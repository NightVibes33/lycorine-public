#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <mach/mach.h>
#include <stdio.h>
#include <unistd.h>
#include "service.h"
#include "log.h"
#include "../Shared/JIT/protocol.h"

extern kern_return_t bootstrap_check_in(mach_port_t, const char *, mach_port_t *);

int main(void) {
    setvbuf(stderr, NULL, _IONBF, 0);
    @autoreleasepool {
        mach_port_t service = MACH_PORT_NULL;
        kern_return_t kr = bootstrap_check_in(bootstrap_port, JIT_SERVICE_NAME, &service);
        jitterd_log("check-in result=%d service=%u", kr, service);
        if (kr != KERN_SUCCESS) {
            return 1;
        }

        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, service,
                                                          0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, ^{
          service_receive(service);
        });
        dispatch_resume(source);

        kr = service_publish(service);
        if (kr != KERN_SUCCESS) {
            jitterd_log("publish failed: %d", kr);
            return 1;
        }
        jitterd_log("listening");
        dispatch_main();
    }
}
