#import <UIKit/UIKit.h>

@class MiOSContainerConfig;

// Two-per-row grid of container tiles, shared by Home and the Containers tab.
@interface MiOSContainerGridView : UIView
- (instancetype)initWithContainers:(NSArray<MiOSContainerConfig *> *)containers
                          activeID:(NSString *)activeID
                             onTap:(void (^)(MiOSContainerConfig *container, UIView *tile))onTap;
// Animates the tile away while the remaining tiles slide into place.
- (void)removeContainerWithID:(NSString *)containerID completion:(void (^)(void))completion;
@end
