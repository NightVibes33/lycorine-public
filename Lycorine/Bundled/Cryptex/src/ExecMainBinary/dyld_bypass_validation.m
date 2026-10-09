//
//  dyld_bypass_validation.m
//  Lycorine
//
//  Created by ruter on 02.10.26.
// https://github.com/xpn/DyldDeNeuralyzer/blob/main/DyldDeNeuralyzer/DyldPatch/dyldpatch.m

@import Darwin;
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>
#include <libkern/OSCacheControl.h>
#include <ptrauth.h>
#include "dyld_bypass_validation.h"

#define PATCH_LITERAL_OFFSET 16

// ldr x8, value; br x8; value: .ascii "\x41\x42\x43\x44\x45\x46\x47\x48"
static const uint8_t patch[] = { 0x88,0x00,0x00,0x58,0x00,0x01,0x1f,0xd6,0x1f,0x20,0x03,0xd5,0x1f,0x20,0x03,0xd5,0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41 };

int (*orig_dyld_fcntl)(int fildes, int cmd, void *param);
int (*orig_dyld_mmap)(int fildes, int cmd, void *param);

int (*orig_fcntl)(int fildes, int cmd, void *param) = 0;
bool redirectFunctionDirect(char *name, void *patchAddr, void *target);
bool (*redirectFunction)(char *name, void *patchAddr, void *target) = redirectFunctionDirect;

extern void* __mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

// avoid calling libsystem_kernel's functions
static void builtin_memcpy(char *target, const char *source, size_t size) {
    for (size_t i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

static int builtin_memcmp(const char *a, const char *b, size_t size) {
    for (size_t i = 0; i < size; i++) {
        if (a[i] != b[i]) return (unsigned char)a[i] - (unsigned char)b[i];
    }
    
    return 0;
}

__attribute__((naked, noinline))
kern_return_t builtin_vm_protect(mach_port_name_t task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot) {
    // Explicit newlines keep every instruction in the Mach VM protection trap.
    __asm__("mov x16, #-14\n\t"
            "svc #0x80\n\t"
            "ret");
}

// sub ios 18
bool redirectFunctionDirect(char *name, void *patchAddr, void *target) {
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (kret != KERN_SUCCESS) {
        printf("(dyld) vm_protect(RW) fails (%d) for %s", kret, name);
        return false;
    }

    builtin_memcpy((char *)patchAddr, (const char *)patch, sizeof(patch));
    // The trampoline uses plain br, so its literal must not contain PAC bits.
    uint64_t t = (uint64_t)ptrauth_strip(target, ptrauth_key_function_pointer);
    builtin_memcpy((char *)patchAddr + PATCH_LITERAL_OFFSET, (const char *)&t, sizeof(t));
    sys_icache_invalidate((void *)patchAddr, sizeof(patch));

    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_EXEC);
    if (kret != KERN_SUCCESS) {
        printf("(dyld) vm_protect(RX) fails (%d) for %s", kret, name);
        return false;
    }
    
    printf("(dyld) hook %s succeed!", name);
    
    return true;
}

static size_t text_segment_size(const char *base) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)base;
    const struct load_command *lc = (const struct load_command *)(mh + 1);
    
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *sc = (const struct segment_command_64 *)lc;
            if (strcmp(sc->segname, "__TEXT") == 0) return (size_t)sc->vmsize;
        }
        
        lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
    }
    
    return 0x80000;
}

bool searchAndPatch(const char *name, const char *base, const char *signature, size_t length, void *target) {
    const size_t size = text_segment_size(base);
    if (size < length) {
        printf("(dyld) hook %s failed: text too small", name);
        return false;
    }

    for (size_t i = 0; i + length <= size; i += 4) {
        if (base[i] == signature[0] && builtin_memcmp(base + i, signature, length) == 0) {
            printf("(dyld) found %s at %p", (char *)name, (void *)(base + i));
            return redirectFunction((char *)name, (void *)(base + i), target);
        }
    }

    printf("(dyld) signature not found for %s", name);
    return false;
}

