// mioscli — CLI tool for MiOS daemon injection (DoritosCLI equivalent).
//
// Can operate in two modes:
//   1. Direct injection (task_for_pid) — works standalone, no daemon required
//   2. XPC to mioshelperd (com.mios.helperd) — delegates to the helper daemon
//
// Usage:
//   mioscli inject <dylib_path> <process_name>   — force-inject dylib into process
//   mioscli inject-all                           — stage + inject into all known daemons
//   mioscli stage <source_path>                  — copy dylib to /var/tmp/
//   mioscli status                               — show PIDs of known daemons

#import <Foundation/Foundation.h>
#include "MiOSInject/mios_inject.h"

static void usage(void) {
    fprintf(stderr, "Usage:\n"
        "  mioscli inject <dylib> <process>   inject dylib into process\n"
        "  mioscli inject-all                 stage + inject all known daemons\n"
        "  mioscli stage <source>             copy dylib to /var/tmp/\n"
        "  mioscli status                     show daemon PIDs\n");
}

static int cmd_inject(const char *dylib, const char *proc) {
    pid_t pid = mios_find_pid(proc);
    if (pid == 0) {
        fprintf(stderr, "process '%s' not found\n", proc);
        return 1;
    }
    fprintf(stderr, "injecting %s into %s (pid %d)...\n", dylib, proc, pid);
    kern_return_t kr = mios_inject_pid(pid, dylib);
    if (kr == KERN_SUCCESS) {
        fprintf(stderr, "ok\n");
        return 0;
    }
    fprintf(stderr, "failed: %s (0x%x)\n", mach_error_string(kr), kr);
    return 1;
}

static int cmd_inject_all(void) {
    @autoreleasepool {
        NSString *src = nil;
        for (NSString *p in @[@"/var/jb/Library/MobileSubstrate/DynamicLibraries/MiOSSupport.dylib",
                              @"/Library/MobileSubstrate/DynamicLibraries/MiOSSupport.dylib"]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) { src = p; break; }
        }
        if (!src) {
            fprintf(stderr, "MiOSSupport.dylib not found\n");
            return 1;
        }

        NSString *staged = mios_stage_dylib(src);
        if (!staged) {
            fprintf(stderr, "staging failed\n");
            return 1;
        }
        fprintf(stderr, "staged: %s -> %s\n", src.UTF8String, staged.UTF8String);

        const char *daemons[] = { "securityd", "containermanagerd", "cfprefsd", NULL };
        int failures = 0;
        for (int i = 0; daemons[i]; i++) {
            pid_t pid = mios_find_pid(daemons[i]);
            if (pid == 0) {
                fprintf(stderr, "%s: not running\n", daemons[i]);
                continue;
            }
            kern_return_t kr = mios_inject_pid(pid, staged.UTF8String);
            fprintf(stderr, "%s (pid %d): %s\n", daemons[i], pid,
                    kr == KERN_SUCCESS ? "ok" : mach_error_string(kr));
            if (kr != KERN_SUCCESS) failures++;
        }
        return failures > 0 ? 1 : 0;
    }
}

static int cmd_stage(const char *source) {
    @autoreleasepool {
        NSString *staged = mios_stage_dylib(@(source));
        if (staged) {
            fprintf(stderr, "staged: %s -> %s\n", source, staged.UTF8String);
            return 0;
        }
        fprintf(stderr, "staging failed\n");
        return 1;
    }
}

static int cmd_status(void) {
    const char *names[] = { "securityd", "containermanagerd", "cfprefsd", "lsd",
                            "miosd", "mioshelperd", NULL };
    for (int i = 0; names[i]; i++) {
        pid_t pid = mios_find_pid(names[i]);
        fprintf(stderr, "%-22s  %s\n", names[i], pid ? [[NSString stringWithFormat:@"pid %d", pid] UTF8String] : "not running");
    }

    // Check ctor markers
    fprintf(stderr, "\nctor markers:\n");
    const char *markers[] = { "securityd", "containermanagerd", "cfprefsd", "lsd", NULL };
    for (int i = 0; markers[i]; i++) {
        char path[160];
        snprintf(path, sizeof(path), "/var/tmp/drt-%s-ctor.log", markers[i]);
        FILE *f = fopen(path, "r");
        if (!f) { fprintf(stderr, "  %s: (none)\n", markers[i]); continue; }
        char line[256]; const char *last = NULL;
        while (fgets(line, sizeof(line), f)) last = line;
        if (last) fprintf(stderr, "  %s: %s", markers[i], last);
        else fprintf(stderr, "  %s: (empty)\n", markers[i]);
        fclose(f);
    }
    return 0;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) { usage(); return 1; }
        const char *cmd = argv[1];

        if (strcmp(cmd, "inject") == 0) {
            if (argc < 4) { fprintf(stderr, "inject requires <dylib> <process>\n"); return 1; }
            return cmd_inject(argv[2], argv[3]);
        }
        if (strcmp(cmd, "inject-all") == 0) return cmd_inject_all();
        if (strcmp(cmd, "stage") == 0) {
            if (argc < 3) { fprintf(stderr, "stage requires <source>\n"); return 1; }
            return cmd_stage(argv[2]);
        }
        if (strcmp(cmd, "status") == 0) return cmd_status();

        fprintf(stderr, "unknown command: %s\n", cmd);
        usage();
        return 1;
    }
}
