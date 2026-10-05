#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <errno.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach-o/dyld.h>
#import <libkern/OSByteOrder.h>
#import "MiOSContainerManager.h"
#import "fishhook.h"

// MARK: - Private declarations

typedef int (*libSandy_applyProfile_t)(const char *profileName);

@interface DCDevice : NSObject
@property (class, readonly) DCDevice *currentDevice;
- (void)generateTokenWithCompletionHandler:(void (^)(NSData *, NSError *))completion;
@end

@interface ASIdentifierManager : NSObject
+ (ASIdentifierManager *)sharedManager;
- (NSUUID *)advertisingIdentifier;
- (BOOL)isAdvertisingTrackingEnabled;
@end

// CoreTelephony (carrier)
@interface CTCarrier : NSObject
- (NSString *)carrierName;
- (NSString *)mobileCountryCode;
- (NSString *)mobileNetworkCode;
- (NSString *)isoCountryCode;
- (BOOL)allowsVOIP;
@end

@interface CTTelephonyNetworkInfo : NSObject
- (CTCarrier *)subscriberCellularProvider;
- (NSDictionary<NSString *, CTCarrier *> *)serviceSubscriberCellularProviders;
- (NSString *)currentRadioAccessTechnology;
- (NSDictionary<NSString *, NSString *> *)serviceCurrentRadioAccessTechnology;
@end

// CaptiveNetwork (Wi-Fi) — SystemConfiguration
typedef CFDictionaryRef (*CNCopyCurrentNetworkInfo_t)(CFStringRef interfaceName);

// MARK: - Shared runtime state (resolved once, in the constructor)

static NSString *gBundleID = nil;
static NSDictionary *gSpoof = nil;             // per-container spoof prefs
static NSString *gContainerUUID = nil;         // seed for deterministic per-container derivation
static NSString *gKcPrefix = nil;              // per-container keychain namespace prefix
static BOOL gKeychainIsolation = YES;          // default on: separate keychain per container (sessions)
static BOOL gGroupRedirectActive = NO;         // per-container App Group redirection active

// Cached, allocation-free spoof values (built once in the constructor; owned for process lifetime).
// The low-level C hooks (sysctl / uname / CNCopy...) read ONLY these, never ObjC.
static BOOL      gDeviceSpoofActive = NO;
static char     *gcMachine  = NULL;   // hw.machine / uname.machine  (deviceIdentifier)
static char     *gcModel    = NULL;   // hw.model                    (hwModel)
static uint64_t  gcMemsize  = 0;      // 0 = leave as-is
static int       gcCPU      = 0;      // 0 = leave as-is
static CFDictionaryRef gcWifiInfo     = NULL;   // pre-built SSID/BSSID dict; NULL = don't spoof
// MobileGestalt values, handed out ONLY to callers that resolve MGCopyAnswer via dlsym (e.g. the
// Facebook/Instagram apps). We never hook the real MGCopyAnswer, so CoreTelephony's init path and
// jailbreak-bypass tweaks are untouched.
static CFStringRef gcMGProductType    = NULL;   // ProductType / HWModelStr   (deviceIdentifier)
static CFStringRef gcMGHWModel        = NULL;   // HardwarePlatform           (hwModel)
static CFStringRef gcMGDeviceName     = NULL;   // DeviceName / marketing-name
static CFStringRef gcMGProductVersion = NULL;   // ProductVersion             (iosVersion)
// Hardware-identity keys, derived per-container so each container reports a distinct, STABLE device
// fingerprint (Phase 3 app-side parity). Handed out ONLY through the app-image-scoped MGCopyAnswer
// path, exactly like the four above — system frameworks never see them.
static CFStringRef gcMGSerialNumber   = NULL;   // SerialNumber
static CFStringRef gcMGUDID           = NULL;   // UniqueDeviceID (modern 25-char ECID form)
static CFTypeRef (*gRealMGCopyAnswer)(CFStringRef) = NULL;  // captured before dlsym is hooked

// NOTE: we deliberately do NOT spoof the low-level OS sysctls (kern.osproductversion / kern.osversion /
// kern.osrelease). Apps read those to pick a RUNTIME code path, not just to report a version — faking
// them pushes Facebook/Instagram's pre-main init down an incompatible path and aborts it. The iOS
// version the app REPORTS is covered by the UIDevice / NSProcessInfo / MGCopyAnswer hooks plus the
// first-launch App Group wipe, which force the cached device header to be rebuilt from the spoof.

// Defined lower down; used by the derivation helpers below.
static NSString *derivedHex(NSString *seed, NSString *salt, NSUInteger length);

static BOOL isMiOSEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:
        @"/var/mobile/Library/Preferences/MiOS/com.mios.core.plist"];
    return [prefs[@"enabled"] boolValue];
}

static BOOL deviceSpoofEnabled(void) {
    return [gSpoof[@"deviceSpoofEnabled"] boolValue];
}

static NSString *spoofStr(NSString *key) {
    id v = gSpoof[key];
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

static BOOL spoofBool(NSString *key) {
    return [gSpoof[key] boolValue];
}

static NSInteger spoofInt(NSString *key) {
    return [gSpoof[key] integerValue];
}

// Each spoof honours its own toggle from the container editor.
static BOOL carrierSpoofActive(void) { return spoofBool(@"spoofCarrier"); }
static BOOL wifiSpoofActive(void)    { return spoofBool(@"spoofWiFi"); }
static BOOL batterySpoofActive(void) { return spoofBool(@"spoofBattery"); }
static BOOL localeSpoofActive(void)  { return spoofBool(@"spoofLocale"); }

// MARK: - Deterministic per-container derivation (so each container looks like a distinct device)

static NSString *derivedPick(NSString *salt, NSArray *options) {
    if (options.count == 0) return @"";
    NSString *hex = derivedHex(gContainerUUID, salt, 8);
    unsigned long v = (unsigned long)strtoull(hex.UTF8String, NULL, 16);
    return options[v % options.count];
}

// {name, mcc, mnc, iso}
static NSArray *derivedCarrierTuple(void) {
    static NSArray *carriers = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        carriers = @[
            @[@"Verizon",  @"311", @"480", @"us"],
            @[@"AT&T",     @"310", @"410", @"us"],
            @[@"T-Mobile", @"310", @"260", @"us"],
            @[@"Vodafone", @"234", @"15",  @"gb"],
            @[@"O2",       @"234", @"10",  @"gb"],
            @[@"Orange",   @"208", @"01",  @"fr"],
            @[@"Telekom",  @"262", @"01",  @"de"],
            @[@"MTS",      @"250", @"01",  @"ru"],
            @[@"Beeline",  @"250", @"99",  @"ru"],
        ];
    });
    NSString *hex = derivedHex(gContainerUUID, @"carrier", 8);
    unsigned long v = (unsigned long)strtoull(hex.UTF8String, NULL, 16);
    return carriers[v % carriers.count];
}

static NSString *carrierField(NSString *explicitKey, NSUInteger tupleIndex) {
    NSString *explicit = spoofStr(explicitKey);
    if (explicit.length > 0) return explicit;
    return derivedCarrierTuple()[tupleIndex];
}

