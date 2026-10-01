#import <UIKit/UIKit.h>

// Draws the miOS mascot — a pixel-art little devil head — tinted with an accent colour so it can
// echo the active container's palette. Used in the home header and as the basis for the app icon.
@interface MiOSMascotRenderer : NSObject

// Mascot head only (transparent background), horns + glowing eyes tinted from `accent`.
+ (UIImage *)mascotWithSize:(CGSize)size accent:(UIColor *)accent;

// Mascot on a neutral dark rounded-gradient plate — the shape used for the app icon / favicon.
+ (UIImage *)iconMascotWithSize:(CGSize)size;

@end
