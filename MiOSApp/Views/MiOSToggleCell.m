#import "MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"

// MARK: - MiOSToggleCell

@implementation MiOSToggleCell {
    UIImageView *_iconView;
    UIView *_iconContainer;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UISwitch *_toggle;
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon color:(UIColor *)color key:(NSString *)key {
    if (self = [super initWithFrame:CGRectZero]) {
        _title = title;
        _subtitle = subtitle;
        _iconName = icon;
        _iconColor = color ?: [MiOSTheme accentColor];
        _key = key;
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor clearColor];

    _iconContainer = [[UIView alloc] init];
    _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _iconContainer.backgroundColor = [_iconColor colorWithAlphaComponent:0.18];
    _iconContainer.layer.cornerRadius = 16;
    _iconContainer.layer.shadowColor = _iconColor.CGColor;
    _iconContainer.layer.shadowOffset = CGSizeZero;
    _iconContainer.layer.shadowRadius = 6;
    _iconContainer.layer.shadowOpacity = 0.2;
    [self addSubview:_iconContainer];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_iconName withConfiguration:config]];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = _iconColor;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconContainer addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = _title;
    _titleLabel.font = [MiOSTheme headlineFont];
    _titleLabel.textColor = [MiOSTheme primaryText];
    _titleLabel.numberOfLines = 1;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.75;
    [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.text = _subtitle;
    _subtitleLabel.font = [MiOSTheme captionFont];
    _subtitleLabel.textColor = [MiOSTheme secondaryText];
    _subtitleLabel.numberOfLines = 2;
    _subtitleLabel.hidden = (_subtitle.length == 0);
    [self addSubview:_subtitleLabel];

    _toggle = [[UISwitch alloc] init];
    _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    _toggle.onTintColor = [MiOSTheme accentColor];
    _toggle.on = _isOn;
    [_toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_toggle];

    [NSLayoutConstraint activateConstraints:@[
        [_iconContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_iconContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconContainer.widthAnchor constraintEqualToConstant:32],
        [_iconContainer.heightAnchor constraintEqualToConstant:32],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconContainer.trailingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-8],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_toggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_toggle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:52],
    ]];

    if (_subtitle.length > 0) {
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        ]];
    } else {
        [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    }
}

- (void)setIsOn:(BOOL)isOn {
    _isOn = isOn;
    _toggle.on = isOn;
}

- (void)toggleChanged:(UISwitch *)sender {
    _isOn = sender.on;
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    if (_delegate) {
        [_delegate toggleCell:self didChangeValue:sender.on forKey:_key];
    }
}

@end

// MARK: - MiOSNavigationCell

@implementation MiOSNavigationCell {
    UIImageView *_iconView;
    UIView *_iconContainer;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UIImageView *_chevron;
    UILabel *_badgeLabel;
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon color:(UIColor *)color {
    if (self = [super initWithFrame:CGRectZero]) {
        _title = title;
        _subtitle = subtitle;
        _iconName = icon;
        _iconColor = color ?: [MiOSTheme accentColor];
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;

    _iconContainer = [[UIView alloc] init];
    _iconContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _iconContainer.backgroundColor = [_iconColor colorWithAlphaComponent:0.18];
    _iconContainer.layer.cornerRadius = 16;
    _iconContainer.layer.shadowColor = _iconColor.CGColor;
    _iconContainer.layer.shadowOffset = CGSizeZero;
    _iconContainer.layer.shadowRadius = 6;
    _iconContainer.layer.shadowOpacity = 0.2;
    [self addSubview:_iconContainer];

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    _iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_iconName withConfiguration:config]];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.tintColor = _iconColor;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    [_iconContainer addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = _title;
    _titleLabel.font = [MiOSTheme headlineFont];
    _titleLabel.textColor = [MiOSTheme primaryText];
    _titleLabel.numberOfLines = 1;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.75;
    [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _subtitleLabel.text = _subtitle;
    _subtitleLabel.font = [MiOSTheme captionFont];
    _subtitleLabel.textColor = [MiOSTheme secondaryText];
    _subtitleLabel.numberOfLines = 2;
    _subtitleLabel.hidden = (_subtitle.length == 0);
    [self addSubview:_subtitleLabel];

    UIImageSymbolConfiguration *chevConfig = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
    _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:chevConfig]];
    _chevron.translatesAutoresizingMaskIntoConstraints = NO;
    _chevron.tintColor = [MiOSTheme tertiaryText];
    [self addSubview:_chevron];

    _badgeLabel = [[UILabel alloc] init];
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _badgeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _badgeLabel.textColor = [UIColor whiteColor];
    _badgeLabel.textAlignment = NSTextAlignmentCenter;
    _badgeLabel.backgroundColor = [MiOSTheme accentColor];
    _badgeLabel.layer.cornerRadius = 10;
    _badgeLabel.layer.masksToBounds = YES;
    _badgeLabel.hidden = YES;
    [self addSubview:_badgeLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    [self addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [_iconContainer.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_iconContainer.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconContainer.widthAnchor constraintEqualToConstant:32],
        [_iconContainer.heightAnchor constraintEqualToConstant:32],
        [_iconView.centerXAnchor constraintEqualToAnchor:_iconContainer.centerXAnchor],
        [_iconView.centerYAnchor constraintEqualToAnchor:_iconContainer.centerYAnchor],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconContainer.trailingAnchor constant:10],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_chevron.leadingAnchor constant:-8],
        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
        [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_badgeLabel.trailingAnchor constraintEqualToAnchor:_chevron.leadingAnchor constant:-8],
        [_badgeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_badgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:20],
        [_badgeLabel.heightAnchor constraintEqualToConstant:20],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:52],
    ]];

    if (_subtitle.length > 0) {
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
            [_subtitleLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        ]];
    } else {
        [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;
    }
}

- (void)setBadgeText:(NSString *)badgeText {
    _badgeText = badgeText;
    _badgeLabel.text = badgeText;
    _badgeLabel.hidden = (badgeText.length == 0);
}

- (void)tapped {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    [UIView animateWithDuration:0.1 animations:^{
        self.alpha = 0.5;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.alpha = 1.0;
        }];
    }];

    if (_tapAction) _tapAction();
}

@end

// MARK: - MiOSButtonCell

@implementation MiOSButtonCell {
    UILabel *_titleLabel;
}

- (instancetype)initWithTitle:(NSString *)title color:(UIColor *)color {
    if (self = [super initWithFrame:CGRectZero]) {
        _title = title;
        _buttonColor = color ?: [MiOSTheme accentColor];
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [_buttonColor colorWithAlphaComponent:0.12];
    self.layer.cornerRadius = 12;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = _title;
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _titleLabel.textColor = _buttonColor;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)];
    [self addGestureRecognizer:tap];

    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [self.heightAnchor constraintEqualToConstant:48],
    ]];
}

- (void)tapped {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    [UIView animateWithDuration:0.08 animations:^{
        self.transform = CGAffineTransformMakeScale(0.97, 0.97);
        self.alpha = 0.7;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:0 animations:^{
            self.transform = CGAffineTransformIdentity;
            self.alpha = 1.0;
        } completion:nil];
    }];

    if (_tapAction) _tapAction();
}

@end
