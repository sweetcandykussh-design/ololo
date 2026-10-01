#import "MiOSTabBarController.h"
#import "MiOSHomeViewController.h"
#import "MiOSContainerListViewController.h"
#import "MiOSCloudViewController.h"
#import "MiOSProxiesViewController.h"
#import "MiOSSettingsViewController.h"
#import "../Views/MiOSFloatingTabBar.h"
#import "../UI/MiOSTheme.h"
#import "../Utils/MiOSAppIconProvider.h"

@implementation MiOSTabBarController {
    MiOSFloatingTabBar *_floatingBar;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [MiOSAppIconProvider applyThemeForActiveContainer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange)
                                                 name:MiOSThemeDidChangeNotification object:nil];

    self.viewControllers = @[
        [self wrap:[[MiOSHomeViewController alloc] init]],
        [self wrap:[[MiOSContainerListViewController alloc] init]],
        [self wrap:[[MiOSCloudViewController alloc] init]],
        [self wrap:[[MiOSProxiesViewController alloc] init]],
        [self wrap:[[MiOSSettingsViewController alloc] init]],
    ];

    self.tabBar.hidden = YES;
    // Children lay out above the floating bar (the home-indicator inset is already in the safe area).
    self.additionalSafeAreaInsets = UIEdgeInsetsMake(0, 0, MiOSFloatingTabBar.contentHeight - 8, 0);

    _floatingBar = [[MiOSFloatingTabBar alloc]
        initWithTitles:@[@"Home", @"Containers", @"Cloud", @"Proxies", @"Settings"]
                 icons:@[@"house.fill", @"square.stack.3d.up.fill", @"cloud.fill",
                         @"antenna.radiowaves.left.and.right", @"gearshape.fill"]];
    _floatingBar.selectedIndex = 0;
    __weak typeof(self) weakSelf = self;
    _floatingBar.onSelect = ^(NSInteger index) {
        [weakSelf selectTab:index];
    };
    [self.view addSubview:_floatingBar];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)themeDidChange {
    UIColor *accent = [MiOSTheme accentColor];
    self.view.window.tintColor = accent;
    for (UINavigationController *nav in self.viewControllers) {
        if ([nav isKindOfClass:[UINavigationController class]]) nav.navigationBar.tintColor = accent;
    }
}

- (UINavigationController *)wrap:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.navigationBar.tintColor = [MiOSTheme accentColor];
    [MiOSTheme styleNavigationBar:nav.navigationBar];
    return nav;
}

- (void)selectTab:(NSInteger)index {
    if (index == (NSInteger)self.selectedIndex) {
        UINavigationController *nav = (UINavigationController *)self.selectedViewController;
        if ([nav isKindOfClass:[UINavigationController class]]) [nav popToRootViewControllerAnimated:YES];
        return;
    }
    self.selectedIndex = index;
    [self.view bringSubviewToFront:_floatingBar];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    self.tabBar.hidden = YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat homeInset = self.view.window ? self.view.window.safeAreaInsets.bottom : 0;
    CGFloat height = MiOSFloatingTabBar.contentHeight + homeInset;
    CGRect bounds = self.view.bounds;
    _floatingBar.frame = CGRectMake(0, bounds.size.height - height, bounds.size.width, height);
    [self.view bringSubviewToFront:_floatingBar];
}

@end