static NSString *derivedBSSID(void) {
    NSString *explicit = spoofStr(@"wifiBSSID");
    if (explicit.length > 0) return explicit;
    NSString *hex = derivedHex(gContainerUUID, @"bssid", 12);
    return [NSString stringWithFormat:@"%c%c:%c%c:%c%c:%c%c:%c%c:%c%c",
        [hex characterAtIndex:0], [hex characterAtIndex:1],
        [hex characterAtIndex:2], [hex characterAtIndex:3],
        [hex characterAtIndex:4], [hex characterAtIndex:5],
        [hex characterAtIndex:6], [hex characterAtIndex:7],
        [hex characterAtIndex:8], [hex characterAtIndex:9],
        [hex characterAtIndex:10], [hex characterAtIndex:11]];
}

static NSString *derivedSSID(void) {
    NSString *explicit = spoofStr(@"wifiSSID");
    if (explicit.length > 0) return explicit;
    NSString *base = derivedPick(@"ssidbase", @[@"Home", @"WiFi", @"Net", @"Linksys", @"NETGEAR", @"TP-Link", @"iPhone"]);
    return [NSString stringWithFormat:@"%@-%@", base, derivedHex(gContainerUUID, @"ssidnum", 4)];
}

// Per-container hardware serial. Explicit prefs win; otherwise a stable 10-char value derived from the
// container UUID (distinct per container, constant across launches). Charset doesn't need to match
// Apple's exactly — apps fingerprint on its stability/uniqueness, not its format.
static NSString *derivedSerial(void) {
    NSString *explicit = spoofStr(@"serialNumber");
    if (explicit.length > 0) return explicit;
    return [@"F" stringByAppendingString:derivedHex(gContainerUUID, @"serial", 9)];
}

// Per-container UniqueDeviceID in the modern 25-char ECID form (8 hex, dash, 16 hex), derived from the
// container UUID so it is distinct and stable per container. Explicit prefs win.
static NSString *derivedUDID(void) {
    NSString *explicit = spoofStr(@"udid");
    if (explicit.length > 0) return explicit;
    return [NSString stringWithFormat:@"%@-%@",
            derivedHex(gContainerUUID, @"udidhi", 8),
            derivedHex(gContainerUUID, @"udidlo", 16)];
}

// MARK: - GPS Location Hooks (per container)

static BOOL locationSpoofEnabled(void) {
    return [gSpoof[@"gpsEnabled"] boolValue];
}

static CLLocationCoordinate2D spoofedCoordinate(void) {
    return CLLocationCoordinate2DMake([gSpoof[@"latitude"] doubleValue], [gSpoof[@"longitude"] doubleValue]);
}

static CLLocation *spoofedLocationObject(void) {
    return [[CLLocation alloc] initWithCoordinate:spoofedCoordinate()
                                         altitude:0
                               horizontalAccuracy:5.0
                                 verticalAccuracy:5.0
                                           course:-1
                                            speed:-1
                                        timestamp:[NSDate date]];
}

%group LocationHooks

%hook CLLocationManager

- (CLLocation *)location {
    if (locationSpoofEnabled()) return spoofedLocationObject();
    return %orig;
}

- (void)startUpdatingLocation {
    %orig;
    if (!locationSpoofEnabled()) return;
    id delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocationManager *mgr = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [delegate locationManager:mgr didUpdateLocations:@[spoofedLocationObject()]];
        });
    }
}

- (void)requestLocation {
    %orig;
    if (!locationSpoofEnabled()) return;
    id delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        CLLocationManager *mgr = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [delegate locationManager:mgr didUpdateLocations:@[spoofedLocationObject()]];
        });
    }
}

%end

%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if (locationSpoofEnabled()) return spoofedCoordinate();
    return %orig;
}

%end

%end // LocationHooks

// MARK: - Device model spoofing (per container)

// Bytes of RAM to report (explicit ramGB, else derived from the model family).
static unsigned long long spoofedMemsize(void) {
    NSInteger gb = spoofInt(@"ramGB");
    if (gb <= 0) gb = [derivedPick(@"ram", @[@"3", @"4", @"6", @"8"]) integerValue];
    if (gb <= 0) gb = 4;
    return (unsigned long long)gb * 1024ULL * 1024ULL * 1024ULL;
}

static NSInteger spoofedCPUCores(void) {
    NSInteger n = spoofInt(@"cpuCores");
    if (n <= 0) n = [derivedPick(@"cpu", @[@"6", @"6", @"8"]) integerValue];
    if (n <= 0) n = 6;
    return n;
}

%group DeviceSpoofHooks

%hook UIDevice

- (NSString *)systemVersion {
    NSString *ver = spoofStr(@"iosVersion");
    return ver.length > 0 ? ver : %orig;
}

- (NSString *)name {
    NSString *custom = spoofStr(@"customDeviceName");
    if ([gSpoof[@"spoofDeviceName"] boolValue] && custom.length > 0) return custom;
    NSString *name = spoofStr(@"deviceName");
    return name.length > 0 ? name : %orig;
}

- (NSString *)model {
    // Keep the generic class ("iPhone"/"iPad") consistent with the spoofed identifier.
    NSString *ident = spoofStr(@"deviceIdentifier");
    if ([ident hasPrefix:@"iPad"]) return @"iPad";
    if ([ident hasPrefix:@"iPod"]) return @"iPod touch";
    if ([ident hasPrefix:@"iPhone"]) return @"iPhone";
    return %orig;
}

%end

%hook NSProcessInfo

- (NSOperatingSystemVersion)operatingSystemVersion {
    NSString *ver = spoofStr(@"iosVersion");
    if (ver.length > 0) {
        NSArray *parts = [ver componentsSeparatedByString:@"."];
        NSOperatingSystemVersion v = {0, 0, 0};
        if (parts.count > 0) v.majorVersion = [parts[0] integerValue];
        if (parts.count > 1) v.minorVersion = [parts[1] integerValue];
        if (parts.count > 2) v.patchVersion = [parts[2] integerValue];
        return v;
    }
    return %orig;
}

- (NSString *)operatingSystemVersionString {
    NSString *ver = spoofStr(@"iosVersion");
    if (ver.length > 0) return [NSString stringWithFormat:@"Version %@", ver];
    return %orig;
}

- (unsigned long long)physicalMemory {
    return gcMemsize ? gcMemsize : %orig;
}

- (NSUInteger)processorCount {
    return gcCPU ? (NSUInteger)gcCPU : %orig;
}

- (NSUInteger)activeProcessorCount {
    return gcCPU ? (NSUInteger)gcCPU : %orig;
}

%end

%end // DeviceSpoofHooks

// MARK: - Battery spoofing (per container)

%group BatteryHooks

%hook UIDevice

- (float)batteryLevel {
    NSInteger lvl = spoofInt(@"batteryLevel");
    if (lvl < 0) lvl = 0; if (lvl > 100) lvl = 100;
    return (float)lvl / 100.0f;
}

