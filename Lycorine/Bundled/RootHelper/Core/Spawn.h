#import <Foundation/Foundation.h>

// The daemon must already run as root. Returns the exit status, 128 + signal,
// or -errno if spawning or waiting fails.
int spawnRoot(NSString *path, NSArray<NSString *> *args, NSString **stdOut, NSString **stdErr);
