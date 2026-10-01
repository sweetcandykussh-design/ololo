// MiOSSupport — Crane-style system-daemon support dylib for real, redirected per-container storage.
//
// This is the "containers are just folders; redirect where the app looks" model, implemented at the
// system-daemon layer (like Crane) so the default container stays clean and there are no in-app file
// hooks to detect. It is injected into the container/prefs/security daemons (see MiOSSupport.plist).
//
// SAFETY MODEL (this is the whole point — read before editing):
//   * We NEVER call replaceContainer / recreateDefaultStructure / destroyContainer. Those MUTATE the
//     container database and killed launchd (pid 1) → kernel panic on iOS 16.7. We only REDIRECT path
//     resolution, which does not touch that database.
//   * Every hook is fail-safe: if the expected class/selector is absent on this iOS, we install NOTHING
//     and the daemon runs stock. A missing hook means "feature off", never a crash.
//   * Kill-switch: /var/mobile/Library/Preferences/MiOS/disable turns all redirection off (checked per
//     resolution, no reboot needed).
//
// PHASE 1 (this file, now): inject containermanagerd, DISCOVER the real MCM container API on-device
// (logged), and attempt a guarded redirect of the app data container URL. The discovery log tells us
// the exact class/selector to lock in for this iOS build. Phases 2-4 (cfprefsd, securityd, lsd) are
// added the same way once Phase 1's resolution is confirmed from the device log.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kMiOSBase = @"/var/mobile/Library/Preferences/MiOS";

// ---- small logging helper (per-daemon file, deduped) -----------------------------------------------
static void supLog(NSString *tag, NSString *line) {
    @try {
        NSString *dir = [kMiOSBase stringByAppendingPathComponent:@"debug"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                                   attributes:nil error:nil];
        NSString *path = [dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"support_%@.log", tag]];
        NSString *entry = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], line];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) { [entry writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        else { @try { [fh seekToEndOfFile]; [fh writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]]; }
               @catch (__unused id e) {} [fh closeFile]; }
    } @catch (__unused id e) {}
}

static BOOL miosDisabled(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:
            [kMiOSBase stringByAppendingPathComponent:@"disable"]];
}

// Active container UUID for a bundle id, read from the central prefs the app writes. Returns nil for
// the default container (no redirect) or when unknown. containermanagerd is root, so it can read this.
static NSString *miosActiveContainerForBundle(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        [kMiOSBase stringByAppendingPathComponent:@"com.mios.containerprefs.plist"]];
    NSString *uuid = [prefs[@"activeContainers"] objectForKey:bundleID];
    if (![uuid isKindOfClass:[NSString class]] || uuid.length == 0 ||
        [uuid isEqualToString:@"DEFAULT"]) return nil;
    return uuid;
}

