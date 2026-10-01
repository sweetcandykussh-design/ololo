#import "MiOSContainerConfig.h"
#import "../Utils/MiOSContainerDaemonClient.h"

static NSString *const kContainersPlistPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.containers.plist";

@interface MiOSContainerConfig ()
+ (NSString *)basePath;
+ (NSString *)spoofPrefsPathForUUID:(NSString *)uuid;
- (void)removeFromSystem;
- (NSDictionary *)spoofPrefsDictionary;
@end

@implementation MiOSContainerConfig

#pragma mark - Class Methods

+ (NSString *)_ensureDirectoryForPath:(NSString *)path {
    NSString *dir = [path stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return path;
}

+ (NSDictionary *)_readPlist {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:kContainersPlistPath]) {
        return [NSDictionary dictionaryWithContentsOfFile:kContainersPlistPath] ?: @{};
    }
    return @{};
}

+ (void)_writePlist:(NSDictionary *)dict {
    [self _ensureDirectoryForPath:kContainersPlistPath];
    [dict writeToFile:kContainersPlistPath atomically:YES];
}

+ (NSArray<MiOSContainerConfig *> *)loadAll {
    NSDictionary *plist = [self _readPlist];
    NSArray *containerDicts = plist[@"containers"] ?: @[];

    NSMutableArray<MiOSContainerConfig *> *result = [NSMutableArray array];
    for (NSDictionary *dict in containerDicts) {
        MiOSContainerConfig *config = [[MiOSContainerConfig alloc] initWithDictionary:dict];
        [result addObject:config];
    }
    return [result copy];
}

+ (void)saveAll:(NSArray<MiOSContainerConfig *> *)containers {
    NSMutableArray *dicts = [NSMutableArray array];
    for (MiOSContainerConfig *config in containers) {
        [dicts addObject:[config toDictionary]];
    }

    NSDictionary *plist = [self _readPlist];
    NSMutableDictionary *updated = [plist mutableCopy];
    updated[@"containers"] = dicts;
    [self _writePlist:updated];
}

+ (NSString *)activeContainerID {
    NSDictionary *plist = [self _readPlist];
    return plist[@"activeContainerID"];
}

+ (void)setActiveContainerID:(NSString *)containerID {
    NSMutableDictionary *plist = [[self _readPlist] mutableCopy];
    if (containerID) {
        plist[@"activeContainerID"] = containerID;
    } else {
        [plist removeObjectForKey:@"activeContainerID"];
    }
    [self _writePlist:plist];
}

+ (MiOSContainerConfig *)activeContainer {
    NSArray<MiOSContainerConfig *> *all = [self loadAll];
    NSString *activeID = [self activeContainerID];
    for (MiOSContainerConfig *c in all) {
        if ([c.identifier isEqualToString:activeID]) return c;
    }
    return all.firstObject;
}

+ (void)removeContainerWithID:(NSString *)containerID {
    if (containerID.length == 0) return;
    NSMutableArray<MiOSContainerConfig *> *all = [[self loadAll] mutableCopy];
    MiOSContainerConfig *removed = nil;
    for (MiOSContainerConfig *c in all) {
        if ([c.identifier isEqualToString:containerID]) {
            removed = c;
            break;
        }
    }
    if (!removed) return;

    [removed removeFromSystem];
    [all removeObject:removed];
    [self saveAll:all];

    if ([[self activeContainerID] isEqualToString:containerID]) {
        MiOSContainerConfig *next = all.firstObject;
        [self setActiveContainerID:next.identifier];
        [next applyToSystem];
    }
}

