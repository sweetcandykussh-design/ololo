#import <Foundation/Foundation.h>

// Talks to the privileged miosd daemon (which creates/switches/deletes real OS containers).
// The app is not root, so all container manipulation goes through the daemon.
@interface MiOSContainerDaemonClient : NSObject
+ (void)createContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps;
+ (void)switchToContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps relaunch:(BOOL)relaunch;
+ (void)deleteContainer:(NSString *)logicalID forApps:(NSArray<NSString *> *)apps;
@end
