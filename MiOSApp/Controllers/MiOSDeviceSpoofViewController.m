#import "MiOSDeviceSpoofViewController.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"
#import "../Models/MiOSDeviceDatabase.h"

static NSString *const kDeviceSpoofPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.devicespoof.plist";

@interface MiOSDeviceSpoofViewController () <UIPickerViewDataSource, UIPickerViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) NSMutableDictionary *prefs;
@property (nonatomic, strong) NSArray<MiOSDeviceModel *> *devices;
@property (nonatomic, strong) NSArray<NSString *> *currentIOSVersions;
@property (nonatomic, strong) UIPickerView *devicePicker;
@property (nonatomic, strong) UIPickerView *iosPicker;
@property (nonatomic, strong) UILabel *deviceLabel;
@property (nonatomic, strong) UILabel *iosLabel;
@property (nonatomic, strong) UIImageView *phoneImageView;
@property (nonatomic, strong) UILabel *phoneNameLabel;
@property (nonatomic, strong) UILabel *phoneVersionLabel;
@end

@implementation MiOSDeviceSpoofViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Device Spoof";
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    _devices = [MiOSDeviceDatabase allDevices];
    [self loadPreferences];
    [self setupUI];
}

- (void)loadPreferences {
    _prefs = [[NSDictionary dictionaryWithContentsOfFile:kDeviceSpoofPrefsPath] mutableCopy];
    if (!_prefs) {
        _prefs = [@{@"enabled": @NO, @"deviceIdentifier": @"", @"iosVersion": @""} mutableCopy];
    }
    [self updateIOSVersionsForCurrentDevice];
}

- (void)updateIOSVersionsForCurrentDevice {
    NSString *ident = _prefs[@"deviceIdentifier"] ?: @"";
    MiOSDeviceModel *dev = [MiOSDeviceDatabase deviceForIdentifier:ident];
    _currentIOSVersions = dev ? [MiOSDeviceDatabase supportedIOSVersionsForDevice:dev] : @[];
}

- (void)savePreferences {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [kDeviceSpoofPrefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [_prefs writeToFile:kDeviceSpoofPrefsPath atomically:YES];
}

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    _mainStack = [[UIStackView alloc] init];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.axis = UILayoutConstraintAxisVertical;
    _mainStack.spacing = 20;
    [_scrollView addSubview:_mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_mainStack.topAnchor constraintEqualToAnchor:_scrollView.topAnchor constant:16],
        [_mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_mainStack.bottomAnchor constraintEqualToAnchor:_scrollView.bottomAnchor constant:-32],
    ]];

    [self buildPreviewCard];
    [self buildDevicePickerSection];
    [self buildIOSPickerSection];
}

- (void)buildPreviewCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [MiOSTheme cardBackground];
    card.layer.cornerRadius = [MiOSTheme cardCornerRadius];
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderColor = [MiOSTheme separator].CGColor;
    card.layer.borderWidth = 0.5;

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:64 weight:UIImageSymbolWeightThin];
    _phoneImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"iphone" withConfiguration:config]];
    _phoneImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _phoneImageView.tintColor = [MiOSTheme accentColor];
    _phoneImageView.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:_phoneImageView];

    _phoneNameLabel = [[UILabel alloc] init];
    _phoneNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _phoneNameLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    _phoneNameLabel.textColor = [MiOSTheme primaryText];
    _phoneNameLabel.text = @"No device selected";
    [card addSubview:_phoneNameLabel];

    _phoneVersionLabel = [[UILabel alloc] init];
    _phoneVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _phoneVersionLabel.font = [MiOSTheme captionFont];
    _phoneVersionLabel.textColor = [MiOSTheme secondaryText];
    _phoneVersionLabel.text = @"Select a device to spoof";
    [card addSubview:_phoneVersionLabel];

    UIView *statusBadge = [[UIView alloc] init];
    statusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    statusBadge.layer.cornerRadius = 6;
    BOOL isEnabled = [_prefs[@"enabled"] boolValue];
    statusBadge.backgroundColor = isEnabled
        ? [[MiOSTheme success] colorWithAlphaComponent:0.15]
        : [[MiOSTheme destructive] colorWithAlphaComponent:0.15];
    [card addSubview:statusBadge];

    UILabel *statusText = [[UILabel alloc] init];
    statusText.translatesAutoresizingMaskIntoConstraints = NO;
    statusText.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    statusText.textColor = isEnabled ? [MiOSTheme success] : [MiOSTheme destructive];
    statusText.text = isEnabled ? @"ACTIVE" : @"DISABLED";
    [statusBadge addSubview:statusText];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:120],
        [_phoneImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [_phoneImageView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [_phoneImageView.widthAnchor constraintEqualToConstant:60],
        [_phoneImageView.heightAnchor constraintEqualToConstant:80],
        [_phoneNameLabel.leadingAnchor constraintEqualToAnchor:_phoneImageView.trailingAnchor constant:16],
        [_phoneNameLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:28],
        [_phoneNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
        [_phoneVersionLabel.leadingAnchor constraintEqualToAnchor:_phoneNameLabel.leadingAnchor],
        [_phoneVersionLabel.topAnchor constraintEqualToAnchor:_phoneNameLabel.bottomAnchor constant:4],
        [statusBadge.leadingAnchor constraintEqualToAnchor:_phoneNameLabel.leadingAnchor],
        [statusBadge.topAnchor constraintEqualToAnchor:_phoneVersionLabel.bottomAnchor constant:8],
        [statusText.topAnchor constraintEqualToAnchor:statusBadge.topAnchor constant:4],
        [statusText.bottomAnchor constraintEqualToAnchor:statusBadge.bottomAnchor constant:-4],
        [statusText.leadingAnchor constraintEqualToAnchor:statusBadge.leadingAnchor constant:8],
        [statusText.trailingAnchor constraintEqualToAnchor:statusBadge.trailingAnchor constant:-8],
    ]];

    [self updatePreviewCard];
    [_mainStack addArrangedSubview:card];
}

