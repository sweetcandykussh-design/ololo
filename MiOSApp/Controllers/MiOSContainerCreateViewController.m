#import "MiOSContainerCreateViewController.h"
#import "../Models/MiOSContainerConfig.h"
#import "../Models/MiOSAppInfo.h"
#import "../Models/MiOSDeviceDatabase.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../Views/MiOSGradientView.h"
#import "../Views/MiOSPrimaryButton.h"
#import "../UI/MiOSTheme.h"
#import "../Utils/MiOSAppIconProvider.h"
#import "../Utils/MiOSDeviceImageRenderer.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

static UIColor *MiOSMix(UIColor *base, UIColor *overlay, CGFloat t) {
    CGFloat r1, g1, b1, a1, r2, g2, b2, a2;
    [base getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
    [overlay getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * t green:g1 + (g2 - g1) * t blue:b1 + (b2 - b1) * t alpha:a1];
}

#pragma mark - App Row Cell

static NSString *const kAppCellReuseID = @"MiOSAppRowCell";

@interface MiOSAppRowCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *bundleLabel;
- (void)setChecked:(BOOL)checked;
@end

@implementation MiOSAppRowCell {
    UIView *_checkCircle;
    UIImageView *_checkMark;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UIView *card = self.contentView;
        card.layer.cornerRadius = 20;
        card.layer.cornerCurve = kCACornerCurveContinuous;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFill;
        _iconView.clipsToBounds = YES;
        _iconView.layer.cornerRadius = 12;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        [card addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [MiOSTheme primaryText];
        [card addSubview:_nameLabel];

        _bundleLabel = [[UILabel alloc] init];
        _bundleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _bundleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _bundleLabel.textColor = [MiOSTheme secondaryText];
        [card addSubview:_bundleLabel];

        _checkCircle = [[UIView alloc] init];
        _checkCircle.translatesAutoresizingMaskIntoConstraints = NO;
        _checkCircle.layer.cornerRadius = 13;
        _checkCircle.layer.borderWidth = 1.5;
        [card addSubview:_checkCircle];

        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold];
        _checkMark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:cfg]];
        _checkMark.translatesAutoresizingMaskIntoConstraints = NO;
        _checkMark.contentMode = UIViewContentModeCenter;
        [_checkCircle addSubview:_checkMark];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
            [_iconView.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:46],
            [_iconView.heightAnchor constraintEqualToConstant:46],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:12],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkCircle.leadingAnchor constant:-10],
            [_nameLabel.bottomAnchor constraintEqualToAnchor:card.centerYAnchor constant:-1],
            [_bundleLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_bundleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_checkCircle.leadingAnchor constant:-10],
            [_bundleLabel.topAnchor constraintEqualToAnchor:card.centerYAnchor constant:2],
            [_checkCircle.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
            [_checkCircle.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
            [_checkCircle.widthAnchor constraintEqualToConstant:26],
            [_checkCircle.heightAnchor constraintEqualToConstant:26],
            [_checkMark.centerXAnchor constraintEqualToAnchor:_checkCircle.centerXAnchor],
            [_checkMark.centerYAnchor constraintEqualToAnchor:_checkCircle.centerYAnchor],
        ]];
    }
    return self;
}

- (void)setChecked:(BOOL)checked {
    UIColor *accent = [MiOSTheme accentColor];
    UIView *card = self.contentView;
    card.backgroundColor = checked ? MiOSMix([MiOSTheme tileBackground], accent, 0.16) : [MiOSTheme tileBackground];
    card.layer.borderWidth = checked ? 1.5 : 1.0;
    card.layer.borderColor = checked ? [accent colorWithAlphaComponent:0.8].CGColor : [MiOSTheme hairline].CGColor;
    _checkCircle.backgroundColor = checked ? accent : [UIColor clearColor];
    _checkCircle.layer.borderColor = checked ? accent.CGColor : [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    _checkMark.hidden = !checked;
    _checkMark.tintColor = [MiOSTheme textColorOnAccent];
}

@end

#pragma mark - Main View Controller

@interface MiOSContainerCreateViewController () <UICollectionViewDataSource, UICollectionViewDelegate,
    UICollectionViewDelegateFlowLayout, UITextFieldDelegate, UISearchBarDelegate,
    MiOSToggleCellDelegate, MKMapViewDelegate, MKLocalSearchCompleterDelegate,
    UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UIView *step1View;
@property (nonatomic, strong) UIView *step2View;
@property (nonatomic, assign) NSInteger currentStep;
@property (nonatomic, strong) CAGradientLayer *bgLayer;
@property (nonatomic, strong) MiOSGradientView *glowView;

// Step 1 - App Selection
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) MiOSPrimaryButton *nextButton;
@property (nonatomic, strong) NSArray<MiOSAppInfo *> *allAppsList;
@property (nonatomic, strong) NSArray<MiOSAppInfo *> *filteredApps;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedBundleIDs;

// Step 2 - Configuration
@property (nonatomic, strong) UIScrollView *step2Scroll;
@property (nonatomic, strong) UIStackView *step2Stack;

// GPS
@property (nonatomic, assign) BOOL gpsEnabled;
@property (nonatomic, strong) UIView *gpsMapContainer;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *locationSearchBar;
@property (nonatomic, strong) UITableView *locationSearchResultsTable;
@property (nonatomic, strong) MKPointAnnotation *mapPin;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) MKLocalSearchCompleter *searchCompleter;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *locationSearchResults;
@property (nonatomic, assign) double selectedLatitude;
@property (nonatomic, assign) double selectedLongitude;
@property (nonatomic, copy) NSString *selectedLocationName;

// Device spoof
@property (nonatomic, assign) BOOL deviceSpoofEnabled;
@property (nonatomic, strong) UIView *deviceCardContainer;
@property (nonatomic, strong) UIImageView *deviceImageView;
@property (nonatomic, strong) UILabel *deviceNameValue;
@property (nonatomic, strong) UILabel *deviceIdentifierValue;
@property (nonatomic, strong) UILabel *deviceChipValue;
@property (nonatomic, strong) UILabel *deviceMemoryValue;
@property (nonatomic, strong) UILabel *iosTitleLabel;
@property (nonatomic, strong) UILabel *iosBadgeLabel;
@property (nonatomic, strong) UILabel *storageTitleLabel;
@property (nonatomic, strong) UIView *iosTile;
@property (nonatomic, strong) UIView *storageTile;
@property (nonatomic, strong) NSArray<MiOSDeviceModel *> *deviceList;
@property (nonatomic, strong) NSArray<NSString *> *iosVersionList;
@property (nonatomic, assign) NSInteger selectedDeviceIndex;
@property (nonatomic, assign) NSInteger selectedIOSIndex;
@property (nonatomic, assign) NSInteger selectedStorageIndex;
@property (nonatomic, assign) BOOL spoofDeviceName;
@property (nonatomic, strong) UIView *customDeviceNameContainer;
@property (nonatomic, strong) UITextField *customDeviceNameField;
@property (nonatomic, copy) NSString *customDeviceNameText;

// Identifiers
@property (nonatomic, assign) BOOL spoofDeviceCheck;
@property (nonatomic, assign) BOOL spoofVendorID;
@property (nonatomic, copy) NSString *vendorID;
@property (nonatomic, strong) UIView *vendorIDContainer;
@property (nonatomic, strong) UILabel *vendorIDLabel;
@property (nonatomic, assign) BOOL spoofAdvertisingID;
@property (nonatomic, copy) NSString *advertisingID;
@property (nonatomic, strong) UIView *advertisingIDContainer;
@property (nonatomic, strong) UILabel *advertisingIDLabel;
@property (nonatomic, assign) BOOL spoofCloudToken;

// Network & sensor spoofing
@property (nonatomic, assign) BOOL spoofCarrier;
@property (nonatomic, assign) BOOL spoofWiFi;
@property (nonatomic, assign) BOOL spoofBattery;
@property (nonatomic, assign) BOOL spoofLocale;
@property (nonatomic, copy) NSString *carrierName;
@property (nonatomic, copy) NSString *carrierMCC;
@property (nonatomic, copy) NSString *carrierMNC;
@property (nonatomic, copy) NSString *carrierISO;
@property (nonatomic, copy) NSString *wifiSSID;
@property (nonatomic, copy) NSString *wifiBSSID;
@property (nonatomic, strong) UIView *carrierContainer;
@property (nonatomic, strong) UITextField *carrierField;
@property (nonatomic, strong) UIView *wifiContainer;
@property (nonatomic, strong) UITextField *wifiSSIDField;
@property (nonatomic, strong) UITextField *wifiBSSIDField;

@end

