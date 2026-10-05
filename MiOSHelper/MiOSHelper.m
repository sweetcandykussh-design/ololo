// mioshelperd — privileged force-injection daemon (DoritosHelper + secretsaucemonitor equivalent).
//
// Runs as root with task_for_pid-allow. Provides an XPC Mach service (com.mios.helperd) for:
//   - inject: force-load a dylib into a running process via task_for_pid + thread_create_running
//   - stage:  copy a dylib to /var/tmp/ (sandbox-readable by all daemons)
//   - inject-all: stage + inject MiOSSupport.dylib into all known system daemons
//   - status: report PIDs of known daemons
//
// Also acts as a watchdog: monitors known daemons and re-injects on respawn (secretsaucemonitor
// equivalent). The 30s poll detects daemon restarts (pid change) and triggers re-injection.

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>
#include "MiOSInject/mios_inject.h"

static NSString *const kLogDir  = @"/var/mobile/Library/Preferences/MiOS/debug";
static NSString *const kMiOSBase = @"/var/mobile/Library/Preferences/MiOS";

static void hlog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    @try {
        [[NSFileManager defaultManager] createDirectoryAtPath:kLogDir withIntermediateDirectories:YES
                                                   attributes:nil error:nil];
        NSString *path = [kLogDir stringByAppendingPathComponent:@"helper.log"];
        NSString *entry = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], line];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) { [entry writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        else { @try { [fh seekToEndOfFile]; [fh writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]]; }
               @catch (__unused id e) {} [fh closeFile]; }
        chown(path.UTF8String, 501, 501);
    } @catch (__unused id e) {}
}

#pragma mark - Dylib source path

