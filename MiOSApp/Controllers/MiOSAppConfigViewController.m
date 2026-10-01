#import "MiOSAppConfigViewController.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"

@interface MiOSAppConfigViewController () <MiOSToggleCellDelegate>
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) NSMutableDictionary *appPrefs;
@property (nonatomic, copy) NSString *prefsPath;
@end

@implementation MiOSAppConfigViewController

- (instancetype)initWithBundleID:(NSString *)bundleID {
    if (self = [super init]) {
        _bundleID = [bundleID copy];
        _prefsPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/MiOS/apps/%@.plist", bundleID];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _bundleID;
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self loadPreferences];
    [self setupUI];
}

- (void)loadPreferences {
    _appPrefs = [[NSMutableDictionary dictionaryWithContentsOfFile:_prefsPath] mutableCopy];
    if (!_appPrefs) {
        _appPrefs = [@{@"enabled": @NO, @"containerEnabled": @NO, @"gpsEnabled": @NO} mutableCopy];
    }
}

- (void)savePreferences {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [_prefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [_appPrefs writeToFile:_prefsPath atomically:YES];
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

    [self buildMainSection];
    [self buildModulesSection];
    [self buildResetSection];
}

- (void)buildMainSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    MiOSToggleCell *enableCell = [[MiOSToggleCell alloc]
        initWithTitle:@"Enable miOS"
             subtitle:@"Activate miOS for this app"
                 icon:@"power"
                color:[MiOSTheme accentColor]
                  key:@"enabled"];
    enableCell.isOn = [_appPrefs[@"enabled"] boolValue];
    enableCell.delegate = self;
    [section addCellView:enableCell];

    [_mainStack addArrangedSubview:section];
}

- (void)buildModulesSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Modules"];

    MiOSToggleCell *containerCell = [[MiOSToggleCell alloc]
        initWithTitle:@"Container Isolation"
             subtitle:@"Use separate data container"
                 icon:@"square.stack.3d.up.fill"
                color:[UIColor systemPurpleColor]
                  key:@"containerEnabled"];
    containerCell.isOn = [_appPrefs[@"containerEnabled"] boolValue];
    containerCell.delegate = self;
    [section addCellView:containerCell];
    [section addSeparator];

    MiOSToggleCell *gpsCell = [[MiOSToggleCell alloc]
        initWithTitle:@"GPS Spoofing"
             subtitle:@"Override location data"
                 icon:@"location.fill"
                color:[UIColor systemBlueColor]
                  key:@"gpsEnabled"];
    gpsCell.isOn = [_appPrefs[@"gpsEnabled"] boolValue];
    gpsCell.delegate = self;
    [section addCellView:gpsCell];

    [_mainStack addArrangedSubview:section];
}

- (void)buildResetSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    __weak typeof(self) weakSelf = self;

    MiOSNavigationCell *resetCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Reset Settings"
             subtitle:@"Reset all miOS settings for this app"
                 icon:@"arrow.counterclockwise"
                color:[MiOSTheme destructive]];
    resetCell.tapAction = ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Settings"
            message:[NSString stringWithFormat:@"Reset all miOS settings for %@?", weakSelf.bundleID]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[NSFileManager defaultManager] removeItemAtPath:weakSelf.prefsPath error:nil];
            weakSelf.appPrefs = [@{@"enabled": @NO, @"containerEnabled": @NO, @"gpsEnabled": @NO} mutableCopy];
            [weakSelf.navigationController popViewControllerAnimated:YES];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    };
    [section addCellView:resetCell];

    [_mainStack addArrangedSubview:section];
}

- (void)toggleCell:(id)cell didChangeValue:(BOOL)value forKey:(NSString *)key {
    _appPrefs[key] = @(value);
    [self savePreferences];
}

@end
