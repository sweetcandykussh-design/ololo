#import "MiOSGPSViewController.h"
#import "../Views/MiOSSectionCardView.h"
#import "../Views/MiOSToggleCell.h"
#import "../UI/MiOSTheme.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

static NSString *const kMiOSLocationPrefsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.locationprefs.plist";
static NSString *const kMiOSSavedLocationsPath = @"/var/mobile/Library/Preferences/MiOS/com.mios.savedlocations.plist";

@interface MiOSGPSViewController () <MKMapViewDelegate, MiOSToggleCellDelegate, UISearchBarDelegate, CLLocationManagerDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) NSMutableDictionary *locationPrefs;
@property (nonatomic, strong) NSMutableDictionary *savedLocations;
@property (nonatomic, strong) UIStackView *savedStack;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL didCenterOnUser;
@property (nonatomic, strong) MKLocalSearchCompleter *searchCompleter;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *searchResults;
@property (nonatomic, strong) UITableView *searchResultsTable;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIView *mapContainer;
@end

@implementation MiOSGPSViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GPS Spoofer";
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self loadPreferences];
    [self setupLocationManager];
    [self setupSearchCompleter];
    [self setupUI];
}

- (void)loadPreferences {
    _locationPrefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kMiOSLocationPrefsPath] mutableCopy];
    if (!_locationPrefs) {
        _locationPrefs = [@{@"enabled": @NO, @"latitude": @(0), @"longitude": @(0), @"altitude": @(0), @"accuracy": @(5)} mutableCopy];
    }
    _savedLocations = [[NSMutableDictionary dictionaryWithContentsOfFile:kMiOSSavedLocationsPath] mutableCopy];
    if (!_savedLocations) _savedLocations = [NSMutableDictionary new];
}

- (void)savePreferences {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [kMiOSLocationPrefsPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    [_locationPrefs writeToFile:kMiOSLocationPrefsPath atomically:YES];
}

- (void)saveSavedLocations {
    [_savedLocations writeToFile:kMiOSSavedLocationsPath atomically:YES];
}

- (void)setupLocationManager {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy = kCLLocationAccuracyBest;

    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = _locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }

    if (status == kCLAuthorizationStatusNotDetermined) {
        [_locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
        [self showLocationDeniedAlert];
    } else {
        [_locationManager startUpdatingLocation];
    }
}

- (void)setupSearchCompleter {
    _searchCompleter = [[MKLocalSearchCompleter alloc] init];
    _searchCompleter.delegate = self;
    _searchCompleter.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypePointOfInterest;
    _searchResults = @[];
}

- (void)showLocationDeniedAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Location Access Required"
                                                                  message:@"Please enable location services for miOS in Settings to show your current location on the map."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Open Settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager API_AVAILABLE(ios(14.0)) {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [_locationManager startUpdatingLocation];
        _mapView.showsUserLocation = YES;
    } else if (status == kCLAuthorizationStatusDenied) {
        [self showLocationDeniedAlert];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways) {
        [_locationManager startUpdatingLocation];
        _mapView.showsUserLocation = YES;
    } else if (status == kCLAuthorizationStatusDenied) {
        [self showLocationDeniedAlert];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (_didCenterOnUser) return;
    CLLocation *loc = locations.lastObject;
    if (!loc) return;

    BOOL hasStoredCoords = [_locationPrefs[@"latitude"] doubleValue] != 0 || [_locationPrefs[@"longitude"] doubleValue] != 0;
    if (hasStoredCoords) {
        _didCenterOnUser = YES;
        return;
    }

    _didCenterOnUser = YES;
    CLLocationCoordinate2D coord = loc.coordinate;
    _locationPrefs[@"latitude"] = @(coord.latitude);
    _locationPrefs[@"longitude"] = @(coord.longitude);
    [self savePreferences];

    _pin.coordinate = coord;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 5000, 5000);
    [_mapView setRegion:region animated:YES];
    [self updateCoordLabel];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
}

#pragma mark - UI

- (void)setupUI {
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    _scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
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

    [self buildToggleSection];
    [self buildMapSection];
    [self buildCoordinateSection];
    [self buildSavedLocationsSection];
    [self buildActionsSection];
}

- (void)buildToggleSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    MiOSToggleCell *enableCell = [[MiOSToggleCell alloc]
        initWithTitle:@"Enable GPS Spoof"
             subtitle:@"Override location for target apps"
                 icon:@"location.fill"
                color:[UIColor systemBlueColor]
                  key:@"enabled"];
    enableCell.isOn = [_locationPrefs[@"enabled"] boolValue];
    enableCell.delegate = self;
    [section addCellView:enableCell];

    [_mainStack addArrangedSubview:section];
}

