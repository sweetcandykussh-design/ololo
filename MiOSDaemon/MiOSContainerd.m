// miosd — privileged container daemon.
//
// Runs as root. Creates / switches / deletes REAL OS data containers via MobileContainerManager
// (the same engine Crane drives through cranehelperd). The app/tweak never redirects HOME in-process
// (that triggers the data-protection mach-port guard crash); instead this daemon reassigns the app's
// data container at the system level, and the app is relaunched into it.
//
// Trigger: the app writes a request plist and posts a Darwin notification; we execute and post back.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import <spawn.h>
#import <unistd.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>

extern char **environ;

// --- Private MobileContainerManager surface ---
@interface MCMContainer : NSObject
@property (readonly, nonatomic) NSUUID *uuid;
@property (readonly, nonatomic) NSURL *url;
- (instancetype)initWithIdentifier:(NSString *)identifier path:(NSString *)path
                uniquePathComponent:(NSString *)unique uuid:(NSUUID *)uuid
                personaUniqueString:(NSString *)persona error:(NSError **)error;
- (BOOL)recreateDefaultStructureWithError:(NSError **)error;
- (id)destroyContainerWithCompletion:(id)completion;
@end
@interface MCMAppDataContainer : MCMContainer @end
@interface MCMSharedDataContainer : MCMContainer @end   // App Group ("group.*") containers
@interface MCMContainerManager : NSObject
+ (instancetype)defaultManager;
- (BOOL)replaceContainer:(id)a withContainer:(id)b error:(NSError **)error;
@end

static NSString *const kBase = @"/var/mobile/Library/Preferences/MiOS";
static NSString *const kAppDataRoot = @"/var/mobile/Containers/Data/Application";
static NSString *const kSharedRoot  = @"/var/mobile/Containers/Shared/AppGroup";
static NSString *const kRequestNote = @"com.mios.containerd.request";

static Class MCMAppDataClass(void) {
    static Class c; static dispatch_once_t t;
    dispatch_once(&t, ^{
        if (!objc_getClass("MCMAppDataContainer"))
            dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_LAZY);
        c = objc_getClass("MCMAppDataContainer");
    });
    return c;
}

static Class MCMSharedDataClass(void) {
    static Class c; static dispatch_once_t t;
    dispatch_once(&t, ^{
        if (!objc_getClass("MCMSharedDataContainer"))
            dlopen("/System/Library/PrivateFrameworks/MobileContainerManager.framework/MobileContainerManager", RTLD_LAZY);
        c = objc_getClass("MCMSharedDataContainer");
    });
    return c;
}

// --- Enumerate the App Groups an installed app belongs to (from its code-signature entitlements) ---

static NSString *appBundlePathForBundleID(NSString *bid) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = @"/var/containers/Bundle/Application";
    for (NSString *sub in [fm contentsOfDirectoryAtPath:root error:nil] ?: @[]) {
        NSString *dir = [root stringByAppendingPathComponent:sub];
        for (NSString *item in [fm contentsOfDirectoryAtPath:dir error:nil] ?: @[]) {
            if (![item hasSuffix:@".app"]) continue;
            NSString *appPath = [dir stringByAppendingPathComponent:item];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                                  [appPath stringByAppendingPathComponent:@"Info.plist"]];
            if ([info[@"CFBundleIdentifier"] isEqualToString:bid]) return appPath;
        }
    }
    return nil;
}

// Read the entitlements plist out of a Mach-O's embedded code signature, then return the app groups.
// Only small regions are read, so this is cheap even for very large binaries (e.g. Instagram).
#define CSMAGIC_EMBEDDED_SIGNATURE    0xfade0cc0
#define CSMAGIC_EMBEDDED_ENTITLEMENTS 0xfade7171

static NSData *readAt(NSFileHandle *fh, unsigned long long off, unsigned long long len) {
    @try { [fh seekToFileOffset:off]; return [fh readDataOfLength:(NSUInteger)len]; }
    @catch (__unused id e) { return nil; }
}

