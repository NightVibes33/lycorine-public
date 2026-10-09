#import <Foundation/Foundation.h>
#include "routes.h"
#include "../Injection/spawn_environment.h"
#include "../Trust/trust.h"
#include "jit_spawn.h"
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static NSString *resolveTarget(const char *path, bool searchPath, char *const envp[]) {
    if (!path || !*path) {
        return nil;
    }

    NSString *targetPath = @(path);
    char resolvedPath[PATH_MAX];
    if (!searchPath || [targetPath containsString:@"/"]) {
        if (!realpath(path, resolvedPath)) {
            return nil;
        }
        return @(resolvedPath);
    }

    NSString *searchDirectories = nil;
    const char *currentPath = getenv("PATH");
    if (currentPath) {
        searchDirectories = @(currentPath);
    }
    for (size_t index = 0; envp && envp[index]; index++) {
        NSString *entry = @(envp[index]);
        if ([entry hasPrefix:@"PATH="]) {
            searchDirectories = [entry substringFromIndex:@"PATH=".length];
            break;
        }
    }
    if (!searchDirectories) {
        searchDirectories = @"/usr/bin:/bin:/usr/sbin:/sbin";
    }

    for (NSString *directory in [searchDirectories componentsSeparatedByString:@":"]) {
        NSString *searchDirectory = directory;
        if (searchDirectory.length == 0) {
            searchDirectory = @".";
        }
        NSString *candidatePath = [searchDirectory stringByAppendingPathComponent:targetPath];
        if (strlen(candidatePath.fileSystemRepresentation) >= PATH_MAX) {
            continue;
        }
        struct stat status;
        if (stat(candidatePath.fileSystemRepresentation, &status) != 0 ||
            !S_ISREG(status.st_mode)) {
            continue;
        }
        if (access(candidatePath.fileSystemRepresentation, X_OK) != 0) {
            continue;
        }
        if (realpath(candidatePath.fileSystemRepresentation, resolvedPath)) {
            return @(resolvedPath);
        }
    }
    return nil;
}

static char **loaderEnvironment(char *const envp[], NSString *targetPath, char **entryOut) {
    extern char **environ;
    char *const *source = envp;
    if (!source) {
        source = environ;
    }

    size_t count = 0;
    while (source && count < 4096 && source[count]) {
        count++;
    }
    if (count == 4096) {
        return NULL;
    }

    NSString *dylibEntry = [@"__DYLIB_PATH=" stringByAppendingString:targetPath];
    char **environment = calloc(count + 2, sizeof(*environment));
    char *entry = strdup(dylibEntry.UTF8String);
    if (!environment || !entry) {
        free(environment);
        free(entry);
        return NULL;
    }

    size_t used = 0;
    for (size_t index = 0; index < count; index++) {
        NSString *existingEntry = @(source[index]);
        if (![existingEntry hasPrefix:@"__DYLIB_PATH="]) {
            environment[used++] = source[index];
        }
    }
    environment[used] = entry;
    *entryOut = entry;
    return environment;
}

int spawn_loader(spawn_function_t original, pid_t *pid, const char *path, bool searchPath,
                 const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                 char *const argv[], char *const envp[]) {
    @autoreleasepool {
        NSString *executablePath = resolveTarget(path, searchPath, envp);
        if (!executablePath) {
            return -1;
        }

        char resolvedRoot[PATH_MAX];
        if (!realpath("/var/jb", resolvedRoot)) {
            return -1;
        }
        NSString *jailbreakRoot = @(resolvedRoot);
        NSString *jailbreakPrefix = [jailbreakRoot stringByAppendingString:@"/"];
        if (![executablePath hasPrefix:jailbreakPrefix]) {
            return -1;
        }

        NSString *cryptexRoot = [jailbreakRoot stringByAppendingPathComponent:@"cryptex"];
        NSString *cryptexPrefix = [cryptexRoot stringByAppendingString:@"/"];
        if ([executablePath hasPrefix:cryptexPrefix]) {
            return -1;
        }
// dont hook xpcproxy with jitterd
        if ([executablePath isEqualToString:
                resolveTarget("/var/jb/usr/libexec/xpcproxy", false, NULL)]) {
            return -1;
        }

        NSString *loaderPath =
            resolveTarget("/var/jb/usr/libexec/lycorine/ExecMainBinary", false, NULL);
        if ([executablePath isEqualToString:loaderPath]) {
            return -1;
        }
        struct stat status;
        if (stat(executablePath.fileSystemRepresentation, &status) != 0 ||
            !S_ISREG(status.st_mode)) {
            return -1;
        }
        if (access(executablePath.fileSystemRepresentation, X_OK) != 0) {
            return -1;
        }

        int trust = trust_query(executablePath.fileSystemRepresentation, NULL);
        if (trust == 1) {

            char *libraryEntry = NULL, *sandboxEntry = NULL;
            char **environment = inject_env(envp, executablePath.fileSystemRepresentation,
                                            &libraryEntry, &sandboxEntry);
            const char *spawnPath =
                searchPath && !strchr(path, '/') ? executablePath.fileSystemRepresentation : path;
            int result = spawn_jit(original, pid, spawnPath, actions, attributes, argv,
                                   environment ? environment : envp, false);
            inject_free(environment, libraryEntry, sandboxEntry);
            return result;
        }
        if (!loaderPath) {
            return -1;
        }
        char *loaderEntry = NULL;
        char **environment = loaderEnvironment(envp, executablePath, &loaderEntry);
        if (!environment) {
            return ENOMEM;
        }

        char *libraryEntry = NULL;
        char *sandboxEntry = NULL;
        char **hookEnvironment = inject_env(environment, executablePath.fileSystemRepresentation,
                                            &libraryEntry, &sandboxEntry);
        char **spawnEnvironment = environment;
        if (hookEnvironment) {
            spawnEnvironment = hookEnvironment;
        }

        char **argumentCopy = NULL;
        char *const *spawnArguments = argv;
        if (argv && argv[0]) {
            size_t count = 0;
            while (argv[count]) {
                count++;
            }
            argumentCopy = calloc(count + 1, sizeof(*argumentCopy));
            if (argumentCopy) {
                for (size_t index = 0; index < count; index++) {
                    argumentCopy[index] = argv[index];
                }
                argumentCopy[0] = (char *)executablePath.fileSystemRepresentation;
                spawnArguments = argumentCopy;
            }
        }

        int result = spawn_jit(original, pid, "/var/jb/usr/libexec/lycorine/ExecMainBinary",
                               actions, attributes, spawnArguments, spawnEnvironment, false);
        free(argumentCopy);
        if (hookEnvironment) {
            inject_free(hookEnvironment, libraryEntry, sandboxEntry);
        }
        free(environment);
        free(loaderEntry);
        return result;
    }
}
