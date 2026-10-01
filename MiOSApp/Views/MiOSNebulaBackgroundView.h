#import <UIKit/UIKit.h>

// Dark cosmic backdrop: layered nebula gradient, neon accent bloom in the top-right (behind the
// mascot) and faint scattered pixel specks — the reference's "space" look. Re-tints to the active
// container's accent.
@interface MiOSNebulaBackgroundView : UIView
- (void)updateAccent:(UIColor *)accent;
@end