- (UIDeviceBatteryState)batteryState {
    return spoofBool(@"batteryCharging") ? UIDeviceBatteryStateCharging : UIDeviceBatteryStateUnplugged;
}

%end

%end // BatteryHooks

// MARK: - Locale / time zone spoofing (per container)

%group LocaleHooks

%hook NSTimeZone

+ (NSTimeZone *)localTimeZone {
    NSString *tz = spoofStr(@"timeZoneID");
    NSTimeZone *z = tz.length > 0 ? [NSTimeZone timeZoneWithName:tz] : nil;
    return z ?: %orig;
}

+ (NSTimeZone *)systemTimeZone {
    NSString *tz = spoofStr(@"timeZoneID");
    NSTimeZone *z = tz.length > 0 ? [NSTimeZone timeZoneWithName:tz] : nil;
    return z ?: %orig;
}

%end

%end // LocaleHooks

// MARK: - Carrier spoofing (per container)

%group CarrierHooks

%hook CTCarrier

- (NSString *)carrierName   { return carrierField(@"carrierName", 0); }
- (NSString *)mobileCountryCode { return carrierField(@"carrierMCC", 1); }
- (NSString *)mobileNetworkCode { return carrierField(@"carrierMNC", 2); }
- (NSString *)isoCountryCode    { return carrierField(@"carrierISO", 3); }

%end

%end // CarrierHooks

// MARK: - Identifier spoofing (per container)

%group IdentifierSpoofHooks

%hook UIDevice

- (NSUUID *)identifierForVendor {
    if ([gSpoof[@"spoofVendorID"] boolValue]) {
        NSString *vid = spoofStr(@"vendorID");
        NSUUID *uuid = vid.length > 0 ? [[NSUUID alloc] initWithUUIDString:vid] : nil;
        if (uuid) return uuid;
    }
    return %orig;
}

%end

%hook ASIdentifierManager

- (NSUUID *)advertisingIdentifier {
    if ([gSpoof[@"spoofAdvertisingID"] boolValue]) {
        NSString *aid = spoofStr(@"advertisingID");
        NSUUID *uuid = aid.length > 0 ? [[NSUUID alloc] initWithUUIDString:aid] : nil;
        if (uuid) return uuid;
    }
    return %orig;
}

- (BOOL)isAdvertisingTrackingEnabled {
    if ([gSpoof[@"spoofAdvertisingID"] boolValue]) return NO;
    return %orig;
}

%end

%hook DCDevice

- (void)generateTokenWithCompletionHandler:(void (^)(NSData *, NSError *))completion {
    if ([gSpoof[@"spoofDeviceCheck"] boolValue]) {
        if (completion) {
            completion(nil, [NSError errorWithDomain:@"DCErrorDomain" code:1 userInfo:@{
                NSLocalizedDescriptionKey: @"DeviceCheck is not supported on this device"}]);
        }
        return;
    }
    %orig;
}

%end

%hook NSFileManager

- (id)ubiquityIdentityToken {
    if ([gSpoof[@"spoofCloudToken"] boolValue]) return nil;
    return %orig;
}

%end

%end // IdentifierSpoofHooks

// MARK: - Keychain namespacing (per container, Crane-style)
//
// We inject into the real app, so we cannot switch to a private access group the way
// LiveContainer does. Instead we namespace items inside the app's own access group by
// prefixing the service-like key fields with a per-container tag, and strip the prefix
// back out of returned attributes so the app never sees it.

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);

// Defined further down (in the App Group redirect section); used here for keychain diagnostics and
// for the blanket-identity-query isolation (both run before those functions are defined).
static void miosRedirectLog(NSString *line);
static BOOL miosRedirectDisabled(void);

static NSArray *kcPrefixedKeys(void) {
    // Namespace the primary-key fields so each container sees only its own items. Account is
    // included so session tokens stored per-account (e.g. Instagram) stay isolated per container.
    // Label is included because Facebook/Instagram key their device-id backup item by label, not
    // service/account — without it that item stays shared and the old device-id gets restored.
    return @[(__bridge id)kSecAttrService, (__bridge id)kSecAttrServer,
             (__bridge id)kSecAttrAccount, (__bridge id)kSecAttrLabel];
}

// Returns a copy of dict with service-like fields prefixed; sets *modified if anything changed.
static NSDictionary *kcApplyPrefix(CFDictionaryRef dict, BOOL *modified) {
    if (!dict) return nil;
    NSMutableDictionary *copy = [(__bridge NSDictionary *)dict mutableCopy];
    BOOL changed = NO;
    for (id key in kcPrefixedKeys()) {
        id value = copy[key];
        if ([value isKindOfClass:[NSString class]] && ![value hasPrefix:gKcPrefix]) {
            copy[key] = [gKcPrefix stringByAppendingString:value];
            changed = YES;
        }
    }
    if (modified) *modified = changed;
    return copy;
}

static id kcStripObject(id obj) {
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[obj count]];
        for (id item in obj) [out addObject:kcStripObject(item)];
        return out;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [obj mutableCopy];
        for (id key in kcPrefixedKeys()) {
            id value = out[key];
            if ([value isKindOfClass:[NSString class]] && [value hasPrefix:gKcPrefix]) {
                out[key] = [value substringFromIndex:gKcPrefix.length];
            }
        }
        return out;
    }
    return obj;
}

static void kcStripResult(CFTypeRef *result) {
    if (!result || !*result) return;
    id obj = (__bridge id)*result;
    if (![obj isKindOfClass:[NSArray class]] && ![obj isKindOfClass:[NSDictionary class]]) return;
    id stripped = kcStripObject(obj);
    CFRelease(*result);
    *result = (__bridge_retained CFTypeRef)stripped;
}

// Diagnostic: record how the app keys its keychain items (class/service/account/accessgroup/label),
// so we can see exactly how the device-id backup is stored and whether our prefixing isolates it.
static void miosLogKeychainAttrs(NSString *op, CFDictionaryRef dict) {
    @try {
        NSDictionary *d = (__bridge NSDictionary *)dict;
        if (![d isKindOfClass:[NSDictionary class]]) return;
        NSString *svce = d[(__bridge id)kSecAttrService];
        NSString *acct = d[(__bridge id)kSecAttrAccount];
        NSString *agrp = d[(__bridge id)kSecAttrAccessGroup];
        NSString *labl = d[(__bridge id)kSecAttrLabel];
        id cls = d[(__bridge id)kSecClass];
        miosRedirectLog([NSString stringWithFormat:@"kc %@ class=%@ svce=%@ acct=%@ agrp=%@ labl=%@",
            op, cls, svce ?: @"-", acct ?: @"-", agrp ?: @"-", labl ?: @"-"]);
    } @catch (__unused id e) {}
}

static OSStatus new_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (gGroupRedirectActive) miosLogKeychainAttrs(@"add", attributes);
    BOOL modified = NO;
    NSDictionary *copy = kcApplyPrefix(attributes, &modified);
    if (!modified) return orig_SecItemAdd(attributes, result);
    OSStatus status = orig_SecItemAdd((__bridge CFDictionaryRef)copy, result);
    if (status == errSecParam) return orig_SecItemAdd(attributes, result);
    return status;
}