void *getDyldBase(void) {
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    struct dyld_all_image_infos *infos;
    
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    
    if (ret != KERN_SUCCESS) return 0;
    
    image_infos = dyld_info.all_image_info_addr;
    
    infos = (struct dyld_all_image_infos *)image_infos;
    return (void *)infos->dyldImageLoadAddress;
}

void* hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    if (flags & MAP_JIT) {
        errno = EINVAL;
        return MAP_FAILED;
    }
    
    void *map = __mmap(addr, len, prot, flags, fd, offset);
    if (fd == -1 || (prot & PROT_EXEC) == 0) return map;
    
    if (mprotect(map, len, prot) == -1) {
        munmap(map, len);
        map = MAP_FAILED;
    }
    
    if (map == MAP_FAILED) {
        printf("(dyld) mmap(prot=%d, flags=%d, fd=%d)\n", prot, flags, fd);
        map = __mmap(addr, len, prot, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        
        void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
        if (redirectFunction == redirectFunctionDirect) {
            mprotect(map, len, PROT_READ | PROT_WRITE);
            memcpy(map, memoryLoadedFile, len);
            mprotect(map, len, prot);
            sys_icache_invalidate(map, len);
        } else {
            vm_address_t mirrored = 0;
            vm_prot_t cur_prot, max_prot;
            kern_return_t ret = vm_remap(mach_task_self(), &mirrored, len, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)map, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
            if (ret == KERN_SUCCESS) {
                vm_protect(mach_task_self(), mirrored, len, false, VM_PROT_READ | VM_PROT_WRITE);
                memcpy((void *)mirrored, memoryLoadedFile, len);
                sys_icache_invalidate(map, len);
                vm_deallocate(mach_task_self(), mirrored, len);
            }
        }
        
        munmap(memoryLoadedFile, len);
    }
    
    return map;
}

int hooked___fcntl(int fildes, int cmd, void *param) {
    if (cmd == F_ADDFILESIGS_RETURN) {
#if !(TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR)
        bool ignoreFcntl = false;
        if (!ignoreFcntl) orig_fcntl(fildes, cmd, param);
#endif
        fsignatures_t *fsig = (fsignatures_t *)param;
        if (fsig == NULL) return orig_fcntl(fildes, cmd, param);
        
        fsig->fs_file_start = 0xFFFFFFFFFFFFFFFFULL;
        return 0;
    }

    else if (cmd == F_CHECK_LV) return 0;
    
    return orig_fcntl(fildes, cmd, param);
}

bool init_bypassDyldLibValidation(void) {
    static bool bypassed;
    if (bypassed) return true;

    signal(SIGBUS, SIG_IGN);
    
    orig_fcntl = __fcntl;
    char *dyldBase = getDyldBase();
    if (!dyldBase) return false;
    
    bool mmapPatchSuccess = searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
    bool fcntlPatchSuccess = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked___fcntl);
    
    // https://github.com/LiveContainer/LiveContainer/commit/c978e62
    // dopamine already hooked it, try to find its hook instead
    if(!fcntlPatchSuccess) {
        char* fcntlAddr = 0;
        size_t dyldTextSize = text_segment_size(dyldBase);
        for (size_t i = 0; i + 4 <= dyldTextSize; i += 4) {
            if (dyldBase[i] == syscallSig[0] && builtin_memcmp(dyldBase + i, syscallSig, 4) == 0) {
                char* syscallAddr = dyldBase + i;
                uint32_t* prev = (uint32_t*)(syscallAddr - 4);
                if(*prev >> 26 == 0x5) {
                    fcntlAddr = (char*)prev;
                    break;
                }
            }
        }
        
        if(fcntlAddr) {
            uint32_t* inst = (uint32_t*)fcntlAddr;
            int32_t offset = ((int32_t)((*inst)<<6))>>4;
            printf("(dyld) dopamine hook = %x\n", offset);
            orig_fcntl = (void*)((char*)fcntlAddr + offset);
            fcntlPatchSuccess = redirectFunction("dyld_fcntl (dopamine)", fcntlAddr, hooked___fcntl);
        } else {
            printf("(dyld) dopamine hook not found\n");
        }
    }
    
    bypassed = mmapPatchSuccess && fcntlPatchSuccess;
    return bypassed;
}