@implementation MiOSContainerCreateViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [MiOSTheme primaryBackground];

    _bgLayer = [MiOSTheme pageBackgroundLayer];
    [self.view.layer insertSublayer:_bgLayer atIndex:0];

    _glowView = [[MiOSGradientView alloc] init];
    _glowView.translatesAutoresizingMaskIntoConstraints = NO;
    _glowView.userInteractionEnabled = NO;
    _glowView.gradientLayer.type = kCAGradientLayerRadial;
    [self.view addSubview:_glowView];
    [NSLayoutConstraint activateConstraints:@[
        [_glowView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_glowView.centerYAnchor constraintEqualToAnchor:self.view.topAnchor constant:30],
        [_glowView.widthAnchor constraintEqualToConstant:520],
        [_glowView.heightAnchor constraintEqualToConstant:420],
    ]];

    _currentStep = 1;
    _selectedBundleIDs = [NSMutableArray array];
    _deviceList = [MiOSDeviceDatabase allDevices];
    _iosVersionList = [MiOSDeviceDatabase allIOSVersions];
    _locationSearchResults = @[];

    [self setupSearchCompleter];
    [self prefillFromEditing];
    [self loadApps];
    if (_selectedBundleIDs.count > 0) [MiOSAppIconProvider applyThemeForBundleIDs:_selectedBundleIDs];
    [self updateGlow];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeDidChange)
                                                 name:MiOSThemeDidChangeNotification object:nil];

    [self buildStep1];
    [self buildStep2];
    [self showStep:(_entry == MiOSEditorEntrySpoofing ? 2 : 1) animated:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgLayer.frame = self.view.bounds;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || !self.presentingViewController) {
        [MiOSAppIconProvider applyThemeForActiveContainer];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setupSearchCompleter {
    _searchCompleter = [[MKLocalSearchCompleter alloc] init];
    _searchCompleter.delegate = self;
    _searchCompleter.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypePointOfInterest;
}

- (void)prefillFromEditing {
    if (!_editingContainer) return;

    for (NSString *bundleID in _editingContainer.apps) {
        if (![_selectedBundleIDs containsObject:bundleID]) [_selectedBundleIDs addObject:bundleID];
    }
    _gpsEnabled = _editingContainer.gpsEnabled;
    _selectedLatitude = _editingContainer.latitude;
    _selectedLongitude = _editingContainer.longitude;
    _selectedLocationName = _editingContainer.locationName;
    _deviceSpoofEnabled = _editingContainer.deviceSpoofEnabled;
    _spoofDeviceName = _editingContainer.spoofDeviceName;
    _customDeviceNameText = _editingContainer.customDeviceName;
    _spoofDeviceCheck = _editingContainer.spoofDeviceCheck;
    _spoofVendorID = _editingContainer.spoofVendorID;
    _vendorID = _editingContainer.vendorID.length > 0 ? _editingContainer.vendorID : nil;
    _spoofAdvertisingID = _editingContainer.spoofAdvertisingID;
    _advertisingID = _editingContainer.advertisingID.length > 0 ? _editingContainer.advertisingID : nil;
    _spoofCloudToken = _editingContainer.spoofCloudToken;
    _spoofCarrier = _editingContainer.spoofCarrier;
    _carrierName = _editingContainer.carrierName;
    _carrierMCC = _editingContainer.carrierMCC;
    _carrierMNC = _editingContainer.carrierMNC;
    _carrierISO = _editingContainer.carrierISO;
    _spoofWiFi = _editingContainer.spoofWiFi;
    _wifiSSID = _editingContainer.wifiSSID;
    _wifiBSSID = _editingContainer.wifiBSSID;
    _spoofBattery = _editingContainer.spoofBattery;
    _spoofLocale = _editingContainer.spoofLocale;

    if (_editingContainer.deviceIdentifier.length > 0) {
        for (NSInteger i = 0; i < (NSInteger)_deviceList.count; i++) {
            if ([_deviceList[i].identifier isEqualToString:_editingContainer.deviceIdentifier]) {
                _selectedDeviceIndex = i;
                break;
            }
        }
        [self updateIOSVersionsForDeviceQuiet];
        for (NSInteger i = 0; i < (NSInteger)_iosVersionList.count; i++) {
            if ([_iosVersionList[i] isEqualToString:_editingContainer.iosVersion]) {
                _selectedIOSIndex = i;
                break;
            }
        }
        MiOSDeviceModel *device = _deviceList[_selectedDeviceIndex];
        for (NSInteger i = 0; i < (NSInteger)device.storageOptions.count; i++) {
            if (device.storageOptions[i].integerValue == _editingContainer.storageSizeGB) {
                _selectedStorageIndex = i;
                break;
            }
        }
    }
}

- (void)loadApps {
    _allAppsList = [MiOSAppInfo allApps];
    [self filterApps];
}

- (void)filterApps {
    NSString *searchText = _searchField.text.lowercaseString ?: @"";
    NSInteger segment = _segmentedControl ? _segmentedControl.selectedSegmentIndex : 0;

    NSMutableArray<MiOSAppInfo *> *result = [NSMutableArray array];
    for (MiOSAppInfo *app in _allAppsList) {
        BOOL isSystem = [app.bundleID hasPrefix:@"com.apple."];
        if (segment == 0 && isSystem) continue;
        if (segment == 1 && !isSystem) continue;
        if (searchText.length > 0) {
            NSString *nameLower = app.name.lowercaseString ?: @"";
            NSString *bundleLower = app.bundleID.lowercaseString ?: @"";
            if (![nameLower containsString:searchText] && ![bundleLower containsString:searchText]) continue;
        }
        [result addObject:app];
    }
    _filteredApps = [result copy];
    [_collectionView reloadData];
}

#pragma mark - Theme

- (void)updateGlow {
    UIColor *accent = [MiOSTheme accentColor];
    [_glowView setColors:@[[accent colorWithAlphaComponent:0.30], [accent colorWithAlphaComponent:0.0]]
                   start:CGPointMake(0.5, 0.5) end:CGPointMake(1.0, 1.0)];
}

- (void)themeDidChange {
    UIColor *accent = [MiOSTheme accentColor];
    [UIView transitionWithView:self.view duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:^{
        [self updateGlow];
        self.segmentedControl.selectedSegmentTintColor = accent;
        [self.segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [MiOSTheme textColorOnAccent],
                                                        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}
                                             forState:UIControlStateSelected];
        [(UIImageView *)[self.nameField.leftView viewWithTag:77] setTintColor:accent];
        self.nameField.tintColor = accent;
        self.searchField.tintColor = accent;
        [self.nextButton refreshTheme];
        for (NSIndexPath *ip in self.collectionView.indexPathsForVisibleItems) {
            MiOSAppRowCell *cell = (MiOSAppRowCell *)[self.collectionView cellForItemAtIndexPath:ip];
            [cell setChecked:[self.selectedBundleIDs containsObject:self.filteredApps[ip.item].bundleID]];
        }
    } completion:nil];
}

#pragma mark - Shared UI helpers

- (UIButton *)circleButtonWithSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [btn setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    btn.tintColor = [MiOSTheme primaryText];
    btn.backgroundColor = [MiOSTheme tileBackground];
    btn.layer.cornerRadius = 20;
    btn.layer.borderWidth = 1.0;
    btn.layer.borderColor = [MiOSTheme hairline].CGColor;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [btn.widthAnchor constraintEqualToConstant:40],
        [btn.heightAnchor constraintEqualToConstant:40],
    ]];
    return btn;
}

- (UITextField *)pillFieldWithPlaceholder:(NSString *)placeholder icon:(NSString *)icon {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    field.textColor = [MiOSTheme primaryText];
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{NSForegroundColorAttributeName: [MiOSTheme tertiaryText]}];
    field.backgroundColor = [MiOSTheme tileBackground];
    field.layer.cornerRadius = 18;
    field.layer.cornerCurve = kCACornerCurveContinuous;
    field.layer.borderWidth = 1.0;
    field.layer.borderColor = [MiOSTheme hairline].CGColor;
    field.tintColor = [MiOSTheme accentColor];
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;

    UIView *left = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon withConfiguration:cfg]];
    iv.frame = CGRectMake(14, 12, 20, 20);
    iv.contentMode = UIViewContentModeCenter;
    iv.tintColor = [MiOSTheme secondaryText];
    iv.tag = 77;
    [left addSubview:iv];
    field.leftView = left;
    field.leftViewMode = UITextFieldViewModeAlways;
    field.rightView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 44)];
    field.rightViewMode = UITextFieldViewModeUnlessEditing;
    return field;
}

- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    return label;
}

#pragma mark - Step Navigation

- (void)showStep:(NSInteger)step animated:(BOOL)animated {
    _currentStep = step;
    UIView *incoming = (step == 1) ? _step1View : _step2View;
    UIView *outgoing = (step == 1) ? _step2View : _step1View;
    BOOL forward = (step == 2);

    if (!animated) {
        incoming.hidden = NO;
        incoming.alpha = 1;
        incoming.transform = CGAffineTransformIdentity;
        outgoing.hidden = YES;
        return;
    }

    CGFloat width = self.view.bounds.size.width;
    incoming.hidden = NO;
    incoming.alpha = 0;
    incoming.transform = CGAffineTransformMakeTranslation(forward ? width : -width, 0);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0.5 options:0 animations:^{
        incoming.alpha = 1;
        incoming.transform = CGAffineTransformIdentity;
        outgoing.alpha = 0;
        outgoing.transform = CGAffineTransformMakeTranslation(forward ? -width : width, 0);
    } completion:^(BOOL finished) {
        outgoing.hidden = YES;
        outgoing.transform = CGAffineTransformIdentity;
    }];
}

- (BOOL)validateStep1 {
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        [self shakeView:_nameField];
        return NO;
    }
    if (_selectedBundleIDs.count == 0) {
        [self showValidationAlert:@"Please select at least one app."];
        return NO;
    }
    return YES;
}

- (void)primaryStep1Tapped {
    if (![self validateStep1]) return;
    [self.view endEditing:YES];
    if (_entry == MiOSEditorEntryApps) {
        [self saveTapped];
        return;
    }
    [self buildStep2];
    [self showStep:2 animated:YES];
}

- (void)backTapped {
    [self.view endEditing:YES];
    [self showStep:1 animated:YES];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)shakeView:(UIView *)view {
    CAKeyframeAnimation *anim = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    anim.duration = 0.4;
    anim.values = @[@(-10), @(10), @(-8), @(8), @(-4), @(4), @(0)];
    [view.layer addAnimation:anim forKey:@"shake"];
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeError];
}

- (void)showValidationAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Missing Info" message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Build Step 1

