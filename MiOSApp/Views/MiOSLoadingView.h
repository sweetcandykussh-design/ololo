#import <UIKit/UIKit.h>

@interface MiOSLoadingView : UIView
@property (nonatomic, copy) void (^onComplete)(void);
- (void)startAnimation;
@end
