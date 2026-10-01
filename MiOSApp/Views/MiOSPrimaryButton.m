#import "MiOSPrimaryButton.h"
#import "MiOSGradientView.h"
#import "../UI/MiOSTheme.h"

@implementation MiOSPrimaryButton {
    MiOSGradientView *_fill;
    MiOSGradientView *_sheen;
    UIImageView *_watermark;
    UILabel *_label;
}

- (instancetype)initWithTitle:(NSString *)title watermark:(NSString *)symbolName {
    if (self = [super initWithFrame:CGRectZero]) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _fill = [[MiOSGradientView alloc] init];
        _fill.translatesAutoresizingMaskIntoConstraints = NO;
        _fill.userInteractionEnabled = NO;
        _fill.layer.cornerRadius = 24;
        _fill.layer.cornerCurve = kCACornerCurveContinuous;
        _fill.layer.borderWidth = 1.0;
        _fill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
        _fill.clipsToBounds = YES;
        [self addSubview:_fill];

        _sheen = [[MiOSGradientView alloc] init];
        _sheen.translatesAutoresizingMaskIntoConstraints = NO;
        _sheen.userInteractionEnabled = NO;
        [_sheen setColors:@[[UIColor colorWithWhite:1 alpha:0.22], [UIColor colorWithWhite:1 alpha:0]]
                    start:CGPointMake(0.5, 0) end:CGPointMake(0.5, 0.75)];
        [_fill addSubview:_sheen];

        if (symbolName) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:54 weight:UIImageSymbolWeightBold];
            _watermark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbolName withConfiguration:cfg]];
            _watermark.translatesAutoresizingMaskIntoConstraints = NO;
            _watermark.transform = CGAffineTransformMakeRotation(-0.2);
            [_fill addSubview:_watermark];
            [NSLayoutConstraint activateConstraints:@[
                [_watermark.centerXAnchor constraintEqualToAnchor:_fill.trailingAnchor constant:-34],
                [_watermark.centerYAnchor constraintEqualToAnchor:_fill.centerYAnchor constant:8],
            ]];
        }

        _label = [[UILabel alloc] init];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _label.textAlignment = NSTextAlignmentCenter;
        [_fill addSubview:_label];

        [NSLayoutConstraint activateConstraints:@[
            [self.heightAnchor constraintEqualToConstant:56],
            [_fill.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_fill.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_fill.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_fill.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [_sheen.topAnchor constraintEqualToAnchor:_fill.topAnchor],
            [_sheen.leadingAnchor constraintEqualToAnchor:_fill.leadingAnchor],
            [_sheen.trailingAnchor constraintEqualToAnchor:_fill.trailingAnchor],
            [_sheen.bottomAnchor constraintEqualToAnchor:_fill.bottomAnchor],
            [_label.centerXAnchor constraintEqualToAnchor:_fill.centerXAnchor],
            [_label.centerYAnchor constraintEqualToAnchor:_fill.centerYAnchor],
            [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:_fill.leadingAnchor constant:20],
        ]];

        self.layer.shadowOffset = CGSizeMake(0, 8);
        self.layer.shadowRadius = 16;
        self.layer.shadowOpacity = 0.35;
        self.title = title;
        [self refreshTheme];
    }
    return self;
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    _label.text = title;
}

- (void)refreshTheme {
    UIColor *accent = [MiOSTheme accentColor];
    [_fill setColors:@[accent, [MiOSTheme accentGradientEnd]] start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    UIColor *text = [MiOSTheme textColorOnAccent];
    _label.textColor = text;
    _watermark.tintColor = [text colorWithAlphaComponent:0.14];
    self.layer.shadowColor = accent.CGColor;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.15 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self.transform = highlighted ? CGAffineTransformMakeScale(0.97, 0.97) : CGAffineTransformIdentity;
        self.alpha = highlighted ? 0.9 : 1.0;
    } completion:nil];
}

@end
