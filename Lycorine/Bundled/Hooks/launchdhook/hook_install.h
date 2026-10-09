#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

typedef struct {
    const char *name;
    void *replacement;
    void *original_storage;
    void *resolved;
} hook_t;

void install_rebind(FILE *log, hook_t *hooks, size_t count);
void install_uspreboot(FILE *log, hook_t *hooks, size_t count);