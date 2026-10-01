#import <UIKit/UIKit.h>

@class MiOSContainerConfig;

typedef NS_ENUM(NSInteger, MiOSEditorEntry) {
    MiOSEditorEntryFull = 0,   // apps, then spoofing settings
    MiOSEditorEntryApps,       // app selection only; saves straight from step 1
    MiOSEditorEntrySpoofing,   // opens directly on the spoofing settings
};

@interface MiOSContainerCreateViewController : UIViewController
@property (nonatomic, strong) MiOSContainerConfig *editingContainer;
@property (nonatomic, assign) MiOSEditorEntry entry;
@property (nonatomic, copy) void (^onSave)(void);
@end
