#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// 1 for present, 0 for absent, -1 for errors.
int trust_query(const char *path, bool *adhoc);
// Returns one CDHash for the slice the system would load, or zero on error.
// adhoc includes valid legacy signatures with no CMS slot, even if CS_ADHOC is unset.
size_t binary_cdhashes(const char *path, uint8_t hashes[64][20], bool *adhoc);