- (void)buildStep1 {
    _step1View = [[UIView alloc] init];
    _step1View.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_step1View];
    [NSLayoutConstraint activateConstraints:@[
        [_step1View.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_step1View.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_step1View.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_step1View.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIButton *closeBtn = [self circleButtonWithSymbol:@"xmark" action:@selector(cancelTapped)];
    [_step1View addSubview:closeBtn];

    UILabel *titleLabel = [self labelWithFont:[UIFont systemFontOfSize:30 weight:UIFontWeightBold] color:[MiOSTheme primaryText]];
    titleLabel.text = _entry == MiOSEditorEntryApps ? @"Apps" : (_editingContainer ? @"Edit Container" : @"New Container");
    [_step1View addSubview:titleLabel];

    UILabel *stepLabel = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] color:[MiOSTheme secondaryText]];
    stepLabel.text = _entry == MiOSEditorEntryApps ? @"Choose the apps inside this container" : @"Step 1 of 2 · Select apps";
    [_step1View addSubview:stepLabel];

    _nameField = [self pillFieldWithPlaceholder:@"Container name" icon:@"square.stack.3d.up.fill"];
    [(UIImageView *)[_nameField.leftView viewWithTag:77] setTintColor:[MiOSTheme accentColor]];
    _nameField.text = _editingContainer.name;
    [_step1View addSubview:_nameField];

    _segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"User Apps", @"System", @"All"]];
    _segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _segmentedControl.selectedSegmentIndex = 0;
    _segmentedControl.backgroundColor = [MiOSTheme tileBackground];
    _segmentedControl.selectedSegmentTintColor = [MiOSTheme accentColor];
    [_segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [MiOSTheme textColorOnAccent],
                                                NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}
                                     forState:UIControlStateSelected];
    [_segmentedControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [MiOSTheme secondaryText],
                                                NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]}
                                     forState:UIControlStateNormal];
    [_segmentedControl addTarget:self action:@selector(filterApps) forControlEvents:UIControlEventValueChanged];
    [_step1View addSubview:_segmentedControl];

    _searchField = [self pillFieldWithPlaceholder:@"Search apps" icon:@"magnifyingglass"];
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.returnKeyType = UIReturnKeySearch;
    [_searchField addTarget:self action:@selector(filterApps) forControlEvents:UIControlEventEditingChanged];
    [_step1View addSubview:_searchField];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8;
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.showsVerticalScrollIndicator = NO;
    _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    _collectionView.contentInset = UIEdgeInsetsMake(4, 0, 12, 0);
    [_collectionView registerClass:[MiOSAppRowCell class] forCellWithReuseIdentifier:kAppCellReuseID];
    [_step1View addSubview:_collectionView];

    _nextButton = [[MiOSPrimaryButton alloc] initWithTitle:@"" watermark:_entry == MiOSEditorEntryApps ? @"checkmark.seal.fill" : @"arrow.right.circle.fill"];
    [_nextButton addTarget:self action:@selector(primaryStep1Tapped) forControlEvents:UIControlEventTouchUpInside];
    [_step1View addSubview:_nextButton];

    [NSLayoutConstraint activateConstraints:@[
        [closeBtn.topAnchor constraintEqualToAnchor:_step1View.topAnchor constant:16],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_step1View.trailingAnchor constant:-16],

        [titleLabel.topAnchor constraintEqualToAnchor:_step1View.topAnchor constant:16],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_step1View.leadingAnchor constant:20],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:closeBtn.leadingAnchor constant:-8],
        [stepLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [stepLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],

        [_nameField.topAnchor constraintEqualToAnchor:stepLabel.bottomAnchor constant:18],
        [_nameField.leadingAnchor constraintEqualToAnchor:_step1View.leadingAnchor constant:16],
        [_nameField.trailingAnchor constraintEqualToAnchor:_step1View.trailingAnchor constant:-16],
        [_nameField.heightAnchor constraintEqualToConstant:52],

        [_segmentedControl.topAnchor constraintEqualToAnchor:_nameField.bottomAnchor constant:12],
        [_segmentedControl.leadingAnchor constraintEqualToAnchor:_nameField.leadingAnchor],
        [_segmentedControl.trailingAnchor constraintEqualToAnchor:_nameField.trailingAnchor],
        [_segmentedControl.heightAnchor constraintEqualToConstant:36],

        [_searchField.topAnchor constraintEqualToAnchor:_segmentedControl.bottomAnchor constant:12],
        [_searchField.leadingAnchor constraintEqualToAnchor:_nameField.leadingAnchor],
        [_searchField.trailingAnchor constraintEqualToAnchor:_nameField.trailingAnchor],
        [_searchField.heightAnchor constraintEqualToConstant:46],

        [_collectionView.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:8],
        [_collectionView.leadingAnchor constraintEqualToAnchor:_nameField.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:_nameField.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:_nextButton.topAnchor constant:-10],

        [_nextButton.leadingAnchor constraintEqualToAnchor:_nameField.leadingAnchor],
        [_nextButton.trailingAnchor constraintEqualToAnchor:_nameField.trailingAnchor],
        [_nextButton.bottomAnchor constraintEqualToAnchor:_step1View.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];

    [self updateNextButtonTitle];
}

- (void)updateNextButtonTitle {
    NSString *verb = _entry == MiOSEditorEntryApps ? @"Save Apps" : @"Next";
    _nextButton.title = [NSString stringWithFormat:@"%@  ·  %lu selected", verb, (unsigned long)_selectedBundleIDs.count];
}

#pragma mark - Build Step 2

- (void)buildStep2 {
    BOOL wasVisible = (_currentStep == 2 && _step2View && !_step2View.hidden);
    [_step2View removeFromSuperview];

    _step2View = [[UIView alloc] init];
    _step2View.translatesAutoresizingMaskIntoConstraints = NO;
    _step2View.hidden = !wasVisible;
    [self.view addSubview:_step2View];
    [NSLayoutConstraint activateConstraints:@[
        [_step2View.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_step2View.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_step2View.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_step2View.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIButton *backBtn = [self circleButtonWithSymbol:@"chevron.left" action:@selector(backTapped)];
    [_step2View addSubview:backBtn];
    UIButton *closeBtn = [self circleButtonWithSymbol:@"xmark" action:@selector(cancelTapped)];
    [_step2View addSubview:closeBtn];

    UILabel *titleLabel = [self labelWithFont:[UIFont systemFontOfSize:30 weight:UIFontWeightBold] color:[MiOSTheme primaryText]];
    titleLabel.text = _entry == MiOSEditorEntrySpoofing ? @"Spoofing" : @"Configure";
    [_step2View addSubview:titleLabel];

    UILabel *stepLabel = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightMedium] color:[MiOSTheme secondaryText]];
    stepLabel.text = _entry == MiOSEditorEntrySpoofing ? @"Location, device & identifiers" : @"Step 2 of 2 · Spoofing";
    [_step2View addSubview:stepLabel];

    _step2Scroll = [[UIScrollView alloc] init];
    _step2Scroll.translatesAutoresizingMaskIntoConstraints = NO;
    _step2Scroll.showsVerticalScrollIndicator = NO;
    _step2Scroll.alwaysBounceVertical = YES;
    _step2Scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [_step2View addSubview:_step2Scroll];

    _step2Stack = [[UIStackView alloc] init];
    _step2Stack.translatesAutoresizingMaskIntoConstraints = NO;
    _step2Stack.axis = UILayoutConstraintAxisVertical;
    _step2Stack.spacing = 22;
    [_step2Scroll addSubview:_step2Stack];

    [NSLayoutConstraint activateConstraints:@[
        [backBtn.topAnchor constraintEqualToAnchor:_step2View.topAnchor constant:16],
        [backBtn.leadingAnchor constraintEqualToAnchor:_step2View.leadingAnchor constant:16],
        [closeBtn.topAnchor constraintEqualToAnchor:backBtn.topAnchor],
        [closeBtn.trailingAnchor constraintEqualToAnchor:_step2View.trailingAnchor constant:-16],

        [titleLabel.topAnchor constraintEqualToAnchor:backBtn.bottomAnchor constant:12],
        [titleLabel.leadingAnchor constraintEqualToAnchor:_step2View.leadingAnchor constant:20],
        [stepLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:2],
        [stepLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],

        [_step2Scroll.topAnchor constraintEqualToAnchor:stepLabel.bottomAnchor constant:14],
        [_step2Scroll.leadingAnchor constraintEqualToAnchor:_step2View.leadingAnchor],
        [_step2Scroll.trailingAnchor constraintEqualToAnchor:_step2View.trailingAnchor],
        [_step2Scroll.bottomAnchor constraintEqualToAnchor:_step2View.bottomAnchor],

        [_step2Stack.topAnchor constraintEqualToAnchor:_step2Scroll.contentLayoutGuide.topAnchor constant:4],
        [_step2Stack.leadingAnchor constraintEqualToAnchor:_step2View.leadingAnchor constant:16],
        [_step2Stack.trailingAnchor constraintEqualToAnchor:_step2View.trailingAnchor constant:-16],
        [_step2Stack.bottomAnchor constraintEqualToAnchor:_step2Scroll.contentLayoutGuide.bottomAnchor constant:-32],
    ]];

    [self buildStep2Content];
}

- (void)buildStep2Content {
    for (UIView *v in [_step2Stack.arrangedSubviews copy]) {
        [_step2Stack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    [self buildRandomSetupRow];
    [self buildGPSSection];
    [self buildIdentifiersSection];
    [self buildDeviceSection];
    [self buildNetworkSpoofSection];
    [self buildSaveButton];
}

#pragma mark - Random Setup

- (void)buildRandomSetupRow {
    UIColor *accent = [MiOSTheme accentColor];
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [MiOSTheme tileBackground];
    row.layer.cornerRadius = 22;
    row.layer.cornerCurve = kCACornerCurveContinuous;
    row.layer.borderWidth = 1.0;
    row.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
    row.clipsToBounds = YES;

    UIImageSymbolConfiguration *bigCfg = [UIImageSymbolConfiguration configurationWithPointSize:70 weight:UIImageSymbolWeightBold];
    UIImageView *watermark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"dice.fill" withConfiguration:bigCfg]];
    watermark.translatesAutoresizingMaskIntoConstraints = NO;
    watermark.tintColor = [accent colorWithAlphaComponent:0.08];
    watermark.transform = CGAffineTransformMakeRotation(0.25);
    [row addSubview:watermark];

    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [accent colorWithAlphaComponent:0.18];
    iconCircle.layer.cornerRadius = 20;
    [row addSubview:iconCircle];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
    UIImageView *dice = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"dice.fill" withConfiguration:cfg]];
    dice.translatesAutoresizingMaskIntoConstraints = NO;
    dice.tintColor = accent;
    [iconCircle addSubview:dice];

    UILabel *title = [self labelWithFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] color:[MiOSTheme primaryText]];
    title.text = @"Random Setup";
    [row addSubview:title];
    UILabel *sub = [self labelWithFont:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium] color:[MiOSTheme secondaryText]];
    sub.text = @"Randomize location, device & IDs";
    [row addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:68],
        [watermark.centerXAnchor constraintEqualToAnchor:row.trailingAnchor constant:-30],
        [watermark.centerYAnchor constraintEqualToAnchor:row.centerYAnchor constant:6],
        [iconCircle.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [iconCircle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [iconCircle.widthAnchor constraintEqualToConstant:40],
        [iconCircle.heightAnchor constraintEqualToConstant:40],
        [dice.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [dice.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:12],
        [title.bottomAnchor constraintEqualToAnchor:row.centerYAnchor constant:-1],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:row.centerYAnchor constant:2],
    ]];

    [row addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(randomSetupTapped)]];
    [_step2Stack addArrangedSubview:row];
}