static NSDictionary *entitlementsForExecutable(NSString *exePath) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:exePath];
    if (!fh) return nil;
    NSDictionary *result = nil;
    @try {
        unsigned long long sliceOff = 0;
        NSData *magicData = readAt(fh, 0, 4);
        if (magicData.length < 4) return nil;
        uint32_t magic = *(const uint32_t *)magicData.bytes;

        if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
            NSData *fh0 = readAt(fh, 0, sizeof(struct fat_header));
            const struct fat_header *fh_ = (const struct fat_header *)fh0.bytes;
            uint32_t nfat = OSSwapBigToHostInt32(fh_->nfat_arch);
            NSData *archs = readAt(fh, sizeof(struct fat_header), nfat * sizeof(struct fat_arch));
            const struct fat_arch *a = (const struct fat_arch *)archs.bytes;
            for (uint32_t i = 0; i < nfat; i++) {
                cpu_type_t ct = OSSwapBigToHostInt32(a[i].cputype);
                if (ct == CPU_TYPE_ARM64) { sliceOff = OSSwapBigToHostInt32(a[i].offset); break; }
            }
            if (sliceOff == 0) sliceOff = OSSwapBigToHostInt32(a[0].offset);
            NSData *m2 = readAt(fh, sliceOff, 4);
            if (m2.length < 4) return nil;
            magic = *(const uint32_t *)m2.bytes;
        }
        if (magic != MH_MAGIC_64 && magic != MH_CIGAM_64) return nil;

        NSData *hdrData = readAt(fh, sliceOff, sizeof(struct mach_header_64));
        const struct mach_header_64 *hdr = (const struct mach_header_64 *)hdrData.bytes;
        uint32_t ncmds = hdr->ncmds, sizeofcmds = hdr->sizeofcmds;
        NSData *cmds = readAt(fh, sliceOff + sizeof(struct mach_header_64), sizeofcmds);
        const uint8_t *p = cmds.bytes;
        const uint8_t *end = p + cmds.length;
        uint32_t csOff = 0, csSize = 0;
        for (uint32_t i = 0; i < ncmds && p + sizeof(struct load_command) <= end; i++) {
            const struct load_command *lc = (const struct load_command *)p;
            if (lc->cmd == LC_CODE_SIGNATURE) {
                const struct linkedit_data_command *ld = (const struct linkedit_data_command *)p;
                csOff = ld->dataoff; csSize = ld->datasize; break;
            }
            if (lc->cmdsize == 0) break;
            p += lc->cmdsize;
        }
        if (!csOff || !csSize) return nil;

        NSData *sig = readAt(fh, sliceOff + csOff, csSize);
        const uint8_t *s = sig.bytes;
        if (sig.length < 12) return nil;
        uint32_t sbMagic = OSSwapBigToHostInt32(*(const uint32_t *)s);
        if (sbMagic != CSMAGIC_EMBEDDED_SIGNATURE) return nil;
        uint32_t count = OSSwapBigToHostInt32(*(const uint32_t *)(s + 8));
        for (uint32_t i = 0; i < count; i++) {
            const uint8_t *idx = s + 12 + i * 8;
            if (idx + 8 > s + sig.length) break;
            uint32_t blobOff = OSSwapBigToHostInt32(*(const uint32_t *)(idx + 4));
            if (blobOff + 8 > sig.length) continue;
            uint32_t bMagic = OSSwapBigToHostInt32(*(const uint32_t *)(s + blobOff));
            if (bMagic == CSMAGIC_EMBEDDED_ENTITLEMENTS) {
                uint32_t bLen = OSSwapBigToHostInt32(*(const uint32_t *)(s + blobOff + 4));
                if (bLen <= 8 || blobOff + bLen > sig.length) break;
                NSData *plist = [NSData dataWithBytes:(s + blobOff + 8) length:(bLen - 8)];
                id obj = [NSPropertyListSerialization propertyListWithData:plist options:0 format:NULL error:NULL];
                if ([obj isKindOfClass:[NSDictionary class]]) result = obj;
                break;
            }
        }
    } @catch (__unused id e) {}
    [fh closeFile];
    return result;
}

static NSArray<NSString *> *appGroupsForBundleID(NSString *bid) {
    NSString *appPath = appBundlePathForBundleID(bid);
    if (!appPath) return @[];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *exe = info[@"CFBundleExecutable"] ?: [appPath.lastPathComponent stringByDeletingPathExtension];
    NSString *exePath = [appPath stringByAppendingPathComponent:exe];
    NSDictionary *ents = entitlementsForExecutable(exePath);
    id g = ents[@"com.apple.security.application-groups"];
    return [g isKindOfClass:[NSArray class]] ? g : @[];
}

