#include "trust.h"

#include <IOKit/IOKitLib.h>

#define AMFI_NOT_FOUND 0xe00002f0U

// Reverse engineered from the bundled iOS trustcachectl query command.
// Selector 6 takes scalar 1 and a 20-byte CDHash, with no output buffers.
static int query_hash(const uint8_t cdhash[20]) {
    io_service_t service = IOServiceGetMatchingService(
        kIOMasterPortDefault, IOServiceMatching("AppleMobileFileIntegrity"));
    if (service == IO_OBJECT_NULL)
        return -1;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t opened = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (opened != KERN_SUCCESS)
        return -1;

    uint64_t operation = 1;
    kern_return_t queried =
        IOConnectCallMethod(connection, 6, &operation, 1, cdhash, 20, NULL, NULL, NULL, NULL);
    IOServiceClose(connection);
    if (queried == KERN_SUCCESS)
        return 1;
    if ((uint32_t)queried == AMFI_NOT_FOUND)
        return 0;
    return -1;
}

int trust_query(const char *path, bool *adhoc) {
    uint8_t hashes[64][20];
    size_t count = binary_cdhashes(path, hashes, adhoc);
    if (count == 0)
        return -1;
    for (size_t i = 0; i < count; ++i) {
        int result = query_hash(hashes[i]);
        if (result != 1)
            return result;
    }
    return 1;
}