- (void)randomSetupTapped {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];

    _gpsEnabled = YES;
    _selectedLatitude = (double)arc4random_uniform(140000000) / 1000000.0 - 60.0;
    _selectedLongitude = (double)arc4random_uniform(360000000) / 1000000.0 - 180.0;
    _selectedLocationName = nil;

    _deviceSpoofEnabled = YES;
    if (_deviceList.count > 0) {
        _selectedDeviceIndex = arc4random_uniform((uint32_t)_deviceList.count);
        [self updateIOSVersionsForDeviceQuiet];
        if (_iosVersionList.count > 0) _selectedIOSIndex = arc4random_uniform((uint32_t)_iosVersionList.count);
        MiOSDeviceModel *device = _deviceList[_selectedDeviceIndex];
        if (device.storageOptions.count > 0) _selectedStorageIndex = arc4random_uniform((uint32_t)device.storageOptions.count);
    }

    _spoofDeviceCheck = YES;
    _spoofVendorID = YES;
    _vendorID = [[NSUUID UUID] UUIDString];
    _spoofAdvertisingID = YES;
    _advertisingID = [[NSUUID UUID] UUIDString];
    _spoofCloudToken = YES;

    _spoofCarrier = YES;
    _spoofWiFi = YES;
    _spoofBattery = NO;
    _spoofLocale = NO;
    [self randomizeCarrier];
    [self randomizeWiFi];

    [self buildStep2Content];

    UIView *flash = [[UIView alloc] initWithFrame:self.view.bounds];
    flash.userInteractionEnabled = NO;
    flash.backgroundColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.10];
    [self.view addSubview:flash];
    [UIView animateWithDuration:0.5 animations:^{
        flash.alpha = 0;
    } completion:^(BOOL finished) {
        [flash removeFromSuperview];
    }];
}

#pragma mark - GPS Section

- (void)buildGPSSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"GPS Spoofing"];

    MiOSToggleCell *gpsToggle = [[MiOSToggleCell alloc] initWithTitle:@"Enable GPS Spoof"
                                                              subtitle:@"Override device location"
                                                                  icon:@"location.fill"
                                                                 color:[UIColor systemBlueColor]
                                                                   key:@"gpsEnabled"];
    gpsToggle.isOn = _gpsEnabled;
    gpsToggle.delegate = self;
    [section addCellView:gpsToggle];

    _gpsMapContainer = [[UIView alloc] init];
    _gpsMapContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _gpsMapContainer.hidden = !_gpsEnabled;

    UIView *mapWrapper = [[UIView alloc] init];
    mapWrapper.translatesAutoresizingMaskIntoConstraints = NO;
    mapWrapper.layer.cornerRadius = 18;
    mapWrapper.layer.cornerCurve = kCACornerCurveContinuous;
    mapWrapper.clipsToBounds = YES;
    mapWrapper.layer.borderColor = [MiOSTheme hairline].CGColor;
    mapWrapper.layer.borderWidth = 1.0;
    [_gpsMapContainer addSubview:mapWrapper];

    _mapView = [[MKMapView alloc] init];
    _mapView.translatesAutoresizingMaskIntoConstraints = NO;
    _mapView.delegate = self;
    _mapView.mapType = MKMapTypeStandard;
    _mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [mapWrapper addSubview:_mapView];

    _locationSearchBar = [[UISearchBar alloc] init];
    _locationSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _locationSearchBar.placeholder = @"Search location";
    _locationSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    _locationSearchBar.backgroundImage = [UIImage new];
    _locationSearchBar.delegate = self;
    _locationSearchBar.tintColor = [MiOSTheme accentColor];
    _locationSearchBar.searchTextField.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.96];
    _locationSearchBar.searchTextField.textColor = [MiOSTheme primaryText];
    _locationSearchBar.searchTextField.layer.cornerRadius = 12;
    _locationSearchBar.searchTextField.clipsToBounds = YES;
    [mapWrapper addSubview:_locationSearchBar];

    _locationSearchResultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _locationSearchResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    _locationSearchResultsTable.dataSource = self;
    _locationSearchResultsTable.delegate = self;
    _locationSearchResultsTable.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.97];
    _locationSearchResultsTable.separatorColor = [MiOSTheme hairline];
    _locationSearchResultsTable.rowHeight = 48;
    _locationSearchResultsTable.hidden = YES;
    _locationSearchResultsTable.layer.cornerRadius = 14;
    _locationSearchResultsTable.clipsToBounds = YES;
    [mapWrapper addSubview:_locationSearchResultsTable];

    [NSLayoutConstraint activateConstraints:@[
        [mapWrapper.topAnchor constraintEqualToAnchor:_gpsMapContainer.topAnchor constant:4],
        [mapWrapper.leadingAnchor constraintEqualToAnchor:_gpsMapContainer.leadingAnchor constant:12],
        [mapWrapper.trailingAnchor constraintEqualToAnchor:_gpsMapContainer.trailingAnchor constant:-12],
        [mapWrapper.heightAnchor constraintEqualToConstant:250],
        [_mapView.topAnchor constraintEqualToAnchor:mapWrapper.topAnchor],
        [_mapView.leadingAnchor constraintEqualToAnchor:mapWrapper.leadingAnchor],
        [_mapView.trailingAnchor constraintEqualToAnchor:mapWrapper.trailingAnchor],
        [_mapView.bottomAnchor constraintEqualToAnchor:mapWrapper.bottomAnchor],
        [_locationSearchBar.topAnchor constraintEqualToAnchor:mapWrapper.topAnchor constant:4],
        [_locationSearchBar.leadingAnchor constraintEqualToAnchor:mapWrapper.leadingAnchor constant:2],
        [_locationSearchBar.trailingAnchor constraintEqualToAnchor:mapWrapper.trailingAnchor constant:-2],
        [_locationSearchResultsTable.topAnchor constraintEqualToAnchor:_locationSearchBar.bottomAnchor],
        [_locationSearchResultsTable.leadingAnchor constraintEqualToAnchor:mapWrapper.leadingAnchor constant:10],
        [_locationSearchResultsTable.trailingAnchor constraintEqualToAnchor:mapWrapper.trailingAnchor constant:-10],
        [_locationSearchResultsTable.heightAnchor constraintLessThanOrEqualToConstant:192],
    ]];

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [_mapView addGestureRecognizer:longPress];
    [_mapView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)]];

    if (_selectedLatitude != 0 || _selectedLongitude != 0) {
        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(_selectedLatitude, _selectedLongitude);
        [_mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 5000, 5000) animated:NO];
        _mapPin = [[MKPointAnnotation alloc] init];
        _mapPin.coordinate = coord;
        _mapPin.title = @"Spoofed Location";
        [_mapView addAnnotation:_mapPin];
    } else {
        _mapPin = nil;
        CLLocationCoordinate2D fallback = CLLocationCoordinate2DMake(37.7749, -122.4194);
        [_mapView setRegion:MKCoordinateRegionMakeWithDistance(fallback, 400000, 400000) animated:NO];
    }

    _coordLabel = [self labelWithFont:[MiOSTheme monoFont] color:[MiOSTheme accentColor]];
    _coordLabel.textAlignment = NSTextAlignmentCenter;
    _coordLabel.adjustsFontSizeToFitWidth = YES;
    _coordLabel.minimumScaleFactor = 0.7;
    [_gpsMapContainer addSubview:_coordLabel];
    [self updateCoordLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_coordLabel.topAnchor constraintEqualToAnchor:mapWrapper.bottomAnchor constant:10],
        [_coordLabel.leadingAnchor constraintEqualToAnchor:_gpsMapContainer.leadingAnchor constant:16],
        [_coordLabel.trailingAnchor constraintEqualToAnchor:_gpsMapContainer.trailingAnchor constant:-16],
        [_coordLabel.bottomAnchor constraintEqualToAnchor:_gpsMapContainer.bottomAnchor constant:-12],
    ]];

    [section addCellView:_gpsMapContainer];
    [_step2Stack addArrangedSubview:section];
}

- (void)updateCoordLabel {
    NSString *coords = [NSString stringWithFormat:@"%.5f, %.5f", _selectedLatitude, _selectedLongitude];
    _coordLabel.text = _selectedLocationName.length > 0
        ? [NSString stringWithFormat:@"%@  ·  %@", _selectedLocationName, coords] : coords;
}

- (void)setMapLocationToCoordinate:(CLLocationCoordinate2D)coord {
    _selectedLatitude = coord.latitude;
    _selectedLongitude = coord.longitude;
    if (!_mapPin) {
        _mapPin = [[MKPointAnnotation alloc] init];
        _mapPin.title = @"Spoofed Location";
        [_mapView addAnnotation:_mapPin];
    }
    _mapPin.coordinate = coord;
    [self updateCoordLabel];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint point = [gesture locationInView:_mapView];
    _selectedLocationName = nil;
    [self setMapLocationToCoordinate:[_mapView convertPoint:point toCoordinateFromView:_mapView]];
}

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    if (!_locationSearchResultsTable.hidden) {
        _locationSearchResultsTable.hidden = YES;
        [_locationSearchBar resignFirstResponder];
        return;
    }
    CGPoint point = [gesture locationInView:_mapView];
    _selectedLocationName = nil;
    [self setMapLocationToCoordinate:[_mapView convertPoint:point toCoordinateFromView:_mapView]];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    MKMarkerAnnotationView *marker = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"pin"];
    if (!marker) marker = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"pin"];
    marker.annotation = annotation;
    marker.markerTintColor = [MiOSTheme accentColor];
    marker.animatesWhenAdded = YES;
    return marker;
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    _locationSearchResults = completer.results;
    _locationSearchResultsTable.hidden = (_locationSearchResults.count == 0);
    [_locationSearchResultsTable reloadData];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
}

#pragma mark - Identifiers Section

