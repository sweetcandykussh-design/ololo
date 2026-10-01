#import "MiOSHeroBannerView.h"
#import "../UI/MiOSTheme.h"

@implementation MiOSHeroBannerView {
    UIView *_gradientContainer;
    CAGradientLayer *_gradient;
    UILabel *_logoLabel;
    UILabel *_versionLabel;
    UILabel *_statusLabel;
    UIView *_statusDot;
    UISwitch *_masterToggle;
    UIView *_pixelGrid;
    UIView *_glowView;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.layer.cornerRadius = [MiOSTheme cardCornerRadius];
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    _gradientContainer = [[UIView alloc] init];
    _gradientContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_gradientContainer];

    [self buildPixelDecoration];

    UIView *overlay = [[UIView alloc] init];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];
    [self addSubview:overlay];

    _logoLabel = [[UILabel alloc] init];
    _logoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _logoLabel.text = @"miOS";
    _logoLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBlack];
    _logoLabel.textColor = [UIColor whiteColor];
    [self addSubview:_logoLabel];

    _versionLabel = [[UILabel alloc] init];
    _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _versionLabel.text = @"v1.0.0";
    _versionLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightMedium];
    _versionLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self addSubview:_versionLabel];

    _statusDot = [[UIView alloc] init];
    _statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    _statusDot.backgroundColor = [UIColor systemGreenColor];
    _statusDot.layer.cornerRadius = 4;
    [self addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.text = @"Active";
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _statusLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    [self addSubview:_statusLabel];

    _masterToggle = [[UISwitch alloc] init];
    _masterToggle.translatesAutoresizingMaskIntoConstraints = NO;
    _masterToggle.onTintColor = [UIColor colorWithWhite:1 alpha:0.3];
    _masterToggle.thumbTintColor = [UIColor whiteColor];
    [_masterToggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_masterToggle];

    // Subtle glow behind the banner
    self.layer.shadowColor = [MiOSTheme accentColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 6);
    self.layer.shadowRadius = 20;
    self.layer.shadowOpacity = 0.2;

    [NSLayoutConstraint activateConstraints:@[
        [_gradientContainer.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_gradientContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_gradientContainer.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_gradientContainer.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [overlay.topAnchor constraintEqualToAnchor:self.topAnchor],
        [overlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_logoLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:24],
        [_logoLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_versionLabel.leadingAnchor constraintEqualToAnchor:_logoLabel.trailingAnchor constant:8],
        [_versionLabel.bottomAnchor constraintEqualToAnchor:_logoLabel.bottomAnchor constant:-4],
        [_statusDot.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_statusDot.widthAnchor constraintEqualToConstant:8],
        [_statusDot.heightAnchor constraintEqualToConstant:8],
        [_statusDot.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_statusDot.trailingAnchor constant:6],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-20],
        [_masterToggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [_masterToggle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
        [self.heightAnchor constraintEqualToConstant:140],
    ]];
}

- (void)buildPixelDecoration {
    _pixelGrid = [[UIView alloc] init];
    _pixelGrid.translatesAutoresizingMaskIntoConstraints = NO;
    _pixelGrid.alpha = 0.10;
    [self addSubview:_pixelGrid];

    [NSLayoutConstraint activateConstraints:@[
        [_pixelGrid.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_pixelGrid.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_pixelGrid.widthAnchor constraintEqualToConstant:120],
        [_pixelGrid.heightAnchor constraintEqualToConstant:120],
    ]];

    CGFloat size = 8;
    NSArray *pixels = @[
        @[@2, @1], @[@3, @1], @[@4, @1], @[@5, @1],
        @[@1, @2], @[@2, @2], @[@5, @2], @[@6, @2],
        @[@1, @3], @[@2, @3], @[@3, @3], @[@4, @3], @[@5, @3], @[@6, @3],
        @[@2, @4], @[@3, @4], @[@4, @4], @[@5, @4],
        @[@1, @5], @[@2, @5], @[@5, @5], @[@6, @5],
        @[@3, @6], @[@4, @6],
        @[@2, @7], @[@3, @7], @[@4, @7], @[@5, @7],
        @[@1, @8], @[@6, @8],
    ];

    for (NSArray *p in pixels) {
        UIView *px = [[UIView alloc] initWithFrame:CGRectMake([p[0] floatValue] * (size + 2) + 20,
                                                              [p[1] floatValue] * (size + 2) + 10,
                                                              size, size)];
        px.backgroundColor = [UIColor whiteColor];
        px.layer.cornerRadius = 2;
        [_pixelGrid addSubview:px];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _gradient.frame = _gradientContainer.bounds;
    if (!_gradient) {
        _gradient = [CAGradientLayer layer];
        _gradient.frame = _gradientContainer.bounds;
        UIColor *accent = [MiOSTheme accentColor];
        UIColor *accentEnd = [MiOSTheme accentGradientEnd];
        CGFloat r1, g1, b1, a1;
        [accent getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
        CGFloat r2, g2, b2, a2;
        [accentEnd getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
        UIColor *mid = [UIColor colorWithRed:(r1+r2)*0.5 green:(g1+g2)*0.5 blue:(b1+b2)*0.5 alpha:1.0];
        _gradient.colors = @[
            (id)accent.CGColor,
            (id)mid.CGColor,
            (id)accentEnd.CGColor,
        ];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [_gradientContainer.layer insertSublayer:_gradient atIndex:0];
    }
}

- (void)setEnabled:(BOOL)enabled animated:(BOOL)animated {
    _isEnabled = enabled;
    _masterToggle.on = enabled;
    void (^updates)(void) = ^{
        self->_statusLabel.text = enabled ? @"Active" : @"Disabled";
        self->_statusDot.backgroundColor = enabled ? [UIColor systemGreenColor] : [UIColor systemRedColor];
        self->_gradientContainer.alpha = enabled ? 1.0 : 0.4;
    };
    if (animated) {
        [UIView animateWithDuration:0.3 animations:updates];
    } else {
        updates();
    }
}

- (void)toggleChanged:(UISwitch *)sender {
    [self setEnabled:sender.on animated:YES];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    if (_onToggle) _onToggle(sender.on);
}

@end