- (void)removeFromSystem {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *containerPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.containerprefs.plist";
    NSMutableDictionary *containerPrefs = [NSMutableDictionary dictionaryWithContentsOfFile:containerPrefsPath];
    NSMutableDictionary *activeContainers = [NSMutableDictionary dictionaryWithDictionary:containerPrefs[@"activeContainers"] ?: @{}];

    for (NSString *bundleID in self.apps) {
        if ([activeContainers[bundleID] isEqualToString:self.identifier]) {
            [activeContainers removeObjectForKey:bundleID];
        }
    }
    [fm removeItemAtPath:[[self class] spoofPrefsPathForUUID:self.identifier] error:nil];

    // If this container was driving the system identity (Settings), stop doing so.
    NSString *systemSpoofPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.systemspoof.plist";
    NSMutableDictionary *sys = [NSMutableDictionary dictionaryWithContentsOfFile:systemSpoofPath];
    if ([sys[@"uuid"] isEqualToString:self.identifier]) {
        sys[@"enabled"] = @NO;
        [sys writeToFile:systemSpoofPath atomically:YES];
    }

    // The real OS container is owned by the daemon; ask it to destroy this one.
    [MiOSContainerDaemonClient deleteContainer:self.identifier forApps:self.apps];

    if (containerPrefs) {
        containerPrefs[@"activeContainers"] = activeContainers;
        [containerPrefs writeToFile:containerPrefsPath atomically:YES];
    }
}

#pragma mark - Serialization

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _identifier = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
        _name = dict[@"name"] ?: @"Untitled";
        _apps = [NSMutableArray arrayWithArray:dict[@"apps"] ?: @[]];

        // GPS
        _gpsEnabled = [dict[@"gpsEnabled"] boolValue];
        _latitude = [dict[@"latitude"] doubleValue];
        _longitude = [dict[@"longitude"] doubleValue];
        _locationName = dict[@"locationName"] ?: @"";

        // Device
        _deviceSpoofEnabled = [dict[@"deviceSpoofEnabled"] boolValue];
        _deviceIdentifier = dict[@"deviceIdentifier"] ?: @"";
        _deviceName = dict[@"deviceName"] ?: @"";
        _hwModel = dict[@"hwModel"] ?: @"";
        _iosVersion = dict[@"iosVersion"] ?: @"";
        _storageSizeGB = [dict[@"storageSizeGB"] integerValue];
        _customDeviceName = dict[@"customDeviceName"] ?: @"";
        _spoofDeviceName = [dict[@"spoofDeviceName"] boolValue];

        // Hardware
        _ramGB = [dict[@"ramGB"] integerValue];
        _cpuCores = [dict[@"cpuCores"] integerValue];
        _chipName = dict[@"chipName"] ?: @"";

        // Carrier
        _spoofCarrier = [dict[@"spoofCarrier"] boolValue];
        _carrierName = dict[@"carrierName"] ?: @"";
        _carrierMCC = dict[@"carrierMCC"] ?: @"";
        _carrierMNC = dict[@"carrierMNC"] ?: @"";
        _carrierISO = dict[@"carrierISO"] ?: @"";

        // Wi-Fi
        _spoofWiFi = [dict[@"spoofWiFi"] boolValue];
        _wifiSSID = dict[@"wifiSSID"] ?: @"";
        _wifiBSSID = dict[@"wifiBSSID"] ?: @"";

        // Battery
        _spoofBattery = [dict[@"spoofBattery"] boolValue];
        _batteryLevel = dict[@"batteryLevel"] ? [dict[@"batteryLevel"] integerValue] : 100;
        _batteryCharging = [dict[@"batteryCharging"] boolValue];

        // Locale / time zone
        _spoofLocale = [dict[@"spoofLocale"] boolValue];
        _localeID = dict[@"localeID"] ?: @"";
        _timeZoneID = dict[@"timeZoneID"] ?: @"";

        // Identifiers
        _spoofDeviceCheck = [dict[@"spoofDeviceCheck"] boolValue];
        _spoofVendorID = [dict[@"spoofVendorID"] boolValue];
        _vendorID = dict[@"vendorID"] ?: @"";
        _spoofAdvertisingID = [dict[@"spoofAdvertisingID"] boolValue];
        _advertisingID = dict[@"advertisingID"] ?: @"";
        _spoofCloudToken = [dict[@"spoofCloudToken"] boolValue];
    }
    return self;
}

