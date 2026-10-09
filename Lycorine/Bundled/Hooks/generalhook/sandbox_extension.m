#include <mach/mach.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include "sandbox.h"
#include "sandbox_extension.h"

static audit_token_t get_own_audit_token(void)
{
    audit_token_t token = {0};
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;

    kern_return_t kr = task_info(
        mach_task_self(),
        TASK_AUDIT_TOKEN,
        (task_info_t)&token,
        &count
    );

    if (kr != KERN_SUCCESS) {
        memset(&token, 0, sizeof(token));
    }

    return token;
}

void applySandboxExtensions(bool writable)
{
    audit_token_t processToken = get_own_audit_token();

    char *readExtension =
        sandbox_extension_issue_file_to_process(
            "com.apple.app-sandbox.read",
            "/var/jb",
            0,
            processToken
        );

    char *execExtension =
        sandbox_extension_issue_file_to_process(
            "com.apple.sandbox.executable",
            "/var/jb",
            0,
            processToken
        );

    char *mobileExtension =
        sandbox_extension_issue_file_to_process(
            writable
                ? "com.apple.app-sandbox.read-write"
                : "com.apple.app-sandbox.read",
            "/var/mobile",
            0,
            processToken
        );

    if (readExtension) {
        sandbox_extension_consume(readExtension);
        free(readExtension);
    }

    if (execExtension) {
        sandbox_extension_consume(execExtension);
        free(execExtension);
    }

    if (mobileExtension) {
        sandbox_extension_consume(mobileExtension);
        free(mobileExtension);
    }
}

