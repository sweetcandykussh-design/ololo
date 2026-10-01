#import <UIKit/UIKit.h>

@interface MiOSHeroBannerView : UIView
@property (nonatomic, assign) BOOL isEnabled;
@property (nonatomic, copy) void (^onToggle)(BOOL enabled);
- (void)setEnabled:(BOOL)enabled animated:(BOOL)animated;
@end
