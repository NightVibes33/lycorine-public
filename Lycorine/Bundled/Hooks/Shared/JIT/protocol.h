#pragma once
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

#define JIT_SERVICE_NAME "com.hrtowii.jitterd.prepare"
#define JIT_MESSAGE_ID 0x4c594a54
#define JIT_PROTOCOL_VERSION 2
// Keep libxpc's registered ports at the beginning of the array intact.
#define JIT_PROXY_PORT_SLOT 2

enum jit_operation { JIT_CHILD = 2, JIT_SETEXEC = 3 };

// One-way requests. No reply right is transferred.
typedef struct {
    mach_msg_header_t header;
    uint32_t version, operation;
    pid_t pid;
    uint32_t resume;
    char path[1024];
} jit_request_t;