- (void)buildMapSection {
    _mapContainer = [[UIView alloc] init];
    _mapContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _mapContainer.layer.cornerRadius = [MiOSTheme cardCornerRadius];
    _mapContainer.layer.cornerCurve = kCACornerCurveContinuous;
    _mapContainer.clipsToBounds = YES;
    _mapContainer.layer.borderColor = [MiOSTheme separator].CGColor;
    _mapContainer.layer.borderWidth = 0.5;

    _mapView = [[MKMapView alloc] init];
    _mapView.translatesAutoresizingMaskIntoConstraints = NO;
    _mapView.delegate = self;
    _mapView.mapType = MKMapTypeStandard;

    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = _locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    _mapView.showsUserLocation = (status == kCLAuthorizationStatusAuthorizedWhenInUse || status == kCLAuthorizationStatusAuthorizedAlways);

    [_mapContainer addSubview:_mapView];

    _searchBar = [[UISearchBar alloc] init];
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    _searchBar.placeholder = @"Search location...";
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.delegate = self;
    _searchBar.backgroundImage = [UIImage new];
    _searchBar.backgroundColor = [[MiOSTheme cardBackground] colorWithAlphaComponent:0.92];
    _searchBar.layer.cornerRadius = 10;
    _searchBar.clipsToBounds = YES;
    [_mapContainer addSubview:_searchBar];

    _searchResultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _searchResultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    _searchResultsTable.dataSource = self;
    _searchResultsTable.delegate = self;
    _searchResultsTable.backgroundColor = [[MiOSTheme cardBackground] colorWithAlphaComponent:0.95];
    _searchResultsTable.separatorColor = [MiOSTheme separator];
    _searchResultsTable.rowHeight = 48;
    _searchResultsTable.hidden = YES;
    _searchResultsTable.layer.cornerRadius = 10;
    _searchResultsTable.clipsToBounds = YES;
    [_mapContainer addSubview:_searchResultsTable];

    [NSLayoutConstraint activateConstraints:@[
        [_mapView.topAnchor constraintEqualToAnchor:_mapContainer.topAnchor],
        [_mapView.leadingAnchor constraintEqualToAnchor:_mapContainer.leadingAnchor],
        [_mapView.trailingAnchor constraintEqualToAnchor:_mapContainer.trailingAnchor],
        [_mapView.bottomAnchor constraintEqualToAnchor:_mapContainer.bottomAnchor],
        [_mapContainer.heightAnchor constraintEqualToConstant:300],
        [_searchBar.topAnchor constraintEqualToAnchor:_mapContainer.topAnchor constant:8],
        [_searchBar.leadingAnchor constraintEqualToAnchor:_mapContainer.leadingAnchor constant:8],
        [_searchBar.trailingAnchor constraintEqualToAnchor:_mapContainer.trailingAnchor constant:-8],
        [_searchResultsTable.topAnchor constraintEqualToAnchor:_searchBar.bottomAnchor constant:4],
        [_searchResultsTable.leadingAnchor constraintEqualToAnchor:_mapContainer.leadingAnchor constant:8],
        [_searchResultsTable.trailingAnchor constraintEqualToAnchor:_mapContainer.trailingAnchor constant:-8],
        [_searchResultsTable.bottomAnchor constraintLessThanOrEqualToAnchor:_mapContainer.bottomAnchor constant:-8],
        [_searchResultsTable.heightAnchor constraintLessThanOrEqualToConstant:192],
    ]];

    double lat = [_locationPrefs[@"latitude"] doubleValue];
    double lon = [_locationPrefs[@"longitude"] doubleValue];
    if (lat != 0 || lon != 0) {
        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat, lon);
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 5000, 5000);
        [_mapView setRegion:region animated:NO];

        _pin = [[MKPointAnnotation alloc] init];
        _pin.coordinate = coord;
        _pin.title = @"Spoofed Location";
        [_mapView addAnnotation:_pin];
    }

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [_mapView addGestureRecognizer:longPress];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    [_mapView addGestureRecognizer:tap];

    [_mainStack addArrangedSubview:_mapContainer];
}

