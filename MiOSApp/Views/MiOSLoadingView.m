#import "MiOSLoadingView.h"

@interface MiOSLoadingView ()
@property (nonatomic, strong) UILabel *logoLabel;
@property (nonatomic, strong) UILabel *taglineLabel;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) CAGradientLayer *progressGradient;
@property (nonatomic, strong) CAGradientLayer *bgGradient;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *orbitDots;
@property (nonatomic, strong) UIView *glowView;
@end

@implementation MiOSLoadingView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0];

    _glowView = [[UIView alloc] init];
    _glowView.translatesAutoresizingMaskIntoConstraints = NO;
    _glowView.backgroundColor = [UIColor clearColor];
    _glowView.alpha = 0;
    [self addSubview:_glowView];

    _logoLabel = [[UILabel alloc] init];
    _logoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _logoLabel.text = @"miOS";
    _logoLabel.font = [UIFont systemFontOfSize:52 weight:UIFontWeightBlack];
    _logoLabel.textColor = [UIColor whiteColor];
    _logoLabel.textAlignment = NSTextAlignmentCenter;
    _logoLabel.alpha = 0;
    _logoLabel.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [self addSubview:_logoLabel];

    _taglineLabel = [[UILabel alloc] init];
    _taglineLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _taglineLabel.text = @"Containerized Privacy";
    _taglineLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _taglineLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.35];
    _taglineLabel.textAlignment = NSTextAlignmentCenter;
    _taglineLabel.alpha = 0;
    [self addSubview:_taglineLabel];

    _progressTrack = [[UIView alloc] init];
    _progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    _progressTrack.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    _progressTrack.layer.cornerRadius = 2;
    _progressTrack.clipsToBounds = YES;
    _progressTrack.alpha = 0;
    [self addSubview:_progressTrack];

    _progressFill = [[UIView alloc] init];
    _progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    _progressFill.layer.cornerRadius = 2;
    _progressFill.clipsToBounds = YES;
    [_progressTrack addSubview:_progressFill];

    [NSLayoutConstraint activateConstraints:@[
        [_glowView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_glowView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
        [_glowView.widthAnchor constraintEqualToConstant:200],
        [_glowView.heightAnchor constraintEqualToConstant:200],

        [_logoLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_logoLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],

        [_taglineLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_taglineLabel.topAnchor constraintEqualToAnchor:_logoLabel.bottomAnchor constant:8],

        [_progressTrack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_progressTrack.topAnchor constraintEqualToAnchor:_taglineLabel.bottomAnchor constant:32],
        [_progressTrack.widthAnchor constraintEqualToConstant:160],
        [_progressTrack.heightAnchor constraintEqualToConstant:4],

        [_progressFill.leadingAnchor constraintEqualToAnchor:_progressTrack.leadingAnchor],
        [_progressFill.topAnchor constraintEqualToAnchor:_progressTrack.topAnchor],
        [_progressFill.bottomAnchor constraintEqualToAnchor:_progressTrack.bottomAnchor],
        [_progressFill.widthAnchor constraintEqualToConstant:0],
    ]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_bgGradient) {
        _bgGradient = [CAGradientLayer layer];
        _bgGradient.frame = self.bounds;
        _bgGradient.colors = @[
            (id)[UIColor colorWithRed:0.04 green:0.04 blue:0.08 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.04 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.03 green:0.02 blue:0.06 alpha:1.0].CGColor,
        ];
        _bgGradient.locations = @[@0.0, @0.5, @1.0];
        [self.layer insertSublayer:_bgGradient atIndex:0];
    }
    if (_progressGradient) {
        _progressGradient.frame = _progressFill.bounds;
    }
}

