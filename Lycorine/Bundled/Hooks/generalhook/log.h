#pragma once
#include "../Shared/Log.h"

#define ghlog(...) hook_log("ghook", "/var/jb/ghook.log", __VA_ARGS__)
