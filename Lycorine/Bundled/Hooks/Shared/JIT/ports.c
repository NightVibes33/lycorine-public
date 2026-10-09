#include "client.h"
#include <errno.h>

extern kern_return_t _kernelrpc_mach_ports_lookup3(task_t, mach_port_t *, mach_port_t *,
                                                  mach_port_t *);

int jit_pass(pid_t pid, mach_port_t service) {
    // Launchd calls this after spawning xpcproxy with START_SUSPENDED. Its hook
    // constructor hasn't run yet, so we can install the right before it reads it.
    task_t task = MACH_PORT_NULL;
    mach_port_t ports[3] = {0};
    int error = EIO;
    if (task_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS)
        return error;
    // Read xpcproxy's three registered ports into launchd's address space.
    // The array wrapper, mach_ports_lookup, allocates in the target task instead;
    // scalar outputs avoid using a remote allocation as a local pointer.
    if (_kernelrpc_mach_ports_lookup3(task, &ports[0], &ports[1], &ports[2]) != KERN_SUCCESS)
        goto cleanup;
    // Slots 0 and 1 stay intact for libxpc. Use slot 2 only if it is empty;
    // replacing an existing registered port could break the service's startup.
    if (ports[JIT_PROXY_PORT_SLOT] != MACH_PORT_NULL)
        goto cleanup;
    ports[JIT_PROXY_PORT_SLOT] = service;
    // Registering copies the send right into xpcproxy; port names themselves
    // are local to each process and cannot simply be passed as environment values.
    // jit_inherit() claims this slot in the hook constructor, then jit_service()
    // uses that right for SETEXEC requests instead of a bootstrap name lookup.
    kern_return_t result = mach_ports_register(task, ports, 3);
    ports[JIT_PROXY_PORT_SLOT] = MACH_PORT_NULL; // The caller still owns service.
    if (result == KERN_SUCCESS)
        error = 0;
cleanup:
    // Lookup gave launchd temporary send-right references to the existing ports.
    // Release those and the task port, leaving xpcproxy's registered copies alive.
    for (unsigned i = 0; i < 3; ++i)
        if (MACH_PORT_VALID(ports[i]))
            mach_port_deallocate(mach_task_self(), ports[i]);
    mach_port_deallocate(mach_task_self(), task);
    return error;
}