- (void)buildIdentifiersSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Identity & Privacy"];

    MiOSToggleCell *deviceCheckCell = [[MiOSToggleCell alloc] initWithTitle:@"DeviceCheck Bypass"
                                                                    subtitle:@"Block DeviceCheck token generation"
                                                                        icon:@"checkmark.shield.fill"
                                                                       color:[UIColor systemRedColor]
                                                                         key:@"spoofDeviceCheck"];
    deviceCheckCell.isOn = _spoofDeviceCheck;
    deviceCheckCell.delegate = self;
    [section addCellView:deviceCheckCell];
    [section addSeparator];

    MiOSToggleCell *vendorCell = [[MiOSToggleCell alloc] initWithTitle:@"Vendor ID Spoof"
                                                               subtitle:@"Spoof identifierForVendor"
                                                                   icon:@"person.badge.key.fill"
                                                                  color:[UIColor systemIndigoColor]
                                                                    key:@"spoofVendorID"];
    vendorCell.isOn = _spoofVendorID;
    vendorCell.delegate = self;
    [section addCellView:vendorCell];

    UILabel *vendorLabelOut = nil;
    _vendorIDContainer = [self buildUUIDRowWithValue:_vendorID ?: @"Not generated" labelOut:&vendorLabelOut
                                         generateSel:@selector(generateVendorID)];
    _vendorIDLabel = vendorLabelOut;
    _vendorIDContainer.hidden = !_spoofVendorID;
    [section addCellView:_vendorIDContainer];
    [section addSeparator];

    MiOSToggleCell *adCell = [[MiOSToggleCell alloc] initWithTitle:@"Advertising ID Spoof"
                                                           subtitle:@"Spoof advertisingIdentifier"
                                                               icon:@"megaphone.fill"
                                                              color:[UIColor systemOrangeColor]
                                                                key:@"spoofAdvertisingID"];
    adCell.isOn = _spoofAdvertisingID;
    adCell.delegate = self;
    [section addCellView:adCell];

    UILabel *adLabelOut = nil;
    _advertisingIDContainer = [self buildUUIDRowWithValue:_advertisingID ?: @"Not generated" labelOut:&adLabelOut
                                              generateSel:@selector(generateAdvertisingID)];
    _advertisingIDLabel = adLabelOut;
    _advertisingIDContainer.hidden = !_spoofAdvertisingID;
    [section addCellView:_advertisingIDContainer];
    [section addSeparator];

    MiOSToggleCell *cloudCell = [[MiOSToggleCell alloc] initWithTitle:@"iCloud Token Spoof"
                                                              subtitle:@"Return nil for ubiquityIdentityToken"
                                                                  icon:@"icloud.slash.fill"
                                                                 color:[UIColor systemGrayColor]
                                                                   key:@"spoofCloudToken"];
    cloudCell.isOn = _spoofCloudToken;
    cloudCell.delegate = self;
    [section addCellView:cloudCell];

    [_step2Stack addArrangedSubview:section];
}

- (UIView *)buildUUIDRowWithValue:(NSString *)value labelOut:(UILabel **)outLabel generateSel:(SEL)sel {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *valueLabel = [self labelWithFont:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]
                                        color:[MiOSTheme secondaryText]];
    valueLabel.text = value;
    valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addSubview:valueLabel];
    if (outLabel) *outLabel = valueLabel;

    UIButton *genBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    genBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [genBtn setTitle:@"Generate" forState:UIControlStateNormal];
    genBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [genBtn setTitleColor:[MiOSTheme accentColor] forState:UIControlStateNormal];
    genBtn.backgroundColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.14];
    genBtn.layer.cornerRadius = 12;
    genBtn.layer.cornerCurve = kCACornerCurveContinuous;
    genBtn.contentEdgeInsets = UIEdgeInsetsMake(6, 14, 6, 14);
    [genBtn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:genBtn];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:44],
        [valueLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:54],
        [valueLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [valueLabel.trailingAnchor constraintLessThanOrEqualToAnchor:genBtn.leadingAnchor constant:-8],
        [genBtn.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-12],
        [genBtn.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

- (void)generateVendorID {
    _vendorID = [[NSUUID UUID] UUIDString];
    _vendorIDLabel.text = _vendorID;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)generateAdvertisingID {
    _advertisingID = [[NSUUID UUID] UUIDString];
    _advertisingIDLabel.text = _advertisingID;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

#pragma mark - Device Section

- (UIView *)specPillWithIcon:(NSString *)icon label:(UILabel *)label accessory:(NSString *)accessory {
    UIView *pill = [[UIView alloc] init];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    pill.layer.cornerRadius = 12;
    pill.layer.cornerCurve = kCACornerCurveContinuous;
    pill.layer.borderWidth = 1.0;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightSemibold];
    UIImageView *iv = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:icon withConfiguration:cfg]];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tintColor = [MiOSTheme secondaryText];
    iv.contentMode = UIViewContentModeCenter;
    [pill addSubview:iv];

    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    [pill addSubview:label];

    NSMutableArray *constraints = [@[
        [iv.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
        [iv.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
        [iv.widthAnchor constraintEqualToConstant:18],
        [label.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:8],
        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
    ] mutableCopy];

    if (accessory) {
        UIImageSymbolConfiguration *acfg = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold];
        UIImageView *acc = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:accessory withConfiguration:acfg]];
        acc.translatesAutoresizingMaskIntoConstraints = NO;
        acc.tintColor = [MiOSTheme accentColor];
        [pill addSubview:acc];
        [constraints addObjectsFromArray:@[
            [acc.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
            [acc.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor],
            [label.trailingAnchor constraintLessThanOrEqualToAnchor:acc.leadingAnchor constant:-6],
        ]];
    } else {
        [constraints addObject:[label.trailingAnchor constraintLessThanOrEqualToAnchor:pill.trailingAnchor constant:-10]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return pill;
}

- (UIView *)pickerTileWithBadge:(UIView *)badge title:(UILabel *)title subtitle:(NSString *)subtitle action:(SEL)action {
    UIView *tile = [[UIView alloc] init];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    tile.layer.cornerRadius = 16;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    tile.layer.borderWidth = 1.0;
    tile.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.08].CGColor;

    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [tile addSubview:badge];

    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.7;
    [tile addSubview:title];

    UILabel *sub = [self labelWithFont:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium] color:[MiOSTheme secondaryText]];
    sub.text = subtitle;
    [tile addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:tile.leadingAnchor constant:10],
        [badge.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:40],
        [badge.heightAnchor constraintEqualToConstant:40],
        [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:10],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:tile.trailingAnchor constant:-8],
        [title.bottomAnchor constraintEqualToAnchor:tile.centerYAnchor constant:-1],
        [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [sub.trailingAnchor constraintLessThanOrEqualToAnchor:tile.trailingAnchor constant:-8],
        [sub.topAnchor constraintEqualToAnchor:tile.centerYAnchor constant:2],
    ]];

    [tile addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:action]];
    return tile;
}

