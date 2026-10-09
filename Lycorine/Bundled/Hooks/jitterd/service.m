#include "service.h"
#include "process.h"
#include "log.h"
#include <mach/task_special_ports.h>
#include <string.h>
#include <unistd.h>

kern_return_t service_publish(mach_port_t service) {
    kern_return_t result =
        mach_port_insert_right(mach_task_self(), service, service, MACH_MSG_TYPE_MAKE_SEND);
    if (result != KERN_SUCCESS)
        return result;

    task_t launchd = MACH_PORT_NULL;
    result = task_for_pid(mach_task_self(), 1, &launchd);
    if (result != KERN_SUCCESS)
        return result;
    result = task_set_special_port(launchd, TASK_BOOTSTRAP_PORT, service);
    mach_port_deallocate(mach_task_self(), launchd);
    return result;
}

static bool valid_request(const jit_request_t *request, const mach_msg_audit_trailer_t *trailer) {
    return trailer->msgh_trailer_size >= sizeof(*trailer) &&
           trailer->msgh_trailer_type == MACH_MSG_TRAILER_FORMAT_0 &&
           request->version == JIT_PROTOCOL_VERSION &&
           (request->operation == JIT_CHILD || request->operation == JIT_SETEXEC) &&
           request->header.msgh_remote_port == MACH_PORT_NULL && request->pid >= 2 &&
           request->pid != getpid() && request->path[0] == '/' &&
           memchr(request->path, 0, sizeof(request->path)) && request->resume <= 1;
}

void service_receive(mach_port_t service) {
    struct {
        jit_request_t request;
        mach_msg_max_trailer_t trailer;
    } incoming = {0};
    mach_msg_header_t *header = &incoming.request.header;
    kern_return_t result = mach_msg(header,
                                    MACH_RCV_MSG | MACH_RCV_TIMEOUT |
                                        MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |
                                        MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
                                    0, sizeof(incoming), service, 0, MACH_PORT_NULL);
    if (result != KERN_SUCCESS)
        return;
    if ((header->msgh_bits & MACH_MSGH_BITS_COMPLEX) ||
        header->msgh_size != sizeof(incoming.request) || header->msgh_id != JIT_MESSAGE_ID) {
        mach_msg_destroy(header);
        return;
    }

    const mach_msg_audit_trailer_t *trailer =
        (const void *)((const char *)header + round_msg(header->msgh_size));
    if (!valid_request(&incoming.request, trailer)) {
        jitterd_log("invalid preparation request");
        mach_msg_destroy(header);
        return;
    }
    pid_t caller = trailer->msgh_audit.val[5];
    if (!process_allowed(&incoming.request, caller)) {
        jitterd_log("rejected pid=%d caller=%d operation=%u", incoming.request.pid, caller,
                    incoming.request.operation);
        mach_msg_destroy(header);
        return;
    }
    process_enqueue(&incoming.request);
}