- (NSDictionary *)toDictionary {
    return @{
        @"id": self.identifier ?: @"",
        @"name": self.name ?: @"",
        @"apps": self.apps ?: @[],
        @"gpsEnabled": @(self.gpsEnabled),
        @"latitude": @(self.latitude),
        @"longitude": @(self.longitude),
        @"locationName": self.locationName ?: @"",
        @"deviceSpoofEnabled": @(self.deviceSpoofEnabled),
        @"deviceIdentifier": self.deviceIdentifier ?: @"",
        @"deviceName": self.deviceName ?: @"",
        @"hwModel": self.hwModel ?: @"",
        @"iosVersion": self.iosVersion ?: @"",
        @"storageSizeGB": @(self.storageSizeGB),
        @"customDeviceName": self.customDeviceName ?: @"",
        @"spoofDeviceName": @(self.spoofDeviceName),
        @"ramGB": @(self.ramGB),
        @"cpuCores": @(self.cpuCores),
        @"chipName": self.chipName ?: @"",
        @"spoofCarrier": @(self.spoofCarrier),
        @"carrierName": self.carrierName ?: @"",
        @"carrierMCC": self.carrierMCC ?: @"",
        @"carrierMNC": self.carrierMNC ?: @"",
        @"carrierISO": self.carrierISO ?: @"",
        @"spoofWiFi": @(self.spoofWiFi),
        @"wifiSSID": self.wifiSSID ?: @"",
        @"wifiBSSID": self.wifiBSSID ?: @"",
        @"spoofBattery": @(self.spoofBattery),
        @"batteryLevel": @(self.batteryLevel),
        @"batteryCharging": @(self.batteryCharging),
        @"spoofLocale": @(self.spoofLocale),
        @"localeID": self.localeID ?: @"",
        @"timeZoneID": self.timeZoneID ?: @"",
        @"spoofDeviceCheck": @(self.spoofDeviceCheck),
        @"spoofVendorID": @(self.spoofVendorID),
        @"vendorID": self.vendorID ?: @"",
        @"spoofAdvertisingID": @(self.spoofAdvertisingID),
        @"advertisingID": self.advertisingID ?: @"",
        @"spoofCloudToken": @(self.spoofCloudToken),
    };
}

#pragma mark - Apply to System

+ (NSString *)basePath {
    return @"/var/mobile/Library/Preferences/MiOS";
}

// Per-container spoof settings, read by the tweak inside each target app.
+ (NSString *)spoofPrefsPathForUUID:(NSString *)uuid {
    return [[[[self basePath] stringByAppendingPathComponent:@"spoof"]
             stringByAppendingPathComponent:uuid]
            stringByAppendingPathExtension:@"plist"];
}

