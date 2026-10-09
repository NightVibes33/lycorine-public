#pragma once
#include "../Shared/JIT/protocol.h"

bool process_allowed(const jit_request_t *request, pid_t caller);
void process_enqueue(const jit_request_t *request);
