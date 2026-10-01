#import "MiOSContainerGridView.h"
#import "../Models/MiOSContainerConfig.h"
#import "../UI/MiOSTheme.h"
#import "../Utils/MiOSAppIconProvider.h"

static const CGFloat kTileHeight = 150;
static const CGFloat kTileSpacing = 12;
static NSString *const kTileReuseID = @"MiOSContainerTile";

#pragma mark - Layout (shrink + fade deleted tiles)

@interface MiOSContainerGridLayout : UICollectionViewFlowLayout
@end

@implementation MiOSContainerGridLayout {
    NSMutableSet<NSIndexPath *> *_deletedPaths;
}

- (void)prepareForCollectionViewUpdates:(NSArray<UICollectionViewUpdateItem *> *)updateItems {
    [super prepareForCollectionViewUpdates:updateItems];
    _deletedPaths = [NSMutableSet set];
    for (UICollectionViewUpdateItem *item in updateItems) {
        if (item.updateAction == UICollectionUpdateActionDelete && item.indexPathBeforeUpdate) {
            [_deletedPaths addObject:item.indexPathBeforeUpdate];
        }
    }
}

- (void)finalizeCollectionViewUpdates {
    [super finalizeCollectionViewUpdates];
    _deletedPaths = nil;
}

- (UICollectionViewLayoutAttributes *)finalLayoutAttributesForDisappearingItemAtIndexPath:(NSIndexPath *)itemIndexPath {
    UICollectionViewLayoutAttributes *attrs = [[super finalLayoutAttributesForDisappearingItemAtIndexPath:itemIndexPath] copy];
    if ([_deletedPaths containsObject:itemIndexPath]) {
        attrs.alpha = 0.0;
        attrs.transform = CGAffineTransformMakeScale(0.6, 0.6);
    }
    return attrs;
}

@end

#pragma mark - Tile cell

@interface MiOSContainerTileCell : UICollectionViewCell
- (void)configureWithContainer:(MiOSContainerConfig *)container active:(BOOL)isActive;
@end

