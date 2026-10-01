#import "MiOSCloudViewController.h"
#import "../UI/MiOSTheme.h"

@implementation MiOSCloudViewController {
    CAGradientLayer *_bgGradient;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Cloud";
    self.view.backgroundColor = [MiOSTheme primaryBackground];

    _bgGradient = [CAGradientLayer layer];
    _bgGradient.colors = @[
        (id)[UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0].CGColor,
        (id)[MiOSTheme primaryBackground].CGColor,
    ];
    _bgGradient.startPoint = CGPointMake(0.5, 0.0);
    _bgGradient.endPoint = CGPointMake(0.5, 1.0);
    _bgGradient.frame = self.view.bounds;
    [self.view.layer insertSublayer:_bgGradient atIndex:0];

    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [MiOSTheme accentTintedCardBackground];
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = [MiOSTheme accentBorderColor].CGColor;
    card.layer.borderWidth = 1.0;
    [self.view addSubview:card];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightThin];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"icloud.fill" withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [MiOSTheme accentColor];
    [card addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Cloud Sync";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textColor = [MiOSTheme primaryText];
    title.textAlignment = NSTextAlignmentCenter;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Back up and sync your containers\nacross devices. Coming soon.";
    subtitle.font = [UIFont systemFontOfSize:14];
    subtitle.textColor = [MiOSTheme secondaryText];
    subtitle.textAlignment = NSTextAlignmentCenter;
    subtitle.numberOfLines = 0;
    [card addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:32],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-32],
        [card.heightAnchor constraintEqualToConstant:220],

        [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:36],
        [title.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [title.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:16],
        [subtitle.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [subtitle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [subtitle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgGradient.frame = self.view.bounds;
}

@end
