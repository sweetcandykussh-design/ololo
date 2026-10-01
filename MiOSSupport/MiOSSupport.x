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
#import <dlfcn.h>

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

// External container storage root. Keeping containers OUTSIDE the default container is what makes the
// default stay truly empty (no bloat, clean deletion). The app reaches this path because MiOSTweak
// applies the libSandy "MiOS-Profile", which grants it a read-write sandbox extension for this root
// (see layout/Library/libSandy/MiOS-Profile.plist). containermanagerd is root, so it can create here.
static NSString *const kMiOSContainersRoot = @"/var/mobile/MiOSContainers";

// Build the redirected, EXTERNAL container directory, create a stock skeleton, copy the container's MCM
// metadata so it looks like a real container, and set mobile (501) ownership. Returns the external URL.
static NSURL *miosRedirectDir(NSURL *realURL, NSString *bundleID, NSString *uuid) {
    if (bundleID.length == 0 || uuid.length == 0) return nil;
    NSString *dirPath = [[kMiOSContainersRoot stringByAppendingPathComponent:bundleID]
                         stringByAppendingPathComponent:uuid];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *own = @{ NSFileOwnerAccountID: @501, NSFileGroupOwnerAccountID: @501 };
    if (![fm fileExistsAtPath:dirPath]) {
        for (NSString *sub in @[@"Documents", @"Library", @"Library/Preferences", @"Library/Caches",
                                @"Library/Application Support", @"Library/Cookies", @"tmp", @"StoreKit",
                                @"SystemData"]) {
            [fm createDirectoryAtPath:[dirPath stringByAppendingPathComponent:sub]
          withIntermediateDirectories:YES attributes:own error:nil];
        }
        // Make it look like a genuine container: copy the real container's MCM metadata plist in, so
        // anything that reads container metadata at this path sees a valid, matching record.
        @try {
            NSString *metaName = @".com.apple.mobile_container_manager.metadata.plist";
            NSString *srcMeta = [realURL.path stringByAppendingPathComponent:metaName];
            NSString *dstMeta = [dirPath stringByAppendingPathComponent:metaName];
            if (realURL && [fm fileExistsAtPath:srcMeta] && ![fm fileExistsAtPath:dstMeta])
                [fm copyItemAtPath:srcMeta toPath:dstMeta error:nil];
        } @catch (__unused id e) {}
        // Ownership on the whole tree (root-created dirs must be owned by mobile for the app to use).
        [fm setAttributes:own ofItemAtPath:kMiOSContainersRoot error:nil];
        [fm setAttributes:own ofItemAtPath:[kMiOSContainersRoot stringByAppendingPathComponent:bundleID] error:nil];
        [fm setAttributes:own ofItemAtPath:dirPath error:nil];
    }
    return [NSURL fileURLWithPath:dirPath isDirectory:YES];
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
        NSURL *red = miosRedirectDir(orig, bundleID, uuid);
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

// ---- generic discovery: dump a class's methods, and classes by name prefix ------------------------
static void miosDumpClassMethods(const char *clsName, NSString *tag) {
    @try {
        Class c = objc_getClass(clsName);
        if (!c) { supLog(tag, [NSString stringWithFormat:@"class %s NOT found", clsName]); return; }
        unsigned int mc = 0; Method *ms = class_copyMethodList(c, &mc);
        NSMutableArray *sels = [NSMutableArray array];
        for (unsigned int j = 0; j < mc && sels.count < 80; j++)
            [sels addObject:@(sel_getName(method_getName(ms[j])))];
        if (ms) free(ms);
        supLog(tag, [NSString stringWithFormat:@"class %s methods: %@", clsName,
                     [sels componentsJoinedByString:@", "]]);
    } @catch (__unused id e) {}
}

static void miosDumpClassesByPrefix(const char *prefix, NSString *keywords, NSString *tag) {
    @try {
        NSArray *kw = [keywords componentsSeparatedByString:@","];
        unsigned int n = 0; Class *all = objc_copyClassList(&n);
        size_t plen = strlen(prefix);
        for (unsigned int i = 0; i < n; i++) {
            const char *cn = class_getName(all[i]);
            if (!cn || strncmp(cn, prefix, plen) != 0) continue;
            unsigned int mc = 0; Method *ms = class_copyMethodList(all[i], &mc);
            NSMutableArray *sels = [NSMutableArray array];
            for (unsigned int j = 0; j < mc && sels.count < 40; j++) {
                const char *sn = sel_getName(method_getName(ms[j]));
                for (NSString *k in kw) { if (k.length && strstr(sn, k.UTF8String)) { [sels addObject:@(sn)]; break; } }
            }
            if (ms) free(ms);
            if (sels.count) supLog(tag, [NSString stringWithFormat:@"class %s : %@", cn,
                                          [sels componentsJoinedByString:@", "]]);
        }
        if (all) free(all);
    } @catch (__unused id e) {}
}

// ---- Phase 2: cfprefsd ----------------------------------------------------------------------------
// With the container already redirected (Phase 1), each container's preference plists live inside its
// own container, so cfprefsd reads the right files after a relaunch. The remaining job is cache
// coherence / the withSourceForDomain path. This iteration DISCOVERS the real CFPrefsDaemon API so we
// can lock the redirect/flush hook next. No behavioral hook yet → safe.
static void initCfprefsd(void) {
    supLog(@"cfprefsd", @"[init] MiOSSupport up in cfprefsd (discovery only)");
    miosDumpClassMethods("CFPrefsDaemon", @"cfprefsd");
    miosDumpClassesByPrefix("CFPrefs", @"ource,omain,ontainer,ath,lush", @"cfprefsd");
}

// ---- Phase 3: securityd ---------------------------------------------------------------------------
// The keychain access-group rewrite is the airtight-but-dangerous part (it can break keychain). It is
// GATED behind an explicit opt-in file so this combined build is safe to install: securityd only logs
// until you create /var/mobile/Library/Preferences/MiOS/enable_securityd. The SecItem server functions
// are C (not ObjC), so they need libundirect to resolve on this iOS — we check/log its availability
// here and wire the actual rewrite once confirmed.
static void initSecurityd(void) {
    supLog(@"securityd", @"[init] MiOSSupport up in securityd (discovery only)");
    BOOL optIn = [[NSFileManager defaultManager] fileExistsAtPath:
                  [kMiOSBase stringByAppendingPathComponent:@"enable_securityd"]];
    void *lu = dlopen("/var/jb/usr/lib/libundirect.dylib", RTLD_NOW);
    if (!lu) lu = dlopen("/usr/lib/libundirect.dylib", RTLD_NOW);
    void *find = lu ? dlsym(lu, "libundirect_find") : NULL;
    supLog(@"securityd", [NSString stringWithFormat:@"libundirect=%@ libundirect_find=%@ optIn=%d",
           lu ? @"yes" : @"no", find ? @"yes" : @"no", optIn]);
    // No SecItem hook installed in this build (needs confirmed libundirect API + opt-in) → safe.
}

// ---- Phase 4: lsd (IDFV per container) ------------------------------------------------------------
static void initLsd(void) {
    supLog(@"lsd", @"[init] MiOSSupport up in lsd (discovery only)");
    miosDumpClassesByPrefix("LS", @"endor,dentif", @"lsd");
    miosDumpClassesByPrefix("_LS", @"endor,dentif", @"lsd");
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

            if ([name isEqualToString:@"containermanagerd"])      initContainermanagerd();
            else if ([name isEqualToString:@"cfprefsd"])          initCfprefsd();
            else if ([name isEqualToString:@"securityd"])         initSecurityd();
            else if ([name isEqualToString:@"lsd"])               initLsd();
        } @catch (__unused id e) {}
    }
}