- (NSDictionary *)spoofPrefsDictionary {
    return @{
        @"spoofDeviceCheck": @(self.spoofDeviceCheck),
        @"spoofVendorID": @(self.spoofVendorID),
        @"vendorID": self.vendorID ?: @"",
        @"spoofAdvertisingID": @(self.spoofAdvertisingID),
        @"advertisingID": self.advertisingID ?: @"",
        @"spoofCloudToken": @(self.spoofCloudToken),
        @"gpsEnabled": @(self.gpsEnabled),
        @"latitude": @(self.latitude),
        @"longitude": @(self.longitude),
        @"deviceSpoofEnabled": @(self.deviceSpoofEnabled),
        @"deviceIdentifier": self.deviceIdentifier ?: @"",
        @"deviceName": self.deviceName ?: @"",
        @"hwModel": self.hwModel ?: @"",
        @"iosVersion": self.iosVersion ?: @"",
        @"storageSizeGB": @(self.storageSizeGB),
        @"customDeviceName": self.customDeviceName ?: @"",
        @"spoofDeviceName": @(self.spoofDeviceName),
        @"ramGB": @(self.ramGB),
        @"cpuCores": @(self.cpuCores),
        @"chipName": self.chipName ?: @"",
        @"spoofCarrier": @(self.spoofCarrier),
        @"carrierName": self.carrierName ?: @"",
        @"carrierMCC": self.carrierMCC ?: @"",
        @"carrierMNC": self.carrierMNC ?: @"",
        @"carrierISO": self.carrierISO ?: @"",
        @"spoofWiFi": @(self.spoofWiFi),
        @"wifiSSID": self.wifiSSID ?: @"",
        @"wifiBSSID": self.wifiBSSID ?: @"",
        @"spoofBattery": @(self.spoofBattery),
        @"batteryLevel": @(self.batteryLevel),
        @"batteryCharging": @(self.batteryCharging),
        @"spoofLocale": @(self.spoofLocale),
        @"localeID": self.localeID ?: @"",
        @"timeZoneID": self.timeZoneID ?: @"",
    };
}

- (void)applyToSystem {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *base = [[self class] basePath];
    NSString *appPlistDir = [base stringByAppendingPathComponent:@"apps"];
    NSString *spoofDir = [base stringByAppendingPathComponent:@"spoof"];
    [fm createDirectoryAtPath:appPlistDir withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:spoofDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *containerPrefsPath = [base stringByAppendingPathComponent:@"com.mios.containerprefs.plist"];
    NSMutableDictionary *containerPrefs = [NSMutableDictionary dictionaryWithContentsOfFile:containerPrefsPath] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *activeContainers = [NSMutableDictionary dictionaryWithDictionary:containerPrefs[@"activeContainers"] ?: @{}];

    // Per-container spoof settings, read by the tweak. The container's file data is created
    // by the tweak inside each app's own sandbox, so nothing is created cross-sandbox here.
    [[self spoofPrefsDictionary] writeToFile:[[self class] spoofPrefsPathForUUID:self.identifier] atomically:YES];

    for (NSString *bundleID in self.apps) {
        NSString *appPlistPath = [appPlistDir stringByAppendingPathComponent:
                                  [NSString stringWithFormat:@"%@.plist", bundleID]];
        [@{@"containerEnabled": @YES, @"enabled": @YES} writeToFile:appPlistPath atomically:YES];
        activeContainers[bundleID] = self.identifier;
    }

    containerPrefs[@"activeContainers"] = activeContainers;
    [containerPrefs writeToFile:containerPrefsPath atomically:YES];

    // Point the SYSTEM identity (Settings → About, read by the tweak inside com.apple.Preferences) at
    // this container's device when device spoof is on. This is purely an in-process hook target — it
    // does NOT rewrite the on-disk MobileGestalt cache, so there is no bootloop risk.
    NSString *systemSpoofPath = [base stringByAppendingPathComponent:@"com.mios.systemspoof.plist"];
    if (self.deviceSpoofEnabled) {
        [@{@"enabled": @YES, @"uuid": self.identifier ?: @""}
            writeToFile:systemSpoofPath atomically:YES];
    } else {
        // This container does not spoof the device; stop driving the system identity from it.
        NSMutableDictionary *sys = [NSMutableDictionary dictionaryWithContentsOfFile:systemSpoofPath];
        if ([sys[@"uuid"] isEqualToString:self.identifier]) {
            sys[@"enabled"] = @NO;
            [sys writeToFile:systemSpoofPath atomically:YES];
        }
    }

    // Ask the privileged daemon to make this the active REAL container for each app (minting it the
    // first time) and relaunch the app into it. This is the actual file isolation (Crane model).
    [MiOSContainerDaemonClient switchToContainer:self.identifier forApps:self.apps relaunch:YES];
}

@end