@implementation MiOSContainerTileCell {
    UIImageView *_iconView;
    UILabel *_nameLabel;
    UILabel *_subLabel;
    UIStackView *_dots;
    UILabel *_badge;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UIView *card = self.contentView;
        card.layer.cornerRadius = 22;
        card.layer.cornerCurve = kCACornerCurveContinuous;
        card.layer.borderWidth = 1.0;

        _iconView = [[UIImageView alloc] init];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFill;
        _iconView.clipsToBounds = YES;
        _iconView.layer.cornerRadius = 12;
        _iconView.layer.cornerCurve = kCACornerCurveContinuous;
        [card addSubview:_iconView];

        _nameLabel = [[UILabel alloc] init];
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _nameLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _nameLabel.textColor = [MiOSTheme primaryText];
        [card addSubview:_nameLabel];

        _subLabel = [[UILabel alloc] init];
        _subLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        _subLabel.textColor = [MiOSTheme secondaryText];
        [card addSubview:_subLabel];

        _dots = [[UIStackView alloc] init];
        _dots.translatesAutoresizingMaskIntoConstraints = NO;
        _dots.axis = UILayoutConstraintAxisHorizontal;
        _dots.spacing = 5;
        [card addSubview:_dots];

        _badge = [[UILabel alloc] init];
        _badge.translatesAutoresizingMaskIntoConstraints = NO;
        _badge.text = @"ACTIVE";
        _badge.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        _badge.textAlignment = NSTextAlignmentCenter;
        _badge.layer.cornerRadius = 8;
        _badge.layer.masksToBounds = YES;
        [card addSubview:_badge];

        [NSLayoutConstraint activateConstraints:@[
            [_iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [_iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [_iconView.widthAnchor constraintEqualToConstant:46],
            [_iconView.heightAnchor constraintEqualToConstant:46],
            [_nameLabel.topAnchor constraintEqualToAnchor:_iconView.bottomAnchor constant:12],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
            [_nameLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
            [_subLabel.topAnchor constraintEqualToAnchor:_nameLabel.bottomAnchor constant:2],
            [_subLabel.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_subLabel.trailingAnchor constraintEqualToAnchor:_nameLabel.trailingAnchor],
            [_dots.topAnchor constraintEqualToAnchor:_subLabel.bottomAnchor constant:10],
            [_dots.leadingAnchor constraintEqualToAnchor:_nameLabel.leadingAnchor],
            [_badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],
            [_badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
            [_badge.widthAnchor constraintEqualToConstant:50],
            [_badge.heightAnchor constraintEqualToConstant:16],
        ]];
    }
    return self;
}

- (void)configureWithContainer:(MiOSContainerConfig *)container active:(BOOL)isActive {
    UIColor *accent = [MiOSAppIconProvider accentForBundleIDs:container.apps];
    CGFloat r, g, b, a;
    [accent getRed:&r green:&g blue:&b alpha:&a];

    UIView *card = self.contentView;
    card.backgroundColor = [UIColor colorWithRed:0.11 + r * 0.06 green:0.11 + g * 0.06 blue:0.15 + b * 0.06 alpha:0.92];
    card.layer.borderColor = isActive ? [accent colorWithAlphaComponent:0.5].CGColor : [MiOSTheme hairline].CGColor;
    self.layer.shadowColor = accent.CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 4);
    self.layer.shadowRadius = isActive ? 14 : 8;
    self.layer.shadowOpacity = isActive ? 0.25 : 0.08;

    UIImage *icon = [MiOSAppIconProvider iconForBundleID:container.apps.firstObject];
    if (icon) {
        _iconView.image = icon;
        _iconView.contentMode = UIViewContentModeScaleAspectFill;
        _iconView.backgroundColor = nil;
    } else {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium];
        _iconView.image = [UIImage systemImageNamed:@"square.stack.3d.up.fill" withConfiguration:cfg];
        _iconView.contentMode = UIViewContentModeCenter;
        _iconView.tintColor = accent;
        _iconView.backgroundColor = [accent colorWithAlphaComponent:0.12];
    }

    _nameLabel.text = container.name.length > 0 ? container.name : @"Container";
    _subLabel.text = [NSString stringWithFormat:@"%lu app%@", (unsigned long)container.apps.count,
                      container.apps.count == 1 ? @"" : @"s"];

    for (UIView *v in [_dots.arrangedSubviews copy]) [v removeFromSuperview];
    NSArray<NSNumber *> *features = @[@(container.gpsEnabled), @(container.deviceSpoofEnabled),
                                      @(container.spoofVendorID || container.spoofAdvertisingID || container.spoofDeviceCheck)];
    for (NSNumber *on in features) {
        UIView *dot = [[UIView alloc] init];
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        dot.backgroundColor = on.boolValue ? accent : [UIColor colorWithWhite:1.0 alpha:0.12];
        dot.layer.cornerRadius = 3;
        [dot.widthAnchor constraintEqualToConstant:6].active = YES;
        [dot.heightAnchor constraintEqualToConstant:6].active = YES;
        [_dots addArrangedSubview:dot];
    }

    _badge.hidden = !isActive;
    _badge.textColor = accent;
    _badge.backgroundColor = [accent colorWithAlphaComponent:0.15];
}

@end

#pragma mark - Grid view

@interface MiOSContainerGridView () <UICollectionViewDataSource, UICollectionViewDelegate>
@end

@implementation MiOSContainerGridView {
    NSMutableArray<MiOSContainerConfig *> *_containers;
    NSString *_activeID;
    void (^_onTap)(MiOSContainerConfig *, UIView *);
    UICollectionView *_collectionView;
    MiOSContainerGridLayout *_layout;
    NSLayoutConstraint *_heightConstraint;
    CGFloat _lastWidth;
}

- (instancetype)initWithContainers:(NSArray<MiOSContainerConfig *> *)containers
                          activeID:(NSString *)activeID
                             onTap:(void (^)(MiOSContainerConfig *, UIView *))onTap {
    if (self = [super initWithFrame:CGRectZero]) {
        _containers = [containers mutableCopy];
        _activeID = [activeID copy];
        _onTap = [onTap copy];
        self.translatesAutoresizingMaskIntoConstraints = NO;

        _layout = [[MiOSContainerGridLayout alloc] init];
        _layout.minimumInteritemSpacing = kTileSpacing;
        _layout.minimumLineSpacing = kTileSpacing;

        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:_layout];
        _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.scrollEnabled = NO;
        _collectionView.clipsToBounds = NO;
        _collectionView.dataSource = self;
        _collectionView.delegate = self;
        [_collectionView registerClass:[MiOSContainerTileCell class] forCellWithReuseIdentifier:kTileReuseID];
        [self addSubview:_collectionView];

        _heightConstraint = [self.heightAnchor constraintEqualToConstant:[self heightForCount:_containers.count]];
        [NSLayoutConstraint activateConstraints:@[
            _heightConstraint,
            [_collectionView.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_collectionView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_collectionView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_collectionView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

- (CGFloat)heightForCount:(NSUInteger)count {
    NSUInteger rows = (count + 1) / 2;
    if (rows == 0) return 0;
    return rows * kTileHeight + (rows - 1) * kTileSpacing;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    if (width > 0 && fabs(width - _lastWidth) > 0.5) {
        _lastWidth = width;
        _layout.itemSize = CGSizeMake(floor((width - kTileSpacing) / 2), kTileHeight);
        [_layout invalidateLayout];
    }
}

- (void)removeContainerWithID:(NSString *)containerID completion:(void (^)(void))completion {
    NSInteger index = NSNotFound;
    for (NSInteger i = 0; i < (NSInteger)_containers.count; i++) {
        if ([_containers[i].identifier isEqualToString:containerID]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        if (completion) completion();
        return;
    }

    [_containers removeObjectAtIndex:index];
    _heightConstraint.constant = [self heightForCount:_containers.count];

    UIView *root = self.superview;
    while (root.superview && ![root isKindOfClass:[UIScrollView class]]) root = root.superview;

    [_collectionView performBatchUpdates:^{
        [self->_collectionView deleteItemsAtIndexPaths:@[[NSIndexPath indexPathForItem:index inSection:0]]];
    } completion:^(BOOL finished) {
        if (completion) completion();
    }];
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:0 animations:^{
        [root layoutIfNeeded];
    } completion:nil];
}

#pragma mark - UICollectionView

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_containers.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MiOSContainerTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kTileReuseID forIndexPath:indexPath];
    MiOSContainerConfig *container = _containers[indexPath.item];
    [cell configureWithContainer:container active:[container.identifier isEqualToString:_activeID]];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:NO];
    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    [UIView animateWithDuration:0.08 animations:^{
        cell.transform = CGAffineTransformMakeScale(0.96, 0.96);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0 options:0 animations:^{
            cell.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    if (_onTap) _onTap(_containers[indexPath.item], cell);
}

@end
