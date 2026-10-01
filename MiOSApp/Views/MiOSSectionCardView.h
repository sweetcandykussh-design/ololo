#import <UIKit/UIKit.h>

@interface MiOSSectionCardView : UIView
@property (nonatomic, copy) NSString *sectionTitle;
@property (nonatomic, strong, readonly) UIStackView *contentStack;
- (instancetype)initWithTitle:(NSString *)title;
- (void)addCellView:(UIView *)cell;
- (void)addSeparator;
@end
