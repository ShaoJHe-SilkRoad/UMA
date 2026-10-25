#import <AppKit/AppKit.h>
#include <pthread.h>

// Runs the test host's main thread inside `NSApp.run`, the way the app runs.
//
// Swift Testing drives the main thread with the Swift concurrency main
// executor, a bare `CFRunLoopRun`, and a run-loop stop ends it: the process
// then exits 0 with every test not yet run silently skipped, while `swift
// test` reports success. AppKit sends such stops routinely. Once a test has
// put windows on screen, HIToolbox wakes the main loop with a stop whenever a
// window-server event arrives for the process, sometimes after the window is
// gone. A modal session's cleanup does the same. In the app those stops
// interrupt `NSApp.run`'s event wait and the loop carries on. In the test host
// they ended the run: about a fifth of the UI tests were never run, and the
// failures among them went unseen.
//
// So the runner's loop gets the app's loop to run inside it. It is started
// from a run-loop block, not from a main-queue job, so the main dispatch queue,
// and with it the main actor, keeps being serviced inside `NSApp.run`. The
// process still ends the way Swift Testing ends it: by calling `exit` when the
// run is complete.
//
// It is installed only under Swift Testing's own runner. XCTest drives the main
// thread differently, and an event loop started there would never hand it
// back. The env-gated UMA015 visual-evidence probes run their own
// `NSApp.run`, so it is left out for them too. Where the checks do not match,
// nothing is installed and the host behaves exactly as before.
__attribute__((constructor)) static void TestHostEventLoopInstall(void) {
    if (!pthread_main_np()) return;
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger flag = [arguments indexOfObject:@"--testing-library"];
    BOOL swiftTesting = flag != NSNotFound && flag + 1 < arguments.count
        && [arguments[flag + 1] isEqualToString:@"swift-testing"];
    if (!swiftTesting) return;
    for (NSString *key in NSProcessInfo.processInfo.environment) {
        if ([key hasPrefix:@"UMA015_"]) return;
    }
    CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopDefaultMode, ^{
        [NSApplication sharedApplication];
        [NSApp run];
    });
    CFRunLoopWakeUp(CFRunLoopGetMain());
}