// Does this access group hold the cross-app device identity shared by the Facebook/Instagram family?
static BOOL kcIsSharedIdentityGroup(id agrp) {
    if (![agrp isKindOfClass:[NSString class]]) return NO;
    NSString *g = agrp;
    return ([g containsString:@"facebook"] || [g containsString:@"burbn"] ||
            [g containsString:@"instagram"] || [g containsString:@"family"]);
}

// Does the query pin down a specific item via one of the fields we namespace? If so, normal prefixing
// already isolates it and we leave it alone.
static BOOL kcQueryNamesPrimaryKey(NSDictionary *q) {
    for (id key in kcPrefixedKeys()) {
        if ([q[key] isKindOfClass:[NSString class]]) return YES;
    }
    return NO;
}

// A blanket enumeration of a shared identity access group (class + access group, but NO service /
// account / label) would return EVERY container's device-id backup plus the original device's — that
// is exactly how the old iPhone-X device-id gets resurrected in a freshly-logged-in container. Return
// ONLY this container's own (prefixed) items, so: (a) the old identity can't leak in, and (b) the app
// still finds the device-id it wrote itself, so it does NOT regenerate one every launch. Returns YES
// when it has fully handled the call. Kill-switchable from Filza (.../MiOS/disable).
static BOOL kcHandleBlanketIdentityQuery(CFDictionaryRef query, CFTypeRef *result, OSStatus *outStatus) {
    if (!(gKeychainIsolation && gKcPrefix.length > 0 && !miosRedirectDisabled())) return NO;
    NSDictionary *q = (__bridge NSDictionary *)query;
    if (![q isKindOfClass:[NSDictionary class]]) return NO;
    if (q[(__bridge id)kSecClass] != (__bridge id)kSecClassGenericPassword &&
        ![q[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassGenericPassword]) return NO;
    if (!kcIsSharedIdentityGroup(q[(__bridge id)kSecAttrAccessGroup])) return NO;
    if (kcQueryNamesPrimaryKey(q)) return NO;   // specific lookups go through normal prefixing

    // Re-run the query asking for attributes + data for ALL matches, so we can filter by our prefix
    // regardless of what the caller asked to receive.
    NSMutableDictionary *probe = [q mutableCopy];
    probe[(__bridge id)kSecReturnAttributes] = @YES;
    probe[(__bridge id)kSecReturnData] = @YES;
    probe[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;
    CFTypeRef raw = NULL;
    OSStatus st = orig_SecItemCopyMatching((__bridge CFDictionaryRef)probe, &raw);
    if (st != errSecSuccess || raw == NULL) {
        if (raw) CFRelease(raw);
        *outStatus = errSecItemNotFound; *result = NULL; return YES;
    }
    NSArray *items = [(__bridge id)raw isKindOfClass:[NSArray class]]
                     ? (__bridge NSArray *)raw : @[(__bridge id)raw];

    BOOL wantAttrs = [q[(__bridge id)kSecReturnAttributes] boolValue];
    BOOL wantData  = [q[(__bridge id)kSecReturnData] boolValue];
    BOOL limitAll  = [q[(__bridge id)kSecMatchLimit] isEqual:(__bridge id)kSecMatchLimitAll];

    NSMutableArray *out = [NSMutableArray array];
    for (id it in items) {
        if (![it isKindOfClass:[NSDictionary class]]) continue;
        BOOL mine = NO;
        for (id key in kcPrefixedKeys()) {
            id v = it[key];
            if ([v isKindOfClass:[NSString class]] && [v hasPrefix:gKcPrefix]) { mine = YES; break; }
        }
        if (!mine) continue;                       // drop other containers' / the original's items
        id stripped = kcStripObject(it);           // remove our prefix before handing back
        if (wantAttrs && wantData)      [out addObject:stripped];
        else if (wantData)              { id d = ((NSDictionary *)stripped)[(__bridge id)kSecValueData]; if (d) [out addObject:d]; }
        else if (wantAttrs)             { NSMutableDictionary *a = [stripped mutableCopy]; [a removeObjectForKey:(__bridge id)kSecValueData]; [out addObject:a]; }
        else                            [out addObject:stripped];
    }
    CFRelease(raw);

    if (out.count == 0) { *outStatus = errSecItemNotFound; *result = NULL; return YES; }
    *result = limitAll ? (__bridge_retained CFTypeRef)out
                       : (__bridge_retained CFTypeRef)out.firstObject;
    *outStatus = errSecSuccess;
    return YES;
}

static OSStatus new_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    OSStatus handled = errSecSuccess;
    if (kcHandleBlanketIdentityQuery(query, result, &handled)) return handled;
    BOOL modified = NO;
    NSDictionary *copy = kcApplyPrefix(query, &modified);
    if (!modified) return orig_SecItemCopyMatching(query, result);
    OSStatus status = orig_SecItemCopyMatching((__bridge CFDictionaryRef)copy, result);
    if (status == errSecParam) return orig_SecItemCopyMatching(query, result);
    if (status == errSecSuccess) kcStripResult(result);
    return status;
}

static OSStatus new_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    BOOL modified = NO;
    NSDictionary *copy = kcApplyPrefix(query, &modified);
    // Prefix the update payload too, so a changed service stays namespaced.
    NSDictionary *attrCopy = kcApplyPrefix(attributesToUpdate, NULL);
    if (!modified) return orig_SecItemUpdate(query, attributesToUpdate);
    OSStatus status = orig_SecItemUpdate((__bridge CFDictionaryRef)copy, (__bridge CFDictionaryRef)attrCopy);
    if (status == errSecParam) return orig_SecItemUpdate(query, attributesToUpdate);
    return status;
}

static OSStatus new_SecItemDelete(CFDictionaryRef query) {
    BOOL modified = NO;
    NSDictionary *copy = kcApplyPrefix(query, &modified);
    if (!modified) return orig_SecItemDelete(query);
    OSStatus status = orig_SecItemDelete((__bridge CFDictionaryRef)copy);
    if (status == errSecParam) return orig_SecItemDelete(query);
    return status;
}

static void miosInitKeychainNamespace(void) {
    MSHookFunction((void *)SecItemAdd, (void *)new_SecItemAdd, (void **)&orig_SecItemAdd);
    MSHookFunction((void *)SecItemCopyMatching, (void *)new_SecItemCopyMatching, (void **)&orig_SecItemCopyMatching);
    MSHookFunction((void *)SecItemUpdate, (void *)new_SecItemUpdate, (void **)&orig_SecItemUpdate);
    MSHookFunction((void *)SecItemDelete, (void *)new_SecItemDelete, (void **)&orig_SecItemDelete);
}


