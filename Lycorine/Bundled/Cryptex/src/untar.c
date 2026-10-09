#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "zstd.h"

static int
write_all(int fd, const void *data, size_t length)
{
    const char *bytes = data;
    while (length != 0) {
        ssize_t written = write(fd, bytes, length);
        if (written < 0 && errno == EINTR)
            continue;
        if (written <= 0)
            return -1;
        bytes += written;
        length -= (size_t)written;
    }
    return 0;
}

int
main(int argc, char **argv)
{
    const char *mount = getenv("CRYPTEX_MOUNT_PATH");
    struct stat destination;
    char toybox[4096], strip[64];
    FILE *archive;
    ZSTD_DStream *stream;
    void *input, *output;
    int pipefd[2], status = 0, waited = 0, failed = 0;
    pid_t child;
    size_t remaining = 1, count;

    if ((argc != 3 && argc != 4) || mount == NULL || mount[0] != '/') {
        fprintf(stderr, "usage: CRYPTEX_MOUNT_PATH=/path untar ARCHIVE.tar.zst DEST [STRIP_COMPONENTS]\n");
        return 2;
    }
    if (stat(argv[2], &destination) != 0 || !S_ISDIR(destination.st_mode)) {
        fprintf(stderr, "untar: destination must be an existing directory: %s\n", argv[2]);
        return 2;
    }
    if (snprintf(toybox, sizeof(toybox), "%s/usr/bin/toybox", mount) >= sizeof(toybox)) {
        fprintf(stderr, "untar: cryptex path is too long\n");
        return 2;
    }
    if (argc == 4) {
        char *end;
        long components = strtol(argv[3], &end, 10);
        if (*argv[3] == '\0' || *end != '\0' || components < 0 || components > 100) {
            fprintf(stderr, "untar: invalid strip count: %s\n", argv[3]);
            return 2;
        }
        snprintf(strip, sizeof(strip), "--strip-components=%ld", components);
    }
    archive = fopen(argv[1], "rb");
    if (archive == NULL) {
        perror("untar: open archive");
        return 1;
    }
    stream = ZSTD_createDStream();
    input = malloc(ZSTD_DStreamInSize());
    output = malloc(ZSTD_DStreamOutSize());
    if (stream == NULL || input == NULL || output == NULL ||
        ZSTD_isError(ZSTD_initDStream(stream)) || pipe(pipefd) != 0) {
        fprintf(stderr, "untar: cannot initialize decompressor\n");
        fclose(archive);
        ZSTD_freeDStream(stream);
        free(input);
        free(output);
        return 1;
    }
    child = fork();
    if (child < 0) {
        perror("untar: fork");
        fclose(archive);
        close(pipefd[0]);
        close(pipefd[1]);
        ZSTD_freeDStream(stream);
        free(input);
        free(output);
        return 1;
    }
    if (child == 0) {
        close(pipefd[1]);
        if (dup2(pipefd[0], STDIN_FILENO) < 0)
            _exit(127);
        close(pipefd[0]);
        fclose(archive);
        if (argc == 4)
            execl(toybox, "toybox", "tar", "-xpf", "-", "-C", argv[2], strip, (char *)NULL);
        else
            execl(toybox, "toybox", "tar", "-xpf", "-", "-C", argv[2], (char *)NULL);
        perror("untar: exec toybox");
        _exit(127);
    }
    close(pipefd[0]);
    signal(SIGPIPE, SIG_IGN);
    while ((count = fread(input, 1, ZSTD_DStreamInSize(), archive)) != 0) {
        ZSTD_inBuffer in = {input, count, 0};
        while (in.pos < in.size) {
            ZSTD_outBuffer out = {output, ZSTD_DStreamOutSize(), 0};
            remaining = ZSTD_decompressStream(stream, &out, &in);
            if (ZSTD_isError(remaining) || write_all(pipefd[1], output, out.pos) != 0) {
                fprintf(stderr, "untar: decompression or tar pipe failed\n");
                failed = 1;
                break;
            }
        }
        if (failed)
            break;
    }
    if (ferror(archive) || remaining != 0)
        failed = 1;
    if (failed)
        fprintf(stderr, "untar: archive is incomplete or invalid\n");
    fclose(archive);
    close(pipefd[1]);
    for (;;) {
        if (waitpid(child, &status, 0) >= 0) {
            waited = 1;
            break;
        }
        if (errno != EINTR) {
            failed = 1;
            break;
        }
    }
    if (!waited || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        failed = 1;
    ZSTD_freeDStream(stream);
    free(input);
    free(output);
    return failed ? 1 : 0;
}
