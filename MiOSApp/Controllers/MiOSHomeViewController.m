#import "MiOSHomeViewController.h"
#import "MiOSContainerCreateViewController.h"
#import "MiOSContainerActions.h"
#import "MiOSLocationPickerViewController.h"
#import "../Models/MiOSContainerConfig.h"
#import "../UI/MiOSTheme.h"
#import "../Utils/MiOSDeviceImageRenderer.h"
#import "../Utils/MiOSAppIconProvider.h"
#import "../Utils/MiOSMascotRenderer.h"
#import "../Views/MiOSGradientView.h"
#import "../Views/MiOSContainerGridView.h"

static NSString *const kMiOSCorePrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.core.plist";

static UIColor *MiOSShiftedHue(UIColor *color, CGFloat shift, CGFloat saturation, CGFloat brightness) {
    CGFloat h, s, b, a;
    if (![color getHue:&h saturation:&s brightness:&b alpha:&a]) return color;
    h = fmod(h + shift, 1.0);
    return [UIColor colorWithHue:h saturation:saturation brightness:brightness alpha:1.0];
}

// A contrasting partner for the accent, like the reference's orange/blue pairing:
// warm accents get a cool indigo tile, cool accents get a warm orange one.
static UIColor *MiOSPartnerHue(UIColor *accent) {
    CGFloat h, s, b, a;
    if (![accent getHue:&h saturation:&s brightness:&b alpha:&a]) return accent;
    BOOL warm = (h < 0.2 || h > 0.85);
    return [UIColor colorWithHue:(warm ? 0.64 : 0.06) saturation:0.60 brightness:0.80 alpha:1.0];
}

@interface MiOSHomeViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) NSMutableDictionary *corePrefs;
@property (nonatomic, strong) NSArray<MiOSContainerConfig *> *containers;
@property (nonatomic, copy) NSString *activeContainerID;
@property (nonatomic, strong) CAGradientLayer *bgGradientLayer;
@property (nonatomic, strong) MiOSContainerGridView *grid;
@end

@implementation MiOSHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Home";
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self loadPreferences];
    [self setupUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self loadPreferences];
    [self reloadContainers];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgGradientLayer.frame = self.view.bounds;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Data

- (void)loadPreferences {
    _corePrefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kMiOSCorePrefsPath] mutableCopy];
    if (!_corePrefs) _corePrefs = [@{@"enabled": @YES} mutableCopy];
}

- (void)savePreferences {
    NSString *dir = [kMiOSCorePrefsPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [_corePrefs writeToFile:kMiOSCorePrefsPath atomically:YES];
}

- (void)reloadContainers {
    _containers = [MiOSContainerConfig loadAll];
    _activeContainerID = [MiOSContainerConfig activeContainerID];
    [MiOSAppIconProvider applyThemeForActiveContainer];
    [self rebuildContent];
}

- (void)reloadContainersAnimated {
    [UIView transitionWithView:_scrollView duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self reloadContainers];
    } completion:nil];
}

- (MiOSContainerConfig *)activeContainer {
    for (MiOSContainerConfig *c in _containers) {
        if ([c.identifier isEqualToString:_activeContainerID]) return c;
    }
    return _containers.firstObject;
}

#pragma mark - Layout

- (void)setupUI {
    _bgGradientLayer = [CAGradientLayer layer];
    _bgGradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.11 green:0.12 blue:0.19 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.05 alpha:1.0].CGColor,
    ];
    _bgGradientLayer.locations = @[@0.0, @0.45, @1.0];
    _bgGradientLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:_bgGradientLayer atIndex:0];

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    _mainStack = [[UIStackView alloc] init];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.axis = UILayoutConstraintAxisVertical;
    _mainStack.spacing = 22;
    [_scrollView addSubview:_mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_mainStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:8],
        [_mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_mainStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-24],
    ]];
}

