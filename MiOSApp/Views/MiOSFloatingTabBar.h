#import <UIKit/UIKit.h>

// Floating bottom navigation: circular buttons laid out on a shallow arc.
@interface MiOSFloatingTabBar : UIView
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^onSelect)(NSInteger index);
// Height of the bar's content above the home indicator.
@property (class, nonatomic, readonly) CGFloat contentHeight;
- (instancetype)initWithTitles:(NSArray<NSString *> *)titles icons:(NSArray<NSString *> *)icons;
@end
