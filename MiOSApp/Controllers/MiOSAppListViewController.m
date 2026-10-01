#import "MiOSAppListViewController.h"
#import "MiOSAppConfigViewController.h"
#import "../UI/MiOSTheme.h"

@interface MiOSAppListViewController () <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *allApps;
@property (nonatomic, strong) NSMutableArray *filteredApps;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation MiOSAppListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"App Manager";
    self.view.backgroundColor = [MiOSTheme primaryBackground];
    [self loadApps];
    [self setupUI];
}

- (void)loadApps {
    _allApps = [NSMutableArray new];
    NSString *appPath = @"/var/mobile/Containers/Data/Application";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *uuids = [fm contentsOfDirectoryAtPath:appPath error:nil];

    for (NSString *uuid in uuids) {
        NSString *metaPath = [[appPath stringByAppendingPathComponent:uuid]
                              stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if (!bid || [bid hasPrefix:@"com.apple."]) continue;

        NSString *appPrefsPath = [NSString stringWithFormat:@"/var/mobile/Library/Preferences/MiOS/apps/%@.plist", bid];
        NSDictionary *appPrefs = [NSDictionary dictionaryWithContentsOfFile:appPrefsPath];
        BOOL isEnabled = [appPrefs[@"enabled"] boolValue];

        [_allApps addObject:@{
            @"bundleID": bid,
            @"path": [appPath stringByAppendingPathComponent:uuid],
            @"enabled": @(isEnabled),
        }];
    }

    [_allApps sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"enabled"] boolValue] != [b[@"enabled"] boolValue]) {
            return [b[@"enabled"] compare:a[@"enabled"]];
        }
        return [a[@"bundleID"] compare:b[@"bundleID"]];
    }];

    _filteredApps = [_allApps mutableCopy];
}

- (void)setupUI {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.placeholder = @"Search apps...";
    self.navigationItem.searchController = _searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorColor = [MiOSTheme separator];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _filteredApps.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    NSDictionary *app = _filteredApps[indexPath.row];

    cell.textLabel.text = app[@"bundleID"];
    cell.textLabel.font = [MiOSTheme bodyFont];
    cell.textLabel.textColor = [MiOSTheme primaryText];
    cell.backgroundColor = [MiOSTheme cardBackground];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if ([app[@"enabled"] boolValue]) {
        cell.imageView.image = [self dotImageWithColor:[MiOSTheme success]];
    } else {
        cell.imageView.image = [self dotImageWithColor:[MiOSTheme separator]];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *app = _filteredApps[indexPath.row];
    MiOSAppConfigViewController *vc = [[MiOSAppConfigViewController alloc] initWithBundleID:app[@"bundleID"]];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text;
    if (query.length == 0) {
        _filteredApps = [_allApps mutableCopy];
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"bundleID CONTAINS[cd] %@", query];
        _filteredApps = [[_allApps filteredArrayUsingPredicate:pred] mutableCopy];
    }
    [_tableView reloadData];
}

- (UIImage *)dotImageWithColor:(UIColor *)color {
    CGFloat size = 10;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, size, size)] fill];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
