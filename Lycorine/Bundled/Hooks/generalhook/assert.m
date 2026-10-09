#import <Foundation/Foundation.h>
#include <stdlib.h>

void __assert_rtn(const char *func, const char *file, int line, const char *failedexpr) {
    [NSException raise:NSInternalInconsistencyException
                format:@"Assertion failed: (%s), file %s, line %d.\n", failedexpr, file, line];
    abort(); // silent compiler warning
}