- (void)buildDeviceSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Device Spoofing"];
    UIColor *accent = [MiOSTheme accentColor];

    MiOSToggleCell *deviceToggle = [[MiOSToggleCell alloc] initWithTitle:@"Enable Device Spoof"
                                                                 subtitle:@"Spoof device model and iOS version"
                                                                     icon:@"iphone.gen3"
                                                                    color:[UIColor systemTealColor]
                                                                      key:@"deviceSpoofEnabled"];
    deviceToggle.isOn = _deviceSpoofEnabled;
    deviceToggle.delegate = self;
    [section addCellView:deviceToggle];

    _deviceCardContainer = [[UIView alloc] init];
    _deviceCardContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceCardContainer.hidden = !_deviceSpoofEnabled;

    MiOSGradientView *card = [[MiOSGradientView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [card setColors:@[MiOSMix([MiOSTheme tileBackground], accent, 0.30),
                      MiOSMix([MiOSTheme tileBackground], [MiOSTheme accentGradientEnd], 0.12)]
              start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [accent colorWithAlphaComponent:0.30].CGColor;
    card.clipsToBounds = YES;
    [_deviceCardContainer addSubview:card];

    _deviceImageView = [[UIImageView alloc] init];
    _deviceImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceImageView.contentMode = UIViewContentModeScaleAspectFit;
    _deviceImageView.userInteractionEnabled = YES;
    [_deviceImageView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chooseDeviceTapped)]];
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(nextDeviceTapped)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [_deviceImageView addGestureRecognizer:swipeLeft];
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(prevDeviceTapped)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [_deviceImageView addGestureRecognizer:swipeRight];
    [card addSubview:_deviceImageView];

    UIFont *pillFont = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _deviceNameValue = [self labelWithFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] color:[MiOSTheme primaryText]];
    _deviceIdentifierValue = [self labelWithFont:pillFont color:[MiOSTheme primaryText]];
    _deviceChipValue = [self labelWithFont:pillFont color:[MiOSTheme primaryText]];
    _deviceMemoryValue = [self labelWithFont:pillFont color:[MiOSTheme primaryText]];

    UIView *namePill = [self specPillWithIcon:@"iphone" label:_deviceNameValue accessory:@"chevron.up.chevron.down"];
    [namePill addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chooseDeviceTapped)]];

    UIStackView *pills = [[UIStackView alloc] initWithArrangedSubviews:@[
        namePill,
        [self specPillWithIcon:@"number" label:_deviceIdentifierValue accessory:nil],
        [self specPillWithIcon:@"cpu" label:_deviceChipValue accessory:nil],
        [self specPillWithIcon:@"memorychip" label:_deviceMemoryValue accessory:nil],
    ]];
    pills.translatesAutoresizingMaskIntoConstraints = NO;
    pills.axis = UILayoutConstraintAxisVertical;
    pills.spacing = 8;
    pills.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:pills];

    // iOS version tile with an iOS-style numbered badge.
    MiOSGradientView *iosBadge = [[MiOSGradientView alloc] init];
    [iosBadge setColors:@[accent, [MiOSTheme accentGradientEnd]] start:CGPointMake(0, 0) end:CGPointMake(1, 1)];
    iosBadge.layer.cornerRadius = 11;
    iosBadge.layer.cornerCurve = kCACornerCurveContinuous;
    iosBadge.clipsToBounds = YES;
    _iosBadgeLabel = [self labelWithFont:[UIFont systemFontOfSize:18 weight:UIFontWeightBold] color:[MiOSTheme textColorOnAccent]];
    _iosBadgeLabel.textAlignment = NSTextAlignmentCenter;
    [iosBadge addSubview:_iosBadgeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_iosBadgeLabel.centerXAnchor constraintEqualToAnchor:iosBadge.centerXAnchor],
        [_iosBadgeLabel.centerYAnchor constraintEqualToAnchor:iosBadge.centerYAnchor],
    ]];
    _iosTitleLabel = [self labelWithFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] color:[MiOSTheme primaryText]];
    _iosTile = [self pickerTileWithBadge:iosBadge title:_iosTitleLabel subtitle:@"Choose Version" action:@selector(iosVersionButtonTapped)];

    UIView *storageBadge = [[UIView alloc] init];
    storageBadge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    storageBadge.layer.cornerRadius = 11;
    storageBadge.layer.cornerCurve = kCACornerCurveContinuous;
    UIImageSymbolConfiguration *driveCfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightSemibold];
    UIImageView *drive = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"internaldrive.fill" withConfiguration:driveCfg]];
    drive.translatesAutoresizingMaskIntoConstraints = NO;
    drive.tintColor = [UIColor colorWithWhite:1 alpha:0.9];
    [storageBadge addSubview:drive];
    [NSLayoutConstraint activateConstraints:@[
        [drive.centerXAnchor constraintEqualToAnchor:storageBadge.centerXAnchor],
        [drive.centerYAnchor constraintEqualToAnchor:storageBadge.centerYAnchor],
    ]];
    _storageTitleLabel = [self labelWithFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] color:[MiOSTheme primaryText]];
    _storageTile = [self pickerTileWithBadge:storageBadge title:_storageTitleLabel subtitle:@"Choose Storage" action:@selector(storageTapped)];

    UIStackView *pickers = [[UIStackView alloc] initWithArrangedSubviews:@[_iosTile, _storageTile]];
    pickers.translatesAutoresizingMaskIntoConstraints = NO;
    pickers.axis = UILayoutConstraintAxisHorizontal;
    pickers.spacing = 10;
    pickers.distribution = UIStackViewDistributionFillEqually;
    [card addSubview:pickers];

    [NSLayoutConstraint activateConstraints:@[
        [card.topAnchor constraintEqualToAnchor:_deviceCardContainer.topAnchor constant:4],
        [card.leadingAnchor constraintEqualToAnchor:_deviceCardContainer.leadingAnchor constant:12],
        [card.trailingAnchor constraintEqualToAnchor:_deviceCardContainer.trailingAnchor constant:-12],
        [card.bottomAnchor constraintEqualToAnchor:_deviceCardContainer.bottomAnchor constant:-12],

        [pills.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
        [pills.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [pills.widthAnchor constraintEqualToAnchor:card.widthAnchor multiplier:0.52],
        [pills.heightAnchor constraintEqualToConstant:34 * 4 + 8 * 3],

        [_deviceImageView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:6],
        [_deviceImageView.trailingAnchor constraintEqualToAnchor:pills.leadingAnchor constant:-6],
        [_deviceImageView.centerYAnchor constraintEqualToAnchor:pills.centerYAnchor],
        [_deviceImageView.heightAnchor constraintEqualToConstant:156],

        [pickers.topAnchor constraintEqualToAnchor:pills.bottomAnchor constant:14],
        [pickers.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [pickers.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [pickers.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12],
        [pickers.heightAnchor constraintEqualToConstant:62],
    ]];

    [section addCellView:_deviceCardContainer];
    [section addSeparator];

    MiOSToggleCell *nameToggle = [[MiOSToggleCell alloc] initWithTitle:@"Custom Device Name"
                                                               subtitle:@"Override reported device name"
                                                                   icon:@"pencil.line"
                                                                  color:[UIColor systemPurpleColor]
                                                                    key:@"spoofDeviceName"];
    nameToggle.isOn = _spoofDeviceName;
    nameToggle.delegate = self;
    [section addCellView:nameToggle];

    _customDeviceNameContainer = [[UIView alloc] init];
    _customDeviceNameContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _customDeviceNameContainer.hidden = !_spoofDeviceName;
    _customDeviceNameField = [self pillFieldWithPlaceholder:@"Custom device name" icon:@"character.cursor.ibeam"];
    _customDeviceNameField.text = _customDeviceNameText;
    [_customDeviceNameField addTarget:self action:@selector(customNameChanged:) forControlEvents:UIControlEventEditingChanged];
    UIButton *nameRnd = [self randomizeButtonWithSel:@selector(randomizeDeviceName)];
    [_customDeviceNameContainer addSubview:_customDeviceNameField];
    [_customDeviceNameContainer addSubview:nameRnd];
    [NSLayoutConstraint activateConstraints:@[
        [_customDeviceNameField.topAnchor constraintEqualToAnchor:_customDeviceNameContainer.topAnchor constant:2],
        [_customDeviceNameField.leadingAnchor constraintEqualToAnchor:_customDeviceNameContainer.leadingAnchor constant:12],
        [_customDeviceNameField.heightAnchor constraintEqualToConstant:46],
        [_customDeviceNameField.bottomAnchor constraintEqualToAnchor:_customDeviceNameContainer.bottomAnchor constant:-12],
        [nameRnd.leadingAnchor constraintEqualToAnchor:_customDeviceNameField.trailingAnchor constant:8],
        [nameRnd.trailingAnchor constraintEqualToAnchor:_customDeviceNameContainer.trailingAnchor constant:-12],
        [nameRnd.centerYAnchor constraintEqualToAnchor:_customDeviceNameField.centerYAnchor],
        [nameRnd.widthAnchor constraintEqualToConstant:46],
        [nameRnd.heightAnchor constraintEqualToConstant:46],
    ]];
    [section addCellView:_customDeviceNameContainer];

    [_step2Stack addArrangedSubview:section];
    [self updateDeviceCardUIAnimated:NO];
}

- (void)customNameChanged:(UITextField *)field {
    _customDeviceNameText = field.text;
}

- (void)randomizeDeviceName {
    NSArray *names = [[self class] deviceNameTemplates];
    _customDeviceNameText = names[arc4random_uniform((uint32_t)names.count)];
    _customDeviceNameField.text = _customDeviceNameText;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

// Ghost-style carrier table: {name, MCC, MNC, ISO}.
+ (NSArray<NSArray<NSString *> *> *)carrierTable {
    return @[
        @[@"Verizon",    @"311", @"480", @"us"],
        @[@"AT&T",       @"310", @"410", @"us"],
        @[@"T-Mobile",   @"310", @"260", @"us"],
        @[@"Sprint",     @"310", @"120", @"us"],
        @[@"Vodafone",   @"234", @"15",  @"gb"],
        @[@"EE",         @"234", @"30",  @"gb"],
        @[@"O2",         @"234", @"10",  @"gb"],
        @[@"Three",      @"234", @"20",  @"gb"],
        @[@"Orange",     @"208", @"01",  @"fr"],
        @[@"SFR",        @"208", @"10",  @"fr"],
        @[@"Telekom",    @"262", @"01",  @"de"],
        @[@"Vodafone",   @"262", @"02",  @"de"],
        @[@"TIM",        @"222", @"01",  @"it"],
        @[@"Movistar",   @"214", @"07",  @"es"],
        @[@"MTS",        @"250", @"01",  @"ru"],
        @[@"Beeline",    @"250", @"99",  @"ru"],
        @[@"MegaFon",    @"250", @"02",  @"ru"],
        @[@"Rogers",     @"302", @"720", @"ca"],
        @[@"Bell",       @"302", @"610", @"ca"],
        @[@"Telstra",    @"505", @"01",  @"au"],
        @[@"NTT docomo", @"440", @"10",  @"jp"],
        @[@"SK Telecom", @"450", @"05",  @"kr"],
    ];
}

// Ghost-style Wi-Fi SSID bases.
+ (NSArray<NSString *> *)ssidBases {
    return @[@"NETGEAR", @"Linksys", @"TP-Link", @"ASUS", @"dlink", @"Xfinity",
             @"ATT-WiFi", @"HOME", @"MyWiFi", @"orbi", @"eero", @"Spectrum"];
}

// Ghost-style device names.
+ (NSArray<NSString *> *)deviceNameTemplates {
    return @[@"iPhone", @"John's iPhone", @"Emma's iPhone", @"Michael's iPhone",
             @"Sarah's iPhone", @"David's iPhone", @"iPhone 15 Pro", @"My iPhone",
             @"Alex's iPhone", @"Olivia's iPhone", @"James's iPhone", @"Mom's iPhone"];
}

- (NSString *)randomHexByte {
    return [NSString stringWithFormat:@"%02X", arc4random_uniform(256)];
}

- (NSString *)randomBSSID {
    return [NSString stringWithFormat:@"%@:%@:%@:%@:%@:%@",
            [self randomHexByte], [self randomHexByte], [self randomHexByte],
            [self randomHexByte], [self randomHexByte], [self randomHexByte]];
}

- (void)buildNetworkSpoofSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Network & Sensors"];

    // --- Carrier ---
    MiOSToggleCell *carrierToggle = [[MiOSToggleCell alloc] initWithTitle:@"Carrier Spoof"
                                                                 subtitle:@"Fake carrier name, MCC/MNC & country"
                                                                     icon:@"antenna.radiowaves.left.and.right"
                                                                    color:[UIColor systemGreenColor]
                                                                      key:@"spoofCarrier"];
    carrierToggle.isOn = _spoofCarrier;
    carrierToggle.delegate = self;
    [section addCellView:carrierToggle];

    _carrierContainer = [[UIView alloc] init];
    _carrierContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _carrierContainer.hidden = !_spoofCarrier;
    _carrierField = [self pillFieldWithPlaceholder:@"Carrier name" icon:@"antenna.radiowaves.left.and.right"];
    _carrierField.text = _carrierName;
    [_carrierField addTarget:self action:@selector(carrierFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    UIButton *carrierRnd = [self randomizeButtonWithSel:@selector(randomizeCarrier)];
    [_carrierContainer addSubview:_carrierField];
    [_carrierContainer addSubview:carrierRnd];
    [NSLayoutConstraint activateConstraints:@[
        [_carrierField.topAnchor constraintEqualToAnchor:_carrierContainer.topAnchor constant:2],
        [_carrierField.leadingAnchor constraintEqualToAnchor:_carrierContainer.leadingAnchor constant:12],
        [_carrierField.heightAnchor constraintEqualToConstant:46],
        [_carrierField.bottomAnchor constraintEqualToAnchor:_carrierContainer.bottomAnchor constant:-12],
        [carrierRnd.leadingAnchor constraintEqualToAnchor:_carrierField.trailingAnchor constant:8],
        [carrierRnd.trailingAnchor constraintEqualToAnchor:_carrierContainer.trailingAnchor constant:-12],
        [carrierRnd.centerYAnchor constraintEqualToAnchor:_carrierField.centerYAnchor],
        [carrierRnd.widthAnchor constraintEqualToConstant:46],
        [carrierRnd.heightAnchor constraintEqualToConstant:46],
    ]];
    [section addCellView:_carrierContainer];
    [section addSeparator];

    // --- Wi-Fi ---
    MiOSToggleCell *wifiToggle = [[MiOSToggleCell alloc] initWithTitle:@"Wi-Fi Spoof"
                                                             subtitle:@"Fake SSID & BSSID for this container"
                                                                 icon:@"wifi"
                                                                color:[UIColor systemBlueColor]
                                                                  key:@"spoofWiFi"];
    wifiToggle.isOn = _spoofWiFi;
    wifiToggle.delegate = self;
    [section addCellView:wifiToggle];

    _wifiContainer = [[UIView alloc] init];
    _wifiContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _wifiContainer.hidden = !_spoofWiFi;
    _wifiSSIDField = [self pillFieldWithPlaceholder:@"Wi-Fi SSID" icon:@"wifi"];
    _wifiSSIDField.text = _wifiSSID;
    [_wifiSSIDField addTarget:self action:@selector(wifiSSIDChanged:) forControlEvents:UIControlEventEditingChanged];
    _wifiBSSIDField = [self pillFieldWithPlaceholder:@"BSSID (AA:BB:CC:DD:EE:FF)" icon:@"dot.radiowaves.left.and.right"];
    _wifiBSSIDField.text = _wifiBSSID;
    [_wifiBSSIDField addTarget:self action:@selector(wifiBSSIDChanged:) forControlEvents:UIControlEventEditingChanged];
    UIButton *wifiRnd = [self randomizeButtonWithSel:@selector(randomizeWiFi)];
    [_wifiContainer addSubview:_wifiSSIDField];
    [_wifiContainer addSubview:_wifiBSSIDField];
    [_wifiContainer addSubview:wifiRnd];
    [NSLayoutConstraint activateConstraints:@[
        [_wifiSSIDField.topAnchor constraintEqualToAnchor:_wifiContainer.topAnchor constant:2],
        [_wifiSSIDField.leadingAnchor constraintEqualToAnchor:_wifiContainer.leadingAnchor constant:12],
        [_wifiSSIDField.heightAnchor constraintEqualToConstant:46],
        [wifiRnd.leadingAnchor constraintEqualToAnchor:_wifiSSIDField.trailingAnchor constant:8],
        [wifiRnd.trailingAnchor constraintEqualToAnchor:_wifiContainer.trailingAnchor constant:-12],
        [wifiRnd.centerYAnchor constraintEqualToAnchor:_wifiSSIDField.centerYAnchor],
        [wifiRnd.widthAnchor constraintEqualToConstant:46],
        [wifiRnd.heightAnchor constraintEqualToConstant:46],
        [_wifiBSSIDField.topAnchor constraintEqualToAnchor:_wifiSSIDField.bottomAnchor constant:8],
        [_wifiBSSIDField.leadingAnchor constraintEqualToAnchor:_wifiContainer.leadingAnchor constant:12],
        [_wifiBSSIDField.trailingAnchor constraintEqualToAnchor:_wifiContainer.trailingAnchor constant:-12],
        [_wifiBSSIDField.heightAnchor constraintEqualToConstant:46],
        [_wifiBSSIDField.bottomAnchor constraintEqualToAnchor:_wifiContainer.bottomAnchor constant:-12],
    ]];
    [section addCellView:_wifiContainer];
    [section addSeparator];

    // --- Battery ---
    MiOSToggleCell *batteryToggle = [[MiOSToggleCell alloc] initWithTitle:@"Battery Spoof"
                                                                 subtitle:@"Report a fixed battery level & state"
                                                                     icon:@"battery.100"
                                                                    color:[UIColor systemYellowColor]
                                                                      key:@"spoofBattery"];
    batteryToggle.isOn = _spoofBattery;
    batteryToggle.delegate = self;
    [section addCellView:batteryToggle];
    [section addSeparator];

    // --- Time zone ---
    MiOSToggleCell *localeToggle = [[MiOSToggleCell alloc] initWithTitle:@"Time Zone Spoof"
                                                                subtitle:@"Override reported system time zone"
                                                                    icon:@"globe"
                                                                   color:[UIColor systemIndigoColor]
                                                                     key:@"spoofLocale"];
    localeToggle.isOn = _spoofLocale;
    localeToggle.delegate = self;
    [section addCellView:localeToggle];

    [_step2Stack addArrangedSubview:section];
}

- (UIButton *)randomizeButtonWithSel:(SEL)sel {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightSemibold];
    [btn setImage:[UIImage systemImageNamed:@"shuffle" withConfiguration:cfg] forState:UIControlStateNormal];
    btn.tintColor = [MiOSTheme accentColor];
    btn.backgroundColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.14];
    btn.layer.cornerRadius = 14;
    btn.layer.cornerCurve = kCACornerCurveContinuous;
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)carrierFieldChanged:(UITextField *)f { _carrierName = f.text; }
- (void)wifiSSIDChanged:(UITextField *)f { _wifiSSID = f.text; }
- (void)wifiBSSIDChanged:(UITextField *)f { _wifiBSSID = f.text; }

- (void)randomizeCarrier {
    NSArray *table = [[self class] carrierTable];
    NSArray<NSString *> *c = table[arc4random_uniform((uint32_t)table.count)];
    _carrierName = c[0]; _carrierMCC = c[1]; _carrierMNC = c[2]; _carrierISO = c[3];
    _carrierField.text = _carrierName;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)randomizeWiFi {
    NSArray *bases = [[self class] ssidBases];
    _wifiSSID = [NSString stringWithFormat:@"%@-%04X",
                 bases[arc4random_uniform((uint32_t)bases.count)], arc4random_uniform(0xFFFF)];
    _wifiBSSID = [self randomBSSID];
    _wifiSSIDField.text = _wifiSSID;
    _wifiBSSIDField.text = _wifiBSSID;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)updateDeviceCardUIAnimated:(BOOL)animated {
    if (_selectedDeviceIndex >= (NSInteger)_deviceList.count) return;
    MiOSDeviceModel *device = _deviceList[_selectedDeviceIndex];

    UIImage *render = [MiOSDeviceImageRenderer renderDeviceForName:device.displayName
                                                              size:CGSizeMake(150, 156)
                                                       accentColor:[MiOSTheme accentColor]];
    if (animated) {
        [UIView transitionWithView:_deviceImageView duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self.deviceImageView.image = render;
        } completion:nil];
    } else {
        _deviceImageView.image = render;
    }

    _deviceNameValue.text = device.displayName;
    _deviceIdentifierValue.text = device.identifier;
    _deviceChipValue.text = device.chipName.length > 0 ? device.chipName : @"Unknown chip";
    _deviceMemoryValue.text = [NSString stringWithFormat:@"%ld GB RAM · %ld cores", (long)device.ramGB, (long)device.cpuCores];

    NSString *version = _selectedIOSIndex < (NSInteger)_iosVersionList.count ? _iosVersionList[_selectedIOSIndex] : @"";
    _iosTitleLabel.text = version.length > 0 ? [NSString stringWithFormat:@"iOS %@", version] : @"iOS";
    _iosBadgeLabel.text = [version componentsSeparatedByString:@"."].firstObject ?: @"";

    NSArray<NSNumber *> *options = device.storageOptions;
    if (_selectedStorageIndex >= (NSInteger)options.count) _selectedStorageIndex = 0;
    _storageTitleLabel.text = options.count > 0 ? [self storageTitle:options[_selectedStorageIndex].integerValue] : @"—";
}

- (NSString *)storageTitle:(NSInteger)gb {
    if (gb >= 1024 && gb % 1024 == 0) return [NSString stringWithFormat:@"%ld TB", (long)(gb / 1024)];
    return [NSString stringWithFormat:@"%ld GB", (long)gb];
}

- (void)presentSheet:(UIAlertController *)sheet from:(UIView *)source {
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = source;
        sheet.popoverPresentationController.sourceRect = source.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)storageTapped {
    MiOSDeviceModel *device = _deviceList[_selectedDeviceIndex];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose Storage" message:device.displayName
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)device.storageOptions.count; i++) {
        NSString *title = [self storageTitle:device.storageOptions[i].integerValue];
        if (i == _selectedStorageIndex) title = [title stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            weakSelf.selectedStorageIndex = i;
            [weakSelf updateDeviceCardUIAnimated:NO];
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:_storageTile];
}

- (void)iosVersionButtonTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose iOS Version"
                                                                   message:_deviceList[_selectedDeviceIndex].displayName
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)_iosVersionList.count; i++) {
        NSString *title = [NSString stringWithFormat:@"iOS %@", _iosVersionList[i]];
        if (i == _selectedIOSIndex) title = [title stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            weakSelf.selectedIOSIndex = i;
            [weakSelf updateDeviceCardUIAnimated:NO];
            [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:_iosTile];
}

- (void)chooseDeviceTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose Device" message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = (NSInteger)_deviceList.count - 1; i >= 0; i--) {
        NSString *title = _deviceList[i].displayName;
        if (i == _selectedDeviceIndex) title = [title stringByAppendingString:@"  ✓"];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            weakSelf.selectedDeviceIndex = i;
            [weakSelf deviceSelectionChanged];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet from:_deviceImageView];
}