- (void)rebuildContent {
    for (UIView *v in [_mainStack.arrangedSubviews copy]) {
        [_mainStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    MiOSContainerConfig *active = [self activeContainer];
    UIColor *accent = [MiOSTheme accentColor];
    _grid = nil;

    [_mainStack addArrangedSubview:[self buildHeaderWithAccent:accent]];

    if (active) {
        [_mainStack addArrangedSubview:[self buildHeroForContainer:active accent:accent]];
        [_mainStack addArrangedSubview:[self buildTilesForContainer:active accent:accent]];
    } else {
        [_mainStack addArrangedSubview:[self buildEmptyHeroWithAccent:accent]];
    }

    [_mainStack addArrangedSubview:[self buildNewContainerCardWithAccent:accent]];

    if (_containers.count > 0) {
        UILabel *header = [[UILabel alloc] init];
        header.text = @"Containers";
        header.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
        header.textColor = [MiOSTheme primaryText];
        [_mainStack addArrangedSubview:header];
        [_mainStack setCustomSpacing:12 afterView:header];

        __weak typeof(self) weakSelf = self;
        _grid = [[MiOSContainerGridView alloc]
            initWithContainers:_containers
                      activeID:active.identifier
                         onTap:^(MiOSContainerConfig *container, UIView *tile) {
            [weakSelf showActionsForContainer:container from:tile];
        }];
        [_mainStack addArrangedSubview:_grid];
    }
}

#pragma mark - Header

- (UIView *)buildHeaderWithAccent:(UIColor *)accent {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    // Wordmark — kept as "miOS" but set in the wide, heavy style of the reference.
    UILabel *logo = [[UILabel alloc] init];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    logo.attributedText = [[NSAttributedString alloc] initWithString:@"miOS" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy],
        NSForegroundColorAttributeName: [MiOSTheme primaryText],
        NSKernAttributeName: @1.5,
    }];
    [row addSubview:logo];

    // Spaced "CONTAINERS" descriptor beneath the wordmark.
    UILabel *descriptor = [[UILabel alloc] init];
    descriptor.translatesAutoresizingMaskIntoConstraints = NO;
    descriptor.attributedText = [[NSAttributedString alloc] initWithString:@"CONTAINERS" attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [MiOSTheme secondaryText],
        NSKernAttributeName: @5.0,
    }];
    [row addSubview:descriptor];

    // Tagline in the active accent colour.
    UILabel *tagline = [[UILabel alloc] init];
    tagline.translatesAutoresizingMaskIntoConstraints = NO;
    tagline.attributedText = [[NSAttributedString alloc] initWithString:@"MORE APPS. MORE FREEDOM." attributes:@{
        NSFontAttributeName: [UIFont systemFontOfSize:10 weight:UIFontWeightBold],
        NSForegroundColorAttributeName: accent,
        NSKernAttributeName: @1.5,
    }];
    [row addSubview:tagline];

    // Pixel-art devil mascot, tinted to the active container's accent.
    UIImageView *mascot = [[UIImageView alloc] initWithImage:
        [MiOSMascotRenderer mascotWithSize:CGSizeMake(78, 78) accent:accent]];
    mascot.translatesAutoresizingMaskIntoConstraints = NO;
    mascot.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:mascot];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:80],
        [logo.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:2],
        [logo.topAnchor constraintEqualToAnchor:row.topAnchor constant:2],
        [descriptor.leadingAnchor constraintEqualToAnchor:logo.leadingAnchor constant:1],
        [descriptor.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:1],
        [tagline.leadingAnchor constraintEqualToAnchor:logo.leadingAnchor constant:1],
        [tagline.topAnchor constraintEqualToAnchor:descriptor.bottomAnchor constant:7],
        [mascot.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:4],
        [mascot.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [mascot.widthAnchor constraintEqualToConstant:78],
        [mascot.heightAnchor constraintEqualToConstant:78],
    ]];
    return row;
}

#pragma mark - Hero

