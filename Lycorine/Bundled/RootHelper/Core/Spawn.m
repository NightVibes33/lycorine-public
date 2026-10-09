#import "Spawn.h"
#import <errno.h>
#import <spawn.h>
#import <stdlib.h>
#import <sys/wait.h>
#import <unistd.h>

extern char **environ;

static NSString *readCapturedOutput(int fd)
{
    NSMutableData *data = [NSMutableData data];
    char buffer[8192];
    if (lseek(fd, 0, SEEK_SET) < 0) return nil;
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count > 0) {
            [data appendBytes:buffer length:(NSUInteger)count];
        } else if (count == 0) {
            break;
        } else if (errno != EINTR) {
            return nil;
        }
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
}

int spawnRoot(NSString *path, NSArray<NSString *> *args, NSString **stdOut, NSString **stdErr)
{
    if (stdOut != NULL) *stdOut = nil;
    if (stdErr != NULL) *stdErr = nil;
    if (geteuid() != 0) return -EPERM;
    if (path.length == 0 || !path.isAbsolutePath) return -EINVAL;

    NSArray<NSString *> *arguments = args ?: @[];
    size_t count = arguments.count;
    char **argv = calloc(count + 2, sizeof(*argv));
    if (argv == NULL) return -ENOMEM;
    argv[0] = (char *)path.lastPathComponent.UTF8String;
    for (size_t i = 0; i < count; i++) {
        if (![arguments[i] isKindOfClass:NSString.class]) {
            free(argv);
            return -EINVAL;
        }
        argv[i + 1] = (char *)arguments[i].UTF8String;
    }

    int outFD = -1, errFD = -1, result = 0;
    char outName[] = "/private/var/tmp/lycorined-out.XXXXXX";
    char errName[] = "/private/var/tmp/lycorined-err.XXXXXX";
    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    if (error != 0) {
        free(argv);
        return -error;
    }
    if (stdOut != NULL) {
        outFD = mkstemp(outName);
        if (outFD < 0) { result = -errno; goto cleanup; }
        unlink(outName);
        error = posix_spawn_file_actions_adddup2(&actions, outFD, STDOUT_FILENO);
        if (error == 0) error = posix_spawn_file_actions_addclose(&actions, outFD);
        if (error != 0) { result = -error; goto cleanup; }
    }
    if (stdErr != NULL) {
        errFD = mkstemp(errName);
        if (errFD < 0) { result = -errno; goto cleanup; }
        unlink(errName);
        error = posix_spawn_file_actions_adddup2(&actions, errFD, STDERR_FILENO);
        if (error == 0) error = posix_spawn_file_actions_addclose(&actions, errFD);
        if (error != 0) { result = -error; goto cleanup; }
    }

    pid_t child;
    error = posix_spawn(&child, path.fileSystemRepresentation, &actions, NULL, argv, environ);
    if (error != 0) { result = -error; goto cleanup; }

    int status;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) { result = -errno; goto cleanup; }
    }
    if (WIFEXITED(status)) result = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) result = 128 + WTERMSIG(status);
    else result = -ECHILD;

    if (stdOut != NULL) *stdOut = readCapturedOutput(outFD);
    if (stdErr != NULL) *stdErr = readCapturedOutput(errFD);

cleanup:
    posix_spawn_file_actions_destroy(&actions);
    if (outFD >= 0) close(outFD);
    if (errFD >= 0) close(errFD);
    free(argv);
    return result;
}
