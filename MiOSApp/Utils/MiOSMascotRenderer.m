#import "MiOSMascotRenderer.h"

// Pixel grid for the devil head. 'A' = body, 'E' = glowing eye, 'M' = dark mouth, '.' = transparent.
static NSArray<NSString *> *MiOSMascotGrid(void) {
    return @[
        @".A.......A.",
        @".AA.....AA.",
        @"..AA...AA..",
        @"..AAAAAAA..",
        @".AAAAAAAAA.",
        @"AAAAAAAAAAA",
        @"AAAAAAAAAAA",
        @"AAEEAAAEEAA",
        @"AAEEAAAEEAA",
        @"AAAAAAAAAAA",
        @".AAAMMMAAA.",
        @"..AAAAAAA..",
    ];
}

static UIColor *MiOSLighten(UIColor *c, CGFloat amount) {
    CGFloat h, s, b, a;
    if (![c getHue:&h saturation:&s brightness:&b alpha:&a]) return c;
    return [UIColor colorWithHue:h saturation:MAX(0, s - amount * 0.5) brightness:MIN(1, b + amount) alpha:1.0];
}

static UIColor *MiOSDarken(UIColor *c, CGFloat amount) {
    CGFloat h, s, b, a;
    if (![c getHue:&h saturation:&s brightness:&b alpha:&a]) return c;
    return [UIColor colorWithHue:h saturation:MIN(1, s + amount * 0.3) brightness:MAX(0, b - amount) alpha:1.0];
}

@implementation MiOSMascotRenderer

+ (void)drawMascotInContext:(CGContextRef)ctx rect:(CGRect)rect accent:(UIColor *)accent glow:(BOOL)glow {
    NSArray<NSString *> *grid = MiOSMascotGrid();
    NSInteger rows = grid.count;
    NSInteger cols = grid.firstObject.length;

    // Fit the grid into rect with a small inset for the glow bleed.
    CGFloat inset = rect.size.width * 0.06;
    CGRect area = CGRectInset(rect, inset, inset);
    CGFloat cell = MIN(area.size.width / cols, area.size.height / rows);
    CGFloat gridW = cell * cols, gridH = cell * rows;
    CGFloat ox = area.origin.x + (area.size.width - gridW) / 2.0;
    CGFloat oy = area.origin.y + (area.size.height - gridH) / 2.0;

    UIColor *bodyTop = MiOSLighten(accent, 0.18);
    UIColor *bodyBottom = MiOSDarken(accent, 0.12);
    UIColor *eye = [UIColor colorWithWhite:1.0 alpha:1.0];
    UIColor *mouth = MiOSDarken(accent, 0.45);

    CGFloat pad = cell * 0.08;       // tiny gap so pixels read as blocks
    CGFloat radius = cell * 0.18;

    for (NSInteger r = 0; r < rows; r++) {
        NSString *row = grid[r];
        for (NSInteger c = 0; c < cols; c++) {
            unichar ch = [row characterAtIndex:c];
            if (ch == '.') continue;

            UIColor *fill;
            BOOL isEye = (ch == 'E');
            if (ch == 'E') fill = eye;
            else if (ch == 'M') fill = mouth;
            else {
                // vertical body gradient per-row
                CGFloat t = (CGFloat)r / (CGFloat)(rows - 1);
                CGFloat rr, gg, bb, aa, rr2, gg2, bb2, aa2;
                [bodyTop getRed:&rr green:&gg blue:&bb alpha:&aa];
                [bodyBottom getRed:&rr2 green:&gg2 blue:&bb2 alpha:&aa2];
                fill = [UIColor colorWithRed:rr + (rr2 - rr) * t
                                       green:gg + (gg2 - gg) * t
                                        blue:bb + (bb2 - bb) * t alpha:1.0];
            }

            CGRect px = CGRectMake(ox + c * cell + pad, oy + r * cell + pad,
                                   cell - pad * 2, cell - pad * 2);
            if (isEye && glow) {
                CGContextSaveGState(ctx);
                CGContextSetShadowWithColor(ctx, CGSizeZero, cell * 0.9, accent.CGColor);
                [[UIBezierPath bezierPathWithRoundedRect:px cornerRadius:radius] fill];
            }
            [fill setFill];
            [[UIBezierPath bezierPathWithRoundedRect:px cornerRadius:radius] fill];
            if (isEye && glow) CGContextRestoreGState(ctx);
        }
    }
}

+ (UIImage *)mascotWithSize:(CGSize)size accent:(UIColor *)accent {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);

        // Soft accent bloom behind the head.
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, size.width * 0.12, [accent colorWithAlphaComponent:0.6].CGColor);
        [self drawMascotInContext:ctx rect:bounds accent:accent glow:NO];
        CGContextRestoreGState(ctx);

        [self drawMascotInContext:ctx rect:bounds accent:accent glow:YES];
    }];
}

+ (UIImage *)iconMascotWithSize:(CGSize)size {
    UIColor *accent = [UIColor colorWithRed:0.62 green:0.38 blue:1.0 alpha:1.0];   // neutral brand violet
    UIColor *accent2 = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0];

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = YES;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        CGRect bounds = CGRectMake(0, 0, size.width, size.height);

        // Dark diagonal gradient plate.
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGFloat comps[] = {
            0.10, 0.09, 0.17, 1.0,
            0.04, 0.04, 0.07, 1.0,
        };
        CGFloat locs[] = {0.0, 1.0};
        CGGradientRef grad = CGGradientCreateWithColorComponents(space, comps, locs, 2);
        CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0),
                                    CGPointMake(size.width, size.height), 0);
        CGGradientRelease(grad);
        CGColorSpaceRelease(space);

        // Blend the two brand colours for the mascot body.
        UIColor *body = [UIColor colorWithRed:(0.62 + 0.0) / 2 green:(0.38 + 0.82) / 2
                                         blue:(1.0 + 0.95) / 2 alpha:1.0];
        (void)accent2;
        [self drawMascotInContext:ctx rect:CGRectInset(bounds, size.width * 0.14, size.width * 0.14)
                           accent:body glow:YES];
        (void)accent;
    }];
}

@end
