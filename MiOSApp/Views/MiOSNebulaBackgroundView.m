#import "MiOSNebulaBackgroundView.h"
#import <math.h>

@implementation MiOSNebulaBackgroundView {
    UIColor *_accent;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.opaque = YES;
        self.contentMode = UIViewContentModeRedraw;
        self.userInteractionEnabled = NO;
        _accent = [UIColor colorWithRed:0.45 green:0.30 blue:1.0 alpha:1.0];
    }
    return self;
}

- (void)updateAccent:(UIColor *)accent {
    if (!accent) return;
    _accent = accent;
    [self setNeedsDisplay];
}

// A small deterministic PRNG so the pixel field is stable across redraws.
static uint32_t miosRand(uint32_t *state) {
    *state = (*state * 1664525u) + 1013904223u;
    return *state;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;

    CGFloat ar, ag, ab, aa;
    if (![_accent getRed:&ar green:&ag blue:&ab alpha:&aa]) { ar = 0.45; ag = 0.30; ab = 1.0; }

    // 1. Base vertical gradient — deep indigo at the top easing to near-black.
    CGFloat baseComps[] = {
        0.07 + ar * 0.05, 0.07 + ag * 0.04, 0.16 + ab * 0.06, 1.0,   // top, faint accent tint
        0.04,             0.04,             0.09,             1.0,    // middle
        0.02,             0.02,             0.04,             1.0,    // bottom
    };
    CGFloat baseLocs[] = {0.0, 0.5, 1.0};
    CGGradientRef base = CGGradientCreateWithColorComponents(space, baseComps, baseLocs, 3);
    CGContextDrawLinearGradient(ctx, base, CGPointMake(0, 0), CGPointMake(0, h), 0);
    CGGradientRelease(base);

    // 2. Neon accent bloom in the top-right (behind the mascot).
    CGFloat bloomComps[] = {
        ar, ag, ab, 0.55,
        ar, ag, ab, 0.0,
    };
    CGFloat bloomLocs[] = {0.0, 1.0};
    CGGradientRef bloom = CGGradientCreateWithColorComponents(space, bloomComps, bloomLocs, 2);
    CGPoint bloomCenter = CGPointMake(w * 0.82, h * 0.10);
    CGContextDrawRadialGradient(ctx, bloom, bloomCenter, 0, bloomCenter, w * 0.72,
                                kCGGradientDrawsBeforeStartLocation);
    CGGradientRelease(bloom);

    // 3. A cooler secondary bloom low-left for depth.
    CGFloat c2r = MIN(1.0, ab + 0.1), c2g = 0.4, c2b = MIN(1.0, ar + 0.5);
    CGFloat bloom2Comps[] = { c2r, c2g, c2b, 0.22, c2r, c2g, c2b, 0.0 };
    CGGradientRef bloom2 = CGGradientCreateWithColorComponents(space, bloom2Comps, bloomLocs, 2);
    CGPoint b2 = CGPointMake(w * 0.12, h * 0.62);
    CGContextDrawRadialGradient(ctx, bloom2, b2, 0, b2, w * 0.6, kCGGradientDrawsBeforeStartLocation);
    CGGradientRelease(bloom2);

    // 4. Faint scattered pixel specks — the "digital dust" from the reference.
    uint32_t state = 0xA5F00D;
    NSInteger specks = (NSInteger)((w * h) / 5200.0);
    for (NSInteger i = 0; i < specks; i++) {
        CGFloat x = (miosRand(&state) % 1000) / 1000.0 * w;
        CGFloat y = (miosRand(&state) % 1000) / 1000.0 * h;
        uint32_t roll = miosRand(&state) % 100;
        CGFloat side = (roll % 3 == 0) ? 3.0 : 2.0;
        CGFloat alpha = 0.05 + (miosRand(&state) % 14) / 100.0;   // 0.05–0.18
        // Denser + brighter toward the top-right bloom.
        CGFloat prox = 1.0 - (hypot(x - bloomCenter.x, y - bloomCenter.y) / (w));
        if (prox > 0) alpha += prox * 0.12;
        BOOL tinted = (roll % 2 == 0);
        if (tinted) {
            CGContextSetRGBFillColor(ctx, ar, ag, ab, MIN(0.5, alpha));
        } else {
            CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, MIN(0.4, alpha));
        }
        CGContextFillRect(ctx, CGRectMake(x, y, side, side));
    }

    CGColorSpaceRelease(space);
}

@end
