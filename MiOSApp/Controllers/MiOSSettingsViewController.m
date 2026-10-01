#import "MiOSSettingsViewController.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"
#import <spawn.h>

extern char **environ;

@interface MiOSSettingsViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@end

@implementation MiOSSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self setupUI];
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

    [self buildAboutSection];
    [self buildIsolationInfoSection];
    [self buildDataSection];
    [self buildInfoSection];
}

#pragma mark - Isolation (always on)

- (void)buildIsolationInfoSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Isolation"];

    MiOSNavigationCell *fileCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"File Isolation"
             subtitle:@"Always on · real per-container storage"
                 icon:@"folder.fill.badge.gearshape"
                color:[UIColor systemTealColor]];
    [section addCellView:fileCell];
    [section addSeparator];

    MiOSNavigationCell *kcCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Keychain Isolation"
             subtitle:@"Always on · separate keychain & sessions per container"
                 icon:@"key.fill"
                color:[UIColor systemIndigoColor]];
    [section addCellView:kcCell];

    [_mainStack addArrangedSubview:section];
}

- (void)buildAboutSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"About"];

    UIView *aboutContainer = [[UIView alloc] init];
    aboutContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    nameLabel.text = @"miOS";
    nameLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    nameLabel.textColor = [MiOSTheme primaryText];
    [aboutContainer addSubview:nameLabel];

    UILabel *verLabel = [[UILabel alloc] init];
    verLabel.translatesAutoresizingMaskIntoConstraints = NO;
    verLabel.text = @"Version 1.0.0";
    verLabel.font = [MiOSTheme captionFont];
    verLabel.textColor = [MiOSTheme secondaryText];
    [aboutContainer addSubview:verLabel];

    UILabel *descLabel = [[UILabel alloc] init];
    descLabel.translatesAutoresizingMaskIntoConstraints = NO;
    descLabel.text = @"App containerization & GPS spoofing tweak for iOS.";
    descLabel.font = [MiOSTheme bodyFont];
    descLabel.textColor = [MiOSTheme secondaryText];
    descLabel.numberOfLines = 0;
    [aboutContainer addSubview:descLabel];

    [NSLayoutConstraint activateConstraints:@[
        [nameLabel.topAnchor constraintEqualToAnchor:aboutContainer.topAnchor constant:16],
        [nameLabel.leadingAnchor constraintEqualToAnchor:aboutContainer.leadingAnchor constant:16],
        [verLabel.leadingAnchor constraintEqualToAnchor:nameLabel.trailingAnchor constant:8],
        [verLabel.bottomAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:-2],
        [descLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:8],
        [descLabel.leadingAnchor constraintEqualToAnchor:aboutContainer.leadingAnchor constant:16],
        [descLabel.trailingAnchor constraintEqualToAnchor:aboutContainer.trailingAnchor constant:-16],
        [descLabel.bottomAnchor constraintEqualToAnchor:aboutContainer.bottomAnchor constant:-16],
    ]];
    [section addCellView:aboutContainer];
    [_mainStack addArrangedSubview:section];
}

- (void)buildDataSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Data"];

    __weak typeof(self) weakSelf = self;

    MiOSNavigationCell *resetCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Reset All Settings"
             subtitle:@"Erase all miOS data and preferences"
                 icon:@"trash.fill"
                color:[MiOSTheme destructive]];
    resetCell.tapAction = ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset All Settings"
            message:@"This will erase all miOS data including containers, GPS settings, and app configurations. This cannot be undone."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Erase All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/Library/Preferences/MiOS" error:nil];
            UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
            [h impactOccurred];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    };
    [section addCellView:resetCell];
    [section addSeparator];

    MiOSNavigationCell *respringCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Respring"
             subtitle:@"Restart SpringBoard to apply changes"
                 icon:@"arrow.clockwise"
                color:[UIColor systemOrangeColor]];
    respringCell.tapAction = ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring"
            message:@"Restart SpringBoard to apply changes?"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [weakSelf respring];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:alert animated:YES completion:nil];
    };
    [section addCellView:respringCell];

    [_mainStack addArrangedSubview:section];
}

- (void)respring {
    NSArray *killallPaths = @[@"/usr/bin/killall", @"/var/jb/usr/bin/killall"];
    NSString *killall = nil;
    for (NSString *path in killallPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            killall = path;
            break;
        }
    }
    if (!killall) killall = @"/usr/bin/killall";

    const char *args[] = { killall.UTF8String, "-9", "SpringBoard", NULL };
    pid_t pid;
    posix_spawn(&pid, killall.UTF8String, NULL, NULL, (char *const *)args, environ);
}

- (void)buildInfoSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    UIView *footerContainer = [[UIView alloc] init];
    footerContainer.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *footerLabel = [[UILabel alloc] init];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = @"miOS v1.0.0\nApp Containerization & GPS Spoofing";
    footerLabel.font = [MiOSTheme captionFont];
    footerLabel.textColor = [MiOSTheme tertiaryText];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.numberOfLines = 0;
    [footerContainer addSubview:footerLabel];

    [NSLayoutConstraint activateConstraints:@[
        [footerLabel.topAnchor constraintEqualToAnchor:footerContainer.topAnchor constant:12],
        [footerLabel.centerXAnchor constraintEqualToAnchor:footerContainer.centerXAnchor],
        [footerLabel.bottomAnchor constraintEqualToAnchor:footerContainer.bottomAnchor constant:-12],
    ]];
    [section addCellView:footerContainer];
    [_mainStack addArrangedSubview:section];
}

@end