- (UIView *)haloWithContent:(UIView *)content accent:(UIColor *)accent inHero:(UIView *)hero {
    // Soft radial bloom behind the device.
    MiOSGradientView *glow = [[MiOSGradientView alloc] init];
    glow.translatesAutoresizingMaskIntoConstraints = NO;
    glow.userInteractionEnabled = NO;
    glow.gradientLayer.type = kCAGradientLayerRadial;
    [glow setColors:@[[accent colorWithAlphaComponent:0.38],
                      [accent colorWithAlphaComponent:0.12],
                      [accent colorWithAlphaComponent:0.0]]
              start:CGPointMake(0.5, 0.5) end:CGPointMake(1.0, 1.0)];
    glow.gradientLayer.locations = @[@0.0, @0.45, @1.0];
    [hero addSubview:glow];

    // Dashed orbit ring, like the ornament around the avatar in the reference.
    UIView *orbit = [[UIView alloc] init];
    orbit.translatesAutoresizingMaskIntoConstraints = NO;
    orbit.userInteractionEnabled = NO;
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, 204, 204)].CGPath;
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    ring.lineWidth = 1.0;
    ring.lineDashPattern = @[@2, @6];
    [orbit.layer addSublayer:ring];
    [hero addSubview:orbit];

    UIView *halo = [[UIView alloc] init];
    halo.translatesAutoresizingMaskIntoConstraints = NO;
    halo.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.04];
    halo.layer.cornerRadius = 82;
    halo.layer.borderWidth = 1.5;
    halo.layer.borderColor = [accent colorWithAlphaComponent:0.55].CGColor;
    halo.layer.shadowColor = accent.CGColor;
    halo.layer.shadowOffset = CGSizeZero;
    halo.layer.shadowRadius = 18;
    halo.layer.shadowOpacity = 0.45;
    [hero addSubview:halo];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [halo addSubview:content];

    [NSLayoutConstraint activateConstraints:@[
        [halo.topAnchor constraintEqualToAnchor:hero.topAnchor constant:24],
        [halo.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
        [halo.widthAnchor constraintEqualToConstant:164],
        [halo.heightAnchor constraintEqualToConstant:164],
        [orbit.centerXAnchor constraintEqualToAnchor:halo.centerXAnchor],
        [orbit.centerYAnchor constraintEqualToAnchor:halo.centerYAnchor],
        [orbit.widthAnchor constraintEqualToConstant:204],
        [orbit.heightAnchor constraintEqualToConstant:204],
        [glow.centerXAnchor constraintEqualToAnchor:halo.centerXAnchor],
        [glow.centerYAnchor constraintEqualToAnchor:halo.centerYAnchor],
        [glow.widthAnchor constraintEqualToConstant:320],
        [glow.heightAnchor constraintEqualToConstant:320],
        [content.centerXAnchor constraintEqualToAnchor:halo.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:halo.centerYAnchor],
    ]];
    return halo;
}

- (UIView *)buildHeroForContainer:(MiOSContainerConfig *)c accent:(UIColor *)accent {
    UIView *hero = [[UIView alloc] init];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.layer.zPosition = -1; // keep the glow behind the header row

    NSString *deviceName = (c.deviceSpoofEnabled && c.deviceName.length > 0) ? c.deviceName : @"iPhone 15 Pro";
    UIImageView *device = [[UIImageView alloc] init];
    device.contentMode = UIViewContentModeScaleAspectFit;
    device.image = [MiOSDeviceImageRenderer renderDeviceForName:deviceName size:CGSizeMake(140, 132) accentColor:accent];
    UIView *halo = [self haloWithContent:device accent:accent inHero:hero];

    UILabel *name = [[UILabel alloc] init];
    name.translatesAutoresizingMaskIntoConstraints = NO;
    name.text = c.name.length > 0 ? c.name : @"Container";
    name.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    name.textColor = [MiOSTheme primaryText];
    name.textAlignment = NSTextAlignmentCenter;
    name.adjustsFontSizeToFitWidth = YES;
    name.minimumScaleFactor = 0.6;
    [hero addSubview:name];

    NSString *subtitle;
    if (c.deviceSpoofEnabled && c.deviceName.length > 0) {
        subtitle = c.iosVersion.length > 0
            ? [NSString stringWithFormat:@"%@  ·  iOS %@", c.deviceName, c.iosVersion]
            : c.deviceName;
    } else {
        subtitle = @"Real device";
    }
    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = subtitle;
    sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    sub.textColor = [MiOSTheme secondaryText];
    sub.textAlignment = NSTextAlignmentCenter;
    [hero addSubview:sub];

    UIView *pill = [self statusPill];
    [hero addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [name.topAnchor constraintEqualToAnchor:halo.bottomAnchor constant:26],
        [name.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:16],
        [name.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-16],
        [sub.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:16],
        [sub.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-16],
        [pill.topAnchor constraintEqualToAnchor:sub.bottomAnchor constant:14],
        [pill.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor],
    ]];

    halo.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(activeContainerTapped)];
    [halo addGestureRecognizer:tap];
    return hero;
}