// MARK: - Low-level C hooks (allocation-free)
//
// sysctlbyname / uname / CNCopyCurrentNetworkInfo are plain C functions that can be called extremely
// early and from threads where the Objective-C runtime and autorelease pools are not safe to touch.
// So the hot paths below NEVER allocate or message ObjC: everything is precomputed into plain C
// values in miosBuildSpoofCache() and only memcpy'd / CFRetain'd here.
//
// NOTE: we deliberately DO NOT hook MGCopyAnswer. Ghost (which never crashes) hooks only
// sysctlbyname/uname/getifaddrs/CNCopyCurrentNetworkInfo and merely *reads* MGCopyAnswer. Replacing
// MGCopyAnswer is what triggers the EXC_GUARD mach-port crash, because libMobileGestalt is invoked
// via XPC/mach during very early process + sandbox bring-up. hw.machine via sysctlbyname (plus the
// UIDevice / NSProcessInfo ObjC hooks) is what apps actually read for the device model anyway.

static int (*orig_sysctlbyname)(const char *, void *, size_t *, void *, size_t);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static int (*orig_uname)(struct utsname *);
static CNCopyCurrentNetworkInfo_t orig_CNCopyCurrentNetworkInfo = NULL;

// Return a C string for a sysctl query, correctly handling the length-probe (oldp == NULL) call that
// callers make first to size their buffer — we must report the SPOOFED length, not the real one, or a
// longer spoofed value silently falls back to the real string.
static int replyCString(void *oldp, size_t *oldlenp, const char *cstr) {
    size_t need = strlen(cstr) + 1;
    if (!oldp) {                 // length probe
        if (oldlenp) *oldlenp = need;
        return 0;
    }
    if (oldlenp && *oldlenp < need) { errno = ENOMEM; return -1; }
    memcpy(oldp, cstr, need);
    if (oldlenp) *oldlenp = need;
    return 0;
}

// Writes an integer back matching the width the real call returned (4 or 8 bytes).
static int copyIntOut(void *oldp, size_t *oldlenp, unsigned long long value) {
    if (*oldlenp >= 8) { *(uint64_t *)oldp = (uint64_t)value; *oldlenp = 8; }
    else if (*oldlenp >= 4) { *(uint32_t *)oldp = (uint32_t)value; *oldlenp = 4; }
    return 0;
}

static int hook_sysctlbyname(const char *name, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && gDeviceSpoofActive) {
        if (gcMachine && strcmp(name, "hw.machine") == 0) return replyCString(oldp, oldlenp, gcMachine);
        if (gcModel   && strcmp(name, "hw.model")   == 0) return replyCString(oldp, oldlenp, gcModel);
        if ((gcMemsize || gcCPU) && oldp && oldlenp) {
            int ret = orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
            if (ret != 0) return ret;
            if (gcMemsize && strcmp(name, "hw.memsize") == 0) return copyIntOut(oldp, oldlenp, gcMemsize);
            if (gcCPU && (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.logicalcpu") == 0 ||
                strcmp(name, "hw.logicalcpu_max") == 0 || strcmp(name, "hw.activecpu") == 0 ||
                strcmp(name, "hw.physicalcpu") == 0 || strcmp(name, "hw.physicalcpu_max") == 0)) {
                return copyIntOut(oldp, oldlenp, (unsigned long long)gcCPU);
            }
            return ret;
        }
    }
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

// Raw MIB form: sysctl({CTL_HW, HW_MACHINE/HW_MODEL}, ...). Some device-model readers use this
// directly instead of sysctlbyname.
static int hook_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name && namelen >= 2 && gDeviceSpoofActive && name[0] == CTL_HW) {
        if (gcMachine && name[1] == HW_MACHINE) return replyCString(oldp, oldlenp, gcMachine);
        if (gcModel   && name[1] == HW_MODEL)   return replyCString(oldp, oldlenp, gcModel);
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static int hook_uname(struct utsname *buf) {
    int ret = orig_uname(buf);
    if (ret != 0 || !buf || !gDeviceSpoofActive || !gcMachine) return ret;
    strncpy(buf->machine, gcMachine, sizeof(buf->machine) - 1);
    buf->machine[sizeof(buf->machine) - 1] = '\0';
    return ret;
}

static CFDictionaryRef hook_CNCopyCurrentNetworkInfo(CFStringRef interfaceName) {
    if (gcWifiInfo) return (CFDictionaryRef)CFRetain(gcWifiInfo);
    return orig_CNCopyCurrentNetworkInfo ? orig_CNCopyCurrentNetworkInfo(interfaceName) : NULL;
}

// MARK: - MGCopyAnswer via dlsym (safe: we never patch the real function)

// Our MGCopyAnswer: spoof the device-identity keys, pass everything else to the real function.
static CFTypeRef mios_MGCopyAnswer(CFStringRef key) {
    if (gDeviceSpoofActive && key) {
        if (gcMGProductType && (CFEqual(key, CFSTR("ProductType")) || CFEqual(key, CFSTR("HWModelStr"))))
            return CFRetain(gcMGProductType);
        if (gcMGDeviceName && (CFEqual(key, CFSTR("DeviceName")) || CFEqual(key, CFSTR("marketing-name")) || CFEqual(key, CFSTR("UserAssignedDeviceName"))))
            return CFRetain(gcMGDeviceName);
        if (gcMGHWModel && CFEqual(key, CFSTR("HardwarePlatform")))
            return CFRetain(gcMGHWModel);
        if (gcMGProductVersion && CFEqual(key, CFSTR("ProductVersion")))
            return CFRetain(gcMGProductVersion);
        if (gcMGSerialNumber && CFEqual(key, CFSTR("SerialNumber")))
            return CFRetain(gcMGSerialNumber);
        if (gcMGUDID && (CFEqual(key, CFSTR("UniqueDeviceID")) || CFEqual(key, CFSTR("UniqueDeviceIDData"))))
            return CFRetain(gcMGUDID);
    }
    return gRealMGCopyAnswer ? gRealMGCopyAnswer(key) : NULL;
}

// Intercept dlsym so that an app resolving "MGCopyAnswer" at runtime gets OUR implementation,
// without ever modifying the real libMobileGestalt function (that path crashes CoreTelephony).
static void *(*orig_dlsym)(void *, const char *) = NULL;

static void *new_dlsym(void *handle, const char *symbol) {
    if (symbol && gDeviceSpoofActive && strcmp(symbol, "MGCopyAnswer") == 0 &&
        (gcMGProductType || gcMGProductVersion || gcMGDeviceName || gcMGHWModel ||
         gcMGSerialNumber || gcMGUDID)) {
        return (void *)mios_MGCopyAnswer;
    }
    return orig_dlsym ? orig_dlsym(handle, symbol) : NULL;
}

// Rebind the MGCopyAnswer import pointer to ours.
//
// CONTAINER apps (allImages == NO): rebind ONLY the app's own binaries — the main executable and any
// framework bundled inside the .app (which includes FBSharedFramework). System frameworks
// (CoreTelephony, Shadow, the shared cache) are matched by neither test and left untouched. This is
// critical: feeding a spoofed ProductType/ProductVersion to a SYSTEM framework inside the app (e.g.
// CoreTelephony during its init) sends it down an incompatible code path and crashes the app — the
// same class of failure as spoofing the kern.* sysctls. This is the tested, non-crashing behavior.
//
// SYSTEM-spoof mode (allImages == YES, Settings only): the About pane reads the model name from a
// system framework, so we must rebind every image — current and future (via fishhook's add-image
// callback). We accept the wider surface only here, where there is no app to crash.
//
// fishhook only swaps the caller's import slot (never patches libMobileGestalt's code), and
// mios_MGCopyAnswer passes every key we don't spoof straight through to the real function.
static void miosRebindMG(BOOL allImages) {
    if (allImages) {
        static struct rebinding rb;   // keep alive for the add-image callback (future images)
        rb.name = "MGCopyAnswer";
        rb.replacement = (void *)mios_MGCopyAnswer;
        rb.replaced = NULL;
        rebind_symbols(&rb, 1);
        return;
    }
    struct rebinding rb = { "MGCopyAnswer", (void *)mios_MGCopyAnswer, NULL };
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const struct mach_header *hdr = _dyld_get_image_header(i);
        const char *name = _dyld_get_image_name(i);
        if (!hdr) continue;
        BOOL isMain = (hdr->filetype == MH_EXECUTE);
        BOOL isAppImage = (name != NULL && strstr(name, ".app/") != NULL);  // main exe + embedded frameworks
        if (isMain || isAppImage) {
            rebind_symbols_image((void *)hdr, _dyld_get_image_vmaddr_slide(i), &rb, 1);
        }
    }
}

