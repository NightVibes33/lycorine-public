#pragma once
#include "../Shared/Log.h"

#define jitterd_log(...) hook_log("jitterd", NULL, __VA_ARGS__)
