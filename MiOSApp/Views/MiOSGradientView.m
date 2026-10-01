#import "MiOSGradientView.h"

@implementation MiOSGradientView

+ (Class)layerClass {
    return [CAGradientLayer class];
}

- (CAGradientLayer *)gradientLayer {
    return (CAGradientLayer *)self.layer;
}

- (void)setColors:(NSArray<UIColor *> *)colors start:(CGPoint)start end:(CGPoint)end {
    NSMutableArray *cg = [NSMutableArray arrayWithCapacity:colors.count];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    self.gradientLayer.colors = cg;
    self.gradientLayer.startPoint = start;
    self.gradientLayer.endPoint = end;
}

@end