static NSString *supportDylibSource(void) {
    for (NSString *p in @[@"/var/jb/Library/MobileSubstrate/DynamicLibraries/MiOSSupport.dylib",
                          @"/Library/MobileSubstrate/DynamicLibraries/MiOSSupport.dylib"]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

#pragma mark - Inject-all: stage + inject into known daemons

static NSDictionary *doInjectAll(void) {
    NSString *src = supportDylibSource();
    if (!src) {
        hlog(@"[inject-all] MiOSSupport.dylib NOT found");
        return @{@"error": @"dylib not found"};
    }
    NSString *staged = mios_stage_dylib(src);
    if (!staged) {
        hlog(@"[inject-all] staging failed");
        return @{@"error": @"staging failed"};
    }
    hlog(@"[inject-all] staged %@ -> %@", src, staged);

    const char *daemons[] = { "securityd", "containermanagerd", "cfprefsd", NULL };
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    for (int i = 0; daemons[i]; i++) {
        pid_t pid = mios_find_pid(daemons[i]);
        if (pid == 0) {
            hlog(@"[inject-all] %s: not running", daemons[i]);
            results[@(daemons[i])] = @"not_running";
            continue;
        }
        kern_return_t kr = mios_inject_pid(pid, staged.UTF8String);
        NSString *res = (kr == KERN_SUCCESS) ? @"ok"
            : [NSString stringWithFormat:@"failed:0x%x(%s)", kr, mach_error_string(kr)];
        hlog(@"[inject-all] %s (pid %d): %@", daemons[i], pid, res);
        results[@(daemons[i])] = res;
    }
    return results;
}

#pragma mark - XPC handler

static void handle_message(xpc_object_t msg, xpc_connection_t peer) {
    @autoreleasepool {
        const char *op = xpc_dictionary_get_string(msg, "op");
        if (!op) return;
        xpc_object_t reply = xpc_dictionary_create_reply(msg);
        if (!reply) return;

        if (strcmp(op, "inject") == 0) {
            const char *dylib = xpc_dictionary_get_string(msg, "dylib");
            const char *proc  = xpc_dictionary_get_string(msg, "process");
            if (dylib && proc) {
                pid_t pid = mios_find_pid(proc);
                if (pid == 0) {
                    xpc_dictionary_set_bool(reply, "success", false);
                    xpc_dictionary_set_string(reply, "error", "process not found");
                } else {
                    kern_return_t kr = mios_inject_pid(pid, dylib);
                    xpc_dictionary_set_bool(reply, "success", kr == KERN_SUCCESS);
                    if (kr != KERN_SUCCESS)
                        xpc_dictionary_set_string(reply, "error", mach_error_string(kr));
                    hlog(@"[xpc] inject %s into %s (pid %d): %s", dylib, proc, pid, mach_error_string(kr));
                }
            } else {
                xpc_dictionary_set_bool(reply, "success", false);
                xpc_dictionary_set_string(reply, "error", "missing dylib or process");
            }

        } else if (strcmp(op, "stage") == 0) {
            const char *src = xpc_dictionary_get_string(msg, "source");
            if (src) {
                NSString *staged = mios_stage_dylib(@(src));
                xpc_dictionary_set_bool(reply, "success", staged != nil);
                if (staged) xpc_dictionary_set_string(reply, "path", staged.UTF8String);
                else xpc_dictionary_set_string(reply, "error", "copy failed");
            } else {
                xpc_dictionary_set_bool(reply, "success", false);
                xpc_dictionary_set_string(reply, "error", "missing source");
            }

        } else if (strcmp(op, "inject-all") == 0) {
            NSDictionary *res = doInjectAll();
            xpc_dictionary_set_bool(reply, "success", res[@"error"] == nil);
            for (NSString *k in res)
                xpc_dictionary_set_string(reply, k.UTF8String, [res[k] description].UTF8String);

        } else if (strcmp(op, "status") == 0) {
            const char *names[] = { "securityd", "containermanagerd", "cfprefsd", "lsd", NULL };
            for (int i = 0; names[i]; i++)
                xpc_dictionary_set_int64(reply, names[i], mios_find_pid(names[i]));
            xpc_dictionary_set_bool(reply, "success", true);

        } else {
            xpc_dictionary_set_bool(reply, "success", false);
            xpc_dictionary_set_string(reply, "error", "unknown op");
        }

        xpc_connection_send_message(peer, reply);
    }
}

#pragma mark - Watchdog

// Track last-known PIDs of monitored daemons. If a PID changes (daemon restarted), re-inject.
static NSMutableDictionary *gLastPIDs;

static void watchdogTick(void) {
    @autoreleasepool {
        if (![[NSFileManager defaultManager] fileExistsAtPath:
              [kMiOSBase stringByAppendingPathComponent:@"enable_daemons"]]) return;

        NSString *staged = @"/var/tmp/MiOSSupport.dylib";
        if (![[NSFileManager defaultManager] fileExistsAtPath:staged]) {
            NSString *src = supportDylibSource();
            if (src) staged = mios_stage_dylib(src);
            if (!staged) return;
        }

        const char *daemons[] = { "securityd", "containermanagerd", "cfprefsd", NULL };
        for (int i = 0; daemons[i]; i++) {
            NSString *name = @(daemons[i]);
            pid_t pid = mios_find_pid(daemons[i]);
            if (pid == 0) continue;
            NSNumber *last = gLastPIDs[name];
            if (last && last.intValue == pid) continue;  // same pid, already injected

            hlog(@"[watchdog] %@ pid changed %@ -> %d, re-injecting", name, last ?: @"(none)", pid);
            kern_return_t kr = mios_inject_pid(pid, staged.UTF8String);
            hlog(@"[watchdog] %@ inject: %s", name, mach_error_string(kr));
            if (kr == KERN_SUCCESS) gLastPIDs[name] = @(pid);
        }
    }
}

#pragma mark - Main

int main(int argc, char **argv) {
    @autoreleasepool {
        hlog(@"[start] mioshelperd up (force-inject helper + watchdog)");
        gLastPIDs = [NSMutableDictionary dictionary];

        // XPC Mach service listener — xpc_connection_create_mach_service is present on iOS but the SDK
        // marks it __API_UNAVAILABLE(ios). Look it up via dlsym (standard jailbreak pattern).
        typedef xpc_connection_t (*xpc_create_mach_fn)(const char *, dispatch_queue_t, uint64_t);
        xpc_create_mach_fn _create_mach = (xpc_create_mach_fn)dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
        if (!_create_mach) { hlog(@"[FATAL] xpc_connection_create_mach_service not found"); return 1; }
        xpc_connection_t listener = _create_mach(
            "com.mios.helperd", NULL, XPC_CONNECTION_MACH_SERVICE_LISTENER);

        xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
            if (xpc_get_type(peer) != XPC_TYPE_CONNECTION) return;
            xpc_connection_set_event_handler((xpc_connection_t)peer, ^(xpc_object_t msg) {
                if (xpc_get_type(msg) != XPC_TYPE_DICTIONARY) return;
                handle_message(msg, (xpc_connection_t)peer);
            });
            xpc_connection_resume((xpc_connection_t)peer);
        });
        xpc_connection_resume(listener);
        hlog(@"[start] XPC listener active on com.mios.helperd");

        // Watchdog timer: every 30s, check if monitored daemons restarted and re-inject.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                          dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                                  30 * NSEC_PER_SEC, 5 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{ watchdogTick(); });
        dispatch_resume(timer);

        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