- (UIView *)statusPill {
    BOOL enabled = [_corePrefs[@"enabled"] boolValue];
    UIColor *stateColor = enabled ? [MiOSTheme success] : [MiOSTheme tertiaryText];

    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    pill.layer.cornerRadius = 16;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [stateColor colorWithAlphaComponent:0.35].CGColor;

    UIView *dot = [[UIView alloc] init];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.backgroundColor = stateColor;
    dot.layer.cornerRadius = 4;
    dot.layer.shadowColor = stateColor.CGColor;
    dot.layer.shadowOffset = CGSizeZero;
    dot.layer.shadowRadius = 4;
    dot.layer.shadowOpacity = enabled ? 0.9 : 0.0;
    [pill addSubview:dot];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = enabled ? @"Active" : @"Paused";
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    label.textColor = [MiOSTheme primaryText];
    [pill addSubview:label];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightBold];
    UIImageView *power = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"power" withConfiguration:cfg]];
    power.translatesAutoresizingMaskIntoConstraints = NO;
    power.tintColor = [MiOSTheme secondaryText];
    [pill addSubview:power];

    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:32],
        [dot.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:14],
        [dot.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [dot.widthAnchor constraintEqualToConstant:8],
        [dot.heightAnchor constraintEqualToConstant:8],
        [label.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:8],
        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [power.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:10],
        [power.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [power.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-14],
    ]];

    [pill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(statusPillTapped)]];
    return pill;
}

- (UIView *)buildEmptyHeroWithAccent:(UIColor *)accent {
    UIView *hero = [[UIView alloc] init];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.layer.zPosition = -1;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:52 weight:UIImageSymbolWeightThin];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"square.stack.3d.up" withConfiguration:cfg]];
    icon.tintColor = accent;
    UIView *halo = [self haloWithContent:icon accent:accent inHero:hero];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"No Containers Yet";
    title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    title.textColor = [MiOSTheme primaryText];
    title.textAlignment = NSTextAlignmentCenter;
    [hero addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = @"Create a container to isolate apps\nand spoof GPS, device and identifiers.";
    sub.numberOfLines = 0;
    sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    sub.textColor = [MiOSTheme secondaryText];
    sub.textAlignment = NSTextAlignmentCenter;
    [hero addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:halo.bottomAnchor constant:26],
        [title.centerXAnchor constraintEqualToAnchor:hero.centerXAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [sub.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:16],
        [sub.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-16],
        [sub.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor],
    ]];
    return hero;
}

#pragma mark - Tiles

// Large faint symbol set into a tile's corner; it gives each card a texture that says what it's about.
- (UIImageView *)addWatermark:(NSString *)symbol toTile:(UIView *)tile pointSize:(CGFloat)size
                        color:(UIColor *)color rotation:(CGFloat)rotation {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold];
    UIImageView *mark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]];
    mark.translatesAutoresizingMaskIntoConstraints = NO;
    mark.userInteractionEnabled = NO;
    mark.tintColor = color;
    mark.transform = CGAffineTransformMakeRotation(rotation);
    [tile insertSubview:mark atIndex:0];
    return mark;
}

