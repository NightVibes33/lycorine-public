#pragma once
#include "protocol.h"

mach_port_t jit_service(void);
int jit_pass(pid_t pid, mach_port_t service);
void jit_inherit(void);
// Success means queued, not that tracing has completed. Never waits for a reply.
int jit_send(mach_port_t service, pid_t pid, const char *path, enum jit_operation operation,
             bool resume);