- (void)prevDeviceTapped {
    if (_deviceList.count == 0) return;
    _selectedDeviceIndex = (_selectedDeviceIndex - 1 + (NSInteger)_deviceList.count) % (NSInteger)_deviceList.count;
    [self deviceSelectionChanged];
}

- (void)nextDeviceTapped {
    if (_deviceList.count == 0) return;
    _selectedDeviceIndex = (_selectedDeviceIndex + 1) % (NSInteger)_deviceList.count;
    [self deviceSelectionChanged];
}

- (void)deviceSelectionChanged {
    [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
    [self updateIOSVersionsForDeviceQuiet];
    _selectedStorageIndex = 0;
    [self updateDeviceCardUIAnimated:YES];
}

- (void)updateIOSVersionsForDeviceQuiet {
    if (_selectedDeviceIndex < (NSInteger)_deviceList.count) {
        _iosVersionList = [MiOSDeviceDatabase supportedIOSVersionsForDevice:_deviceList[_selectedDeviceIndex]];
    } else {
        _iosVersionList = [MiOSDeviceDatabase allIOSVersions];
    }
    if (_selectedIOSIndex >= (NSInteger)_iosVersionList.count) _selectedIOSIndex = 0;
}

#pragma mark - Save

- (void)buildSaveButton {
    MiOSPrimaryButton *saveBtn = [[MiOSPrimaryButton alloc] initWithTitle:@"Save Container" watermark:@"checkmark.seal.fill"];
    [saveBtn addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [_step2Stack addArrangedSubview:saveBtn];
}

- (void)saveTapped {
    if (![self validateStep1]) {
        [self showStep:1 animated:YES];
        return;
    }
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy] impactOccurred];

    BOOL isNew = (_editingContainer == nil);
    MiOSContainerConfig *config = _editingContainer ?: [[MiOSContainerConfig alloc] init];
    if (isNew) config.identifier = [[NSUUID UUID] UUIDString];

    config.name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    config.apps = [_selectedBundleIDs mutableCopy];

    config.gpsEnabled = _gpsEnabled;
    config.latitude = _selectedLatitude;
    config.longitude = _selectedLongitude;
    config.locationName = _selectedLocationName;

    config.deviceSpoofEnabled = _deviceSpoofEnabled;
    if (_deviceSpoofEnabled && _selectedDeviceIndex < (NSInteger)_deviceList.count) {
        MiOSDeviceModel *device = _deviceList[_selectedDeviceIndex];
        config.deviceIdentifier = device.identifier;
        config.deviceName = device.displayName;
        config.hwModel = device.hwModel;
        if (_selectedStorageIndex < (NSInteger)device.storageOptions.count) {
            config.storageSizeGB = device.storageOptions[_selectedStorageIndex].integerValue;
        }
        if (_selectedIOSIndex < (NSInteger)_iosVersionList.count) {
            config.iosVersion = _iosVersionList[_selectedIOSIndex];
        }
    }

    config.spoofDeviceName = _spoofDeviceName;
    config.customDeviceName = _spoofDeviceName
        ? [_customDeviceNameText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : config.customDeviceName;

    config.spoofDeviceCheck = _spoofDeviceCheck;
    config.spoofVendorID = _spoofVendorID;
    config.vendorID = _vendorID;
    config.spoofAdvertisingID = _spoofAdvertisingID;
    config.advertisingID = _advertisingID;
    config.spoofCloudToken = _spoofCloudToken;

    config.spoofCarrier = _spoofCarrier;
    config.carrierName = _carrierName;
    config.carrierMCC = _carrierMCC;
    config.carrierMNC = _carrierMNC;
    config.carrierISO = _carrierISO;
    config.spoofWiFi = _spoofWiFi;
    config.wifiSSID = _wifiSSID;
    config.wifiBSSID = _wifiBSSID;
    config.spoofBattery = _spoofBattery;
    config.spoofLocale = _spoofLocale;

    NSMutableArray<MiOSContainerConfig *> *all = [[MiOSContainerConfig loadAll] mutableCopy] ?: [NSMutableArray array];
    BOOL replaced = NO;
    for (NSUInteger i = 0; i < all.count; i++) {
        if ([all[i].identifier isEqualToString:config.identifier]) {
            [all replaceObjectAtIndex:i withObject:config];
            replaced = YES;
            break;
        }
    }
    if (!replaced) [all addObject:config];
    [MiOSContainerConfig saveAll:all];

    // New containers become active; edits keep the current active container.
    NSString *activeID = [MiOSContainerConfig activeContainerID];
    BOOL activeExists = NO;
    for (MiOSContainerConfig *c in all) {
        if ([c.identifier isEqualToString:activeID]) activeExists = YES;
    }
    if (isNew || !activeExists) {
        [MiOSContainerConfig setActiveContainerID:config.identifier];
        activeID = config.identifier;
    }
    if ([activeID isEqualToString:config.identifier]) [config applyToSystem];

    [MiOSAppIconProvider applyThemeForActiveContainer];
    if (_onSave) _onSave();
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_filteredApps.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MiOSAppRowCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kAppCellReuseID forIndexPath:indexPath];
    MiOSAppInfo *app = _filteredApps[indexPath.item];
    cell.iconView.image = app.icon;
    cell.nameLabel.text = app.name;
    cell.bundleLabel.text = app.bundleID;
    [cell setChecked:[_selectedBundleIDs containsObject:app.bundleID]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    MiOSAppInfo *app = _filteredApps[indexPath.item];
    if ([_selectedBundleIDs containsObject:app.bundleID]) {
        [_selectedBundleIDs removeObject:app.bundleID];
    } else {
        [_selectedBundleIDs addObject:app.bundleID];
    }

    MiOSAppRowCell *cell = (MiOSAppRowCell *)[collectionView cellForItemAtIndexPath:indexPath];
    [cell setChecked:[_selectedBundleIDs containsObject:app.bundleID]];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [self updateNextButtonTitle];

    // The first selected app drives the color scheme, live.
    if (_selectedBundleIDs.count > 0) {
        [MiOSAppIconProvider applyThemeForBundleIDs:_selectedBundleIDs];
    } else {
        [MiOSAppIconProvider applyThemeForActiveContainer];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return CGSizeMake(collectionView.bounds.size.width, 72);
}

#pragma mark - MiOSToggleCellDelegate

- (void)toggleCell:(id)cell didChangeValue:(BOOL)value forKey:(NSString *)key {
    if ([key isEqualToString:@"gpsEnabled"]) {
        _gpsEnabled = value;
        _gpsMapContainer.hidden = !value;
    } else if ([key isEqualToString:@"deviceSpoofEnabled"]) {
        _deviceSpoofEnabled = value;
        _deviceCardContainer.hidden = !value;
    } else if ([key isEqualToString:@"spoofDeviceName"]) {
        _spoofDeviceName = value;
        _customDeviceNameContainer.hidden = !value;
    } else if ([key isEqualToString:@"spoofDeviceCheck"]) {
        _spoofDeviceCheck = value;
    } else if ([key isEqualToString:@"spoofVendorID"]) {
        _spoofVendorID = value;
        _vendorIDContainer.hidden = !value;
        if (value && !_vendorID) {
            _vendorID = [[NSUUID UUID] UUIDString];
            _vendorIDLabel.text = _vendorID;
        }
    } else if ([key isEqualToString:@"spoofAdvertisingID"]) {
        _spoofAdvertisingID = value;
        _advertisingIDContainer.hidden = !value;
        if (value && !_advertisingID) {
            _advertisingID = [[NSUUID UUID] UUIDString];
            _advertisingIDLabel.text = _advertisingID;
        }
    } else if ([key isEqualToString:@"spoofCloudToken"]) {
        _spoofCloudToken = value;
    } else if ([key isEqualToString:@"spoofCarrier"]) {
        _spoofCarrier = value;
        _carrierContainer.hidden = !value;
        if (value && _carrierName.length == 0) [self randomizeCarrier];
    } else if ([key isEqualToString:@"spoofWiFi"]) {
        _spoofWiFi = value;
        _wifiContainer.hidden = !value;
        if (value && _wifiSSID.length == 0) [self randomizeWiFi];
    } else if ([key isEqualToString:@"spoofBattery"]) {
        _spoofBattery = value;
    } else if ([key isEqualToString:@"spoofLocale"]) {
        _spoofLocale = value;
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - UISearchBarDelegate (location)

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        _locationSearchResults = @[];
        _locationSearchResultsTable.hidden = YES;
        [_locationSearchResultsTable reloadData];
        return;
    }
    _searchCompleter.queryFragment = searchText;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    _locationSearchResultsTable.hidden = YES;
    NSString *query = searchBar.text;
    if (query.length == 0) return;

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    __weak typeof(self) weakSelf = self;
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.selectedLocationName = item.name;
            [weakSelf setMapLocationToCoordinate:item.placemark.coordinate];
            [weakSelf.mapView setRegion:MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 5000, 5000) animated:YES];
            searchBar.text = @"";
        });
    }];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    searchBar.showsCancelButton = NO;
    [searchBar resignFirstResponder];
    _locationSearchResults = @[];
    _locationSearchResultsTable.hidden = YES;
    [_locationSearchResultsTable reloadData];
}

