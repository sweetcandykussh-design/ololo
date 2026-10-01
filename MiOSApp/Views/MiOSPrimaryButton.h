#import <UIKit/UIKit.h>

// Accent-gradient call-to-action with a glossy sheen and an optional faint watermark symbol.
@interface MiOSPrimaryButton : UIControl
@property (nonatomic, copy) NSString *title;
- (instancetype)initWithTitle:(NSString *)title watermark:(NSString *)symbolName;
// Re-reads the theme accent (call after the accent changes).
- (void)refreshTheme;
@end
