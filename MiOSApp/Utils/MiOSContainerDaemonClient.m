#import "MiOSContainerDaemonClient.h"
#import <notify.h>

static NSString *const kBase = @"/var/mobile/Library/Preferences/MiOS";
static NSString *const kRequestNote = @"com.mios.containerd.request";

@implementation MiOSContainerDaemonClient

+ (void)sendOp:(NSString *)op logicalID:(NSString *)logicalID apps:(NSArray<NSString *> *)apps relaunch:(BOOL)relaunch {
    if (apps.count == 0 || logicalID.length == 0) return;
    NSString *token = [NSUUID UUID].UUIDString;
    NSDictionary *req = @{
        @"token": token,
        @"op": op,
        @"logicalID": logicalID,
        @"apps": apps,
        @"relaunch": @(relaunch),
    };
    [[NSFileManager defaultManager] createDirectoryAtPath:kBase withIntermediateDirectories:YES attributes:nil error:nil];
    [req writeToFile:[kBase stringByAppendingPathComponent:@"daemon_request.plist"] atomically:YES];
    notify_post(kRequestNote.UTF8String);
}

+ (void)createContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps {
    [self sendOp:@"create" logicalID:logicalID apps:apps relaunch:NO];
}

+ (void)switchToContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps relaunch:(BOOL)relaunch {
    [self sendOp:@"switch" logicalID:logicalID apps:apps relaunch:relaunch];
}

+ (void)deleteContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps {
    [self sendOp:@"delete" logicalID:logicalID apps:apps relaunch:NO];
}

@end
