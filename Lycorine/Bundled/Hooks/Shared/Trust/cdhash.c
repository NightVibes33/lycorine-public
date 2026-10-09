#include "trust.h"

#include <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <mach-o/utils.h>
#include <stdbool.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static uint32_t big32(const void *pointer) {
    uint32_t value;
    memcpy(&value, pointer, sizeof(value));
    return ntohl(value);
}

static unsigned rank_for_type(uint8_t type) {
    switch (type) {
    case 1:
        return 1;
    case 3:
        return 2;
    case 2:
        return 3;
    case 4:
        return 4;
    default:
        return 0;
    }
}

static bool slice_hash(const uint8_t *data, size_t size, uint8_t result[20], bool *adhoc) {
    if (size < sizeof(struct mach_header_64))
        return false;
    const struct mach_header_64 *header = (const void *)data;
    if (header->magic != MH_MAGIC_64 || header->sizeofcmds > size - sizeof(*header))
        return false;
    size_t cursor = sizeof(*header);
    size_t end = cursor + header->sizeofcmds;
    uint32_t signature_offset = 0, signature_size = 0;
    for (uint32_t index = 0; index < header->ncmds; ++index) {
        if (cursor > end || end - cursor < sizeof(struct load_command))
            return false;
        const struct load_command *command = (const void *)(data + cursor);
        if (command->cmdsize < sizeof(*command) || command->cmdsize > end - cursor)
            return false;
        if (command->cmd == LC_CODE_SIGNATURE &&
            command->cmdsize >= sizeof(struct linkedit_data_command)) {
            const struct linkedit_data_command *signature = (const void *)command;
            signature_offset = signature->dataoff;
            signature_size = signature->datasize;
        }
        cursor += command->cmdsize;
    }
    if (signature_size < 12 || signature_offset > size || signature_size > size - signature_offset)
        return false;
    const uint8_t *blob = data + signature_offset;
    uint32_t length = big32(blob + 4), count = big32(blob + 8);
    if (big32(blob) != 0xfade0cc0 || length < 12 || length > signature_size ||
        count > (length - 12) / 8)
        return false;
    unsigned best = 0;
    bool has_cms = false;
    for (uint32_t index = 0; index < count; ++index) {
        uint32_t slot = big32(blob + 12 + index * 8);
        uint32_t offset = big32(blob + 16 + index * 8);
        if (offset < 12 + count * 8 || offset > length || length - offset < 8)
            return false;
        const uint8_t *directory = blob + offset;
        uint32_t directory_length = big32(directory + 4);
        if (directory_length < 8 || directory_length > length - offset)
            return false;
        if (slot == 0x10000) { // CSSLOT_SIGNATURESLOT
            if (big32(directory) != 0xfade0b01) // CSMAGIC_BLOBWRAPPER
                return false;
            has_cms = true;
        }
        if (slot != 0 && (slot < 0x1000 || slot >= 0x1005))
            continue;
        if (big32(directory) != 0xfade0c02 || directory_length < 40)
            return false;
        uint8_t type = directory[37];
        unsigned rank = rank_for_type(type);
        if (rank <= best)
            continue;
        uint8_t digest[CC_SHA512_DIGEST_LENGTH];
        if (type == 1)
            CC_SHA1(directory, directory_length, digest);
        else if (type == 2 || type == 3)
            CC_SHA256(directory, directory_length, digest);
        else if (type == 4)
            CC_SHA384(directory, directory_length, digest);
        else
            continue;
        memcpy(result, digest, 20);
        *adhoc = (big32(directory + 12) & 0x2U) != 0; // CS_ADHOC
        best = rank;
    }
    // Some older ldid signatures omit CMS without setting CS_ADHOC (e.g. Filza).
    if (best != 0 && !has_cms)
        *adhoc = true;
    return best != 0;
}

size_t binary_cdhashes(const char *path, uint8_t hashes[64][20], bool *adhoc) {
    if (adhoc)
        *adhoc = false;
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0)
        return 0;
    struct stat status;
    __block size_t found = 0;
    __block bool slice_adhoc = false;
    if (fstat(fd, &status) == 0 && S_ISREG(status.st_mode) &&
        status.st_size >= (off_t)sizeof(struct mach_header_64) &&
        (uintmax_t)status.st_size <= SIZE_MAX) {
        int error = macho_best_slice_in_fd(fd, ^(const struct mach_header *slice,
                                                uint64_t offset, size_t size) {
            if (slice_hash((const uint8_t *)slice, size, hashes[0], &slice_adhoc))
                found = 1;
        });
        if (error)
            found = 0;
    }
    close(fd);
    if (adhoc)
        *adhoc = found != 0 && slice_adhoc;
    return found;
}
