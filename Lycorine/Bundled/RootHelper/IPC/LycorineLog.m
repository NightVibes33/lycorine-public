#import "LycorineLog.h"
#import <stdarg.h>

static NSString *processingPath;
static NSObject *logLock;

void lycorinedSetProcessingPath(NSString *path)
{
    if (logLock == nil) logLock = [NSObject new];
    @synchronized (logLock) {
        processingPath = [path copy];
    }
}

void lycorinedClearProcessingPath(void)
{
    if (logLock == nil) logLock = [NSObject new];
    @synchronized (logLock) {
        processingPath = nil;
    }
}

void lycorinedLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[lycorined] %@", message);
    if (logLock == nil) logLock = [NSObject new];
    @synchronized (logLock) {
        if (processingPath.length == 0) return;
        NSData *data = [[message stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:processingPath];
        if (file == nil) return;
        [file seekToEndOfFile];
        [file writeData:data];
        [file closeFile];
    }
}

void lycorinedLogMessage(const char *message)
{
    lycorinedLog(@"%s", message);
}