// MARK: - Derived unique-device identifiers (stable per container)

static NSString *derivedHex(NSString *seed, NSString *salt, NSUInteger length) {
    NSString *combined = [NSString stringWithFormat:@"%@-%@", seed ?: @"", salt];
    unsigned long hash = 1469598103934665603UL; // FNV-1a-ish, deterministic
    const char *bytes = combined.UTF8String;
    for (NSUInteger i = 0; bytes[i]; i++) { hash ^= (unsigned char)bytes[i]; hash *= 1099511628211UL; }
    NSMutableString *out = [NSMutableString string];
    const char *alphabet = "0123456789ABCDEF";
    for (NSUInteger i = 0; i < length; i++) {
        [out appendFormat:@"%c", alphabet[(hash >> ((i % 15) * 4)) & 0xF]];
        hash = hash * 6364136223846793005UL + 1442695040888963407UL;
    }
    return out;
}

// MARK: - Build the allocation-free spoof cache (runs once, in the constructor)

static char *dupCString(NSString *s) {
    if (s.length == 0) return NULL;
    const char *c = s.UTF8String;
    return c ? strdup(c) : NULL;
}

static CFStringRef retainedCF(NSString *s) {
    if (s.length == 0) return NULL;
    return (__bridge_retained CFStringRef)[s copy];
}

static void miosBuildSpoofCache(void) {
    gDeviceSpoofActive = deviceSpoofEnabled();
    if (gDeviceSpoofActive) {
        gcMachine = dupCString(spoofStr(@"deviceIdentifier"));
        gcModel   = dupCString(spoofStr(@"hwModel"));
        gcMemsize = spoofedMemsize();
        gcCPU     = (int)spoofedCPUCores();
        gcMGProductType    = retainedCF(spoofStr(@"deviceIdentifier"));
        gcMGHWModel        = retainedCF(spoofStr(@"hwModel"));
        gcMGDeviceName     = retainedCF(spoofStr(@"deviceName"));
        gcMGProductVersion = retainedCF(spoofStr(@"iosVersion"));
        // Hardware-identity fingerprint: explicit prefs win; otherwise derive a distinct, STABLE value
        // per container so each container looks like its own physical unit (serial + UDID).
        gcMGSerialNumber   = retainedCF(derivedSerial());
        gcMGUDID           = retainedCF(derivedUDID());
    }
    if (wifiSpoofActive()) {
        NSString *ssid  = derivedSSID();
        NSString *bssid = derivedBSSID();
        NSDictionary *info = @{
            @"SSID":     ssid,
            @"BSSID":    bssid,
            @"SSIDDATA": [ssid dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data],
        };
        gcWifiInfo = (__bridge_retained CFDictionaryRef)[info copy];
    }
}

// MARK: - App Group redirection (per-container, in-process — Crane-style but daemon-free)
//
// Crane isolates the App Group by redirecting container-path resolution inside system daemons
// (cfprefsd/containermanagerd). We achieve the same per-container isolation entirely IN-PROCESS, which
// is safe (no system-daemon hooks → cannot destabilise the system or panic the kernel like the
// replaceContainer path did): we rewrite the app's own App Group accesses to a per-container namespace.
//
//   - NSUserDefaults(suiteName:"group.X")      -> suite "group.X__mios_<uuid>"
//   - containerURLForSecurityApplicationGroupIdentifier:"group.X" -> <group>/___MiOS_Containers/<uuid>
//
// So each logical container sees its OWN empty group state on first use: Instagram regenerates its
// device-id/header and registers as the spoofed device (the reason it still showed the old device was
// that every container shared one real group). The REAL group is never modified, so other apps and the
// user's existing data are untouched, and no logout happens (auth lives in the private container).
//
// Kill-switch: create /var/mobile/Library/Preferences/MiOS/disable (e.g. in Filza) to turn redirection
// off instantly with no reboot. Every hook is fail-safe: on any uncertainty it returns the original.

static BOOL miosRedirectDisabled(void) {
    static BOOL disabled = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        disabled = [[NSFileManager defaultManager] fileExistsAtPath:
            @"/var/mobile/Library/Preferences/MiOS/disable"];
    });
    return disabled;
}

// Diagnostic: append a line once per unique message to a per-app log in the central MiOS debug dir
// (libSandy grants access). Lets us see WHERE the app keeps its device-id without a terminal.
static void miosRedirectLog(NSString *line) {
    static NSMutableSet *seen = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    @synchronized (seen) {
        if ([seen containsObject:line]) return;
        [seen addObject:line];
    }
    @try {
        NSString *dir = @"/var/mobile/Library/Preferences/MiOS/debug";
        NSString *path = [dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"redirect_%@.log", gBundleID ?: @"app"]];
        NSString *entry = [NSString stringWithFormat:@"%@  %@\n", [NSDate date], line];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) { [entry writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]; }
        else { @try { [fh seekToEndOfFile]; [fh writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (__unused id e) {} [fh closeFile]; }
    } @catch (__unused id e) {}
}

%group GroupRedirectHooks

%hook NSUserDefaults

- (instancetype)initWithSuiteName:(NSString *)suiteName {
    // Rewrite a real App Group suite to a PRIVATE per-container domain. The scoped name must NOT start
    // with "group." — cfprefsd refuses to persist a group-looking suite the app isn't entitled to, so
    // the old "group.X__mios_<uuid>" scheme silently failed to save and the device-id was regenerated
    // every launch. "mios.<uuid>.group.X" is a normal private domain that persists in the app's prefs.
    if (gGroupRedirectActive && gContainerUUID.length > 0 &&
        [suiteName isKindOfClass:[NSString class]] &&
        [suiteName hasPrefix:@"group."]) {
        miosRedirectLog([NSString stringWithFormat:@"defaults suite=%@ -> scoped", suiteName]);
        NSString *scoped = [NSString stringWithFormat:@"mios.%@.%@", gContainerUUID, suiteName];
        return %orig(scoped);
    }
    return %orig;
}