- (UIView *)buildTilesForContainer:(MiOSContainerConfig *)c accent:(UIColor *)accent {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *location = [self locationTileForContainer:c accent:accent];
    UIView *apps = [self appsTileForContainer:c accent:accent];
    UIView *privacy = [self privacyTileForContainer:c accent:accent];
    [row addSubview:location];
    [row addSubview:apps];
    [row addSubview:privacy];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:184],
        [location.topAnchor constraintEqualToAnchor:row.topAnchor],
        [location.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [location.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [location.trailingAnchor constraintEqualToAnchor:apps.leadingAnchor constant:-12],
        [location.widthAnchor constraintEqualToAnchor:apps.widthAnchor],

        [apps.topAnchor constraintEqualToAnchor:row.topAnchor],
        [apps.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [apps.heightAnchor constraintEqualToConstant:72],

        [privacy.topAnchor constraintEqualToAnchor:apps.bottomAnchor constant:12],
        [privacy.leadingAnchor constraintEqualToAnchor:apps.leadingAnchor],
        [privacy.trailingAnchor constraintEqualToAnchor:apps.trailingAnchor],
        [privacy.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];

    [location addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(locationTileTapped:)]];
    [apps addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(appsTileTapped:)]];
    [privacy addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(spoofingTileTapped:)]];
    return row;
}

