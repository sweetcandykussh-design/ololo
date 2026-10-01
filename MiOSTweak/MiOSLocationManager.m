#import "MiOSLocationManager.h"

static NSString *const kMiOSPrefsPath = @"/var/mobile/Library/Preferences/MiOS";
static NSString *const kMiOSLocationPrefs = @"com.mios.locationprefs.plist";
static NSString *const kMiOSSavedLocations = @"com.mios.savedlocations.plist";

@implementation MiOSLocationManager

+ (instancetype)sharedManager {
    static MiOSLocationManager *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[MiOSLocationManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    if (self = [super init]) {
        _enabled = NO;
        _spoofedCoordinate = CLLocationCoordinate2DMake(0, 0);
        _spoofedAltitude = 0;
        _spoofedSpeed = -1;
        _spoofedCourse = -1;
        _spoofedAccuracy = 5.0;
        [self loadPreferences];
    }
    return self;
}

- (void)loadPreferences {
    NSString *path = [kMiOSPrefsPath stringByAppendingPathComponent:kMiOSLocationPrefs];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    if (!prefs) return;

    _enabled = [prefs[@"enabled"] boolValue];
    _spoofedCoordinate = CLLocationCoordinate2DMake(
        [prefs[@"latitude"] doubleValue],
        [prefs[@"longitude"] doubleValue]
    );
    _spoofedAltitude = [prefs[@"altitude"] doubleValue];
    _spoofedSpeed = [prefs[@"speed"] doubleValue] ?: -1;
    _spoofedCourse = [prefs[@"course"] doubleValue] ?: -1;
    _spoofedAccuracy = [prefs[@"accuracy"] doubleValue] ?: 5.0;
    _targetBundleID = prefs[@"targetBundleID"];
}

- (void)savePreferences {
    NSString *path = [kMiOSPrefsPath stringByAppendingPathComponent:kMiOSLocationPrefs];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kMiOSPrefsPath]) {
        [fm createDirectoryAtPath:kMiOSPrefsPath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDictionary *prefs = @{
        @"enabled": @(_enabled),
        @"latitude": @(_spoofedCoordinate.latitude),
        @"longitude": @(_spoofedCoordinate.longitude),
        @"altitude": @(_spoofedAltitude),
        @"speed": @(_spoofedSpeed),
        @"course": @(_spoofedCourse),
        @"accuracy": @(_spoofedAccuracy),
        @"targetBundleID": _targetBundleID ?: @""
    };
    [prefs writeToFile:path atomically:YES];
}

- (CLLocation *)spoofedLocation {
    return [[CLLocation alloc] initWithCoordinate:_spoofedCoordinate
                                         altitude:_spoofedAltitude
                               horizontalAccuracy:_spoofedAccuracy
                                 verticalAccuracy:_spoofedAccuracy
                                           course:_spoofedCourse
                                            speed:_spoofedSpeed
                                        timestamp:[NSDate date]];
}

- (BOOL)shouldSpoofForBundleID:(NSString *)bundleID {
    if (!_enabled) return NO;
    if (!_targetBundleID || _targetBundleID.length == 0) return YES;
    return [_targetBundleID isEqualToString:bundleID];
}

- (NSDictionary *)savedLocations {
    NSString *path = [kMiOSPrefsPath stringByAppendingPathComponent:kMiOSSavedLocations];
    return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}

- (void)saveLocationWithName:(NSString *)name coordinate:(CLLocationCoordinate2D)coord {
    NSString *path = [kMiOSPrefsPath stringByAppendingPathComponent:kMiOSSavedLocations];
    NSMutableDictionary *saved = [[self savedLocations] mutableCopy];
    saved[name] = @{@"latitude": @(coord.latitude), @"longitude": @(coord.longitude)};
    [saved writeToFile:path atomically:YES];
}

- (void)deleteSavedLocation:(NSString *)name {
    NSString *path = [kMiOSPrefsPath stringByAppendingPathComponent:kMiOSSavedLocations];
    NSMutableDictionary *saved = [[self savedLocations] mutableCopy];
    [saved removeObjectForKey:name];
    [saved writeToFile:path atomically:YES];
}

@end
