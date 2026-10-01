#import "MiOSLocationPickerViewController.h"
#import "../Models/MiOSContainerConfig.h"
#import "../Views/MiOSPrimaryButton.h"
#import "../UI/MiOSTheme.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@interface MiOSLocationPickerViewController () <MKMapViewDelegate, MKLocalSearchCompleterDelegate,
    UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UITableView *resultsTable;
@property (nonatomic, strong) MKLocalSearchCompleter *completer;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *results;
@property (nonatomic, strong) UILabel *placeLabel;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) BOOL hasCoordinate;
@property (nonatomic, copy) NSString *placeName;
@end

@implementation MiOSLocationPickerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    _results = @[];

    _completer = [[MKLocalSearchCompleter alloc] init];
    _completer.delegate = self;
    _completer.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypePointOfInterest;

    if (_container.latitude != 0 || _container.longitude != 0) {
        _coordinate = CLLocationCoordinate2DMake(_container.latitude, _container.longitude);
        _hasCoordinate = YES;
        _placeName = _container.locationName;
    }

    [self buildMap];
    [self buildTopBar];
    [self buildBottomCard];
    [self refreshSelection];
}

#pragma mark - Layout

- (void)buildMap {
    _mapView = [[MKMapView alloc] init];
    _mapView.translatesAutoresizingMaskIntoConstraints = NO;
    _mapView.delegate = self;
    _mapView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self.view addSubview:_mapView];
    [NSLayoutConstraint activateConstraints:@[
        [_mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    CLLocationCoordinate2D center = _hasCoordinate ? _coordinate : CLLocationCoordinate2DMake(37.7749, -122.4194);
    CLLocationDistance span = _hasCoordinate ? 6000 : 400000;
    [_mapView setRegion:MKCoordinateRegionMakeWithDistance(center, span, span) animated:NO];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapPressed:)];
    press.minimumPressDuration = 0.35;
    [_mapView addGestureRecognizer:press];
    [_mapView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mapTapped:)]];
}

