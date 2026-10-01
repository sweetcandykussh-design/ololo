#import "MiOSContainerDetailViewController.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"
#import "../Models/MiOSDeviceDatabase.h"
#import <objc/runtime.h>

static NSString *const kMiOSContainerDirName = @"___MiOS_Containers";
static NSString *const kMiOSContainerPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.containerprefs.plist";
static NSString *const kDeviceSpoofPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.devicespoof.plist";
static NSString *const kLocationPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.locationprefs.plist";

@interface MiOSContainerDetailViewController () <MiOSToggleCellDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *appDataPath;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) NSMutableArray *containers;
@property (nonatomic, copy) NSString *activeContainerID;
@property (nonatomic, strong) NSMutableDictionary *spoofPrefs;
@end

@implementation MiOSContainerDetailViewController

- (instancetype)initWithBundleID:(NSString *)bundleID appDataPath:(NSString *)path {
    if (self = [super init]) {
        _bundleID = [bundleID copy];
        _appDataPath = [path copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _bundleID;
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self loadContainers];
    [self setupUI];
}

- (void)loadContainers {
    _containers = [NSMutableArray new];
    [_containers addObject:@{@"id": @"DEFAULT", @"name": @"Default"}];

    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:kMiOSContainerPrefsPath] mutableCopy];
    NSDictionary *activeMap = prefs[@"activeContainers"];
    _activeContainerID = activeMap[_bundleID] ?: @"DEFAULT";

    NSString *containerDir = [_appDataPath stringByAppendingPathComponent:kMiOSContainerDirName];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *dirs = [fm contentsOfDirectoryAtPath:containerDir error:nil];
    for (NSString *dir in dirs) {
        NSString *metaPath = [[containerDir stringByAppendingPathComponent:dir]
                              stringByAppendingPathComponent:@".mios_container_meta.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *name = meta[@"name"] ?: dir;
        [_containers addObject:@{@"id": dir, @"name": name}];
    }
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    _mainStack = [[UIStackView alloc] init];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.axis = UILayoutConstraintAxisVertical;
    _mainStack.spacing = 20;
    [_scrollView addSubview:_mainStack];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(addContainer)];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_mainStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:16],
        [_mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_mainStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-32],
    ]];

    [self loadSpoofPrefs];
    [self buildDashboardCard];
    [self buildContainerList];
    [self buildIdentifiersSection];
    [self buildActionsSection];
}

- (NSString *)spoofPrefsPathForContainerID:(NSString *)containerID {
    if ([containerID isEqualToString:@"DEFAULT"]) {
        return [_appDataPath stringByAppendingPathComponent:@".mios_spoof_prefs.plist"];
    }
    NSString *containerDir = [_appDataPath stringByAppendingPathComponent:kMiOSContainerDirName];
    NSString *containerPath = [containerDir stringByAppendingPathComponent:containerID];
    return [containerPath stringByAppendingPathComponent:@".mios_spoof_prefs.plist"];
}

- (void)loadSpoofPrefs {
    NSString *path = [self spoofPrefsPathForContainerID:_activeContainerID];
    _spoofPrefs = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
    if (!_spoofPrefs) _spoofPrefs = [NSMutableDictionary new];
}

