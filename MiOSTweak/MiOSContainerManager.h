#import <Foundation/Foundation.h>

// Resolves the active container for the current app and the home path to redirect into.
// Containers live centrally so both the companion app and the injected tweak can reach them
// (the libSandy "MiOS-Profile" grants RW to /var/mobile/Library/Preferences/MiOS).
@interface MiOSContainerManager : NSObject
+ (instancetype)sharedManager;

// The active container UUID for a bundle id, or nil when it is the default (no redirect).
- (NSString *)activeContainerUUIDForBundleID:(NSString *)bundleID;

// Absolute path of the container that HOME should point at, or nil for the default container.
// When create is YES the home-directory skeleton (Documents/Library/tmp/...) is created.
- (NSString *)homePathForBundleID:(NSString *)bundleID ensureCreated:(BOOL)create;

// Per-container spoof settings (device model, identifiers, GPS); empty for the default container.
- (NSDictionary *)spoofPrefsForBundleID:(NSString *)bundleID;
@end