// --- Debug log (so we can see what the root daemon actually did) ---
static void dlog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *dir = [kBase stringByAppendingPathComponent:@"debug"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:@"daemon.log"];
    NSString *stamped = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], line];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [stamped writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
    else { @try { [fh seekToEndOfFile]; [fh writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (__unused id e) {} [fh closeFile]; }
    chown(path.UTF8String, 501, 501);
}

static NSString *reqPath(void)  { return [kBase stringByAppendingPathComponent:@"daemon_request.plist"]; }
static NSString *respPath(NSString *token) {
    return [kBase stringByAppendingPathComponent:[NSString stringWithFormat:@"daemon_response_%@.plist", token]];
}

#pragma mark - Mapping (bundleID -> { logicalID -> realUUID })

static NSString *prefsPath(void) { return [kBase stringByAppendingPathComponent:@"com.mios.containerprefs.plist"]; }

static NSString *storedRealUUID(NSString *bid, NSString *lid) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:prefsPath()];
    return p[@"realUUIDs"][bid][lid];
}

static void storeRealUUID(NSString *bid, NSString *lid, NSString *real) {
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:prefsPath()] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *m = [p[@"realUUIDs"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *per = [m[bid] mutableCopy] ?: [NSMutableDictionary dictionary];
    per[lid] = real; m[bid] = per; p[@"realUUIDs"] = m;
    [p writeToFile:prefsPath() atomically:YES];
}

#pragma mark - MCM helpers

// Current assigned container for a bundle id (nil if none / createIfNecessary NO).
static MCMContainer *currentContainer(NSString *bid, BOOL create) {
    Class cls = MCMAppDataClass();
    if (!cls) return nil;
    BOOL existed = NO; NSError *err = nil;
    MCMContainer *(*send)(id, SEL, id, BOOL, BOOL *, NSError **) = (void *)objc_msgSend;
    return send(cls, @selector(containerWithIdentifier:createIfNecessary:existed:error:), bid, create, &existed, &err);
}

// Build a container object for a specific UUID/path (constructing its on-disk structure if new).
static MCMContainer *containerForUUID(NSString *bid, NSString *uuidStr, BOOL createStructure) {
    Class cls = MCMAppDataClass();
    if (!cls) return nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
    NSString *path = [kAppDataRoot stringByAppendingPathComponent:uuidStr];
    NSError *err = nil;
    MCMContainer *c = [[cls alloc] initWithIdentifier:bid path:path uniquePathComponent:uuidStr
                                                 uuid:uuid personaUniqueString:nil error:&err];
    if (c && createStructure) [c recreateDefaultStructureWithError:&err];
    return c;
}

// --- App Group shared-container helpers (mirror the data-container ones) ---

// Group containers are keyed in the prefs under the group id itself (e.g. "group.com.burbn.instagram"),
// which never collides with an app bundle id, so we reuse storeRealUUID/storedRealUUID.
static MCMContainer *currentGroupContainer(NSString *groupID, BOOL create) {
    Class cls = MCMSharedDataClass();
    if (!cls) return nil;
    BOOL existed = NO; NSError *err = nil;
    MCMContainer *(*send)(id, SEL, id, BOOL, BOOL *, NSError **) = (void *)objc_msgSend;
    return send(cls, @selector(containerWithIdentifier:createIfNecessary:existed:error:), groupID, create, &existed, &err);
}

static MCMContainer *groupContainerForUUID(NSString *groupID, NSString *uuidStr, BOOL createStructure) {
    Class cls = MCMSharedDataClass();
    if (!cls) return nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:uuidStr];
    NSString *path = [kSharedRoot stringByAppendingPathComponent:uuidStr];
    NSError *err = nil;
    MCMContainer *c = [[cls alloc] initWithIdentifier:groupID path:path uniquePathComponent:uuidStr
                                                 uuid:uuid personaUniqueString:nil error:&err];
    if (c && createStructure) [c recreateDefaultStructureWithError:&err];
    return c;
}

