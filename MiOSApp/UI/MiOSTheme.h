#import <UIKit/UIKit.h>

// Posted whenever the accent palette changes (e.g. a different container becomes active).
extern NSString *const MiOSThemeDidChangeNotification;

@interface MiOSTheme : NSObject

// Sets both accent colors at once and notifies observers.
+ (void)setAccent:(UIColor *)accent gradientEnd:(UIColor *)gradientEnd;
+ (BOOL)isLightColor:(UIColor *)color;
// Readable text color on top of an accent-filled surface.
+ (UIColor *)textColorOnAccent;

// Page and surface styling shared by all redesigned screens.
+ (CAGradientLayer *)pageBackgroundLayer;
+ (UIColor *)tileBackground;
+ (UIColor *)hairline;

+ (UIColor *)primaryBackground;
+ (UIColor *)secondaryBackground;
+ (UIColor *)cardBackground;
+ (UIColor *)glassBackground;
+ (UIColor *)accentColor;
+ (UIColor *)accentGradientEnd;
+ (UIColor *)primaryText;
+ (UIColor *)secondaryText;
+ (UIColor *)tertiaryText;
+ (UIColor *)separator;
+ (UIColor *)destructive;
+ (UIColor *)success;
+ (UIColor *)warning;

+ (UIFont *)titleFont;
+ (UIFont *)headlineFont;
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;
+ (UIFont *)monoFont;

+ (CGFloat)cornerRadius;
+ (CGFloat)cardCornerRadius;
+ (CGFloat)cardPadding;

+ (void)styleNavigationBar:(UINavigationBar *)bar;
+ (CAGradientLayer *)accentGradientForBounds:(CGRect)bounds;
+ (CAGradientLayer *)backgroundGradientForBounds:(CGRect)bounds;

+ (void)setDynamicAccentColor:(UIColor *)color;
+ (void)setDynamicAccentGradientEnd:(UIColor *)color;
+ (void)resetDynamicAccent;
+ (BOOL)hasDynamicAccent;

+ (void)applyGlassEffectToView:(UIView *)view;
+ (void)applyAccentGlassEffectToView:(UIView *)view;
+ (void)applyGlowToView:(UIView *)view color:(UIColor *)color radius:(CGFloat)radius;

+ (UIColor *)accentTintedCardBackground;
+ (UIColor *)accentBorderColor;

@end
