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
#import <Security/Security.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/sysctl.h>
#import <sys/time.h>

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

// ---- ANTI-BRICK SAFETY LAYER (mirrors Crane's own protection) --------------------------------------
// Three independent safeguards so a bad daemon hook can NEVER permanently kill the jailbreak:
//   1. Safe mode: ellekit sets _MSSafeMode=1 when booting with Volume-Up held. We no-op in it, so a
//      Volume-Up boot ALWAYS comes up clean — the guaranteed manual escape hatch.
//   2. Opt-in: daemon injection does NOTHING unless /…/MiOS/enable_daemons exists. Default = off, so
//      simply installing miOS never touches a system daemon.
//   3. Boot watchdog: we "arm" a file (stamped with this boot's id) before hooking; SpringBoard clears
//      it once the GUI is up. If a daemon starts and finds the file armed with a DIFFERENT (previous)
//      boot id, that previous boot never reached SpringBoard → it crashed → we DISABLE for this boot.
//      Result: one failed boot, then the next boot self-heals with no user action.

static BOOL miosSafeMode(void) {
    const char *s = getenv("_MSSafeMode"); if (s && atoi(s) != 0) return YES;
    s = getenv("_SafeMode");               if (s && atoi(s) != 0) return YES;
    return NO;
}

// Per-daemon opt-in: the master "enable_daemons" turns all on; "enable_<name>" turns just one on, so a
// single daemon can be enabled and tested in isolation (e.g. enable_securityd). Tolerant of a trailing
// ".txt" because Filza appends it by default when creating a file.
static BOOL miosFlagExists(NSString *flag) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // Accept the flag in MiOS/ or MiOS/debug/ (people often drop it next to the logs), with or without
    // a trailing .txt (Filza appends it).
    NSArray *dirs = @[kMiOSBase, [kMiOSBase stringByAppendingPathComponent:@"debug"]];
    for (NSString *d in dirs) {
        NSString *base = [d stringByAppendingPathComponent:flag];
        if ([fm fileExistsAtPath:base]) return YES;
        if ([fm fileExistsAtPath:[base stringByAppendingPathExtension:@"txt"]]) return YES;
    }
    return NO;
}
static BOOL miosDaemonEnabled(NSString *shortName) {
    if (miosFlagExists(@"enable_daemons")) return YES;
    return miosFlagExists([@"enable_" stringByAppendingString:shortName]);
}

static long miosBootID(void) {
    struct timeval bt; memset(&bt, 0, sizeof(bt));
    size_t sz = sizeof(bt); int mib[2] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &bt, &sz, NULL, 0) == 0) return (long)bt.tv_sec;
    return 0;
}

// Per-daemon, SELF-CLEARING watchdog. Arm a file before hooking; if the daemon survives a short health
// window, a GCD timer deletes it (hooks are fine). If the daemon instead crashes within that window
// (e.g. a bad hook hangs boot), the file remains, and the NEXT launch of that daemon sees it and stands
// down — auto-heal, no user action and no dependence on SpringBoard. Per-daemon file names avoid
// siblings interfering, and a stale file from an old build (the single "boot_armed") is simply ignored.
static BOOL miosWatchdogArmOrDisable(NSString *name) {
    NSString *armPath = [kMiOSBase stringByAppendingPathComponent:
                         [@"boot_armed_" stringByAppendingString:name]];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:armPath]) {
        supLog(@"watchdog", [NSString stringWithFormat:
            @"%@: previous run armed but did not clear (likely crashed) — DISABLE this run (self-heal)", name]);
        return NO;
    }
    @try {
        [[NSString stringWithFormat:@"%ld", miosBootID()] writeToFile:armPath atomically:YES
                                                    encoding:NSUTF8StringEncoding error:nil];
        [fm setAttributes:@{ NSFilePosixPermissions: @(0666) } ofItemAtPath:armPath error:nil];
    } @catch (__unused id e) {}
    // Survived the health window → healthy → clear the arm so the next launch proceeds normally.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)25 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [[NSFileManager defaultManager] removeItemAtPath:armPath error:nil];
    });
    return YES;
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

