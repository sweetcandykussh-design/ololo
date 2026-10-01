#import "MiOSFloatingTabBar.h"
#import "../UI/MiOSTheme.h"

static const CGFloat kItemSize = 50;
static const CGFloat kCenterItemSize = 60;
static const CGFloat kTopPadding = 8;

// Rounded-design system font for the tab labels (the new typographic style).
static UIFont *MiOSRoundedFont(CGFloat size, UIFontWeight weight) {
    UIFont *base = [UIFont systemFontOfSize:size weight:weight];
    UIFontDescriptor *desc = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    return desc ? [UIFont fontWithDescriptor:desc size:size] : base;
}

@implementation MiOSFloatingTabBar {
    NSArray<NSString *> *_titles;
    NSArray<NSString *> *_icons;
    NSMutableArray<UIView *> *_circles;
    NSMutableArray<UIImageView *> *_iconViews;
    NSMutableArray<UILabel *> *_labels;
    CAGradientLayer *_fadeLayer;
    CAShapeLayer *_arcLayer;
}

+ (CGFloat)contentHeight {
    return 104;
}

- (instancetype)initWithTitles:(NSArray<NSString *> *)titles icons:(NSArray<NSString *> *)icons {
    if (self = [super initWithFrame:CGRectZero]) {
        _titles = [titles copy];
        _icons = [icons copy];
        _circles = [NSMutableArray array];
        _iconViews = [NSMutableArray array];
        _labels = [NSMutableArray array];
        [self setupView];
    }
    return self;
}

- (void)setupView {
    // Content scrolling underneath fades into the bar instead of hard-clipping.
    _fadeLayer = [CAGradientLayer layer];
    _fadeLayer.colors = @[
        (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.06 alpha:0.0].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.06 alpha:0.85].CGColor,
        (id)[UIColor colorWithRed:0.03 green:0.03 blue:0.06 alpha:0.97].CGColor,
    ];
    _fadeLayer.locations = @[@0.0, @0.35, @1.0];
    [self.layer addSublayer:_fadeLayer];

    _arcLayer = [CAShapeLayer layer];
    _arcLayer.fillColor = [UIColor clearColor].CGColor;
    _arcLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    _arcLayer.lineWidth = 1.0;
    [self.layer addSublayer:_arcLayer];

    for (NSInteger i = 0; i < (NSInteger)_titles.count; i++) {
        UIView *circle = [[UIView alloc] init];
        circle.tag = i;
        circle.layer.borderWidth = 1.0;
        [circle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(itemTapped:)]];
        [self addSubview:circle];
        [_circles addObject:circle];

        BOOL isCenter = [self isCenterIndex:i];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:isCenter ? 22 : 19
                                                                                           weight:UIImageSymbolWeightSemibold];
        UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:_icons[i] withConfiguration:cfg]];
        iconView.contentMode = UIViewContentModeCenter;
        [circle addSubview:iconView];
        [_iconViews addObject:iconView];

        UILabel *label = [[UILabel alloc] init];
        label.text = _titles[i];
        label.textAlignment = NSTextAlignmentCenter;
        label.font = MiOSRoundedFont(10, UIFontWeightMedium);
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.8;
        [self addSubview:label];
        [_labels addObject:label];
    }
    [self applySelectionStyle];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applySelectionStyle)
                                                 name:MiOSThemeDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isCenterIndex:(NSInteger)index {
    return index == (NSInteger)_titles.count / 2;
}

// Outer items sit a little higher than their neighbours; the center item is highest and largest.
- (CGFloat)verticalOffsetForIndex:(NSInteger)index {
    NSInteger count = (NSInteger)_titles.count;
    NSInteger center = count / 2;
    NSInteger distance = labs(index - center);
    if (distance == 0) return 0;
    return (distance % 2 == 1) ? 22 : 10;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _fadeLayer.frame = self.bounds;

    NSInteger count = (NSInteger)_titles.count;
    if (count == 0) return;
    CGFloat columnWidth = (width - 16) / count;

    for (NSInteger i = 0; i < count; i++) {
        CGFloat size = [self isCenterIndex:i] ? kCenterItemSize : kItemSize;
        CGFloat centerX = 8 + columnWidth * (i + 0.5);
        CGFloat top = kTopPadding + [self verticalOffsetForIndex:i];

        UIView *circle = _circles[i];
        circle.frame = CGRectMake(centerX - size / 2, top, size, size);
        circle.layer.cornerRadius = size / 2;
        _iconViews[i].frame = circle.bounds;
        _labels[i].frame = CGRectMake(centerX - columnWidth / 2, CGRectGetMaxY(circle.frame) + 5, columnWidth, 13);
    }

    // Faint arc tracing the button row, echoing the reference's orbit ornament.
    UIBezierPath *arc = [UIBezierPath bezierPath];
    CGFloat arcY = kTopPadding + kItemSize / 2 + 30;
    [arc moveToPoint:CGPointMake(-20, arcY)];
    [arc addQuadCurveToPoint:CGPointMake(width + 20, arcY) controlPoint:CGPointMake(width / 2, kTopPadding - 26)];
    _arcLayer.path = arc.CGPath;
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    _selectedIndex = selectedIndex;
    [self applySelectionStyle];
}

- (void)applySelectionStyle {
    for (NSInteger i = 0; i < (NSInteger)_circles.count; i++) {
        BOOL selected = (i == _selectedIndex);
        UIView *circle = _circles[i];
        if (selected) {
            circle.backgroundColor = [UIColor whiteColor];
            circle.layer.borderColor = [UIColor whiteColor].CGColor;
            circle.layer.shadowColor = [UIColor whiteColor].CGColor;
            circle.layer.shadowOpacity = 0.35;
            circle.layer.shadowRadius = 12;
            circle.layer.shadowOffset = CGSizeZero;
            _iconViews[i].tintColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
            _labels[i].textColor = [UIColor whiteColor];
            _labels[i].font = MiOSRoundedFont(10, UIFontWeightSemibold);
        } else {
            BOOL isCenter = [self isCenterIndex:i];
            UIColor *accent = [MiOSTheme accentColor];
            circle.backgroundColor = isCenter
                ? [accent colorWithAlphaComponent:0.95]
                : [UIColor colorWithRed:0.16 green:0.17 blue:0.24 alpha:0.92];
            circle.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:isCenter ? 0.30 : 0.10].CGColor;
            circle.layer.shadowOpacity = isCenter ? 0.45 : 0.0;
            circle.layer.shadowColor = accent.CGColor;
            circle.layer.shadowRadius = 14;
            circle.layer.shadowOffset = CGSizeZero;
            _iconViews[i].tintColor = isCenter ? [MiOSTheme textColorOnAccent] : [UIColor colorWithWhite:1.0 alpha:0.85];
            _labels[i].textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
            _labels[i].font = MiOSRoundedFont(10, UIFontWeightMedium);
        }
    }
}

- (void)itemTapped:(UITapGestureRecognizer *)sender {
    NSInteger index = sender.view.tag;
    UIView *circle = sender.view;
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    [UIView animateWithDuration:0.08 animations:^{
        circle.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:0 animations:^{
            circle.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
    self.selectedIndex = index;
    if (_onSelect) _onSelect(index);
}

// Let touches in the transparent fade area fall through to the scroll view beneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

@end
