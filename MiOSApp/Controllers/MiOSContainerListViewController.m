#import "MiOSContainerListViewController.h"
#import "MiOSContainerCreateViewController.h"
#import "MiOSContainerActions.h"
#import "../Models/MiOSContainerConfig.h"
#import "../Views/MiOSContainerGridView.h"
#import "../UI/MiOSTheme.h"

@interface MiOSContainerListViewController ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *mainStack;
@property (nonatomic, strong) CAGradientLayer *bgGradientLayer;
@property (nonatomic, weak) MiOSContainerGridView *grid;
@end

@implementation MiOSContainerListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Containers";
    self.view.backgroundColor = [MiOSTheme primaryBackground];

    _bgGradientLayer = [CAGradientLayer layer];
    _bgGradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.11 green:0.12 blue:0.19 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.05 alpha:1.0].CGColor,
    ];
    _bgGradientLayer.locations = @[@0.0, @0.45, @1.0];
    [self.view.layer insertSublayer:_bgGradientLayer atIndex:0];

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];

    _mainStack = [[UIStackView alloc] init];
    _mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    _mainStack.axis = UILayoutConstraintAxisVertical;
    _mainStack.spacing = 18;
    [_scrollView addSubview:_mainStack];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_mainStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor constant:8],
        [_mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [_mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [_mainStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor constant:-24],
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self reload];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _bgGradientLayer.frame = self.view.bounds;
}

- (void)reload {
    for (UIView *v in [_mainStack.arrangedSubviews copy]) {
        [_mainStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<MiOSContainerConfig *> *containers = [MiOSContainerConfig loadAll];
    NSString *activeID = [MiOSContainerConfig activeContainerID];
    if (activeID.length == 0) activeID = containers.firstObject.identifier;

    [_mainStack addArrangedSubview:[self buildHeaderWithCount:containers.count]];

    if (containers.count == 0) {
        [_mainStack addArrangedSubview:[self buildEmptyState]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    MiOSContainerGridView *grid = [[MiOSContainerGridView alloc]
        initWithContainers:containers
                  activeID:activeID
                     onTap:^(MiOSContainerConfig *container, UIView *tile) {
        [weakSelf showActionsForContainer:container from:tile];
    }];
    _grid = grid;
    [_mainStack addArrangedSubview:grid];
}

- (void)reloadAnimated {
    [UIView transitionWithView:_scrollView duration:0.35 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self reload];
    } completion:nil];
}

- (void)showActionsForContainer:(MiOSContainerConfig *)container from:(UIView *)tile {
    __weak typeof(self) weakSelf = self;
    [MiOSContainerActions presentForContainer:container from:self sourceView:tile completion:^(MiOSContainerActionResult result) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (result == MiOSContainerActionRemoved && strongSelf.grid) {
            [strongSelf.grid removeContainerWithID:container.identifier completion:^{
                [weakSelf reloadAnimated];
            }];
        } else {
            [strongSelf reloadAnimated];
        }
    }];
}

- (UIView *)buildHeaderWithCount:(NSUInteger)count {
    UIView *row = [[UIView alloc] init];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Containers";
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    title.textColor = [MiOSTheme primaryText];
    [row addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = [NSString stringWithFormat:@"%lu total", (unsigned long)count];
    subtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    subtitle.textColor = [MiOSTheme secondaryText];
    [row addSubview:subtitle];

    UIView *addButton = [[UIView alloc] init];
    addButton.translatesAutoresizingMaskIntoConstraints = NO;
    addButton.backgroundColor = [UIColor colorWithRed:0.16 green:0.17 blue:0.24 alpha:0.92];
    addButton.layer.cornerRadius = 21;
    addButton.layer.borderWidth = 1.0;
    addButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [addButton addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(addTapped)]];
    [row addSubview:addButton];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold];
    UIImageView *plus = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"plus" withConfiguration:cfg]];
    plus.translatesAutoresizingMaskIntoConstraints = NO;
    plus.tintColor = [UIColor whiteColor];
    [addButton addSubview:plus];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:row.topAnchor],
        [title.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:4],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
        [addButton.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [addButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [addButton.widthAnchor constraintEqualToConstant:42],
        [addButton.heightAnchor constraintEqualToConstant:42],
        [plus.centerXAnchor constraintEqualToAnchor:addButton.centerXAnchor],
        [plus.centerYAnchor constraintEqualToAnchor:addButton.centerYAnchor],
    ]];
    return row;
}

- (UIView *)buildEmptyState {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor colorWithRed:0.14 green:0.15 blue:0.21 alpha:0.92];
    card.layer.cornerRadius = 26;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = @"No containers yet.\nTap + to create one.";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textColor = [MiOSTheme secondaryText];
    [card addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:160],
        [label.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
    ]];
    return card;
}

- (void)addTapped {
    [self presentEditorForContainer:nil];
}

- (void)presentEditorForContainer:(MiOSContainerConfig *)container {
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    MiOSContainerCreateViewController *vc = [[MiOSContainerCreateViewController alloc] init];
    vc.editingContainer = container;
    __weak typeof(self) weakSelf = self;
    vc.onSave = ^{
        [weakSelf reloadAnimated];
    };
    vc.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:vc animated:YES completion:nil];
}

@end
