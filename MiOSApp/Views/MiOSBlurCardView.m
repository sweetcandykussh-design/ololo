#import "MiOSBlurCardView.h"
#import "../UI/MiOSTheme.h"

@implementation MiOSBlurCardView {
    CAGradientLayer *_glowLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _cardCornerRadius = [MiOSTheme cardCornerRadius];
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.backgroundColor = [UIColor clearColor];
    self.layer.cornerRadius = _cardCornerRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_blurView];

    _contentView = [[UIView alloc] init];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    _contentView.backgroundColor = [UIColor clearColor];
    [_blurView.contentView addSubview:_contentView];

    [NSLayoutConstraint activateConstraints:@[
        [_blurView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_blurView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_blurView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_blurView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_contentView.topAnchor constraintEqualToAnchor:_blurView.contentView.topAnchor],
        [_contentView.leadingAnchor constraintEqualToAnchor:_blurView.contentView.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:_blurView.contentView.trailingAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:_blurView.contentView.bottomAnchor],
    ]];
}

- (void)setGlowEnabled:(BOOL)enabled {
    if (enabled && !_glowLayer) {
        _glowLayer = [CAGradientLayer layer];
        _glowLayer.colors = @[(id)[MiOSTheme accentColor].CGColor, (id)[MiOSTheme accentGradientEnd].CGColor];
        _glowLayer.startPoint = CGPointMake(0, 0);
        _glowLayer.endPoint = CGPointMake(1, 1);
        _glowLayer.cornerRadius = _cardCornerRadius;
        self.layer.shadowColor = [MiOSTheme accentColor].CGColor;
        self.layer.shadowOffset = CGSizeZero;
        self.layer.shadowRadius = 12;
        self.layer.shadowOpacity = 0.3;
        self.clipsToBounds = NO;
    } else if (!enabled) {
        self.layer.shadowOpacity = 0;
        _glowLayer = nil;
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
        _blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialLight];
    } else {
        _blurView.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
    }
}

@end
