#import "MiOSContainerManager.h"
#import <stdlib.h>

static NSString *const kMiOSBasePath = @"/var/mobile/Library/Preferences/MiOS";
static NSString *const kMiOSContainerPrefsFile = @"com.mios.containerprefs.plist";

@implementation MiOSContainerManager

+ (instancetype)sharedManager {
    static MiOSContainerManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[MiOSContainerManager alloc] init]; });
    return shared;
}

- (NSString *)activeContainerUUIDForBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return nil;
    NSString *prefsPath = [kMiOSBasePath stringByAppendingPathComponent:kMiOSContainerPrefsFile];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    NSDictionary *active = prefs[@"activeContainers"];
    NSString *uuid = active[bundleID];
    if (uuid.length == 0 || [uuid isEqualToString:@"DEFAULT"]) return nil;
    return uuid;
}

// The app's REAL data container (HOME before any redirect). Keeping container data here
// guarantees the sandbox allows reads AND writes, with no dependency on libSandy.
- (NSString *)realHomePath {
    const char *home = getenv("HOME");
    return home ? [NSString stringWithUTF8String:home] : NSHomeDirectory();
}

- (NSString *)homePathForBundleID:(NSString *)bundleID ensureCreated:(BOOL)create {
    NSString *uuid = [self activeContainerUUIDForBundleID:bundleID];
    if (!uuid) return nil;

    NSString *dir = [[[self realHomePath] stringByAppendingPathComponent:@"___MiOS_Containers"]
                     stringByAppendingPathComponent:uuid];
    if (create) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *subdirs = @[@"Documents", @"Library", @"Library/Preferences", @"Library/Caches",
                             @"Library/Application Support", @"Library/Cookies", @"Library/SplashBoard",
                             @"SystemData", @"tmp", @"StoreKit"];
        for (NSString *sub in subdirs) {
            [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:sub]
          withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return dir;
}

// Spoof prefs live centrally (the companion can write them there; the app only reads them).
- (NSDictionary *)spoofPrefsForBundleID:(NSString *)bundleID {
    NSString *uuid = [self activeContainerUUIDForBundleID:bundleID];
    if (!uuid) return @{};
    NSString *path = [[[kMiOSBasePath stringByAppendingPathComponent:@"spoof"]
                       stringByAppendingPathComponent:uuid]
                      stringByAppendingPathExtension:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}

@end