- (void)setupProgressGradient {
    _progressGradient = [CAGradientLayer layer];
    _progressGradient.colors = @[
        (id)[UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.45 green:0.30 blue:1.0 alpha:1.0].CGColor,
    ];
    _progressGradient.startPoint = CGPointMake(0, 0.5);
    _progressGradient.endPoint = CGPointMake(1, 0.5);
    _progressGradient.frame = CGRectMake(0, 0, 160, 4);
    [_progressFill.layer addSublayer:_progressGradient];
}

- (void)setupGlow {
    _glowView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0].CGColor;
    _glowView.layer.shadowOffset = CGSizeZero;
    _glowView.layer.shadowRadius = 60;
    _glowView.layer.shadowOpacity = 0.6;

    _glowView.backgroundColor = [[UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0] colorWithAlphaComponent:0.08];
    _glowView.layer.cornerRadius = 100;
}

- (void)setupOrbitDots {
    NSMutableArray *dots = [NSMutableArray array];
    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds) - 30);
    CGFloat radius = 70;

    for (NSInteger i = 0; i < 3; i++) {
        CAShapeLayer *dot = [CAShapeLayer layer];
        CGFloat dotSize = 4 - i;
        dot.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-dotSize/2, -dotSize/2, dotSize, dotSize)].CGPath;

        CGFloat hue = 0.52 + i * 0.08;
        dot.fillColor = [UIColor colorWithHue:hue saturation:0.8 brightness:0.95 alpha:0.7 - i * 0.15].CGColor;
        dot.position = CGPointMake(center.x + radius, center.y);
        [self.layer addSublayer:dot];

        CAKeyframeAnimation *orbit = [CAKeyframeAnimation animationWithKeyPath:@"position"];
        CGMutablePathRef orbitPath = CGPathCreateMutable();
        CGPathAddEllipseInRect(orbitPath, NULL, CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2));
        orbit.path = orbitPath;
        orbit.duration = 2.5 + i * 0.5;
        orbit.repeatCount = HUGE_VALF;
        orbit.calculationMode = kCAAnimationPaced;
        orbit.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        orbit.timeOffset = i * 0.8;
        [dot addAnimation:orbit forKey:@"orbit"];
        CGPathRelease(orbitPath);

        [dots addObject:dot];
    }
    _orbitDots = dots;
}

- (void)startAnimation {
    [self layoutIfNeeded];
    [self setupGlow];
    [self setupOrbitDots];
    [self setupProgressGradient];

    [UIView animateWithDuration:0.6 delay:0.1 usingSpringWithDamping:0.7 initialSpringVelocity:0.5
                        options:0 animations:^{
        self.glowView.alpha = 1.0;
        self.logoLabel.alpha = 1.0;
        self.logoLabel.transform = CGAffineTransformIdentity;
    } completion:nil];

    [UIView animateWithDuration:0.4 delay:0.4 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.taglineLabel.alpha = 1.0;
        self.progressTrack.alpha = 1.0;
    } completion:nil];

    NSLayoutConstraint *widthConstraint = nil;
    for (NSLayoutConstraint *c in _progressFill.constraints) {
        if (c.firstAttribute == NSLayoutAttributeWidth && c.firstItem == _progressFill) {
            widthConstraint = c;
            break;
        }
    }

    if (widthConstraint) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            widthConstraint.constant = 160;
            [UIView animateWithDuration:1.3
                                  delay:0
                                options:UIViewAnimationOptionCurveEaseInOut
                             animations:^{
                [self layoutIfNeeded];
                self.progressGradient.frame = CGRectMake(0, 0, 160, 4);
            }
                             completion:^(BOOL finished) {
                [UIView animateWithDuration:0.5
                                      delay:0.1
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                    self.alpha = 0;
                    self.transform = CGAffineTransformMakeScale(1.05, 1.05);
                }
                                 completion:^(BOOL finished) {
                    for (CAShapeLayer *dot in self.orbitDots) {
                        [dot removeAllAnimations];
                        [dot removeFromSuperlayer];
                    }
                    if (self.onComplete) {
                        self.onComplete();
                    }
                }];
            }];
        });
    }
}

@end
