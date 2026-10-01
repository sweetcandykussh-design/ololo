#import <UIKit/UIKit.h>

@interface MiOSBlurCardView : UIView
@property (nonatomic, strong, readonly) UIVisualEffectView *blurView;
@property (nonatomic, strong, readonly) UIView *contentView;
@property (nonatomic, assign) CGFloat cardCornerRadius;
- (void)setGlowEnabled:(BOOL)enabled;
@end
