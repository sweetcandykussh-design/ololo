#import <UIKit/UIKit.h>

@class MiOSContainerConfig;

@interface MiOSAppIconProvider : NSObject
+ (UIImage *)iconForBundleID:(NSString *)bundleID;
// Dominant color of the first app's icon, or the theme accent.
+ (UIColor *)accentForBundleIDs:(NSArray<NSString *> *)bundleIDs;
// [primary, secondary]; secondary is derived when the icon has only one strong hue.
+ (NSArray<UIColor *> *)paletteForBundleIDs:(NSArray<NSString *> *)bundleIDs;
// Makes the app-wide accent follow the given apps' first icon (default accent if none).
+ (void)applyThemeForBundleIDs:(NSArray<NSString *> *)bundleIDs;
+ (void)applyThemeForActiveContainer;
@end
