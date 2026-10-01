#import "MiOSAppIconProvider.h"
#import "MiOSColorExtractor.h"
#import "../Models/MiOSAppInfo.h"
#import "../Models/MiOSContainerConfig.h"
#import "../UI/MiOSTheme.h"

@interface UIImage (MiOSIconPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

static UIColor *MiOSDefaultAccent(void) {
    return [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0];
}

static UIColor *MiOSDefaultAccentEnd(void) {
    return [UIColor colorWithRed:0.45 green:0.30 blue:1.0 alpha:1.0];
}

@implementation MiOSAppIconProvider

+ (NSCache *)iconCache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

+ (NSCache *)paletteCache {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
    return cache;
}

+ (UIImage *)iconForBundleID:(NSString *)bundleID {
    if (bundleID.length == 0) return nil;
    UIImage *img = [[self iconCache] objectForKey:bundleID];
    if (img) return img;

    img = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        for (MiOSAppInfo *app in [MiOSAppInfo allApps]) {
            if ([app.bundleID isEqualToString:bundleID]) {
                img = app.icon;
                break;
            }
        }
    }
    if (img) [[self iconCache] setObject:img forKey:bundleID];
    return img;
}

+ (NSArray<UIColor *> *)paletteForBundleIDs:(NSArray<NSString *> *)bundleIDs {
    NSString *first = bundleIDs.firstObject;
    if (first.length == 0) return @[MiOSDefaultAccent(), MiOSDefaultAccentEnd()];

    NSArray<UIColor *> *cached = [[self paletteCache] objectForKey:first];
    if (cached) return cached;

    NSArray<UIColor *> *palette = [MiOSColorExtractor paletteFromImage:[self iconForBundleID:first]];
    NSArray<UIColor *> *result;
    if (palette.count >= 2) {
        result = @[palette[0], palette[1]];
    } else if (palette.count == 1) {
        result = @[palette[0], [MiOSColorExtractor accentGradientEndFromColor:palette[0]]];
    } else {
        result = @[MiOSDefaultAccent(), MiOSDefaultAccentEnd()];
    }
    [[self paletteCache] setObject:result forKey:first];
    return result;
}

+ (UIColor *)accentForBundleIDs:(NSArray<NSString *> *)bundleIDs {
    return [self paletteForBundleIDs:bundleIDs].firstObject;
}

+ (void)applyThemeForBundleIDs:(NSArray<NSString *> *)bundleIDs {
    NSArray<UIColor *> *palette = [self paletteForBundleIDs:bundleIDs];
    [MiOSTheme setAccent:palette[0] gradientEnd:palette[1]];
}

+ (void)applyThemeForActiveContainer {
    [self applyThemeForBundleIDs:[MiOSContainerConfig activeContainer].apps];
}

@end
