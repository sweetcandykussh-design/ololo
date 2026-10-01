#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface MiOSLocationManager : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) CLLocationCoordinate2D spoofedCoordinate;
@property (nonatomic, assign) double spoofedAltitude;
@property (nonatomic, assign) double spoofedSpeed;
@property (nonatomic, assign) double spoofedCourse;
@property (nonatomic, assign) double spoofedAccuracy;
@property (nonatomic, copy) NSString *targetBundleID;
+ (instancetype)sharedManager;
- (void)loadPreferences;
- (void)savePreferences;
- (CLLocation *)spoofedLocation;
- (BOOL)shouldSpoofForBundleID:(NSString *)bundleID;
- (NSDictionary *)savedLocations;
- (void)saveLocationWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coord;
- (void)deleteSavedLocation:(NSString *)name;
@end