// Read a container/identity object's bundle identifier without compile-time headers (KVC, fail-safe).
static NSString *miosContainerIdentifier(id obj) {
    if (!obj) return nil;
    @try {
        for (NSString *key in @[@"bundleIdentifier", @"identifier", @"metadataIdentifier",
                                @"uniqueIdentifier", @"applicationIdentifier"]) {
            @try {
                id v = [obj valueForKey:key];
                if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] &&
                    [(NSString *)v containsString:@"."]) return v;   // looks like a bundle id
            } @catch (__unused id e) {}
        }
    } @catch (__unused id e) {}
    return nil;
}

// Rewrite an MCMContainer's path ivars to the external per-container folder (Crane's mechanism). Done
// via KVC so no compile-time headers are needed; every access is fail-safe.
static void miosRedirectContainerObject(id container, NSString *bundleID) {
    @try {
        if (!container || bundleID.length == 0) return;
        NSString *uuid = miosActiveContainerForBundle(bundleID);
        if (!uuid) return;                               // default container → leave as-is
        NSURL *rootURL = nil;
        for (NSString *k in @[@"url", @"containerURL", @"containerRootURL",
                              @"dataContainerURL", @"containerDataURL"]) {
            @try { id v = [container valueForKey:k];
                   if ([v isKindOfClass:[NSURL class]]) { rootURL = v; break; } } @catch (__unused id e) {}
        }
        if (!rootURL) return;
        NSURL *red = miosRedirectDir(rootURL, bundleID, uuid);
        if (!red) return;
        BOOL any = NO;
        for (NSString *k in @[@"url", @"containerURL", @"containerRootURL",
                              @"dataContainerURL", @"containerDataURL"]) {
            @try { [container setValue:red forKey:k]; any = YES; } @catch (__unused id e) {}
        }
        supLog(@"containermanagerd", [NSString stringWithFormat:@"redirect bid=%@ uuid=%@ set=%d %@ -> %@",
               bundleID, uuid, any, rootURL.path, red.path]);
    } @catch (__unused id e) {}
}

// ---- containermanagerd: discovery + guarded redirect ----------------------------------------------

// Faithful Crane mechanism: hook MCMContainerFactory's createOrLookup methods, let the original create
// the real container, then rewrite its path ivars to our external per-container folder. Two selector
// variants cover iOS 16 and newer; Logos installs only the one(s) the class implements (fail-safe).
@interface MCMContainerFactory : NSObject
@end

%group CMD_MCMContainerFactory
%hook MCMContainerFactory

- (id)createOrLookupContainerWithContainerIdentity:(id)identity createIfNecessary:(BOOL)c
        transient:(BOOL)t useLocking:(BOOL)l withError:(NSError **)e {
    id container = %orig;
    @try {
        if (container && !miosDisabled()) {
            NSString *bid = miosContainerIdentifier(identity) ?: miosContainerIdentifier(container);
            if (bid) miosRedirectContainerObject(container, bid);
        }
    } @catch (__unused id ex) {}
    return container;
}

- (id)createOrLookupContainerWithContainerIdentity:(id)identity createIfNecessary:(BOOL)c
        transient:(BOOL)t useLocking:(BOOL)l updateLinks:(BOOL)u withError:(NSError **)e {
    id container = %orig;
    @try {
        if (container && !miosDisabled()) {
            NSString *bid = miosContainerIdentifier(identity) ?: miosContainerIdentifier(container);
            if (bid) miosRedirectContainerObject(container, bid);
        }
    } @catch (__unused id ex) {}
    return container;
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
    if (objc_getClass("MCMContainerFactory")) {
        %init(CMD_MCMContainerFactory);
        supLog(@"containermanagerd", @"[init] MCMContainerFactory createOrLookup hook installed");
    } else {
        supLog(@"containermanagerd", @"[init] MCMContainerFactory NOT found — no hook (fail-safe)");
    }
}

