#pragma once

void hook_log(const char *component, const char *path, const char *format, ...)
    __attribute__((format(printf, 3, 4)));