// Diagnostic only: record where the app stores device-id-ish values (which domain/key), so we can see
// if its identity lives in standardUserDefaults (private container — NOT covered by the group redirect)
// vs a group suite. Does not change behaviour.
- (void)setObject:(id)value forKey:(NSString *)key {
    if (gGroupRedirectActive && [key isKindOfClass:[NSString class]]) {
        NSString *lk = key.lowercaseString;
        if ([lk containsString:@"device"] || [lk containsString:@"guid"] || [lk containsString:@"uuid"] ||
            [lk containsString:@"phone_id"] || [lk containsString:@"pigeon"] || [lk containsString:@"familydevice"] ||
            [lk containsString:@"deviceid"] || [lk containsString:@"device_id"]) {
            miosRedirectLog([NSString stringWithFormat:@"setDefault key=%@ type=%@", key,
                [value isKindOfClass:[NSString class]] ? value : NSStringFromClass([value class])]);
        }
    }
    %orig;
}

%end

%hook NSFileManager

- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupID {
    NSURL *real = %orig;
    if (!gGroupRedirectActive || gContainerUUID.length == 0 || !real) return real;
    miosRedirectLog([NSString stringWithFormat:@"groupURL id=%@ -> scoped", groupID]);
    NSURL *scoped = [[real URLByAppendingPathComponent:@"___MiOS_Containers" isDirectory:YES]
                          URLByAppendingPathComponent:gContainerUUID isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:scoped withIntermediateDirectories:YES
                                              attributes:nil error:nil];
    return scoped;
}

%end

%end // GroupRedirectHooks

// MARK: - Constructor

