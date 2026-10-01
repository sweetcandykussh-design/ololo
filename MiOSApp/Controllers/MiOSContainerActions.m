#import "MiOSContainerActions.h"
#import "MiOSContainerCreateViewController.h"
#import "../Models/MiOSContainerConfig.h"
#import "../Utils/MiOSAppIconProvider.h"

@implementation MiOSContainerActions

+ (void)presentForContainer:(MiOSContainerConfig *)container
                       from:(UIViewController *)presenter
                 sourceView:(UIView *)sourceView
                 completion:(void (^)(MiOSContainerActionResult))completion {
    NSString *message = [NSString stringWithFormat:@"%lu app%@", (unsigned long)container.apps.count,
                         container.apps.count == 1 ? @"" : @"s"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:container.name
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    BOOL isActive = [[MiOSContainerConfig activeContainer].identifier isEqualToString:container.identifier];
    if (!isActive) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Select as Active" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [MiOSContainerConfig setActiveContainerID:container.identifier];
            [container applyToSystem];
            [MiOSAppIconProvider applyThemeForActiveContainer];
            [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
            if (completion) completion(MiOSContainerActionActivated);
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Edit Container" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        MiOSContainerCreateViewController *editor = [[MiOSContainerCreateViewController alloc] init];
        editor.editingContainer = container;
        editor.onSave = ^{
            if (completion) completion(MiOSContainerActionEdited);
        };
        editor.modalPresentationStyle = UIModalPresentationPageSheet;
        [presenter presentViewController:editor animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Remove Container" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [MiOSContainerConfig removeContainerWithID:container.identifier];
        [MiOSAppIconProvider applyThemeForActiveContainer];
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        if (completion) completion(MiOSContainerActionRemoved);
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = sourceView ?: presenter.view;
        sheet.popoverPresentationController.sourceRect = (sourceView ?: presenter.view).bounds;
    }
    [presenter presentViewController:sheet animated:YES completion:nil];
}

@end