// Give every App Group the app belongs to its own per-logical-container shared container, so cached
// state that lives in the group container (e.g. Instagram's device header in FBFamilySharedUserDefaults)
// is isolated per container and a fresh container really starts empty.
static void switchGroupContainers(NSString *bid, NSString *lid, MCMContainerManager *mgr) {
    NSArray *groups = appGroupsForBundleID(bid);
    dlog(@"[groups] %@ -> %@ sharedClass=%@", bid, groups, MCMSharedDataClass() ? @"ok" : @"MISSING");
    for (NSString *g in groups) {
        if (![g isKindOfClass:[NSString class]] || g.length == 0) continue;
        NSString *greal = storedRealUUID(g, lid);
        if (!greal) {
            NSString *u = [NSUUID UUID].UUIDString;
            MCMContainer *made = groupContainerForUUID(g, u, YES);
            greal = made.uuid.UUIDString ?: u;
            storeRealUUID(g, lid, greal);
            dlog(@"[groups]   minted %@ = %@ (made=%@)", g, greal, made ? @"ok" : @"nil");
        }
        MCMContainer *cur = currentGroupContainer(g, YES);
        MCMContainer *target = groupContainerForUUID(g, greal, NO);
        if (!cur || !target) { dlog(@"[groups]   %@ cur=%@ target=%@ SKIP", g, cur?cur.uuid.UUIDString:@"nil", target?@"ok":@"nil"); continue; }
        if ([cur.uuid.UUIDString isEqualToString:greal]) { dlog(@"[groups]   %@ already active %@", g, greal); continue; }
        NSError *err = nil;
        BOOL ok = [mgr replaceContainer:cur withContainer:target error:&err];
        dlog(@"[groups]   %@ replace %@ -> %@ ok=%d err=%@", g, cur.uuid.UUIDString, greal, ok, err.localizedDescription);
    }
}

#pragma mark - Operations

// Mint a brand-new empty real container; returns its UUID.
static NSString *opCreate(NSString *bid, NSString *lid) {
    NSString *uuidStr = [NSUUID UUID].UUIDString;
    dlog(@"[create] mint %@ for %@ (MCMAppDataClass=%@)", uuidStr, bid, MCMAppDataClass() ? @"ok" : @"MISSING");
    MCMContainer *c = containerForUUID(bid, uuidStr, YES);
    dlog(@"[create]   containerForUUID -> %@", c ? @"ok" : @"nil");
    if (!c) return nil;
    NSString *real = c.uuid.UUIDString ?: uuidStr;
    storeRealUUID(bid, lid, real);
    return real;
}

// Make a saved container the app's active (assigned) container by replacing the current one, and do
// the same for all of the app's App Group shared containers (full isolation, empty cache per container).
static BOOL opSwitch(NSString *bid, NSString *lid) {
    dlog(@"[switch] start bid=%@ lid=%@", bid, lid);
    NSString *real = storedRealUUID(bid, lid);
    dlog(@"[switch]   storedRealUUID=%@", real ?: @"nil");
    if (!real) real = opCreate(bid, lid);
    if (!real) { dlog(@"[switch]   abort: no real uuid"); return NO; }

    dlog(@"[switch]   defaultManager...");
    MCMContainerManager *mgr = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("MCMContainerManager"), @selector(defaultManager));
    dlog(@"[switch]   mgr=%@", mgr ? @"ok" : @"nil");

    dlog(@"[switch]   currentContainer...");
    MCMContainer *cur = currentContainer(bid, YES);
    dlog(@"[switch]   cur=%@", cur ? cur.uuid.UUIDString : @"nil");
    MCMContainer *target = containerForUUID(bid, real, NO);
    dlog(@"[switch]   target=%@", target ? target.uuid.UUIDString : @"nil");
    if (!cur || !target) { dlog(@"[switch]   abort: cur/target nil"); return NO; }

    BOOL dataOK = YES;
    if (![cur.uuid.UUIDString isEqualToString:real]) {
        NSError *err = nil;
        dlog(@"[switch]   replaceContainer...");
        dataOK = [mgr replaceContainer:cur withContainer:target error:&err];
        dlog(@"[data] %@ replace %@ -> %@ ok=%d err=%@", bid, cur.uuid.UUIDString, real, dataOK, err.localizedDescription);
    } else {
        dlog(@"[data] %@ already active %@", bid, real);
    }

    // Isolate the App Group containers too (best-effort; never fail the switch over these).
    dlog(@"[switch]   switchGroupContainers...");
    switchGroupContainers(bid, lid, mgr);
    dlog(@"[switch]   done ok=%d", dataOK);

    return dataOK;
}