%ctor {
    @autoreleasepool {
        gBundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (gBundleID.length == 0 || [gBundleID isEqualToString:@"com.mios.app"]) return;

        // Grant the sandbox extension (used for the central-prefs fallback path below).
        void *sandyHandle = dlopen("/usr/lib/libsandy.dylib", RTLD_LAZY);
        if (!sandyHandle) sandyHandle = dlopen("/var/jb/usr/lib/libsandy.dylib", RTLD_LAZY);
        if (sandyHandle) {
            libSandy_applyProfile_t applyProfile = (libSandy_applyProfile_t)dlsym(sandyHandle, "libSandy_applyProfile");
            if (applyProfile) applyProfile("MiOS-Profile");
        }

        // Boot-watchdog DISARM: SpringBoard reaching this point means the GUI came up, i.e. the system
        // daemons survived this boot. Clear the arm file so MiOSSupport keeps its daemon hooks enabled.
        // If a daemon hook had hung the boot, we'd never get here, the file would stay armed, and the
        // next boot's daemons would self-disable. (See the safety layer in MiOSSupport.x.)
        if ([gBundleID isEqualToString:@"com.apple.springboard"]) {
            [[NSFileManager defaultManager] removeItemAtPath:
                @"/var/mobile/Library/Preferences/MiOS/boot_armed" error:nil];
        }

        NSString *uuid = nil;

        // PRIMARY: the daemon drops a bootstrap file INSIDE our own container when it switches us in.
        // Our own HOME is always readable in-sandbox, so this works with no libSandy / central access.
        NSString *bootPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.mios.active.plist"];
        NSDictionary *boot = [NSDictionary dictionaryWithContentsOfFile:bootPath];
        if ([boot[@"uuid"] isKindOfClass:[NSString class]]) {
            uuid = boot[@"uuid"];
            gSpoof = [boot[@"spoof"] isKindOfClass:[NSDictionary class]] ? boot[@"spoof"] : @{};
        } else {
            // FALLBACK: read the central MiOS prefs (needs libSandy + the global enable switch).
            if (isMiOSEnabled()) {
                MiOSContainerManager *mgr = [MiOSContainerManager sharedManager];
                uuid = [mgr activeContainerUUIDForBundleID:gBundleID];
                if (uuid) gSpoof = [mgr spoofPrefsForBundleID:gBundleID];
            }
        }

        // Resolve the mode. Container apps get full isolation (keychain + App Group redirect). A
        // selected SYSTEM app (Settings) with no container of its own gets the "active container drives
        // the system identity" path: ONLY the in-process device/MG/sysctl hooks, so Settings → About
        // shows the spoofed device. We never rewrite the on-disk MobileGestalt cache (bootloop risk).
        BOOL systemSpoofMode = NO;
        if (!uuid) {
            if (isMiOSEnabled() && !miosRedirectDisabled()) {
                NSDictionary *sysSpoof =
                    [[MiOSContainerManager sharedManager] activeSystemSpoofForBundleID:gBundleID];
                if ([sysSpoof isKindOfClass:[NSDictionary class]] &&
                    [sysSpoof[@"deviceSpoofEnabled"] boolValue]) {
                    gSpoof = sysSpoof;
                    systemSpoofMode = YES;
                }
            }
            if (!systemSpoofMode) return;   // not a container app and not a system-spoof target
        } else {
            // Container app: keychain isolation is always on so sessions persist per container.
            gContainerUUID = uuid;
            gKeychainIsolation = YES;
            gKcPrefix = [NSString stringWithFormat:@"__mios_%@_", uuid];
            miosInitKeychainNamespace();
        }

        if (!gSpoof) gSpoof = @{};

        // Per-container App Group redirection (in-process, Crane-style). Gives this container its own
        // group state so the app registers as the spoofed device. Kill-switch + fail-safe above.
        gGroupRedirectActive = (gContainerUUID.length > 0) && !miosRedirectDisabled();
        if (gGroupRedirectActive) {
            %init(GroupRedirectHooks);
        }

        // Precompute every C-hook value NOW (ObjC is safe here), so the low-level hooks never allocate.
        miosBuildSpoofCache();

        if (locationSpoofEnabled()) {
            %init(LocationHooks);
        }

        %init(IdentifierSpoofHooks);

        NSString *selfTestBefore = @"";
        NSString *selfTestAfter = @"";
        if (deviceSpoofEnabled()) {
            // Read hw.machine BEFORE hooking (real value) for the diagnostic.
            char b0[64] = {0}; size_t s0 = sizeof(b0);
            if (orig_sysctlbyname == NULL) { sysctlbyname("hw.machine", b0, &s0, NULL, 0); selfTestBefore = @(b0); }

            %init(DeviceSpoofHooks);

            // Device model via sysctl + uname (exactly what Ghost hooks). We deliberately do NOT
            // hook MGCopyAnswer: CoreTelephony calls it during init (hasBaseband) and hooking it
            // trips an EXC_BREAKPOINT trap there — Ghost only reads MGCopyAnswer, never replaces it.
            MSHookFunction((void *)sysctlbyname, (void *)hook_sysctlbyname, (void **)&orig_sysctlbyname);
            MSHookFunction((void *)sysctl, (void *)hook_sysctl, (void **)&orig_sysctl);
            MSHookFunction((void *)uname, (void *)hook_uname, (void **)&orig_uname);

            // Self-test: call hw.machine AFTER hooking. If the hook works this returns the spoofed id.
            char b1[64] = {0}; size_t s1 = sizeof(b1);
            sysctlbyname("hw.machine", b1, &s1, NULL, 0);
            selfTestAfter = @(b1);

            // MGCopyAnswer: apps like Instagram read the model/iOS from MobileGestalt. We never patch
            // the real MGCopyAnswer (that crashes CoreTelephony/Shadow). First we capture the real
            // function, then hook dlsym so a runtime lookup of "MGCopyAnswer" returns OUR impl.
            if (gcMGProductType || gcMGProductVersion || gcMGDeviceName || gcMGHWModel ||
                gcMGSerialNumber || gcMGUDID) {
                void *mgH = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
                if (!mgH) mgH = dlopen("/var/jb/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
                if (mgH) gRealMGCopyAnswer = (CFTypeRef(*)(CFStringRef))dlsym(mgH, "MGCopyAnswer");
                MSHookFunction((void *)dlsym, (void *)new_dlsym, (void **)&orig_dlsym);

                // Many apps bind MGCopyAnswer directly in their import tables, bypassing the dlsym hook
                // above. Rebind that import pointer to ours with fishhook, in EVERY container app (not
                // just Instagram) so the spoofed device shows in the app's own UI. Scoped to the app's
                // own binaries only (main exe + embedded frameworks) — the real libMobileGestalt and
                // system frameworks like CoreTelephony are never touched, and fishhook is per-process.
                // Honour the kill-switch so it can be turned off from Filza without a reboot.
                if (gRealMGCopyAnswer && !miosRedirectDisabled()) {
                    // Container apps: app images only (never touch system frameworks → no crash).
                    // Settings (system spoof): all images, so About's model name is covered.
                    miosRebindMG(systemSpoofMode);
                }
            }
        }

        // Extra probes: what does uname() report, and what does MGCopyAnswer("ProductType") report?
        // (MGCopyAnswer is only READ here, never hooked.) This tells us which API the app trusts.
        NSString *unameMachine = @"";
        NSString *mgProductType = @"";
        NSString *mgProductVersion = @"";
        NSString *rawSysctlMachine = @"";
        NSString *uiSystemVersion = @"";
        if (deviceSpoofEnabled()) {
            struct utsname un; memset(&un, 0, sizeof(un));
            if (uname(&un) == 0) unameMachine = @(un.machine);
            // Raw MIB sysctl self-test (what UniversalSpoof hooks).
            int mib[2] = { CTL_HW, HW_MACHINE };
            char rb[64] = {0}; size_t rl = sizeof(rb);
            if (sysctl(mib, 2, rb, &rl, NULL, 0) == 0) rawSysctlMachine = @(rb);
            uiSystemVersion = [[UIDevice currentDevice] systemVersion] ?: @"";
            void *mgH = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
            if (mgH) {
                CFTypeRef (*mg)(CFStringRef) = (CFTypeRef(*)(CFStringRef))dlsym(mgH, "MGCopyAnswer");
                if (mg) {
                    CFTypeRef v = mg(CFSTR("ProductType"));
                    if (v) {
                        if (CFGetTypeID(v) == CFStringGetTypeID()) mgProductType = [(__bridge NSString *)v copy];
                        CFRelease(v);
                    }
                    CFTypeRef v2 = mg(CFSTR("ProductVersion"));
                    if (v2) {
                        if (CFGetTypeID(v2) == CFStringGetTypeID()) mgProductVersion = [(__bridge NSString *)v2 copy];
                        CFRelease(v2);
                    }
                }
            }
        }

        // 3. Carrier spoofing (part of the device fingerprint, or standalone).
        if (carrierSpoofActive()) {
            %init(CarrierHooks);
        }

        // 4. Wi-Fi (SSID/BSSID) spoofing via CaptiveNetwork.
        if (wifiSpoofActive()) {
            void *scHandle = dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration", RTLD_LAZY);
            if (scHandle) {
                CNCopyCurrentNetworkInfo_t cnFn = (CNCopyCurrentNetworkInfo_t)dlsym(scHandle, "CNCopyCurrentNetworkInfo");
                if (cnFn) MSHookFunction((void *)cnFn, (void *)hook_CNCopyCurrentNetworkInfo, (void **)&orig_CNCopyCurrentNetworkInfo);
            }
        }

        // 5. Battery + locale/time-zone (explicit opt-ins).
        if (batterySpoofActive()) {
            %init(BatteryHooks);
        }
        if (localeSpoofActive()) {
            %init(LocaleHooks);
        }

        // --- Diagnostic dump (temporary) ---
        // Written both into our own container and to the central MiOS folder so it is easy to retrieve.
        @try {
            NSMutableDictionary *dbg = [NSMutableDictionary dictionary];
            dbg[@"bundleID"] = gBundleID ?: @"";
            dbg[@"home"] = NSHomeDirectory() ?: @"";
            dbg[@"uuid"] = uuid ?: @"(nil)";
            dbg[@"deviceSpoofEnabled"] = @(deviceSpoofEnabled());
            dbg[@"deviceIdentifier"] = spoofStr(@"deviceIdentifier");
            dbg[@"gpsEnabled"] = @(locationSpoofEnabled());
            dbg[@"gcMachine"] = gcMachine ? @(gcMachine) : @"(null)";
            dbg[@"selfTest_before_hook"] = selfTestBefore;
            dbg[@"selfTest_after_hook"] = selfTestAfter;   // should equal deviceIdentifier if hook works
            dbg[@"probe_uname_machine"] = unameMachine;    // should be spoofed if uname hook works
            dbg[@"probe_rawSysctl_machine"] = rawSysctlMachine; // should be spoofed if raw sysctl hook works
            dbg[@"probe_UIDevice_systemVersion"] = uiSystemVersion; // should be spoofed iOS if UIDevice hook works
            dbg[@"probe_MGCopyAnswer_ProductType"] = mgProductType; // real (we don't hook MG) — is this what IG uses?
            dbg[@"probe_MGCopyAnswer_ProductVersion"] = mgProductVersion;
            // App Group container paths as seen by the app — shows whether group isolation reached us.
            NSMutableDictionary *grp = [NSMutableDictionary dictionary];
            for (NSString *gid in @[@"group.com.burbn.instagram", @"group.com.facebook.family"]) {
                NSURL *u = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:gid];
                grp[gid] = u ? u.path : @"(nil)";
            }
            dbg[@"appGroupContainers"] = grp;
            dbg[@"spoofKeys"] = [gSpoof allKeys] ?: @[];
            dbg[@"ts"] = [NSDate date].description;
            [dbg writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/mios_debug.plist"] atomically:YES];
            NSString *cdir = @"/var/mobile/Library/Preferences/MiOS/debug";
            [[NSFileManager defaultManager] createDirectoryAtPath:cdir withIntermediateDirectories:YES attributes:nil error:nil];
            [dbg writeToFile:[cdir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", gBundleID]] atomically:YES];
        } @catch (__unused id e) {}
    }
}