- (void)buildCoordinateSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Coordinates"];

    _coordLabel = [[UILabel alloc] init];
    _coordLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _coordLabel.font = [MiOSTheme monoFont];
    _coordLabel.textColor = [MiOSTheme accentColor];
    _coordLabel.textAlignment = NSTextAlignmentCenter;
    _coordLabel.numberOfLines = 0;
    [self updateCoordLabel];

    UIView *coordContainer = [[UIView alloc] init];
    coordContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [coordContainer addSubview:_coordLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_coordLabel.topAnchor constraintEqualToAnchor:coordContainer.topAnchor constant:16],
        [_coordLabel.leadingAnchor constraintEqualToAnchor:coordContainer.leadingAnchor constant:16],
        [_coordLabel.trailingAnchor constraintEqualToAnchor:coordContainer.trailingAnchor constant:-16],
        [_coordLabel.bottomAnchor constraintEqualToAnchor:coordContainer.bottomAnchor constant:-16],
    ]];
    [section addCellView:coordContainer];

    [_mainStack addArrangedSubview:section];
}

- (void)buildSavedLocationsSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@"Saved Locations"];

    _savedStack = [[UIStackView alloc] init];
    _savedStack.translatesAutoresizingMaskIntoConstraints = NO;
    _savedStack.axis = UILayoutConstraintAxisVertical;
    _savedStack.spacing = 0;

    [self rebuildSavedList];
    [section addCellView:_savedStack];

    MiOSNavigationCell *addCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Save Current Location"
             subtitle:nil
                 icon:@"plus.circle.fill"
                color:[MiOSTheme success]];
    __weak typeof(self) weakSelf = self;
    addCell.tapAction = ^{ [weakSelf promptSaveLocation]; };
    [section addSeparator];
    [section addCellView:addCell];

    [_mainStack addArrangedSubview:section];
}

- (void)rebuildSavedList {
    for (UIView *v in _savedStack.arrangedSubviews) [v removeFromSuperview];

    __weak typeof(self) weakSelf = self;
    for (NSString *name in _savedLocations) {
        NSDictionary *loc = _savedLocations[name];
        double lat = [loc[@"latitude"] doubleValue];
        double lon = [loc[@"longitude"] doubleValue];
        NSString *sub = [NSString stringWithFormat:@"%.4f, %.4f", lat, lon];

        MiOSNavigationCell *cell = [[MiOSNavigationCell alloc]
            initWithTitle:name
                 subtitle:sub
                     icon:@"mappin.circle.fill"
                    color:[UIColor systemIndigoColor]];
        cell.tapAction = ^{
            weakSelf.locationPrefs[@"latitude"] = @(lat);
            weakSelf.locationPrefs[@"longitude"] = @(lon);
            [weakSelf savePreferences];
            [weakSelf updateMapPin];
            [weakSelf updateCoordLabel];
        };
        [_savedStack addArrangedSubview:cell];

        UIView *sep = [[UIView alloc] init];
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        sep.backgroundColor = [MiOSTheme separator];
        [_savedStack addArrangedSubview:sep];
        [sep.heightAnchor constraintEqualToConstant:0.5].active = YES;
    }

    if (_savedLocations.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.translatesAutoresizingMaskIntoConstraints = NO;
        empty.text = @"No saved locations yet";
        empty.font = [MiOSTheme captionFont];
        empty.textColor = [MiOSTheme tertiaryText];
        empty.textAlignment = NSTextAlignmentCenter;

        UIView *emptyContainer = [[UIView alloc] init];
        emptyContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyContainer addSubview:empty];
        [NSLayoutConstraint activateConstraints:@[
            [empty.topAnchor constraintEqualToAnchor:emptyContainer.topAnchor constant:20],
            [empty.centerXAnchor constraintEqualToAnchor:emptyContainer.centerXAnchor],
            [empty.bottomAnchor constraintEqualToAnchor:emptyContainer.bottomAnchor constant:-20],
        ]];
        [_savedStack addArrangedSubview:emptyContainer];
    }
}

- (void)buildActionsSection {
    MiOSSectionCardView *section = [[MiOSSectionCardView alloc] initWithTitle:@""];

    __weak typeof(self) weakSelf = self;

    MiOSNavigationCell *myLocCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Center on My Location"
             subtitle:nil
                 icon:@"location.circle.fill"
                color:[UIColor systemBlueColor]];
    myLocCell.tapAction = ^{
        CLLocation *loc = weakSelf.locationManager.location;
        if (loc) {
            CLLocationCoordinate2D coord = loc.coordinate;
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 2000, 2000);
            [weakSelf.mapView setRegion:region animated:YES];
        }
    };
    [section addCellView:myLocCell];
    [section addSeparator];

    MiOSNavigationCell *resetCell = [[MiOSNavigationCell alloc]
        initWithTitle:@"Reset to Real Location"
             subtitle:nil
                 icon:@"arrow.counterclockwise"
                color:[MiOSTheme destructive]];
    resetCell.tapAction = ^{
        CLLocation *loc = weakSelf.locationManager.location;
        if (loc) {
            weakSelf.locationPrefs[@"latitude"] = @(loc.coordinate.latitude);
            weakSelf.locationPrefs[@"longitude"] = @(loc.coordinate.longitude);
        }
        weakSelf.locationPrefs[@"enabled"] = @NO;
        [weakSelf savePreferences];
        [weakSelf updateMapPin];
        [weakSelf updateCoordLabel];
    };
    [section addCellView:resetCell];

    [_mainStack addArrangedSubview:section];
}

