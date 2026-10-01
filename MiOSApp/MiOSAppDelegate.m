#import "MiOSAppDelegate.h"
#import "Views/MiOSLoadingView.h"
#import "Controllers/MiOSTabBarController.h"
#import "UI/MiOSTheme.h"

@implementation MiOSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    MiOSTabBarController *tabBar = [[MiOSTabBarController alloc] init];

    self.window.rootViewController = tabBar;
    self.window.tintColor = [MiOSTheme accentColor];
    self.window.backgroundColor = [MiOSTheme primaryBackground];
    [self.window makeKeyAndVisible];

    MiOSLoadingView *loadingView = [[MiOSLoadingView alloc] initWithFrame:self.window.bounds];
    loadingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.window addSubview:loadingView];

    __weak typeof(loadingView) weakLoading = loadingView;
    loadingView.onComplete = ^{
        [weakLoading removeFromSuperview];
    };

    [loadingView startAnimation];

    return YES;
}

@end
