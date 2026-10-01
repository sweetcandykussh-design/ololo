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

// System-wide ("active container drives the system identity") spoof for selected SYSTEM apps such as
// Settings (com.apple.Preferences). Returns the active container's spoof dict when system spoof is
// enabled AND this bundle is an allow-listed system target; nil otherwise. This path installs ONLY
// the in-process device/MobileGestalt/sysctl hooks — never the keychain or App-Group redirect, and it
// NEVER rewrites the on-disk MobileGestalt cache (that can bootloop the device).
- (NSDictionary *)activeSystemSpoofForBundleID:(NSString *)bundleID;
@end
