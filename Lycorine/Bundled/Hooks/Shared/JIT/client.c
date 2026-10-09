#include "client.h"
#include <mach/task_special_ports.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

extern mach_port_t bootstrap_port;
extern kern_return_t bootstrap_look_up(mach_port_t, const char *, mach_port_t *);

static mach_port_t proxy_service = MACH_PORT_NULL;

void jit_inherit(void) {
    // Only claim the reserved slot when launchd actually supplied it.
    const char *handoff = getenv("LYCORINE_JIT_PORT");
    if (!handoff || strcmp(handoff, "2"))
        return;
    unsetenv("LYCORINE_JIT_PORT");
    mach_port_array_t ports = NULL;
    mach_msg_type_number_t count = 0;
    if (mach_ports_lookup(mach_task_self(), &ports, &count) != KERN_SUCCESS)
        return;
    if (count > JIT_PROXY_PORT_SLOT && MACH_PORT_VALID(ports[JIT_PROXY_PORT_SLOT])) {
        proxy_service = ports[JIT_PROXY_PORT_SLOT];
        ports[JIT_PROXY_PORT_SLOT] = MACH_PORT_NULL;
        // Don't carry the preparation right into the eventual service executable.
        mach_ports_register(mach_task_self(), ports, count);
    }
    for (mach_msg_type_number_t i = 0; i < count; ++i)
        if (MACH_PORT_VALID(ports[i]))
            mach_port_deallocate(mach_task_self(), ports[i]);
    vm_deallocate(mach_task_self(), (vm_address_t)ports, count * sizeof(*ports));
}

mach_port_t jit_service(void) {
    if (MACH_PORT_VALID(proxy_service)) {
        // Each caller releases its own reference after sending.
        if (mach_port_mod_refs(mach_task_self(), proxy_service, MACH_PORT_RIGHT_SEND, 1) ==
            KERN_SUCCESS)
            return proxy_service;
        return MACH_PORT_NULL;
    }
    mach_port_t service = MACH_PORT_NULL;
    kern_return_t result;
    if (getpid() == 1) {
        result = task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &service);
        // Until jitterd publishes, this is launchd's original bootstrap port.
        if (result == KERN_SUCCESS && service == bootstrap_port) {
            mach_port_deallocate(mach_task_self(), service);
            return MACH_PORT_NULL;
        }
    } else {
        result = bootstrap_look_up(bootstrap_port, JIT_SERVICE_NAME, &service);
    }
    if (result != KERN_SUCCESS)
        return MACH_PORT_NULL;
    return service;
}

int jit_send(mach_port_t service, pid_t pid, const char *path, enum jit_operation operation,
             bool resume) {
    if (!MACH_PORT_VALID(service))
        return ENOTCONN;
    if (pid < 2 || (operation != JIT_CHILD && operation != JIT_SETEXEC))
        return EINVAL;
    if (!path || path[0] != '/' || strlen(path) >= sizeof(((jit_request_t *)0)->path))
        return EINVAL;
    jit_request_t request = {0};
    request.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    request.header.msgh_size = sizeof(request);
    request.header.msgh_remote_port = service;
    request.header.msgh_id = JIT_MESSAGE_ID;
    request.version = JIT_PROTOCOL_VERSION;
    request.operation = operation;
    request.pid = pid;
    request.resume = resume;
    strlcpy(request.path, path, sizeof(request.path));
    kern_return_t kr = mach_msg(&request.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof(request),
                                0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
    if (kr == MACH_SEND_TIMED_OUT)
        return ETIMEDOUT;
    if (kr != KERN_SUCCESS)
        return ENOTCONN;
    return 0;
}