#pragma mark - Map Interactions

- (void)updateCoordLabel {
    double lat = [_locationPrefs[@"latitude"] doubleValue];
    double lon = [_locationPrefs[@"longitude"] doubleValue];
    _coordLabel.text = [NSString stringWithFormat:@"Lat: %.6f\nLon: %.6f", lat, lon];
}

- (void)updateMapPin {
    double lat = [_locationPrefs[@"latitude"] doubleValue];
    double lon = [_locationPrefs[@"longitude"] doubleValue];
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(lat, lon);

    if (!_pin) {
        _pin = [[MKPointAnnotation alloc] init];
        _pin.title = @"Spoofed Location";
        [_mapView addAnnotation:_pin];
    }
    _pin.coordinate = coord;
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 5000, 5000);
    [_mapView setRegion:region animated:YES];
}

- (void)setLocationToCoordinate:(CLLocationCoordinate2D)coord {
    _locationPrefs[@"latitude"] = @(coord.latitude);
    _locationPrefs[@"longitude"] = @(coord.longitude);
    [self savePreferences];

    if (!_pin) {
        _pin = [[MKPointAnnotation alloc] init];
        _pin.title = @"Spoofed Location";
        [_mapView addAnnotation:_pin];
    }
    _pin.coordinate = coord;
    [self updateCoordLabel];

    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    CGPoint point = [gesture locationInView:_mapView];
    CLLocationCoordinate2D coord = [_mapView convertPoint:point toCoordinateFromView:_mapView];
    [self setLocationToCoordinate:coord];
}

- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    if (!_searchResultsTable.hidden) {
        _searchResultsTable.hidden = YES;
        [_searchBar resignFirstResponder];
    }
}

- (void)promptSaveLocation {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Location"
                                                                  message:@"Enter a name for this location"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"Location name...";
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text;
        if (name.length == 0) return;
        double lat = [weakSelf.locationPrefs[@"latitude"] doubleValue];
        double lon = [weakSelf.locationPrefs[@"longitude"] doubleValue];
        weakSelf.savedLocations[name] = @{@"latitude": @(lat), @"longitude": @(lon)};
        [weakSelf saveSavedLocations];
        [weakSelf rebuildSavedList];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - MiOSToggleCellDelegate

- (void)toggleCell:(id)cell didChangeValue:(BOOL)value forKey:(NSString *)key {
    _locationPrefs[key] = @(value);
    [self savePreferences];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        _searchResults = @[];
        _searchResultsTable.hidden = YES;
        [_searchResultsTable reloadData];
        return;
    }
    _searchCompleter.queryFragment = searchText;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    _searchResultsTable.hidden = YES;

    NSString *query = searchBar.text;
    if (query.length == 0) return;

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setLocationToCoordinate:item.placemark.coordinate];
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 5000, 5000);
            [weakSelf.mapView setRegion:region animated:YES];
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
    _searchResults = @[];
    _searchResultsTable.hidden = YES;
    [_searchResultsTable reloadData];
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    _searchResults = completer.results;
    _searchResultsTable.hidden = (_searchResults.count == 0);
    [_searchResultsTable reloadData];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
}

#pragma mark - UITableViewDataSource / Delegate (search results)

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MIN(_searchResults.count, 5);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"result"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"result"];
    }
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [MiOSTheme primaryText];
    cell.textLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.textColor = [MiOSTheme secondaryText];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];

    MKLocalSearchCompletion *result = _searchResults[indexPath.row];
    cell.textLabel.text = result.title;
    cell.detailTextLabel.text = result.subtitle;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:cfg];
    cell.imageView.tintColor = [MiOSTheme accentColor];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MKLocalSearchCompletion *completion = _searchResults[indexPath.row];
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf setLocationToCoordinate:item.placemark.coordinate];
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(item.placemark.coordinate, 5000, 5000);
            [weakSelf.mapView setRegion:region animated:YES];
            weakSelf.searchBar.text = @"";
            weakSelf.searchBar.showsCancelButton = NO;
            [weakSelf.searchBar resignFirstResponder];
            weakSelf.searchResults = @[];
            weakSelf.searchResultsTable.hidden = YES;
            [weakSelf.searchResultsTable reloadData];
        });
    }];
}

@end