#pragma mark - Location results table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MIN((NSInteger)_locationSearchResults.count, 5);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"locResult"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"locResult"];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [MiOSTheme primaryText];
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [MiOSTheme secondaryText];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    MKLocalSearchCompletion *result = _locationSearchResults[indexPath.row];
    cell.textLabel.text = result.title;
    cell.detailTextLabel.text = result.subtitle;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:cfg];
    cell.imageView.tintColor = [MiOSTheme accentColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MKLocalSearchCompletion *completion = _locationSearchResults[indexPath.row];
    NSString *displayName = completion.title;
    NSString *queryString = completion.subtitle.length > 0
        ? [NSString stringWithFormat:@"%@ %@", completion.title, completion.subtitle] : completion.title;

    _locationSearchBar.text = @"";
    _locationSearchBar.showsCancelButton = NO;
    [_locationSearchBar resignFirstResponder];
    _locationSearchResults = @[];
    _locationSearchResultsTable.hidden = YES;
    [_locationSearchResultsTable reloadData];

    __weak typeof(self) weakSelf = self;
    void (^applyCoord)(CLLocationCoordinate2D) = ^(CLLocationCoordinate2D coord) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.selectedLocationName = displayName;
            [weakSelf setMapLocationToCoordinate:coord];
            [weakSelf.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 5000, 5000) animated:YES];
        });
    };

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (item) {
            applyCoord(item.placemark.coordinate);
            return;
        }
        [[[CLGeocoder alloc] init] geocodeAddressString:queryString completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *geoErr) {
            CLLocation *loc = placemarks.firstObject.location;
            if (loc) applyCoord(loc.coordinate);
        }];
    }];
}

@end
