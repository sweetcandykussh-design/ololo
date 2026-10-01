#import <UIKit/UIKit.h>

@interface MiOSAppInfo : NSObject
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *dataPath;
@property (nonatomic, strong) UIImage *icon;
+ (NSArray<MiOSAppInfo *> *)userApps;
+ (NSArray<MiOSAppInfo *> *)allApps;
@end
