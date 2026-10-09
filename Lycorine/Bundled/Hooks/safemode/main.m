#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <os/log.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>
#include <string.h>

static const char *const marker = "/var/mobile/.lycorine-safe-mode";
static const char *const ellekit_marker = "/var/mobile/.eksafemode";
static NSUncaughtExceptionHandler *previous_handler;

bool lycorine_safemode_active(void) {
    struct stat status;
    if (lstat(marker, &status) == 0 && S_ISREG(status.st_mode) &&
        status.st_nlink == 1 && (status.st_uid == 0 || status.st_uid == 501) &&
        (status.st_mode & (S_IWGRP | S_IWOTH)) == 0) return true;
    return access(ellekit_marker, F_OK) == 0;
}

static void record_exception(NSException *exception) {
    int descriptor = open(marker, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (descriptor >= 0) {
        NSString *line = [NSString stringWithFormat:@"tweak=Unknown tweak\nreason=%@\n", exception.name ?: @"Uncaught exception"];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        (void)write(descriptor, data.bytes, MIN(data.length, 4096U));
        close(descriptor);
    }
    if (previous_handler != NULL) previous_handler(exception);
}

static bool is_replacement_springboard(void) {
    char path[PATH_MAX];
    uint32_t length = sizeof(path);
    return _NSGetExecutablePath(path, &length) == 0 &&
        strcmp(path, "/var/jb/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0;
}

static void show_alert(unsigned attempt) {
    if (attempt >= 60) return;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] ||
            scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (window != nil) break;
    }
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (presenter == nil || presenter.view.window == nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ show_alert(attempt + 1); });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Lycorine Safe Mode"
        message:@"SpringBoard started without tweaks after a crash. Disable the faulty tweak, then respring."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Stay in Safe Mode" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring With Tweaks" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        (void)unlink(marker);
        (void)unlink(ellekit_marker);
        (void)kill(getpid(), SIGTERM);
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor)) static void initialize_safemode(void) {
    if (!is_replacement_springboard()) return;
    if (lycorine_safemode_active()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ show_alert(0); });
        os_log(OS_LOG_DEFAULT, "Lycorine: SpringBoard safe mode active");
    } else {
        previous_handler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(record_exception);
    }
}
