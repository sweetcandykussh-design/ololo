#import <Foundation/Foundation.h>

@interface MiOSDeviceModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *hwModel;
@property (nonatomic, copy) NSString *minIOS;
@property (nonatomic, copy) NSString *maxIOS;
@property (nonatomic, copy) NSString *sfSymbol;
@property (nonatomic, copy) NSString *chipName;
@property (nonatomic, assign) NSInteger ramGB;
@property (nonatomic, assign) NSInteger cpuCores;
@property (nonatomic, strong) NSArray<NSNumber *> *storageOptions;
@end

@interface MiOSDeviceDatabase : NSObject
+ (NSArray<MiOSDeviceModel *> *)allDevices;
+ (MiOSDeviceModel *)deviceForIdentifier:(NSString *)identifier;
+ (NSArray<NSString *> *)supportedIOSVersionsForDevice:(MiOSDeviceModel *)device;
+ (NSArray<NSString *> *)allIOSVersions;
@end