- (MiOSGradientView *)gradientTileWithColors:(NSArray<UIColor *> *)colors radius:(CGFloat)radius {
    MiOSGradientView *tile = [[MiOSGradientView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    [tile setColors:colors start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    tile.layer.cornerRadius = radius;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.borderWidth = 1.0;
    tile.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    tile.clipsToBounds = YES;
    return tile;
}

- (UIView *)locationTileForContainer:(MiOSContainerConfig *)c accent:(UIColor *)accent {
    UIColor *partner = MiOSPartnerHue(accent);
    MiOSGradientView *tile = [self gradientTileWithColors:@[MiOSShiftedHue(partner, 0.0, 0.50, 0.82),
                                                           MiOSShiftedHue(partner, 0.04, 0.70, 0.46)] radius:26];

    // City skyline with a pin above it.
    UIImageView *skyline = [self addWatermark:@"building.2.fill" toTile:tile pointSize:96
                                        color:[UIColor colorWithWhite:1 alpha:0.14] rotation:0];
    UIImageView *pinMark = [self addWatermark:@"mappin.and.ellipse" toTile:tile pointSize:34
                                        color:[UIColor colorWithWhite:1 alpha:0.22] rotation:0];

    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    iconCircle.layer.cornerRadius = 20;
    [tile addSubview:iconCircle];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightBold];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"location.fill" withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor whiteColor];
    [iconCircle addSubview:icon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.numberOfLines = 2;
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    title.textColor = [UIColor whiteColor];
    [tile addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    sub.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    [tile addSubview:sub];

    if (c.gpsEnabled) {
        title.text = c.locationName.length > 0 ? c.locationName : @"Custom location";
        sub.text = [NSString stringWithFormat:@"%.4f, %.4f", c.latitude, c.longitude];
    } else {
        title.text = @"Real location";
        sub.text = @"Tap to spoof GPS";
    }

    [NSLayoutConstraint activateConstraints:@[
        [skyline.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:14],
        [skyline.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:12],
        [pinMark.centerXAnchor constraintEqualToAnchor:skyline.centerXAnchor constant:-10],
        [pinMark.bottomAnchor constraintEqualToAnchor:skyline.topAnchor constant:4],
        [iconCircle.topAnchor constraintEqualToAnchor:tile.topAnchor constant:16],
        [iconCircle.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:16],
        [iconCircle.widthAnchor constraintEqualToConstant:40],
        [iconCircle.heightAnchor constraintEqualToConstant:40],
        [icon.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-16],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [sub.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-16],
    ]];
    return tile;
}

- (UIView *)appsTileForContainer:(MiOSContainerConfig *)c accent:(UIColor *)accent {
    MiOSGradientView *tile = [self gradientTileWithColors:@[accent, [MiOSTheme accentGradientEnd]] radius:22];
    UIColor *textColor = [MiOSTheme textColorOnAccent];

    UIImageView *grid = [self addWatermark:@"square.grid.2x2.fill" toTile:tile pointSize:62
                                     color:[textColor colorWithAlphaComponent:0.12] rotation:-0.25];

    UILabel *count = [[UILabel alloc] init];
    count.translatesAutoresizingMaskIntoConstraints = NO;
    count.text = [NSString stringWithFormat:@"%lu", (unsigned long)c.apps.count];
    count.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    count.textColor = textColor;
    [tile addSubview:count];

    UILabel *caption = [[UILabel alloc] init];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    caption.text = c.apps.count == 1 ? @"app" : @"apps";
    caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    caption.textColor = [textColor colorWithAlphaComponent:0.75];
    [tile addSubview:caption];

    UIView *icons = [[UIView alloc] init];
    icons.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:icons];
    NSInteger shown = MIN((NSInteger)c.apps.count, 3);
    CGFloat size = 26, step = 18;
    for (NSInteger i = 0; i < shown; i++) {
        UIImageView *iv = [[UIImageView alloc] init];
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        iv.image = [MiOSAppIconProvider iconForBundleID:c.apps[i]];
        iv.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.layer.cornerRadius = 7;
        iv.layer.borderWidth = 1.5;
        iv.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        [icons addSubview:iv];
        [NSLayoutConstraint activateConstraints:@[
            [iv.trailingAnchor constraintEqualToAnchor:icons.trailingAnchor constant:-(step * (shown - 1 - i))],
            [iv.centerYAnchor constraintEqualToAnchor:icons.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:size],
            [iv.heightAnchor constraintEqualToConstant:size],
        ]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [grid.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor constant:6],
        [grid.centerYAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-6],
        [count.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:16],
        [count.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [caption.leadingAnchor constraintEqualToAnchor:count.trailingAnchor constant:5],
        [caption.lastBaselineAnchor constraintEqualToAnchor:count.lastBaselineAnchor],
        [icons.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-14],
        [icons.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [icons.heightAnchor constraintEqualToConstant:size],
        [icons.widthAnchor constraintEqualToConstant:shown > 0 ? size + step * (shown - 1) : 0],
    ]];
    return tile;
}

- (UIView *)privacyTileForContainer:(MiOSContainerConfig *)c accent:(UIColor *)accent {
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [MiOSTheme tileBackground];
    tile.layer.cornerRadius = 22;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.borderWidth = 1.0;
    tile.layer.borderColor = [MiOSTheme hairline].CGColor;
    tile.clipsToBounds = YES;

    // Chipset watermark: this is the "under the hood" tile.
    UIImageView *chip = [self addWatermark:@"cpu" toTile:tile pointSize:78
                                     color:[accent colorWithAlphaComponent:0.10] rotation:0.2];

    NSArray<NSNumber *> *flags = @[@(c.spoofDeviceCheck), @(c.spoofVendorID), @(c.spoofAdvertisingID),
                                   @(c.spoofCloudToken), @(c.deviceSpoofEnabled), @(c.gpsEnabled)];
    NSInteger onCount = 0;
    for (NSNumber *f in flags) onCount += f.boolValue ? 1 : 0;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Spoofing";
    title.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    title.textColor = [MiOSTheme secondaryText];
    [tile addSubview:title];

    UILabel *score = [[UILabel alloc] init];
    score.translatesAutoresizingMaskIntoConstraints = NO;
    score.text = [NSString stringWithFormat:@"%ld/%lu", (long)onCount, (unsigned long)flags.count];
    score.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    score.textColor = accent;
    [tile addSubview:score];

    UIStackView *bars = [[UIStackView alloc] init];
    bars.translatesAutoresizingMaskIntoConstraints = NO;
    bars.axis = UILayoutConstraintAxisHorizontal;
    bars.distribution = UIStackViewDistributionFillEqually;
    bars.alignment = UIStackViewAlignmentBottom;
    bars.spacing = 5;
    for (NSNumber *flag in flags) {
        BOOL on = flag.boolValue;
        UIView *bar = [[UIView alloc] init];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.backgroundColor = on ? accent : [UIColor colorWithWhite:1.0 alpha:0.10];
        bar.layer.cornerRadius = 4;
        [bar.heightAnchor constraintEqualToConstant:on ? 30 : 18].active = YES;
        [bars addArrangedSubview:bar];
    }
    [tile addSubview:bars];

    [NSLayoutConstraint activateConstraints:@[
        [chip.centerXAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-18],
        [chip.centerYAnchor constraintEqualToAnchor:tile.topAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:tile.topAnchor constant:14],
        [title.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:14],
        [score.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [score.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-14],
        [bars.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:14],
        [bars.trailingAnchor constraintEqualToAnchor:tile.trailingAnchor constant:-14],
        [bars.bottomAnchor constraintEqualToAnchor:tile.bottomAnchor constant:-14],
        [bars.heightAnchor constraintEqualToConstant:30],
    ]];
    return tile;
}

#pragma mark - New Container Card

- (UIView *)buildNewContainerCardWithAccent:(UIColor *)accent {
    UIView *host = [[UIView alloc] init];
    host.translatesAutoresizingMaskIntoConstraints = NO;
    host.layer.shadowColor = accent.CGColor;
    host.layer.shadowOffset = CGSizeMake(0, 8);
    host.layer.shadowRadius = 18;
    host.layer.shadowOpacity = 0.35;

    MiOSGradientView *card = [self gradientTileWithColors:@[accent, [MiOSTheme accentGradientEnd]] radius:28];
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    [host addSubview:card];

    MiOSGradientView *sheen = [[MiOSGradientView alloc] init];
    sheen.translatesAutoresizingMaskIntoConstraints = NO;
    sheen.userInteractionEnabled = NO;
    [sheen setColors:@[[UIColor colorWithWhite:1.0 alpha:0.22], [UIColor colorWithWhite:1.0 alpha:0.0]]
               start:CGPointMake(0.5, 0.0) end:CGPointMake(0.5, 0.7)];
    [card addSubview:sheen];

    UIColor *textColor = [MiOSTheme textColorOnAccent];

    // 3D cube glyph set into the left, echoing the reference's isolate-box motif.
    UIImageView *cubeMark = [self addWatermark:@"cube.fill" toTile:card pointSize:92
                                         color:[textColor colorWithAlphaComponent:0.16] rotation:0.0];

    UIView *cubeBadge = [[UIView alloc] init];
    cubeBadge.translatesAutoresizingMaskIntoConstraints = NO;
    cubeBadge.userInteractionEnabled = NO;
    cubeBadge.backgroundColor = [textColor colorWithAlphaComponent:0.16];
    cubeBadge.layer.cornerRadius = 15;
    cubeBadge.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:cubeBadge];
    UIImageSymbolConfiguration *cubeCfg = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightBold];
    UIImageView *cubeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"cube.fill" withConfiguration:cubeCfg]];
    cubeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    cubeIcon.tintColor = textColor;
    [cubeBadge addSubview:cubeIcon];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"New Container";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = textColor;
    [card addSubview:title];

    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = @"Isolate apps · spoof GPS, device & IDs";
    sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    sub.textColor = [textColor colorWithAlphaComponent:0.85];
    sub.adjustsFontSizeToFitWidth = YES;
    sub.minimumScaleFactor = 0.8;
    [card addSubview:sub];

    // Trailing arrow in a soft chip.
    UIView *arrowChip = [[UIView alloc] init];
    arrowChip.translatesAutoresizingMaskIntoConstraints = NO;
    arrowChip.userInteractionEnabled = NO;
    arrowChip.backgroundColor = [textColor colorWithAlphaComponent:0.18];
    arrowChip.layer.cornerRadius = 16;
    [card addSubview:arrowChip];
    UIImageSymbolConfiguration *arrCfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    UIImageView *arrow = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right" withConfiguration:arrCfg]];
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    arrow.tintColor = textColor;
    [arrowChip addSubview:arrow];

    [NSLayoutConstraint activateConstraints:@[
        [host.heightAnchor constraintEqualToConstant:100],
        [card.topAnchor constraintEqualToAnchor:host.topAnchor],
        [card.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [card.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [card.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [sheen.topAnchor constraintEqualToAnchor:card.topAnchor],
        [sheen.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [sheen.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [sheen.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
        [cubeMark.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:38],
        [cubeMark.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [cubeBadge.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [cubeBadge.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [cubeBadge.widthAnchor constraintEqualToConstant:52],
        [cubeBadge.heightAnchor constraintEqualToConstant:52],
        [cubeIcon.centerXAnchor constraintEqualToAnchor:cubeBadge.centerXAnchor],
        [cubeIcon.centerYAnchor constraintEqualToAnchor:cubeBadge.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:cubeBadge.trailingAnchor constant:14],
        [title.bottomAnchor constraintEqualToAnchor:card.centerYAnchor constant:2],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],
        [sub.trailingAnchor constraintEqualToAnchor:arrowChip.leadingAnchor constant:-8],
        [arrowChip.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [arrowChip.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [arrowChip.widthAnchor constraintEqualToConstant:32],
        [arrowChip.heightAnchor constraintEqualToConstant:32],
        [arrow.centerXAnchor constraintEqualToAnchor:arrowChip.centerXAnchor],
        [arrow.centerYAnchor constraintEqualToAnchor:arrowChip.centerYAnchor],
    ]];

    [host addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(newContainerTapped:)]];
    return host;
}

#pragma mark - Actions

- (void)bounce:(UIView *)view {
    [UIView animateWithDuration:0.08 animations:^{
        view.transform = CGAffineTransformMakeScale(0.97, 0.97);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:0 animations:^{
            view.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)statusPillTapped {
    BOOL enabled = ![_corePrefs[@"enabled"] boolValue];
    _corePrefs[@"enabled"] = @(enabled);
    [self savePreferences];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    [self rebuildContent];
}

- (void)activeContainerTapped {
    MiOSContainerConfig *active = [self activeContainer];
    if (active) [self presentEditorForContainer:active entry:MiOSEditorEntryFull];
}

- (void)appsTileTapped:(UITapGestureRecognizer *)sender {
    [self bounce:sender.view];
    MiOSContainerConfig *active = [self activeContainer];
    if (active) [self presentEditorForContainer:active entry:MiOSEditorEntryApps];
}

- (void)spoofingTileTapped:(UITapGestureRecognizer *)sender {
    [self bounce:sender.view];
    MiOSContainerConfig *active = [self activeContainer];
    if (active) [self presentEditorForContainer:active entry:MiOSEditorEntrySpoofing];
}

- (void)locationTileTapped:(UITapGestureRecognizer *)sender {
    [self bounce:sender.view];
    MiOSContainerConfig *active = [self activeContainer];
    if (!active) return;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    MiOSLocationPickerViewController *picker = [[MiOSLocationPickerViewController alloc] init];
    picker.container = active;
    __weak typeof(self) weakSelf = self;
    picker.onSave = ^{
        [weakSelf reloadContainersAnimated];
    };
    picker.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)newContainerTapped:(UITapGestureRecognizer *)sender {
    [self bounce:sender.view];
    [self presentEditorForContainer:nil entry:MiOSEditorEntryFull];
}

- (void)showActionsForContainer:(MiOSContainerConfig *)container from:(UIView *)tile {
    __weak typeof(self) weakSelf = self;
    [MiOSContainerActions presentForContainer:container from:self sourceView:tile completion:^(MiOSContainerActionResult result) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (result == MiOSContainerActionRemoved && strongSelf.grid) {
            [strongSelf.grid removeContainerWithID:container.identifier completion:^{
                [weakSelf reloadContainersAnimated];
            }];
        } else {
            [strongSelf reloadContainersAnimated];
        }
    }];
}

- (void)presentEditorForContainer:(MiOSContainerConfig *)container entry:(MiOSEditorEntry)entry {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    MiOSContainerCreateViewController *vc = [[MiOSContainerCreateViewController alloc] init];
    vc.editingContainer = container;
    vc.entry = entry;
    __weak typeof(self) weakSelf = self;
    vc.onSave = ^{
        [weakSelf reloadContainersAnimated];
    };
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:vc animated:YES completion:nil];
}

@end
