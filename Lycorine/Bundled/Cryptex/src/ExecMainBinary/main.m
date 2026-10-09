#import "dyld_bypass_validation.h"
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#import <assert.h>
@import MachO;

#define PT_KILL 8
#define PT_DETACH 11
#define PT_ATTACHEXC 14
int ptrace(int request, pid_t pid, caddr_t addr, int data);
const struct mach_header* _dyld_get_dlopen_image_header(void* handle);

void *getAppEntryPoint(void *handle) {
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)_dyld_get_dlopen_image_header(handle);
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds; ++i) {
        if(command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            entryoff = ucmd.entryoff;
            break;
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    assert(entryoff > 0);
    return (void *)header + entryoff;
}

struct dyld_all_image_infos *_alt_dyld_get_all_image_infos(void) {
    static struct dyld_all_image_infos *result;
    if (result) {
        return result;
    }
    struct task_dyld_info dyld_info;
    mach_vm_address_t image_infos;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t ret;
    ret = task_info(mach_task_self_,
                    TASK_DYLD_INFO,
                    (task_info_t)&dyld_info,
                    &count);
    if (ret != KERN_SUCCESS) {
        return NULL;
    }
    image_infos = dyld_info.all_image_info_addr;
    result = (struct dyld_all_image_infos *)image_infos;
    return result;
}

void init_enableJIT(void) {
    pid_t pid = fork();
    if (pid == 0) {
        while (true) {
            kill(getpid(), SIGSTOP);
            kill(getpid(), SIGKILL);
        }
    } else if (pid > 0) {
        ptrace(PT_ATTACHEXC, pid, NULL, 0);
        ptrace(PT_DETACH, pid, NULL, 0);
        ptrace(PT_KILL, pid, NULL, 0);
        waitpid(pid, NULL, 0);
    } else {
        fprintf(stderr, "Failed to fork process\n");
        exit(EXIT_FAILURE);
    }
}

int main(int argc, const char *argv[], const char *envp[], const char *apple[]) {
    init_enableJIT();
    init_bypassDyldLibValidation();
    
    char dylibPath[PATH_MAX];
    const char *testDylibFile = getenv("__DYLIB_PATH");
    if(testDylibFile) {
        snprintf(dylibPath, sizeof(dylibPath), "%s", testDylibFile);
    } else {
        snprintf(dylibPath, sizeof(dylibPath), "@executable_path/%s.dylib", basename((char *)argv[0]));
    }
    void *handle = dlopen(dylibPath, RTLD_GLOBAL | RTLD_NOW);
    if(!handle) {
        fprintf(stderr, "Failed to load dylib: %s\n", dlerror());
        return EXIT_FAILURE;
    }
    
    int (*mainFunction)(int, const char *[], const char *[], const char *[]) = getAppEntryPoint(handle);
    if(!mainFunction) {
        fprintf(stderr, "Failed to get entry point from dylib\n");
        return EXIT_FAILURE;
    }
    
    return mainFunction(argc, argv, envp, apple);
}
