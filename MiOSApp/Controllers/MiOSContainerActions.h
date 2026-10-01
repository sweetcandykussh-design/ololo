#import <UIKit/UIKit.h>

@class MiOSContainerConfig;

typedef NS_ENUM(NSInteger, MiOSContainerActionResult) {
    MiOSContainerActionActivated,
    MiOSContainerActionEdited,
    MiOSContainerActionRemoved,
};

// Standard action sheet shown when a container tile is tapped.
@interface MiOSContainerActions : NSObject
+ (void)presentForContainer:(MiOSContainerConfig *)container
                       from:(UIViewController *)presenter
                 sourceView:(UIView *)sourceView
                 completion:(void (^)(MiOSContainerActionResult result))completion;
@end
