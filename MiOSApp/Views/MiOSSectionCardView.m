#import "MiOSSectionCardView.h"
#import "../UI/MiOSTheme.h"

@implementation MiOSSectionCardView {
    UILabel *_headerLabel;
    UIView *_cardBg;
}

- (instancetype)initWithTitle:(NSString *)title {
    if (self = [super initWithFrame:CGRectZero]) {
        _sectionTitle = title;
        [self setupView];
    }
    return self;
}

- (void)setupView {
    self.translatesAutoresizingMaskIntoConstraints = NO;

    _headerLabel = [[UILabel alloc] init];
    _headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerLabel.text = [_sectionTitle uppercaseString];
    _headerLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _headerLabel.textColor = [MiOSTheme accentColor];
    _headerLabel.hidden = (_sectionTitle.length == 0);
    [self addSubview:_headerLabel];

    _cardBg = [[UIView alloc] init];
    _cardBg.translatesAutoresizingMaskIntoConstraints = NO;
    _cardBg.backgroundColor = [MiOSTheme tileBackground];
    _cardBg.layer.cornerRadius = 24;
    _cardBg.layer.cornerCurve = kCACornerCurveContinuous;
    _cardBg.layer.borderWidth = 1.0;
    _cardBg.layer.borderColor = [MiOSTheme hairline].CGColor;
    [self addSubview:_cardBg];

    _contentStack = [[UIStackView alloc] init];
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 0;
    [_cardBg addSubview:_contentStack];

    CGFloat headerHeight = _sectionTitle.length > 0 ? 24 : 0;

    [NSLayoutConstraint activateConstraints:@[
        [_headerLabel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
        [_headerLabel.heightAnchor constraintEqualToConstant:headerHeight],
        [_cardBg.topAnchor constraintEqualToAnchor:_headerLabel.bottomAnchor constant:_sectionTitle.length > 0 ? 8 : 0],
        [_cardBg.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_cardBg.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_cardBg.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_contentStack.topAnchor constraintEqualToAnchor:_cardBg.topAnchor],
        [_contentStack.leadingAnchor constraintEqualToAnchor:_cardBg.leadingAnchor],
        [_contentStack.trailingAnchor constraintEqualToAnchor:_cardBg.trailingAnchor],
        [_contentStack.bottomAnchor constraintEqualToAnchor:_cardBg.bottomAnchor],
    ]];
}

- (void)addCellView:(UIView *)cell {
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:cell];
}

- (void)addSeparator {
    // The inset line lives inside a full-width wrapper: constraining an arranged subview's
    // leading edge directly fights the stack view's fill alignment and shifts every row.
    UIView *wrapper = [[UIView alloc] init];
    wrapper.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentStack addArrangedSubview:wrapper];

    UIView *line = [[UIView alloc] init];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [MiOSTheme separator];
    [wrapper addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [wrapper.heightAnchor constraintEqualToConstant:0.5],
        [line.topAnchor constraintEqualToAnchor:wrapper.topAnchor],
        [line.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor],
        [line.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:54],
        [line.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor],
    ]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    _cardBg.layer.borderColor = [MiOSTheme hairline].CGColor;
}

@end
