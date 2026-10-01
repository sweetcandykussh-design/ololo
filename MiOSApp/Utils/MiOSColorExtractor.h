#import <UIKit/UIKit.h>

@interface MiOSColorExtractor : NSObject
+ (UIColor *)dominantColorFromImage:(UIImage *)image;
+ (UIColor *)vibrantColorFromImage:(UIImage *)image;
+ (UIColor *)accentGradientEndFromColor:(UIColor *)color;
// Dominant hue of the image first, then a clearly different secondary hue if the icon has one.
+ (NSArray<UIColor *> *)paletteFromImage:(UIImage *)image;
@end
