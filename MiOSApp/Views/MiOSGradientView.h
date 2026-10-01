#import <UIKit/UIKit.h>

// A view whose backing layer is a CAGradientLayer, so the gradient always tracks the view's bounds.
@interface MiOSGradientView : UIView
@property (nonatomic, readonly) CAGradientLayer *gradientLayer;
- (void)setColors:(NSArray<UIColor *> *)colors start:(CGPoint)start end:(CGPoint)end;
@end
