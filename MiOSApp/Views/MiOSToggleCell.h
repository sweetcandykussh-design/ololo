#import <UIKit/UIKit.h>

@protocol MiOSToggleCellDelegate <NSObject>
- (void)toggleCell:(id)cell didChangeValue:(BOOL)value forKey:(NSString *)key;
@end

@interface MiOSToggleCell : UIView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *iconColor;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, weak) id<MiOSToggleCellDelegate> delegate;
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon color:(UIColor *)color key:(NSString *)key;
@end

@interface MiOSNavigationCell : UIView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *iconColor;
@property (nonatomic, copy) NSString *badgeText;
@property (nonatomic, copy) void (^tapAction)(void);
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon color:(UIColor *)color;
@end

@interface MiOSButtonCell : UIView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIColor *buttonColor;
@property (nonatomic, copy) void (^tapAction)(void);
- (instancetype)initWithTitle:(NSString *)title color:(UIColor *)color;
@end
