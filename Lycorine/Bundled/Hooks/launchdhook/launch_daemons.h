#pragma once
#include <xpc/xpc.h>

extern xpc_object_t (*orig_xpc_dictionary_get_value)(xpc_object_t, const char *);
xpc_object_t hook_xpc_dictionary_get_value(xpc_object_t, const char *);
