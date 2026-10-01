#import "MiOSAppInfo.h"

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@property (nonatomic, readonly) NSString *applicationType;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

@implementation MiOSAppInfo

+ (NSArray<MiOSAppInfo *> *)userApps {
    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    NSArray *proxies = [workspace allInstalledApplications];

    NSMutableArray<MiOSAppInfo *> *apps = [NSMutableArray array];
    UIImage *fallbackIcon = [UIImage systemImageNamed:@"app.fill"];

    for (LSApplicationProxy *proxy in proxies) {
        if (![proxy.applicationType isEqualToString:@"User"]) continue;
        if ([proxy.applicationIdentifier hasPrefix:@"com.apple."]) continue;
        if ([proxy.applicationIdentifier isEqualToString:@"com.mios.app"]) continue;

        MiOSAppInfo *info = [[MiOSAppInfo alloc] init];
        info.bundleID = proxy.applicationIdentifier;
        info.name = proxy.localizedName ?: proxy.applicationIdentifier;
        info.dataPath = proxy.dataContainerURL.path ?: @"";

        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:proxy.applicationIdentifier
                                                                  format:2
                                                                   scale:[UIScreen mainScreen].scale];
        info.icon = icon ?: fallbackIcon;
        [apps addObject:info];
    }

    [apps sortUsingComparator:^NSComparisonResult(MiOSAppInfo *a, MiOSAppInfo *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    return [apps copy];
}

+ (NSArray<MiOSAppInfo *> *)allApps {
    LSApplicationWorkspace *workspace = [LSApplicationWorkspace defaultWorkspace];
    NSArray *proxies = [workspace allInstalledApplications];

    NSMutableArray<MiOSAppInfo *> *apps = [NSMutableArray array];
    UIImage *fallbackIcon = [UIImage systemImageNamed:@"app.fill"];

    for (LSApplicationProxy *proxy in proxies) {
        if ([proxy.applicationIdentifier isEqualToString:@"com.mios.app"]) continue;

        MiOSAppInfo *info = [[MiOSAppInfo alloc] init];
        info.bundleID = proxy.applicationIdentifier;
        info.name = proxy.localizedName ?: proxy.applicationIdentifier;
        info.dataPath = proxy.dataContainerURL.path ?: @"";

        UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:proxy.applicationIdentifier
                                                                  format:2
                                                                   scale:[UIScreen mainScreen].scale];
        info.icon = icon ?: fallbackIcon;
        [apps addObject:info];
    }

    [apps sortUsingComparator:^NSComparisonResult(MiOSAppInfo *a, MiOSAppInfo *b) {
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];

    return [apps copy];
}

@end
