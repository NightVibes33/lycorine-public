#import "UserspaceReboot.h"
#import "IPC/LycorineLog.h"
#import <Foundation/Foundation.h>
#import <errno.h>
#import <unistd.h>
#import <xpc/xpc.h>

extern xpc_connection_t _xpc_connection_create_mach_service(
    const char *name, dispatch_queue_t targetq, uint64_t flags)
    __asm("_xpc_connection_create_mach_service");

int userspace_reboot(void) {
    xpc_object_t xdict = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(xdict, "cmd", 5);
    unlink("/private/var/mobile/Library/MemoryMaintenance/mmaintenanced");
    xpc_connection_t connection =
        _xpc_connection_create_mach_service("com.apple.mmaintenanced", NULL, 0);
    if (xpc_get_type(connection) == XPC_TYPE_ERROR) {
        lycorinedLog(@"userspace-reboot: no mmaintenanced service");
        xpc_release(xdict);
        return ENOSYS;
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        (void)event;
    });
    xpc_connection_activate(connection);
    xpc_object_t reply =
        xpc_connection_send_message_with_reply_sync(connection, xdict);
    xpc_release(xdict);
    if (reply) {
        xpc_release(reply);
        xpc_connection_cancel(connection);
        return 0;
    }
    xpc_connection_cancel(connection);
    return EIO;
}