// Build the redirected directory for a container and make sure it exists with a stock skeleton. For
// Phase 1 we keep it as a subfolder of the real container (guaranteed inside the app's sandbox grant);
// moving it OUT of the default (so the default is truly empty) is a later refinement once redirect is
// confirmed working, because an external path also needs a sandbox extension.
static NSURL *miosRedirectDir(NSURL *realURL, NSString *uuid) {
    if (!realURL || uuid.length == 0) return nil;
    NSURL *dir = [[realURL URLByAppendingPathComponent:@"___MiOS_Containers" isDirectory:YES]
                  URLByAppendingPathComponent:uuid isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir.path]) {
        for (NSString *sub in @[@"Documents", @"Library", @"Library/Preferences", @"Library/Caches",
                                @"Library/Application Support", @"Library/Cookies", @"tmp", @"StoreKit",
                                @"SystemData"]) {
            [fm createDirectoryAtPath:[dir.path stringByAppendingPathComponent:sub]
          withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return dir;
}

// Read a container object's bundle identifier without compile-time headers (KVC, fail-safe).
static NSString *miosContainerIdentifier(id container) {
    @try {
        for (NSString *key in @[@"identifier", @"bundleIdentifier", @"metadataIdentifier"]) {
            @try {
                id v = [container valueForKey:key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) return v;
            } @catch (__unused id e) {}
        }
    } @catch (__unused id e) {}
    return nil;
}

// ---- containermanagerd: discovery + guarded redirect ----------------------------------------------

// Minimal declaration so Logos can install the hook. If MCMContainer does not exist on this iOS, the
// %init below is a no-op (fail-safe).
@interface MCMContainer : NSObject
- (NSURL *)url;
@end

%group CMD_MCMContainer
%hook MCMContainer

- (NSURL *)url {
    NSURL *orig = %orig;
    @try {
        if (miosDisabled() || !orig) return orig;
        NSString *bundleID = miosContainerIdentifier(self);
        if (!bundleID) return orig;
        NSString *uuid = miosActiveContainerForBundle(bundleID);
        if (!uuid) return orig;                       // default container → untouched
        NSURL *red = miosRedirectDir(orig, uuid);
        if (!red) return orig;
        supLog(@"containermanagerd",
               [NSString stringWithFormat:@"redirect url bid=%@ uuid=%@ %@ -> %@",
                bundleID, uuid, orig.path, red.path]);
        return red;
    } @catch (__unused id e) { return orig; }
}

%end
%end

// Dump the real MCM container API so we can see, from the device, the exact class/selectors to hook on
// this iOS (names differ by version; this is how we lock Phase 1 in without guessing blind).
static void miosDumpMCM(void) {
    @try {
        unsigned int n = 0;
        Class *all = objc_copyClassList(&n);
        for (unsigned int i = 0; i < n; i++) {
            const char *cn = class_getName(all[i]);
            if (!cn) continue;
            if (strncmp(cn, "MCM", 3) != 0) continue;   // MobileContainerManager classes
            NSMutableArray *sels = [NSMutableArray array];
            unsigned int mc = 0;
            Method *ms = class_copyMethodList(all[i], &mc);
            for (unsigned int j = 0; j < mc && sels.count < 40; j++) {
                const char *sn = sel_getName(method_getName(ms[j]));
                if (!sn) continue;
                if (strstr(sn, "url") || strstr(sn, "URL") || strstr(sn, "path") ||
                    strstr(sn, "Path") || strstr(sn, "dentif") || strstr(sn, "ontainer"))
                    [sels addObject:@(sn)];
            }
            if (ms) free(ms);
            if (sels.count)
                supLog(@"containermanagerd",
                       [NSString stringWithFormat:@"class %s : %@", cn, [sels componentsJoinedByString:@", "]]);
        }
        if (all) free(all);
    } @catch (__unused id e) {}
}

static void initContainermanagerd(void) {
    supLog(@"containermanagerd", @"[init] MiOSSupport up in containermanagerd");
    miosDumpMCM();
    if (objc_getClass("MCMContainer")) {
        %init(CMD_MCMContainer);
        supLog(@"containermanagerd", @"[init] MCMContainer url hook installed");
    } else {
        supLog(@"containermanagerd", @"[init] MCMContainer NOT found — no hook (fail-safe)");
    }
}

// ---- entry point -----------------------------------------------------------------------------------
%ctor {
    @autoreleasepool {
        @try {
            char buf[1024]; buf[0] = 0;
            uint32_t sz = sizeof(buf);
            extern int _NSGetExecutablePath(char *, uint32_t *);
            NSString *exe = (_NSGetExecutablePath(buf, &sz) == 0) ? @(buf) : @"";
            NSString *name = exe.lastPathComponent;

            if ([name isEqualToString:@"containermanagerd"]) {
                initContainermanagerd();
            }
            // Phases 2-4 dispatch here once Phase 1 resolution is confirmed from the device log:
            //   else if ([name isEqualToString:@"cfprefsd"])  initCfprefsd();
            //   else if ([name isEqualToString:@"securityd"]) initSecurityd();
            //   else if ([name isEqualToString:@"lsd"])       initLsd();
        } @catch (__unused id e) {}
    }
}