- (void)saveSpoofPrefs {
    NSString *path = [self spoofPrefsPathForContainerID:_activeContainerID];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [path stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [_spoofPrefs writeToFile:path atomically:YES];
}

- (void)buildDashboardCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;

    UIView *gradBg = [[UIView alloc] init];
    gradBg.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:gradBg];
    [NSLayoutConstraint activateConstraints:@[
        [gradBg.topAnchor constraintEqualToAnchor:card.topAnchor],
        [gradBg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [gradBg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [gradBg.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];

    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[
        (id)[UIColor colorWithRed:0.10 green:0.10 blue:0.18 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.08 green:0.08 blue:0.14 alpha:1.0].CGColor,
    ];
    gradient.startPoint = CGPointMake(0, 0);
    gradient.endPoint = CGPointMake(1, 1);
    [gradBg.layer insertSublayer:gradient atIndex:0];

    dispatch_async(dispatch_get_main_queue(), ^{
        gradient.frame = gradBg.bounds;
    });
    [gradBg setNeedsLayout];

    NSDictionary *devicePrefs = [NSDictionary dictionaryWithContentsOfFile:kDeviceSpoofPrefsPath];
    NSString *deviceName = devicePrefs[@"deviceName"] ?: @"iPhone";
    NSString *iosVer = devicePrefs[@"iosVersion"] ?: @"—";

    NSDictionary *locPrefs = [NSDictionary dictionaryWithContentsOfFile:kLocationPrefsPath];
    BOOL gpsEnabled = [locPrefs[@"enabled"] boolValue];
    double lat = [locPrefs[@"latitude"] doubleValue];
    double lon = [locPrefs[@"longitude"] doubleValue];

    NSDictionary *activeContainer = nil;
    for (NSDictionary *c in _containers) {
        if ([c[@"id"] isEqualToString:_activeContainerID]) {
            activeContainer = c;
            break;
        }
    }

    UIImageSymbolConfiguration *phoneConfig = [UIImageSymbolConfiguration configurationWithPointSize:80 weight:UIImageSymbolWeightUltraLight];
    UIImageView *phoneImage = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone" withConfiguration:phoneConfig]];
    phoneImage.translatesAutoresizingMaskIntoConstraints = NO;
    phoneImage.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
    phoneImage.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:phoneImage];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = deviceName;
    nameLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    nameLabel.textColor = [UIColor whiteColor];
    [card addSubview:nameLabel];

    UIView *enabledBadge = [[UIView alloc] init];
    enabledBadge.translatesAutoresizingMaskIntoConstraints = NO;
    enabledBadge.backgroundColor = [[UIColor systemGreenColor] colorWithAlphaComponent:0.2];
    enabledBadge.layer.cornerRadius = 6;
    [card addSubview:enabledBadge];

    UILabel *enabledLabel = [[UILabel alloc] init];
    enabledLabel.translatesAutoresizingMaskIntoConstraints = NO;
    enabledLabel.text = @"Enabled";
    enabledLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    enabledLabel.textColor = [UIColor systemGreenColor];
    [enabledBadge addSubview:enabledLabel];

    UIStackView *infoStack = [[UIStackView alloc] init];
    infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    infoStack.axis = UILayoutConstraintAxisVertical;
    infoStack.spacing = 6;
    [card addSubview:infoStack];

    NSString *containerText = activeContainer
        ? [NSString stringWithFormat:@"Container: %@", activeContainer[@"name"]]
        : @"Container: Default";
    [infoStack addArrangedSubview:[self infoRowWithIcon:@"square.stack.3d.up.fill" text:containerText]];

    NSString *iosText = [NSString stringWithFormat:@"iOS %@", iosVer];
    [infoStack addArrangedSubview:[self infoRowWithIcon:@"gearshape.fill" text:iosText]];

    if (gpsEnabled && (lat != 0 || lon != 0)) {
        NSString *locText = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];
        [infoStack addArrangedSubview:[self infoRowWithIcon:@"location.fill" text:locText]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:180],

        [phoneImage.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [phoneImage.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [phoneImage.widthAnchor constraintEqualToConstant:70],
        [phoneImage.heightAnchor constraintEqualToConstant:100],

        [nameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
        [nameLabel.leadingAnchor constraintEqualToAnchor:phoneImage.trailingAnchor constant:16],
        [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],

        [enabledBadge.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [enabledBadge.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:6],
        [enabledLabel.topAnchor constraintEqualToAnchor:enabledBadge.topAnchor constant:3],
        [enabledLabel.bottomAnchor constraintEqualToAnchor:enabledBadge.bottomAnchor constant:-3],
        [enabledLabel.leadingAnchor constraintEqualToAnchor:enabledBadge.leadingAnchor constant:8],
        [enabledLabel.trailingAnchor constraintEqualToAnchor:enabledBadge.trailingAnchor constant:-8],

        [infoStack.leadingAnchor constraintEqualToAnchor:nameLabel.leadingAnchor],
        [infoStack.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
        [infoStack.topAnchor constraintEqualToAnchor:enabledBadge.bottomAnchor constant:10],
    ]];

    [_mainStack addArrangedSubview:card];
}

- (UIView *)infoRowWithIcon:(NSString *)iconName text:(NSString *)text {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightMedium];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName withConfiguration:cfg]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = [UIColor colorWithWhite:1 alpha:0.5];
    [row addSubview:icon];

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [row addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:14],
        [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6],
        [label.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [label.topAnchor constraintEqualToAnchor:row.topAnchor],
        [label.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [row.heightAnchor constraintEqualToConstant:18],
    ]];
    return row;
}

- (void)buildContainerList {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Containers"];

    for (NSUInteger i = 0; i < _containers.count; i++) {
        NSDictionary *container = _containers[i];
        BOOL isActive = [container[@"id"] isEqualToString:_activeContainerID];

        UIView *cell = [[UIView alloc] init];
        cell.translatesAutoresizingMaskIntoConstraints = NO;
        cell.tag = (NSInteger)i;
        cell.userInteractionEnabled = YES;

        UIView *dot = [[UIView alloc] init];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.backgroundColor = isActive ? [MiOSTheme success] : [MiOSTheme separator];
        dot.layer.cornerRadius = 5;
        [cell addSubview:dot];

        UILabel *nameLabel = [[UILabel alloc] init];
        nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        nameLabel.text = container[@"name"];
        nameLabel.font = [MiOSTheme headlineFont];
        nameLabel.textColor = [MiOSTheme primaryText];
        [cell addSubview:nameLabel];

        UIImageView *check = nil;
        if (isActive) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
            check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:cfg]];
            check.translatesAutoresizingMaskIntoConstraints = NO;
            check.tintColor = [MiOSTheme accentColor];
            [cell addSubview:check];
        }

        [NSLayoutConstraint activateConstraints:@[
            [cell.heightAnchor constraintEqualToConstant:48],
            [dot.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:16],
            [dot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:10],
            [dot.heightAnchor constraintEqualToConstant:10],
            [nameLabel.leadingAnchor constraintEqualToAnchor:dot.trailingAnchor constant:12],
            [nameLabel.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];

        if (check) {
            [NSLayoutConstraint activateConstraints:@[
                [check.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-16],
                [check.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:check.leadingAnchor constant:-8],
            ]];
        } else {
            [nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor constant:-16].active = YES;
        }

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(containerCellTapped:)];
        [cell addGestureRecognizer:tap];

        [section addCellView:cell];
        if (i < _containers.count - 1) [section addSeparator];
    }

    [_mainStack addArrangedSubview:section];
}

- (void)containerCellTapped:(UITapGestureRecognizer *)sender {
    NSInteger idx = sender.view.tag;
    if (idx < 0 || idx >= (NSInteger)_containers.count) return;

    NSDictionary *container = _containers[idx];
    _activeContainerID = container[@"id"];
    [self saveActiveContainer];

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    [self rebuildUI];
}

- (void)rebuildUI {
    for (UIView *v in _mainStack.arrangedSubviews) {
        [_mainStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self loadSpoofPrefs];
    [self buildDashboardCard];
    [self buildContainerList];
    [self buildIdentifiersSection];
    [self buildActionsSection];
}

- (void)buildIdentifiersSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Privacy & Identifiers"];
    __weak typeof(self) weakSelf = self;

    MiOSToggleCell *deviceCheckCell = [[MiOSToggleCell alloc]
        initWithTitle:@"DeviceCheck Bypass"
             subtitle:@"Block DeviceCheck token generation"
                 icon:@"checkmark.shield.fill"
                color:[UIColor systemRedColor]
                  key:@"spoofDeviceCheck"];
    deviceCheckCell.isOn = [_spoofPrefs[@"spoofDeviceCheck"] boolValue];
    deviceCheckCell.delegate = self;
    [section addCellView:deviceCheckCell];
    [section addSeparator];

    MiOSToggleCell *vendorCell = [[MiOSToggleCell alloc]
        initWithTitle:@"Vendor ID Spoof"
             subtitle:@"Spoof identifierForVendor"
                 icon:@"person.badge.key.fill"
                color:[UIColor systemIndigoColor]
                  key:@"spoofVendorID"];
    vendorCell.isOn = [_spoofPrefs[@"spoofVendorID"] boolValue];
    vendorCell.delegate = self;
    [section addCellView:vendorCell];

    if ([_spoofPrefs[@"spoofVendorID"] boolValue]) {
        NSString *vid = _spoofPrefs[@"vendorID"] ?: @"Not generated";
        [section addCellView:[self identifierValueRowWithValue:vid key:@"vendorID" generateAction:^{
            [weakSelf generateIdentifier:@"vendorID"];
        }]];
    }
    [section addSeparator];

    MiOSToggleCell *adCell = [[MiOSToggleCell alloc]
        initWithTitle:@"Advertising ID Spoof"
             subtitle:@"Spoof advertisingIdentifier"
                 icon:@"megaphone.fill"
                color:[UIColor systemOrangeColor]
                  key:@"spoofAdvertisingID"];
    adCell.isOn = [_spoofPrefs[@"spoofAdvertisingID"] boolValue];
    adCell.delegate = self;
    [section addCellView:adCell];

    if ([_spoofPrefs[@"spoofAdvertisingID"] boolValue]) {
        NSString *aid = _spoofPrefs[@"advertisingID"] ?: @"Not generated";
        [section addCellView:[self identifierValueRowWithValue:aid key:@"advertisingID" generateAction:^{
            [weakSelf generateIdentifier:@"advertisingID"];
        }]];
    }
    [section addSeparator];

    MiOSToggleCell *cloudCell = [[MiOSToggleCell alloc]
        initWithTitle:@"iCloud Token Spoof"
             subtitle:@"Return nil for ubiquityIdentityToken"
                 icon:@"icloud.slash.fill"
                color:[UIColor systemGrayColor]
                  key:@"spoofCloudToken"];
    cloudCell.isOn = [_spoofPrefs[@"spoofCloudToken"] boolValue];
    cloudCell.delegate = self;
    [section addCellView:cloudCell];

    [_mainStack addArrangedSubview:section];
}

- (UIView *)identifierValueRowWithValue:(NSString *)value key:(NSString *)key generateAction:(void (^)(void))action {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *valueLabel = [[UILabel alloc] init];
    valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    valueLabel.text = value;
    valueLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    valueLabel.textColor = [MiOSTheme secondaryText];
    valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [row addSubview:valueLabel];

    UIButton *genBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    genBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [genBtn setTitle:@"Generate" forState:UIControlStateNormal];
    genBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [genBtn setTitleColor:[MiOSTheme accentColor] forState:UIControlStateNormal];
    genBtn.backgroundColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.12];
    genBtn.layer.cornerRadius = 8;
    genBtn.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    [row addSubview:genBtn];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
    [copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc" withConfiguration:cfg] forState:UIControlStateNormal];
    copyBtn.tintColor = [MiOSTheme secondaryText];
    [row addSubview:copyBtn];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:40],
        [valueLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:64],
        [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:copyBtn.leadingAnchor constant:-8],
        [copyBtn.trailingAnchor constraintEqualToAnchor:genBtn.leadingAnchor constant:-8],
        [copyBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [copyBtn.widthAnchor constraintEqualToConstant:28],
        [genBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [genBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    NSString *valueCopy = [value copy];
    [copyBtn addTarget:self action:@selector(copyValueFromButton:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(copyBtn, "copyValue", valueCopy, OBJC_ASSOCIATION_COPY_NONATOMIC);

    [genBtn addTarget:self action:@selector(generateFromButton:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(genBtn, "genKey", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(genBtn, "genAction", action, OBJC_ASSOCIATION_COPY_NONATOMIC);

    return row;
}

- (void)copyValueFromButton:(UIButton *)sender {
    NSString *val = objc_getAssociatedObject(sender, "copyValue");
    if (val.length > 0 && ![val isEqualToString:@"Not generated"]) {
        [UIPasteboard generalPasteboard].string = val;
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [haptic impactOccurred];
    }
}

- (void)generateFromButton:(UIButton *)sender {
    void (^action)(void) = objc_getAssociatedObject(sender, "genAction");
    if (action) action();
}

- (void)generateIdentifier:(NSString *)key {
    NSString *newUUID = [[NSUUID UUID] UUIDString];
    _spoofPrefs[key] = newUUID;
    [self saveSpoofPrefs];
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    [self rebuildUI];
}

#pragma mark - MiOSToggleCellDelegate

- (void)toggleCell:(id)cell didChangeValue:(BOOL)value forKey:(NSString *)key {
    _spoofPrefs[key] = @(value);

    if ([key isEqualToString:@"spoofVendorID"] && value && !_spoofPrefs[@"vendorID"]) {
        _spoofPrefs[@"vendorID"] = [[NSUUID UUID] UUIDString];
    }
    if ([key isEqualToString:@"spoofAdvertisingID"] && value && !_spoofPrefs[@"advertisingID"]) {
        _spoofPrefs[@"advertisingID"] = [[NSUUID UUID] UUIDString];
    }

    [self saveSpoofPrefs];
    [self rebuildUI];
}

- (void)buildActionsSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    __weak typeof(self) weakSelf = self;

    MiOSNavigationCell *deleteCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Delete All Containers"
             subtitle:nil
                 icon:@"trash.fill"
                color:[MiOSTheme destructive]];
    deleteCell.tapAction = ^{
        [weakSelf confirmDeleteAll];
    };
    [section addCellView:deleteCell];

    [_mainStack addArrangedSubview:section];
}

- (void)addContainer {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Container"
                                                                  message:@"Enter a name for the new container"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Container name...";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) return;
        [weakSelf createContainerWithName:name];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createContainerWithName:(NSString *)name {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *containerDir = [_appDataPath stringByAppendingPathComponent:kMiOSContainerDirName];
    NSString *containerPath = [containerDir stringByAppendingPathComponent:uuid];
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray *subdirs = @[@"Documents", @"Library", @"Library/Preferences", @"Library/Caches",
                         @"Library/Application Support", @"Library/SplashBoard", @"SystemData", @"tmp"];
    for (NSString *sub in subdirs) {
        [fm createDirectoryAtPath:[containerPath stringByAppendingPathComponent:sub]
      withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDictionary *meta = @{@"name": name, @"createdAt": [NSDate date].description, @"bundleID": _bundleID};
    NSString *metaFile = [containerPath stringByAppendingPathComponent:@".mios_container_meta.plist"];
    [meta writeToFile:metaFile atomically:YES];

    [_containers addObject:@{@"id": uuid, @"name": name}];
    [self rebuildUI];
}

- (void)confirmDeleteAll {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete All Containers"
        message:[NSString stringWithFormat:@"This will delete all containers for %@. This cannot be undone.", _bundleID]
        preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSString *containerDir = [weakSelf.appDataPath stringByAppendingPathComponent:kMiOSContainerDirName];
        [[NSFileManager defaultManager] removeItemAtPath:containerDir error:nil];
        weakSelf.activeContainerID = @"DEFAULT";
        [weakSelf saveActiveContainer];
        [weakSelf loadContainers];
        [weakSelf rebuildUI];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveActiveContainer {
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:kMiOSContainerPrefsPath] mutableCopy];
    if (!prefs) prefs = [NSMutableDictionary new];
    NSMutableDictionary *active = [prefs[@"activeContainers"] mutableCopy] ?: [NSMutableDictionary new];
    active[_bundleID] = _activeContainerID;
    prefs[@"activeContainers"] = active;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [kMiOSContainerPrefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [prefs writeToFile:kMiOSContainerPrefsPath atomically:YES];
}

@end