- (void)updatePreviewCard {
    NSString *ident = _prefs[@"deviceIdentifier"] ?: @"";
    NSString *ver = _prefs[@"iosVersion"] ?: @"";
    MiOSDeviceModel *dev = [MiOSDeviceDatabase deviceForIdentifier:ident];
    if (dev) {
        _phoneNameLabel.text = dev.displayName;
        _phoneVersionLabel.text = ver.length > 0
            ? [NSString stringWithFormat:@"iOS %@  •  %@", ver, dev.identifier]
            : [NSString stringWithFormat:@"%@", dev.identifier];
    } else {
        _phoneNameLabel.text = @"No device selected";
        _phoneVersionLabel.text = @"Select a device to spoof";
    }
}

- (void)buildDevicePickerSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"iPhone Model"];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    _devicePicker = [[UIPickerView alloc] init];
    _devicePicker.translatesAutoresizingMaskIntoConstraints = NO;
    _devicePicker.dataSource = self;
    _devicePicker.delegate = self;
    _devicePicker.tag = 1;
    [container addSubview:_devicePicker];

    [NSLayoutConstraint activateConstraints:@[
        [_devicePicker.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_devicePicker.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_devicePicker.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_devicePicker.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_devicePicker.heightAnchor constraintEqualToConstant:150],
    ]];

    NSString *ident = _prefs[@"deviceIdentifier"] ?: @"";
    for (NSUInteger i = 0; i < _devices.count; i++) {
        if ([_devices[i].identifier isEqualToString:ident]) {
            [_devicePicker selectRow:i inComponent:0 animated:NO];
            break;
        }
    }

    [section addCellView:container];
    [_mainStack addArrangedSubview:section];
}

- (void)buildIOSPickerSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"iOS Version"];

    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    _iosPicker = [[UIPickerView alloc] init];
    _iosPicker.translatesAutoresizingMaskIntoConstraints = NO;
    _iosPicker.dataSource = self;
    _iosPicker.delegate = self;
    _iosPicker.tag = 2;
    [container addSubview:_iosPicker];

    [NSLayoutConstraint activateConstraints:@[
        [_iosPicker.topAnchor constraintEqualToAnchor:container.topAnchor],
        [_iosPicker.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [_iosPicker.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [_iosPicker.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
        [_iosPicker.heightAnchor constraintEqualToConstant:150],
    ]];

    NSString *ver = _prefs[@"iosVersion"] ?: @"";
    for (NSUInteger i = 0; i < _currentIOSVersions.count; i++) {
        if ([_currentIOSVersions[i] isEqualToString:ver]) {
            [_iosPicker selectRow:i inComponent:0 animated:NO];
            break;
        }
    }

    [section addCellView:container];
    [_mainStack addArrangedSubview:section];
}

#pragma mark - UIPickerView

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView { return 1; }

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    if (pickerView.tag == 1) return _devices.count;
    return _currentIOSVersions.count;
}

- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view {
    UILabel *label = (UILabel *)view;
    if (!label) {
        label = [[UILabel alloc] init];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        label.textColor = [MiOSTheme primaryText];
    }
    if (pickerView.tag == 1) {
        label.text = _devices[row].displayName;
    } else {
        label.text = [NSString stringWithFormat:@"iOS %@", _currentIOSVersions[row]];
    }
    return label;
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];

    if (pickerView.tag == 1) {
        MiOSDeviceModel *dev = _devices[row];
        _prefs[@"deviceIdentifier"] = dev.identifier;
        _prefs[@"deviceName"] = dev.displayName;
        _prefs[@"hwModel"] = dev.hwModel;
        _prefs[@"enabled"] = @YES;

        [self updateIOSVersionsForCurrentDevice];
        [_iosPicker reloadAllComponents];

        if (_currentIOSVersions.count > 0) {
            NSString *currentVer = _prefs[@"iosVersion"] ?: @"";
            NSUInteger idx = [_currentIOSVersions indexOfObject:currentVer];
            if (idx == NSNotFound) {
                idx = _currentIOSVersions.count - 1;
                _prefs[@"iosVersion"] = _currentIOSVersions[idx];
            }
            [_iosPicker selectRow:idx inComponent:0 animated:YES];
        } else {
            _prefs[@"iosVersion"] = @"";
        }
    } else {
        if (row < (NSInteger)_currentIOSVersions.count) {
            _prefs[@"iosVersion"] = _currentIOSVersions[row];
            _prefs[@"enabled"] = @YES;
        }
    }
    [self savePreferences];
    [self updatePreviewCard];
}

@end
