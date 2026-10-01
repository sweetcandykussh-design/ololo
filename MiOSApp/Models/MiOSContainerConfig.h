#import <Foundation/Foundation.h>

@interface MiOSContainerConfig : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<NSString *> *apps;
// GPS
@property (nonatomic, assign) BOOL gpsEnabled;
@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, copy) NSString *locationName;
// Device
@property (nonatomic, assign) BOOL deviceSpoofEnabled;
@property (nonatomic, copy) NSString *deviceIdentifier;
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic, copy) NSString *hwModel;
@property (nonatomic, copy) NSString *iosVersion;
@property (nonatomic, assign) NSInteger storageSizeGB;
@property (nonatomic, copy) NSString *customDeviceName;
@property (nonatomic, assign) BOOL spoofDeviceName;
// Hardware (RAM/CPU/chip). 0/empty = derive automatically from the chosen model.
@property (nonatomic, assign) NSInteger ramGB;
@property (nonatomic, assign) NSInteger cpuCores;
@property (nonatomic, copy) NSString *chipName;
// Carrier. Empty values are derived automatically when spoofCarrier is on.
@property (nonatomic, assign) BOOL spoofCarrier;
@property (nonatomic, copy) NSString *carrierName;
@property (nonatomic, copy) NSString *carrierMCC;
@property (nonatomic, copy) NSString *carrierMNC;
@property (nonatomic, copy) NSString *carrierISO;
// Wi-Fi. Empty values are derived automatically when spoofWiFi is on.
@property (nonatomic, assign) BOOL spoofWiFi;
@property (nonatomic, copy) NSString *wifiSSID;
@property (nonatomic, copy) NSString *wifiBSSID;
// Battery.
@property (nonatomic, assign) BOOL spoofBattery;
@property (nonatomic, assign) NSInteger batteryLevel;   // 0-100
@property (nonatomic, assign) BOOL batteryCharging;
// Locale / time zone.
@property (nonatomic, assign) BOOL spoofLocale;
@property (nonatomic, copy) NSString *localeID;
@property (nonatomic, copy) NSString *timeZoneID;
// Identifiers
@property (nonatomic, assign) BOOL spoofDeviceCheck;
@property (nonatomic, assign) BOOL spoofVendorID;
@property (nonatomic, copy) NSString *vendorID;
@property (nonatomic, assign) BOOL spoofAdvertisingID;
@property (nonatomic, copy) NSString *advertisingID;
@property (nonatomic, assign) BOOL spoofCloudToken;

+ (NSArray<MiOSContainerConfig *> *)loadAll;
+ (void)saveAll:(NSArray<MiOSContainerConfig *> *)containers;
+ (NSString *)activeContainerID;
+ (void)setActiveContainerID:(NSString *)containerID;
// The container marked active, falling back to the first one.
+ (MiOSContainerConfig *)activeContainer;
// Deletes the container from the saved list and the system (mappings + data); picks a new active one if needed.
+ (void)removeContainerWithID:(NSString *)containerID;
- (NSDictionary *)toDictionary;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (void)applyToSystem;
@end
