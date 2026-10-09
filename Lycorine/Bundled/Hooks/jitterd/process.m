#include "process.h"
#include "log.h"
#include <dispatch/dispatch.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc.h>
#include <time.h>
#include <unistd.h>

#define PT_DETACH 11
#define PT_ATTACHEXC 14
#define EXEC_TIMEOUT_MS 5000
#define DETACH_TIMEOUT_MS 500

extern int ptrace(int, pid_t, void *, int);
extern int proc_pidinfo(int, int, uint64_t, void *, int);
extern int proc_pidpath(int, void *, uint32_t);

struct jit_bsdinfo {
    uint32_t flags, status, xstatus, pid, ppid;
    uid_t uid;
    gid_t gid;
    uid_t ruid;
    gid_t rgid;
    uid_t svuid;
    gid_t svgid;
    uint32_t reserved;
    char comm[16], name[32];
    uint32_t nfiles, pgid, pjobc, e_tdev, e_tpgid;
    int32_t nice;
    uint64_t start_tvsec, start_tvusec;
};
_Static_assert(sizeof(struct jit_bsdinfo) == 136, "proc_bsdinfo ABI mismatch");

static uint64_t milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static bool process_info(pid_t pid, struct jit_bsdinfo *info) {
    return proc_pidinfo(pid, 3, 0, info, sizeof(*info)) == sizeof(*info) &&
           info->pid == (uint32_t)pid;
}

static bool matching_path(pid_t pid, const char *expected) {
    char observed[PATH_MAX], resolved[PATH_MAX];
    return proc_pidpath(pid, observed, sizeof(observed)) > 0 && realpath(observed, resolved) &&
           !strcmp(resolved, expected);
}

bool process_allowed(const jit_request_t *request, pid_t caller) {
    if (request->operation == JIT_SETEXEC)
        return request->pid == caller;
    struct jit_bsdinfo info = {0};
    return process_info(request->pid, &info) && info.ppid == (uint32_t)caller;
}

static int resume_process(pid_t pid) {
    int error = kill(pid, SIGCONT) == 0 ? 0 : errno;
    jitterd_log("resume pid=%d error=%d", pid, error);
    return error;
}

static int detach_process(pid_t pid) {
    // ATTACHEXC posts its stop asynchronously; immediate detach can be EBUSY.
    uint64_t deadline = milliseconds() + DETACH_TIMEOUT_MS;
    int error;
    do {
        error = ptrace(PT_DETACH, pid, NULL, 0) == 0 ? 0 : errno;
        if (error != EBUSY || milliseconds() >= deadline)
            break;
        usleep(1000);
    } while (true);
    jitterd_log("detach pid=%d error=%d", pid, error);
    return error;
}

static int trace_process(pid_t pid, bool resume) {
    int error = ptrace(PT_ATTACHEXC, pid, NULL, 0) == 0 ? 0 : errno;
    jitterd_log("attach pid=%d error=%d", pid, error);
    if (!error)
        error = detach_process(pid);
    if (resume) {
        int resume_error = resume_process(pid);
        if (!error)
            error = resume_error;
    }
    return error;
}

static bool wait_for_exec(const jit_request_t *request, uint64_t deadline) {
    while (milliseconds() < deadline) {
        struct jit_bsdinfo info = {0};
        if (process_info(request->pid, &info) && info.status == SSTOP &&
            matching_path(request->pid, request->path))
            return true;
        usleep(10000);
    }
    return false;
}

static void prepare_process(const jit_request_t *request, uint64_t deadline) {
    bool found = request->operation == JIT_SETEXEC ? wait_for_exec(request, deadline)
                                                   : matching_path(request->pid, request->path);
    int error;
    if (found && milliseconds() < deadline) {
        error = trace_process(request->pid, request->resume);
    } else {
        error =
            request->operation == JIT_SETEXEC || milliseconds() >= deadline ? ETIMEDOUT : EINVAL;
        if (request->resume)
            resume_process(request->pid);
    }
    jitterd_log("prepared pid=%d operation=%u error=%d", request->pid, request->operation, error);
}

void process_enqueue(const jit_request_t *request) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      queue = dispatch_queue_create("com.hrtowii.jitterd.trace", DISPATCH_QUEUE_SERIAL);
    });
    jit_request_t copy = *request;
    uint64_t deadline = milliseconds() + EXEC_TIMEOUT_MS;
    dispatch_async(queue, ^{
      prepare_process(&copy, deadline);
    });
}
