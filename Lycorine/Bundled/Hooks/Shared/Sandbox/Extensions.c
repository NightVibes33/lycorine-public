#include "Extensions.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

extern int64_t sandbox_extension_consume(const char *token);

void sandbox_consume_inherited_extensions(void) {
    const char *value = getenv("SANDBOX_EXTENSION");
    if (!value)
        return;
    char *copy = strdup(value);
    if (!copy)
        return;
    char *cursor = copy;
    char *token;
    while ((token = strsep(&cursor, "|"))) {
        if (*token)
            (void)sandbox_extension_consume(token);
    }
    free(copy);
}
