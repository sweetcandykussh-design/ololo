#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, MiOSDeviceFormFactor) {
    MiOSDeviceFormFactorHomeButton,
    MiOSDeviceFormFactorNotch,
    MiOSDeviceFormFactorDynamicIsland,
};

@interface MiOSDeviceImageRenderer : NSObject
+ (UIImage *)renderDeviceForName:(NSString *)displayName size:(CGSize)size accentColor:(UIColor *)color;
+ (MiOSDeviceFormFactor)formFactorForDeviceName:(NSString *)name;
@end