// ---- generic discovery: dump a class's methods, and classes by name prefix ------------------------
static void miosDumpClassMethods(const char *clsName, NSString *tag) {
    @try {
        Class c = objc_getClass(clsName);
        if (!c) { supLog(tag, [NSString stringWithFormat:@"class %s NOT found", clsName]); return; }
        unsigned int mc = 0; Method *ms = class_copyMethodList(c, &mc);
        NSMutableArray *sels = [NSMutableArray array];
        for (unsigned int j = 0; j < mc && sels.count < 80; j++) {
            const char *sn = sel_getName(method_getName(ms[j]));
            const char *ty = method_getTypeEncoding(ms[j]);   // ABI signature (incl. block layout)
            [sels addObject:[NSString stringWithFormat:@"%s %s", sn, ty ?: ""]];
        }
        if (ms) free(ms);
        supLog(tag, [NSString stringWithFormat:@"class %s methods:\n  %@", clsName,
                     [sels componentsJoinedByString:@"\n  "]]);
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

// ---- Phase 3: securityd — per-container keychain (faithful Crane mechanism) ------------------------
// Resolve the private SecItem server functions via MSGetImageByName/MSFindSymbol (what Crane uses) and
// hook them. In each hook, read the caller's bundle id from client->task (offset 0), look up its active
// container, and REPLACE client->accessGroups (offset 8) with per-container-suffixed groups
// (<group>.m_i_o_s.<uuid>), skipping Apple's shared groups. securityd already validated the client
// before calling these, so the swap is accepted (this is Crane's "unrestrictClientInfo"). Restored
// after the call. Offsets 0/8 are the first two pointer fields of SecurityClient (task, accessGroups)
// per Apple's open source, so they are stable across iOS versions.

// SecTaskRef is private on iOS (not in the public Security umbrella) — declare it ourselves.
typedef struct __SecTask *SecTaskRef;

// SecurityClient field access (first two fields are pointers: SecTaskRef task; CFArrayRef accessGroups;)
#define MIOS_SC_TASK(c)   (*(SecTaskRef *)((char *)(c) + 0))
#define MIOS_SC_AGRPS(c)  (*(CFArrayRef *)((char *)(c) + sizeof(void *)))

typedef bool (*SecItemAddFn)(CFDictionaryRef, void *, CFTypeRef *, CFErrorRef *);
typedef bool (*SecItemCopyMatchingFn)(CFDictionaryRef, void *, CFTypeRef *, CFErrorRef *);
typedef bool (*SecItemUpdateFn)(CFDictionaryRef, CFDictionaryRef, void *, CFErrorRef *);
typedef bool (*SecItemDeleteFn)(CFDictionaryRef, void *, CFErrorRef *);
static SecItemAddFn          origSecItemAdd;
static SecItemCopyMatchingFn origSecItemCopyMatching;
static SecItemUpdateFn       origSecItemUpdate;
static SecItemDeleteFn       origSecItemDelete;

extern CFStringRef SecTaskCopySigningIdentifier(SecTaskRef task, CFErrorRef *error);

static BOOL kcGroupIgnored(id g) {
    static NSArray *ign; static dispatch_once_t o;
    dispatch_once(&o, ^{ ign = @[@"apple", @"com.apple.token", @"com.apple.certificates",
        @"com.apple.identities", @"com.apple.cfnetwork", @"com.apple.ProtectedCloudStorage",
        @"com.apple.passd", @"com.apple.managed.vpn.shared"]; });
    if (![g isKindOfClass:[NSString class]]) return YES;
    if ([(NSString *)g containsString:@".m_i_o_s."]) return YES;   // never double-suffix
    for (NSString *i in ign) if ([(NSString *)g isEqualToString:i]) return YES;
    return NO;
}

// Active container for the SecurityClient's calling task, or nil for default (no isolation).
static NSString *kcContainerForClient(void *client) {
    @try {
        SecTaskRef task = MIOS_SC_TASK(client);
        if (!task) return nil;
        CFStringRef sid = SecTaskCopySigningIdentifier(task, NULL);
        if (!sid) return nil;
        NSString *bid = (__bridge_transfer NSString *)sid;
        return miosActiveContainerForBundle(bid);
    } @catch (__unused id e) { return nil; }
}

static CFArrayRef kcSuffixedGroups(CFArrayRef orig, NSString *uuid) {
    NSArray *a = (__bridge NSArray *)orig;
    if (![a isKindOfClass:[NSArray class]] || a.count == 0) return NULL;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:a.count];
    for (id g in a) {
        if (kcGroupIgnored(g)) [out addObject:g];
        else [out addObject:[NSString stringWithFormat:@"%@.m_i_o_s.%@", g, uuid]];
    }
    return (__bridge_retained CFArrayRef)out;
}

#define MIOS_SEC_WRAP(call) \
    do { \
        if (miosDisabled()) break; \
        NSString *uuid = kcContainerForClient(client); \
        if (!uuid) break; \
        CFArrayRef saved = MIOS_SC_AGRPS(client); \
        CFArrayRef repl = kcSuffixedGroups(saved, uuid); \
        if (repl) { \
            MIOS_SC_AGRPS(client) = repl; \
            bool _r = call; \
            MIOS_SC_AGRPS(client) = saved; CFRelease(repl); \
            return _r; \
        } \
    } while (0)

static bool new_SecItemCopyMatching(CFDictionaryRef q, void *client, CFTypeRef *r, CFErrorRef *e) {
    @try { MIOS_SEC_WRAP(origSecItemCopyMatching(q, client, r, e)); } @catch (__unused id ex) {}
    return origSecItemCopyMatching(q, client, r, e);
}
static bool new_SecItemAdd(CFDictionaryRef a, void *client, CFTypeRef *r, CFErrorRef *e) {
    @try { MIOS_SEC_WRAP(origSecItemAdd(a, client, r, e)); } @catch (__unused id ex) {}
    return origSecItemAdd(a, client, r, e);
}
static bool new_SecItemUpdate(CFDictionaryRef q, CFDictionaryRef a, void *client, CFErrorRef *e) {
    @try { MIOS_SEC_WRAP(origSecItemUpdate(q, a, client, e)); } @catch (__unused id ex) {}
    return origSecItemUpdate(q, a, client, e);
}
static bool new_SecItemDelete(CFDictionaryRef q, void *client, CFErrorRef *e) {
    @try { MIOS_SEC_WRAP(origSecItemDelete(q, client, e)); } @catch (__unused id ex) {}
    return origSecItemDelete(q, client, e);
}

static void initSecurityd(void) {
    supLog(@"securityd", @"[init] MiOSSupport up in securityd");
    MSImageRef img = MSGetImageByName("/usr/libexec/securityd");
    if (!img) { supLog(@"securityd", @"securityd image NOT found — no hook (fail-safe)"); return; }
    void *cm = MSFindSymbol(img, "__SecItemCopyMatching");
    void *ad = MSFindSymbol(img, "__SecItemAdd");
    void *dl = MSFindSymbol(img, "__SecItemDelete");
    void *up = MSFindSymbol(img, "__SecItemUpdate");
    supLog(@"securityd", [NSString stringWithFormat:@"MSFindSymbol cm=%p ad=%p dl=%p up=%p", cm, ad, dl, up]);
    if (cm) MSHookFunction(cm, (void *)new_SecItemCopyMatching, (void **)&origSecItemCopyMatching);
    if (ad) MSHookFunction(ad, (void *)new_SecItemAdd,          (void **)&origSecItemAdd);
    if (dl) MSHookFunction(dl, (void *)new_SecItemDelete,       (void **)&origSecItemDelete);
    if (up) MSHookFunction(up, (void *)new_SecItemUpdate,       (void **)&origSecItemUpdate);
    supLog(@"securityd", @"[init] SecItem hooks installed (per-container access-group isolation)");
}

// ---- Phase 4: lsd (IDFV per container) ------------------------------------------------------------
// The real vendor-id (IDFV) method, found in the Crane binary's selector table. Hook it to return a
// per-container vendor id. This build LOGS the method's ABI type encoding (the reply block's layout)
// and the resolved container, then calls %orig unchanged — so it is safe and tells us the exact reply
// signature to substitute with next (calling a block with the wrong arity would crash lsd).
@interface _LSDDeviceIdentifierClient : NSObject
@end

%group LSD_Client
%hook _LSDDeviceIdentifierClient
- (void)readDeviceVendorIdentifierFromApplicationWithIdentifier:(id)appID reply:(id)reply {
    @try {
        Method m = class_getInstanceMethod([self class], _cmd);
        const char *ty = m ? method_getTypeEncoding(m) : "?";
        NSString *bid = [appID isKindOfClass:[NSString class]] ? (NSString *)appID : [appID description];
        NSString *uuid = [bid isKindOfClass:[NSString class]] ? miosActiveContainerForBundle(bid) : nil;
        supLog(@"lsd", [NSString stringWithFormat:@"readVendorID app=%@ container=%@ reply_type=%s",
               bid, uuid ?: @"(default)", ty ?: "?"]);
    } @catch (__unused id e) {}
    %orig;
}
%end
%end

static void initLsd(void) {
    supLog(@"lsd", @"[init] MiOSSupport up in lsd (discovery + vendor-id selector probe)");
    // Full method lists of the exact classes Crane works with, so lsd can be implemented precisely for
    // this iOS (names/selectors are registered dynamically and not extractable from the Crane binary).
    const char *lsClasses[] = { "_LSDDeviceIdentifierClient", "_LSDeviceIdentifierManager",
                                "_LSDeviceIdentifierCache", "LSApplicationProxy" };
    for (size_t i = 0; i < sizeof(lsClasses) / sizeof(lsClasses[0]); i++) {
        miosDumpClassMethods(lsClasses[i], @"lsd");
    }
    miosDumpClassesByPrefix("LS", @"endor,dentif,evice", @"lsd");
    miosDumpClassesByPrefix("_LS", @"endor,dentif,evice", @"lsd");
    // The device-identifier protocol's methods (what the XPC interface exposes).
    @try {
        Protocol *p = objc_getProtocol("_LSDDeviceIdentifierProtocol");
        if (p) {
            unsigned int mc = 0;
            struct objc_method_description *ms = protocol_copyMethodDescriptionList(p, YES, YES, &mc);
            NSMutableArray *sels = [NSMutableArray array];
            for (unsigned int i = 0; i < mc; i++) [sels addObject:@(sel_getName(ms[i].name))];
            if (ms) free(ms);
            supLog(@"lsd", [NSString stringWithFormat:@"_LSDDeviceIdentifierProtocol methods: %@",
                            [sels componentsJoinedByString:@", "]]);
        } else {
            supLog(@"lsd", @"_LSDDeviceIdentifierProtocol NOT found");
        }
    } @catch (__unused id e) {}

    if (objc_getClass("_LSDDeviceIdentifierClient")) {
        %init(LSD_Client);
        supLog(@"lsd", @"[init] _LSDDeviceIdentifierClient readVendorID probe installed");
    } else {
        supLog(@"lsd", @"_LSDDeviceIdentifierClient NOT found — no hook (fail-safe)");
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
            if (![name isEqualToString:@"containermanagerd"] && ![name isEqualToString:@"cfprefsd"] &&
                ![name isEqualToString:@"securityd"] && ![name isEqualToString:@"lsd"]) return;

            // Unconditional proof-of-injection log — written the moment the dylib loads into the daemon,
            // BEFORE any gate, so we can tell "not injected" from "gated out" and see WHY it stops.
            supLog(name, [NSString stringWithFormat:@"[ctor] loaded in %@ (pid %d)", name, getpid()]);

            // --- anti-brick gates (any one of them → install nothing) ---
            if (miosSafeMode())          { supLog(name, @"[ctor] safe mode → skip"); return; }
            if (!miosDaemonEnabled(name)) {
                // Dump what THIS daemon actually sees, so the flag location/name is unambiguous.
                @try {
                    NSFileManager *fm = [NSFileManager defaultManager];
                    NSArray *a = [fm contentsOfDirectoryAtPath:kMiOSBase error:nil];
                    NSArray *b = [fm contentsOfDirectoryAtPath:
                                  [kMiOSBase stringByAppendingPathComponent:@"debug"] error:nil];
                    supLog(name, [NSString stringWithFormat:
                        @"[ctor] NOT enabled (build=flags-v3). MiOS/ = [%@] ; MiOS/debug/ = [%@] → skip",
                        [a componentsJoinedByString:@", "] ?: @"(nil)",
                        [b componentsJoinedByString:@", "] ?: @"(nil)"]);
                } @catch (__unused id e) { supLog(name, @"[ctor] not enabled → skip"); }
                return;
            }
            if (!miosWatchdogArmOrDisable(name)) { supLog(name, @"[ctor] watchdog: prior run crashed → skip"); return; }

            if ([name isEqualToString:@"containermanagerd"])      initContainermanagerd();
            else if ([name isEqualToString:@"cfprefsd"])          initCfprefsd();
            else if ([name isEqualToString:@"securityd"])         initSecurityd();
            else if ([name isEqualToString:@"lsd"])               initLsd();
        } @catch (__unused id e) {}
    }
}