// Write a bootstrap file INSIDE the app's real container. The sandboxed app can always read its
// own HOME, so the tweak picks up its container UUID + spoof settings without needing libSandy or
// access to the central MiOS prefs folder (which the sandbox may deny). This is what makes the
// in-process spoofing actually fire inside container apps.
static void writeBootstrap(NSString *bid, NSString *lid) {
    MCMContainer *cur = currentContainer(bid, NO);
    NSString *cpath = cur.url.path;
    if (cpath.length == 0) return;

    NSString *spoofPath = [[[kBase stringByAppendingPathComponent:@"spoof"]
                            stringByAppendingPathComponent:lid] stringByAppendingPathExtension:@"plist"];
    NSDictionary *spoof = [NSDictionary dictionaryWithContentsOfFile:spoofPath] ?: @{};
    NSDictionary *boot = @{ @"uuid": lid, @"spoof": spoof, @"keychainIsolation": @YES };

    NSString *prefDir = [cpath stringByAppendingPathComponent:@"Library/Preferences"];
    [[NSFileManager defaultManager] createDirectoryAtPath:prefDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *out = [prefDir stringByAppendingPathComponent:@"com.mios.active.plist"];
    [boot writeToFile:out atomically:YES];
    // The daemon is root; make sure the app's user (mobile) owns these so the read always succeeds.
    chown(prefDir.UTF8String, 501, 501);
    chown(out.UTF8String, 501, 501);
}

static BOOL opDelete(NSString *bid, NSString *lid) {
    // Destroy this logical container's App Group shared containers first.
    for (NSString *g in appGroupsForBundleID(bid)) {
        if (![g isKindOfClass:[NSString class]] || g.length == 0) continue;
        NSString *greal = storedRealUUID(g, lid);
        if (!greal) continue;
        MCMContainer *gc = groupContainerForUUID(g, greal, NO);
        if (gc) [gc destroyContainerWithCompletion:nil];
        [[NSFileManager defaultManager] removeItemAtPath:[kSharedRoot stringByAppendingPathComponent:greal] error:nil];
    }

    NSString *real = storedRealUUID(bid, lid);
    if (!real) return YES;
    MCMContainer *c = containerForUUID(bid, real, NO);
    if (c) [c destroyContainerWithCompletion:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[kAppDataRoot stringByAppendingPathComponent:real] error:nil];
    return YES;
}

#pragma mark - Request handling

static void relaunchApp(NSString *bid) {
    // Best-effort: kill the app so it relaunches into the reassigned container.
    const char *killall = "/var/jb/usr/bin/killall";
    if (access(killall, X_OK) != 0) killall = "/usr/bin/killall";
    pid_t pid; const char *args[] = { killall, bid.UTF8String, NULL };
    posix_spawn(&pid, killall, NULL, NULL, (char *const *)args, environ);
}

static void handleRequest(void) {
    @autoreleasepool {
        NSDictionary *req = [NSDictionary dictionaryWithContentsOfFile:reqPath()];
        if (!req) return;
        NSString *token = req[@"token"] ?: @"0";
        NSString *op = req[@"op"];
        NSString *lid = req[@"logicalID"];
        NSArray *apps = [req[@"apps"] isKindOfClass:[NSArray class]] ? req[@"apps"] : @[];
        BOOL relaunch = [req[@"relaunch"] boolValue];

        dlog(@"[req] op=%@ lid=%@ apps=%@", op, lid, apps);
        BOOL ok = (apps.count > 0);
        for (NSString *bid in apps) {
            if (![bid isKindOfClass:[NSString class]]) continue;
            // Catch ObjC exceptions from the private MobileContainerManager API so a bad call logs its
            // reason instead of aborting the daemon (which KeepAlive then restarts — the [req]->[start]
            // loop we were seeing). A hard (non-ObjC) crash still shows in the crash report.
            @try {
                if ([op isEqualToString:@"create"]) {
                    ok = (opCreate(bid, lid) != nil) && ok;
                } else if ([op isEqualToString:@"switch"]) {
                    BOOL s = opSwitch(bid, lid);
                    ok = s && ok;
                    if (s) {
                        writeBootstrap(bid, lid);
                        if (relaunch) relaunchApp(bid);
                    }
                } else if ([op isEqualToString:@"delete"]) {
                    ok = opDelete(bid, lid) && ok;
                }
            } @catch (NSException *e) {
                dlog(@"[EXCEPTION] op=%@ bid=%@ : %@ — %@", op, bid, e.name, e.reason);
                ok = NO;
            }
        }

        NSDictionary *resp = @{ @"ok": @(ok), @"op": op ?: @"" };
        [resp writeToFile:respPath(token) atomically:YES];
        notify_post([NSString stringWithFormat:@"com.mios.containerd.done.%@", token].UTF8String);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        dlog(@"[start] miosd up (build with App Group isolation + logging)");
        int token = 0;
        notify_register_dispatch(kRequestNote.UTF8String, &token, dispatch_get_main_queue(), ^(int t) {
            handleRequest();
        });
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
