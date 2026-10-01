#import <UIKit/UIKit.h>

@class MiOSContainerConfig;

// Full-screen map for changing one container's spoofed location.
@interface MiOSLocationPickerViewController : UIViewController
@property (nonatomic, strong) MiOSContainerConfig *container;
@property (nonatomic, copy) void (^onSave)(void);
@end