- (void)buildTopBar {
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold];
    [close setImage:[UIImage systemImageNamed:@"xmark" withConfiguration:cfg] forState:UIControlStateNormal];
    close.tintColor = [MiOSTheme primaryText];
    close.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.96];
    close.layer.cornerRadius = 22;
    close.layer.borderWidth = 1.0;
    close.layer.borderColor = [MiOSTheme hairline].CGColor;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    _searchField = [[UITextField alloc] init];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _searchField.textColor = [MiOSTheme primaryText];
    _searchField.tintColor = [MiOSTheme accentColor];
    _searchField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:@"Search city, address or place"
        attributes:@{NSForegroundColorAttributeName: [MiOSTheme tertiaryText]}];
    _searchField.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.96];
    _searchField.layer.cornerRadius = 22;
    _searchField.layer.borderWidth = 1.0;
    _searchField.layer.borderColor = [MiOSTheme hairline].CGColor;
    _searchField.returnKeyType = UIReturnKeySearch;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    _searchField.delegate = self;
    UIView *left = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 42, 44)];
    UIImageView *glass = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass" withConfiguration:cfg]];
    glass.frame = CGRectMake(14, 12, 20, 20);
    glass.contentMode = UIViewContentModeCenter;
    glass.tintColor = [MiOSTheme secondaryText];
    [left addSubview:glass];
    _searchField.leftView = left;
    _searchField.leftViewMode = UITextFieldViewModeAlways;
    [_searchField addTarget:self action:@selector(searchChanged) forControlEvents:UIControlEventEditingChanged];
    [self.view addSubview:_searchField];

    _resultsTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _resultsTable.translatesAutoresizingMaskIntoConstraints = NO;
    _resultsTable.dataSource = self;
    _resultsTable.delegate = self;
    _resultsTable.rowHeight = 54;
    _resultsTable.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.98];
    _resultsTable.separatorColor = [MiOSTheme hairline];
    _resultsTable.layer.cornerRadius = 20;
    _resultsTable.clipsToBounds = YES;
    _resultsTable.hidden = YES;
    [self.view addSubview:_resultsTable];

    [NSLayoutConstraint activateConstraints:@[
        [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [close.widthAnchor constraintEqualToConstant:44],
        [close.heightAnchor constraintEqualToConstant:44],
        [_searchField.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [_searchField.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_searchField.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-10],
        [_searchField.heightAnchor constraintEqualToConstant:44],
        [_resultsTable.topAnchor constraintEqualToAnchor:_searchField.bottomAnchor constant:8],
        [_resultsTable.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_resultsTable.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_resultsTable.heightAnchor constraintEqualToConstant:54 * 5],
    ]];
}

- (void)buildBottomCard {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [[MiOSTheme tileBackground] colorWithAlphaComponent:0.97];
    card.layer.cornerRadius = 28;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [MiOSTheme hairline].CGColor;
    card.clipsToBounds = YES;
    [self.view addSubview:card];

    UIImageSymbolConfiguration *bigCfg = [UIImageSymbolConfiguration configurationWithPointSize:90 weight:UIImageSymbolWeightBold];
    UIImageView *watermark = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"building.2.fill" withConfiguration:bigCfg]];
    watermark.translatesAutoresizingMaskIntoConstraints = NO;
    watermark.tintColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.07];
    [card addSubview:watermark];

    UIView *iconCircle = [[UIView alloc] init];
    iconCircle.translatesAutoresizingMaskIntoConstraints = NO;
    iconCircle.backgroundColor = [[MiOSTheme accentColor] colorWithAlphaComponent:0.18];
    iconCircle.layer.cornerRadius = 22;
    [card addSubview:iconCircle];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightBold];
    UIImageView *pinIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"mappin.and.ellipse" withConfiguration:cfg]];
    pinIcon.translatesAutoresizingMaskIntoConstraints = NO;
    pinIcon.tintColor = [MiOSTheme accentColor];
    [iconCircle addSubview:pinIcon];

    _placeLabel = [[UILabel alloc] init];
    _placeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _placeLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    _placeLabel.textColor = [MiOSTheme primaryText];
    [card addSubview:_placeLabel];

    _coordLabel = [[UILabel alloc] init];
    _coordLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _coordLabel.font = [MiOSTheme monoFont];
    _coordLabel.textColor = [MiOSTheme secondaryText];
    [card addSubview:_coordLabel];

    MiOSPrimaryButton *setButton = [[MiOSPrimaryButton alloc] initWithTitle:@"Set Location" watermark:@"location.fill"];
    [setButton addTarget:self action:@selector(saveTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:setButton];

    UIButton *realButton = [UIButton buttonWithType:UIButtonTypeSystem];
    realButton.translatesAutoresizingMaskIntoConstraints = NO;
    [realButton setTitle:@"Use Real Location" forState:UIControlStateNormal];
    realButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [realButton setTitleColor:[MiOSTheme secondaryText] forState:UIControlStateNormal];
    [realButton addTarget:self action:@selector(useRealLocationTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:realButton];

    UILabel *hint = [[UILabel alloc] init];
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    hint.text = @"Search, tap or long-press the map to drop the pin";
    hint.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    hint.textColor = [MiOSTheme tertiaryText];
    [card addSubview:hint];

    [NSLayoutConstraint activateConstraints:@[
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8],

        [watermark.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:18],
        [watermark.topAnchor constraintEqualToAnchor:card.topAnchor constant:-8],

        [iconCircle.topAnchor constraintEqualToAnchor:card.topAnchor constant:18],
        [iconCircle.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18],
        [iconCircle.widthAnchor constraintEqualToConstant:44],
        [iconCircle.heightAnchor constraintEqualToConstant:44],
        [pinIcon.centerXAnchor constraintEqualToAnchor:iconCircle.centerXAnchor],
        [pinIcon.centerYAnchor constraintEqualToAnchor:iconCircle.centerYAnchor],

        [_placeLabel.leadingAnchor constraintEqualToAnchor:iconCircle.trailingAnchor constant:12],
        [_placeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-18],
        [_placeLabel.bottomAnchor constraintEqualToAnchor:iconCircle.centerYAnchor constant:-1],
        [_coordLabel.leadingAnchor constraintEqualToAnchor:_placeLabel.leadingAnchor],
        [_coordLabel.topAnchor constraintEqualToAnchor:iconCircle.centerYAnchor constant:3],

        [hint.topAnchor constraintEqualToAnchor:iconCircle.bottomAnchor constant:12],
        [hint.leadingAnchor constraintEqualToAnchor:iconCircle.leadingAnchor],

        [setButton.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:14],
        [setButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [setButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [realButton.topAnchor constraintEqualToAnchor:setButton.bottomAnchor constant:6],
        [realButton.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [realButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
    ]];
}

#pragma mark - Selection

- (void)refreshSelection {
    if (_hasCoordinate) {
        if (!_pin) {
            _pin = [[MKPointAnnotation alloc] init];
            [_mapView addAnnotation:_pin];
        }
        _pin.coordinate = _coordinate;
        _placeLabel.text = _placeName.length > 0 ? _placeName : @"Dropped pin";
        _coordLabel.text = [NSString stringWithFormat:@"%.5f, %.5f", _coordinate.latitude, _coordinate.longitude];
    } else {
        _placeLabel.text = @"No location yet";
        _coordLabel.text = @"Pick a place to spoof";
    }
}

- (void)selectCoordinate:(CLLocationCoordinate2D)coord name:(NSString *)name zoom:(BOOL)zoom {
    _coordinate = coord;
    _hasCoordinate = YES;
    _placeName = name;
    [self refreshSelection];
    if (zoom) [_mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 6000, 6000) animated:YES];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
}

- (void)mapPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    CGPoint p = [gesture locationInView:_mapView];
    [self selectCoordinate:[_mapView convertPoint:p toCoordinateFromView:_mapView] name:nil zoom:NO];
}

- (void)mapTapped:(UITapGestureRecognizer *)gesture {
    if (!_resultsTable.hidden || _searchField.isFirstResponder) {
        [self hideResults];
        return;
    }
    CGPoint p = [gesture locationInView:_mapView];
    [self selectCoordinate:[_mapView convertPoint:p toCoordinateFromView:_mapView] name:nil zoom:NO];
}

- (void)hideResults {
    [_searchField resignFirstResponder];
    _resultsTable.hidden = YES;
}

#pragma mark - Actions

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)persistWithGPSEnabled:(BOOL)enabled {
    NSMutableArray<MiOSContainerConfig *> *all = [[MiOSContainerConfig loadAll] mutableCopy];
    MiOSContainerConfig *target = nil;
    for (MiOSContainerConfig *c in all) {
        if ([c.identifier isEqualToString:_container.identifier]) target = c;
    }
    if (!target) return;

    target.gpsEnabled = enabled;
    if (enabled) {
        target.latitude = _coordinate.latitude;
        target.longitude = _coordinate.longitude;
        target.locationName = _placeName ?: @"";
    }
    [MiOSContainerConfig saveAll:all];
    if ([[MiOSContainerConfig activeContainer].identifier isEqualToString:target.identifier]) [target applyToSystem];

    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    if (_onSave) _onSave();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)saveTapped {
    if (!_hasCoordinate) {
        [_searchField becomeFirstResponder];
        return;
    }
    [self persistWithGPSEnabled:YES];
}

- (void)useRealLocationTapped {
    [self persistWithGPSEnabled:NO];
}

#pragma mark - Search

- (void)searchChanged {
    NSString *text = _searchField.text;
    if (text.length == 0) {
        _results = @[];
        _resultsTable.hidden = YES;
        [_resultsTable reloadData];
        return;
    }
    _completer.queryFragment = text;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    NSString *query = textField.text;
    [self hideResults];
    if (query.length == 0) return YES;

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    __weak typeof(self) weakSelf = self;
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (!item) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf selectCoordinate:item.placemark.coordinate name:item.name zoom:YES];
        });
    }];
    return YES;
}

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    _results = completer.results;
    _resultsTable.hidden = (_results.count == 0 || _searchField.text.length == 0);
    [_resultsTable reloadData];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MIN((NSInteger)_results.count, 5);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"place"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"place"];
    cell.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = [MiOSTheme primaryText];
    cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    cell.detailTextLabel.textColor = [MiOSTheme secondaryText];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
    MKLocalSearchCompletion *result = _results[indexPath.row];
    cell.textLabel.text = result.title;
    cell.detailTextLabel.text = result.subtitle;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:cfg];
    cell.imageView.tintColor = [MiOSTheme accentColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MKLocalSearchCompletion *completion = _results[indexPath.row];
    NSString *name = completion.title;
    NSString *query = completion.subtitle.length > 0
        ? [NSString stringWithFormat:@"%@ %@", completion.title, completion.subtitle] : completion.title;
    _searchField.text = @"";
    [self hideResults];

    __weak typeof(self) weakSelf = self;
    void (^apply)(CLLocationCoordinate2D) = ^(CLLocationCoordinate2D coord) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf selectCoordinate:coord name:name zoom:YES];
        });
    };
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    [[[MKLocalSearch alloc] initWithRequest:request] startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        MKMapItem *item = response.mapItems.firstObject;
        if (item) {
            apply(item.placemark.coordinate);
            return;
        }
        [[[CLGeocoder alloc] init] geocodeAddressString:query completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *geoErr) {
            CLLocation *loc = placemarks.firstObject.location;
            if (loc) apply(loc.coordinate);
        }];
    }];
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    MKMarkerAnnotationView *marker = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"pin"];
    if (!marker) marker = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"pin"];
    marker.annotation = annotation;
    marker.markerTintColor = [MiOSTheme accentColor];
    marker.glyphImage = [UIImage systemImageNamed:@"location.fill"];
    marker.animatesWhenAdded = YES;
    return marker;
}

@end
