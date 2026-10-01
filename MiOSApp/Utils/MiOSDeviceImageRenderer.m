#import "MiOSDeviceImageRenderer.h"

typedef NS_ENUM(NSInteger, MiOSCameraLayout) {
    MiOSCameraSingle,
    MiOSCameraDualHorizontalPill,   // 7 Plus / 8 Plus
    MiOSCameraDualVerticalPill,     // X / XS / 16 / 17
    MiOSCameraDualSquareVertical,   // 11 / 12
    MiOSCameraDualSquareDiagonal,   // 13 / 14 / 15
    MiOSCameraTripleSquare,         // Pro models
    MiOSCameraPlateauSingle,        // 17 Air
    MiOSCameraPlateauTriple,        // 17 Pro
};

#pragma mark - Color helpers

static UIColor *MiOSAdjust(UIColor *c, CGFloat delta) {
    CGFloat r, g, b, a;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [UIColor colorWithRed:fmin(fmax(r + delta, 0), 1) green:fmin(fmax(g + delta, 0), 1)
                            blue:fmin(fmax(b + delta, 0), 1) alpha:a];
}

static BOOL MiOSIsLight(UIColor *c) {
    CGFloat r, g, b, a;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55;
}

static void MiOSFillLinear(CGContextRef ctx, UIBezierPath *path, NSArray<UIColor *> *colors, CGPoint start, CGPoint end) {
    NSMutableArray *cg = [NSMutableArray array];
    for (UIColor *c in colors) [cg addObject:(id)c.CGColor];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cg, NULL);
    CGContextSaveGState(ctx);
    [path addClip];
    CGContextDrawLinearGradient(ctx, gradient, start, end, kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRestoreGState(ctx);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

static void MiOSFillRadial(CGContextRef ctx, CGPoint center, CGFloat radius, UIColor *inner, UIColor *outer) {
    NSArray *cg = @[(id)inner.CGColor, (id)outer.CGColor];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)cg, NULL);
    CGContextDrawRadialGradient(ctx, gradient, center, 0, center, radius, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}

@implementation MiOSDeviceImageRenderer

#pragma mark - Model traits

+ (MiOSDeviceFormFactor)formFactorForDeviceName:(NSString *)name {
    NSString *lower = name.lowercaseString ?: @"";
    if ([lower containsString:@"iphone se"] || [lower containsString:@"iphone 7"] || [lower containsString:@"iphone 8"]) {
        return MiOSDeviceFormFactorHomeButton;
    }
    if ([lower containsString:@"16e"]) return MiOSDeviceFormFactorNotch;
    if ([lower containsString:@"14 pro"] || [lower containsString:@"iphone 15"] ||
        [lower containsString:@"iphone 16"] || [lower containsString:@"iphone 17"]) {
        return MiOSDeviceFormFactorDynamicIsland;
    }
    return MiOSDeviceFormFactorNotch;
}

+ (MiOSCameraLayout)cameraLayoutForName:(NSString *)name {
    NSString *lower = name.lowercaseString ?: @"";
    BOOL pro = [lower containsString:@"pro"];
    if ([lower containsString:@"17 air"]) return MiOSCameraPlateauSingle;
    if ([lower containsString:@"17 pro"]) return MiOSCameraPlateauTriple;
    if (pro) return MiOSCameraTripleSquare;
    if ([lower containsString:@"16e"] || [lower containsString:@"xr"] || [lower containsString:@"iphone se"]) return MiOSCameraSingle;
    if ([lower containsString:@"iphone 7"] || [lower containsString:@"iphone 8"]) {
        return [lower containsString:@"plus"] ? MiOSCameraDualHorizontalPill : MiOSCameraSingle;
    }
    if ([lower containsString:@"iphone x"] || [lower containsString:@"iphone 16"] || [lower containsString:@"iphone 17"]) {
        return MiOSCameraDualVerticalPill;
    }
    if ([lower containsString:@"iphone 11"] || [lower containsString:@"iphone 12"]) return MiOSCameraDualSquareVertical;
    return MiOSCameraDualSquareDiagonal;
}

+ (UIColor *)finishForName:(NSString *)name {
    NSString *lower = name.lowercaseString ?: @"";
    NSUInteger hash = 0;
    for (NSUInteger i = 0; i < lower.length; i++) hash = hash * 31 + [lower characterAtIndex:i];

    if ([lower containsString:@"15 pro"] || [lower containsString:@"16 pro"] || [lower containsString:@"17 pro"]) {
        return [UIColor colorWithRed:0.74 green:0.72 blue:0.68 alpha:1.0]; // natural titanium
    }
    BOOL steelX = [lower containsString:@"iphone x"] && ![lower containsString:@"xr"];
    if ([lower containsString:@"pro"] || steelX) {
        NSArray *premium = @[
            [UIColor colorWithRed:0.30 green:0.31 blue:0.33 alpha:1.0], // graphite
            [UIColor colorWithRed:0.89 green:0.89 blue:0.87 alpha:1.0], // silver
            [UIColor colorWithRed:0.91 green:0.85 blue:0.73 alpha:1.0], // gold
            [UIColor colorWithRed:0.38 green:0.34 blue:0.44 alpha:1.0], // deep purple
        ];
        return premium[hash % premium.count];
    }
    NSArray *colors = @[
        [UIColor colorWithRed:0.20 green:0.21 blue:0.23 alpha:1.0],
        [UIColor colorWithRed:0.93 green:0.93 blue:0.92 alpha:1.0],
        [UIColor colorWithRed:0.72 green:0.12 blue:0.18 alpha:1.0],
        [UIColor colorWithRed:0.38 green:0.55 blue:0.74 alpha:1.0],
        [UIColor colorWithRed:0.95 green:0.80 blue:0.84 alpha:1.0],
        [UIColor colorWithRed:0.63 green:0.78 blue:0.69 alpha:1.0],
        [UIColor colorWithRed:0.96 green:0.88 blue:0.60 alpha:1.0],
        [UIColor colorWithRed:0.75 green:0.71 blue:0.87 alpha:1.0],
    ];
    return colors[hash % colors.count];
}

#pragma mark - Public

+ (UIImage *)renderDeviceForName:(NSString *)displayName size:(CGSize)size accentColor:(UIColor *)accent {
    if (size.width < 1 || size.height < 1) return nil;
    if (!accent) accent = [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0];

    MiOSDeviceFormFactor form = [self formFactorForDeviceName:displayName];
    MiOSCameraLayout camera = [self cameraLayoutForName:displayName];
    UIColor *finish = [self finishForName:displayName];

    CGFloat aspect = (form == MiOSDeviceFormFactorHomeButton) ? 0.50 : 0.485;
    CGFloat phoneHeight = size.height * 0.90;
    CGFloat phoneWidth = phoneHeight * aspect;
    const CGFloat spread = 1.70; // front overlaps the back by 30% of a phone width
    if (phoneWidth * spread > size.width * 0.94) {
        phoneWidth = size.width * 0.94 / spread;
        phoneHeight = phoneWidth / aspect;
    }
    CGFloat originX = (size.width - phoneWidth * spread) / 2.0;
    CGFloat originY = (size.height - phoneHeight) / 2.0;
    CGRect backRect = CGRectMake(originX, originY - phoneHeight * 0.015, phoneWidth, phoneHeight);
    CGRect frontRect = CGRectMake(originX + phoneWidth * 0.70, originY + phoneHeight * 0.015, phoneWidth, phoneHeight);

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rc) {
        CGContextRef ctx = rc.CGContext;
        [self drawBackInRect:backRect finish:finish camera:camera form:form context:ctx];
        [self drawFrontInRect:frontRect finish:finish accent:accent form:form context:ctx];
    }];
}

#pragma mark - Back

+ (void)drawBackInRect:(CGRect)r finish:(UIColor *)finish camera:(MiOSCameraLayout)camera
                  form:(MiOSDeviceFormFactor)form context:(CGContextRef)ctx {
    CGFloat pw = r.size.width;
    CGFloat radius = pw * (form == MiOSDeviceFormFactorHomeButton ? 0.16 : 0.19);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, pw * 0.05), pw * 0.14, [UIColor colorWithWhite:0 alpha:0.55].CGColor);
    [MiOSAdjust(finish, -0.1) setFill];
    [body fill];
    CGContextRestoreGState(ctx);

    // Frosted glass back with a soft diagonal sheen.
    MiOSFillLinear(ctx, body, @[MiOSAdjust(finish, 0.08), finish, MiOSAdjust(finish, -0.10)],
                   CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)), CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)));
    CGContextSaveGState(ctx);
    [body addClip];
    MiOSFillRadial(ctx, CGPointMake(CGRectGetMinX(r) + pw * 0.3, CGRectGetMinY(r) + pw * 0.4), pw * 1.1,
                   [UIColor colorWithWhite:1 alpha:0.16], [UIColor colorWithWhite:1 alpha:0]);
    CGContextRestoreGState(ctx);

    // Metal frame edge.
    [MiOSAdjust(finish, -0.22) setStroke];
    body.lineWidth = MAX(pw * 0.022, 1.0);
    [body stroke];
    UIBezierPath *inner = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(r, pw * 0.02, pw * 0.02) cornerRadius:radius - pw * 0.02];
    [[UIColor colorWithWhite:1 alpha:0.22] setStroke];
    inner.lineWidth = 0.6;
    [inner stroke];

    [self drawCameraLayout:camera inRect:r finish:finish context:ctx];

    // Apple logo, slightly tone-on-tone.
    UIImage *logo = [UIImage systemImageNamed:@"apple.logo"];
    if (logo) {
        UIColor *tint = MiOSIsLight(finish) ? [MiOSAdjust(finish, -0.22) colorWithAlphaComponent:0.8]
                                            : [MiOSAdjust(finish, 0.20) colorWithAlphaComponent:0.8];
        logo = [logo imageWithTintColor:tint renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGFloat lw = pw * 0.22;
        CGFloat lh = lw * logo.size.height / MAX(logo.size.width, 1);
        [logo drawInRect:CGRectMake(CGRectGetMidX(r) - lw / 2, CGRectGetMinY(r) + r.size.height * 0.47 - lh / 2, lw, lh)];
    }
}

+ (void)drawLensAt:(CGPoint)c radius:(CGFloat)rad context:(CGContextRef)ctx {
    UIBezierPath *outer = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - rad, c.y - rad, rad * 2, rad * 2)];
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, rad * 0.15), rad * 0.4, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
    [[UIColor colorWithWhite:0.12 alpha:1] setFill];
    [outer fill];
    CGContextRestoreGState(ctx);
    [[UIColor colorWithWhite:0.62 alpha:0.9] setStroke];
    outer.lineWidth = MAX(rad * 0.14, 0.6);
    [outer stroke];

    CGFloat g = rad * 0.64;
    CGContextSaveGState(ctx);
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - g, c.y - g, g * 2, g * 2)] addClip];
    MiOSFillRadial(ctx, CGPointMake(c.x - g * 0.2, c.y - g * 0.2), g * 1.3,
                   [UIColor colorWithRed:0.20 green:0.24 blue:0.40 alpha:1], [UIColor colorWithRed:0.02 green:0.02 blue:0.05 alpha:1]);
    CGContextRestoreGState(ctx);

    CGFloat h = g * 0.32;
    [[UIColor colorWithWhite:1 alpha:0.65] setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - g * 0.45, c.y - g * 0.45, h, h)] fill];
}

+ (void)drawDotAt:(CGPoint)c radius:(CGFloat)rad color:(UIColor *)color {
    [color setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - rad, c.y - rad, rad * 2, rad * 2)] fill];
}

+ (void)drawBumpPath:(UIBezierPath *)bump finish:(UIColor *)finish context:(CGContextRef)ctx {
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.35].CGColor);
    [MiOSAdjust(finish, -0.06) setFill];
    [bump fill];
    CGContextRestoreGState(ctx);
    CGRect b = bump.bounds;
    MiOSFillLinear(ctx, bump, @[MiOSAdjust(finish, 0.06), MiOSAdjust(finish, -0.08)],
                   CGPointMake(CGRectGetMinX(b), CGRectGetMinY(b)), CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b)));
    [[UIColor colorWithWhite:1 alpha:0.30] setStroke];
    bump.lineWidth = 0.7;
    [bump stroke];
}

+ (void)drawCameraLayout:(MiOSCameraLayout)layout inRect:(CGRect)r finish:(UIColor *)finish context:(CGContextRef)ctx {
    CGFloat pw = r.size.width;
    CGFloat m = pw * 0.07;
    CGFloat x = CGRectGetMinX(r) + m, y = CGRectGetMinY(r) + m;
    UIColor *flash = [UIColor colorWithRed:1.0 green:0.96 blue:0.85 alpha:0.95];
    UIColor *sensor = [UIColor colorWithWhite:0.08 alpha:1];

    switch (layout) {
        case MiOSCameraTripleSquare: {
            CGFloat s = pw * 0.46;
            [self drawBumpPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, s, s) cornerRadius:s * 0.28] finish:finish context:ctx];
            CGFloat lr = s * 0.2;
            [self drawLensAt:CGPointMake(x + s * 0.28, y + s * 0.27) radius:lr context:ctx];
            [self drawLensAt:CGPointMake(x + s * 0.28, y + s * 0.73) radius:lr context:ctx];
            [self drawLensAt:CGPointMake(x + s * 0.72, y + s * 0.50) radius:lr context:ctx];
            [self drawDotAt:CGPointMake(x + s * 0.74, y + s * 0.18) radius:s * 0.06 color:flash];
            [self drawDotAt:CGPointMake(x + s * 0.74, y + s * 0.82) radius:s * 0.06 color:sensor];
            break;
        }
        case MiOSCameraDualSquareDiagonal:
        case MiOSCameraDualSquareVertical: {
            CGFloat s = pw * 0.38;
            [self drawBumpPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, s, s) cornerRadius:s * 0.28] finish:finish context:ctx];
            CGFloat lr = s * 0.22;
            BOOL diagonal = (layout == MiOSCameraDualSquareDiagonal);
            [self drawLensAt:CGPointMake(x + s * 0.30, y + s * 0.30) radius:lr context:ctx];
            [self drawLensAt:CGPointMake(x + (diagonal ? s * 0.70 : s * 0.30), y + s * 0.70) radius:lr context:ctx];
            [self drawDotAt:CGPointMake(x + s * 0.74, y + s * (diagonal ? 0.26 : 0.30)) radius:s * 0.07 color:flash];
            break;
        }
        case MiOSCameraDualVerticalPill: {
            CGFloat w = pw * 0.18, h = pw * 0.38;
            [self drawBumpPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:w / 2] finish:finish context:ctx];
            CGFloat lr = w * 0.38;
            [self drawLensAt:CGPointMake(x + w / 2, y + w / 2) radius:lr context:ctx];
            [self drawLensAt:CGPointMake(x + w / 2, y + h - w / 2) radius:lr context:ctx];
            [self drawDotAt:CGPointMake(x + w + pw * 0.07, y + h / 2) radius:pw * 0.03 color:flash];
            break;
        }
        case MiOSCameraDualHorizontalPill: {
            CGFloat w = pw * 0.38, h = pw * 0.18;
            [self drawBumpPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(x, y, w, h) cornerRadius:h / 2] finish:finish context:ctx];
            CGFloat lr = h * 0.38;
            [self drawLensAt:CGPointMake(x + h / 2, y + h / 2) radius:lr context:ctx];
            [self drawLensAt:CGPointMake(x + w - h / 2, y + h / 2) radius:lr context:ctx];
            [self drawDotAt:CGPointMake(x + w + pw * 0.07, y + h / 2) radius:pw * 0.03 color:flash];
            break;
        }
        case MiOSCameraPlateauSingle:
        case MiOSCameraPlateauTriple: {
            CGFloat w = pw * 0.94, h = pw * 0.30;
            CGFloat px = CGRectGetMinX(r) + (pw - w) / 2, py = CGRectGetMinY(r) + pw * 0.06;
            [self drawBumpPath:[UIBezierPath bezierPathWithRoundedRect:CGRectMake(px, py, w, h) cornerRadius:h * 0.45] finish:finish context:ctx];
            if (layout == MiOSCameraPlateauTriple) {
                CGFloat lr = h * 0.2;
                [self drawLensAt:CGPointMake(px + h * 0.32, py + h * 0.30) radius:lr context:ctx];
                [self drawLensAt:CGPointMake(px + h * 0.32, py + h * 0.72) radius:lr context:ctx];
                [self drawLensAt:CGPointMake(px + h * 0.76, py + h * 0.51) radius:lr context:ctx];
            } else {
                [self drawLensAt:CGPointMake(px + h * 0.5, py + h * 0.5) radius:h * 0.28 context:ctx];
            }
            [self drawDotAt:CGPointMake(px + w - h * 0.4, py + h * 0.5) radius:h * 0.1 color:flash];
            break;
        }
        case MiOSCameraSingle:
        default: {
            CGFloat lr = pw * 0.085;
            CGPoint c = CGPointMake(x + lr * 1.2, y + lr * 1.2);
            [self drawBumpPath:[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - lr * 1.25, c.y - lr * 1.25, lr * 2.5, lr * 2.5)]
                        finish:finish context:ctx];
            [self drawLensAt:c radius:lr context:ctx];
            [self drawDotAt:CGPointMake(c.x + lr * 2.4, c.y) radius:pw * 0.03 color:flash];
            break;
        }
    }
}

#pragma mark - Front

+ (void)drawFrontInRect:(CGRect)r finish:(UIColor *)finish accent:(UIColor *)accent
                   form:(MiOSDeviceFormFactor)form context:(CGContextRef)ctx {
    CGFloat pw = r.size.width, ph = r.size.height;
    BOOL homeButton = (form == MiOSDeviceFormFactorHomeButton);
    CGFloat radius = pw * (homeButton ? 0.16 : 0.19);
    UIBezierPath *body = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:radius];

    // Side button peeking out of the frame.
    [MiOSAdjust(finish, -0.08) setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMaxX(r) - pw * 0.01, CGRectGetMinY(r) + ph * 0.24, pw * 0.03, ph * 0.11)
                                cornerRadius:pw * 0.01] fill];

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(-pw * 0.03, pw * 0.05), pw * 0.16, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    [finish setFill];
    [body fill];
    CGContextRestoreGState(ctx);

    // Metal frame, then the black glass face.
    MiOSFillLinear(ctx, body, @[MiOSAdjust(finish, 0.12), MiOSAdjust(finish, -0.12)],
                   CGPointMake(CGRectGetMinX(r), CGRectGetMinY(r)), CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r)));
    CGFloat rim = pw * 0.022;
    UIBezierPath *face = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(r, rim, rim) cornerRadius:radius - rim];
    [[UIColor colorWithRed:0.03 green:0.03 blue:0.04 alpha:1] setFill];
    [face fill];

    CGRect screen;
    CGFloat screenRadius;
    if (homeButton) {
        screen = CGRectMake(CGRectGetMinX(r) + pw * 0.065, CGRectGetMinY(r) + ph * 0.125, pw * 0.87, ph * 0.75);
        screenRadius = pw * 0.015;
    } else {
        CGFloat inset = pw * 0.05;
        screen = CGRectInset(r, inset, inset);
        screenRadius = radius - inset;
    }
    UIBezierPath *screenPath = [UIBezierPath bezierPathWithRoundedRect:screen cornerRadius:screenRadius];

    // Lock-screen wallpaper tinted by the container accent.
    CGContextSaveGState(ctx);
    [screenPath addClip];
    MiOSFillLinear(ctx, screenPath, @[[UIColor colorWithRed:0.12 green:0.11 blue:0.24 alpha:1],
                                      [UIColor colorWithRed:0.03 green:0.03 blue:0.08 alpha:1]],
                   CGPointMake(CGRectGetMidX(screen), CGRectGetMinY(screen)), CGPointMake(CGRectGetMidX(screen), CGRectGetMaxY(screen)));
    CGFloat h, s, v, a;
    [accent getHue:&h saturation:&s brightness:&v alpha:&a];
    UIColor *second = [UIColor colorWithHue:fmod(h + 0.12, 1.0) saturation:s brightness:v alpha:1];
    MiOSFillRadial(ctx, CGPointMake(CGRectGetMinX(screen) + screen.size.width * 0.25, CGRectGetMinY(screen) + screen.size.height * 0.72),
                   screen.size.width * 0.95, [accent colorWithAlphaComponent:0.95], [accent colorWithAlphaComponent:0.0]);
    MiOSFillRadial(ctx, CGPointMake(CGRectGetMinX(screen) + screen.size.width * 0.85, CGRectGetMinY(screen) + screen.size.height * 0.40),
                   screen.size.width * 0.75, [second colorWithAlphaComponent:0.75], [second colorWithAlphaComponent:0.0]);

    // Clock.
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.alignment = NSTextAlignmentCenter;
    CGFloat fontSize = pw * 0.17;
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1 alpha:0.92],
        NSParagraphStyleAttributeName: para,
    };
    [@"9:41" drawInRect:CGRectMake(CGRectGetMinX(screen), CGRectGetMinY(screen) + screen.size.height * 0.13,
                                   screen.size.width, fontSize * 1.3) withAttributes:attrs];

    // Glass glare.
    UIBezierPath *glare = [UIBezierPath bezierPath];
    [glare moveToPoint:CGPointMake(CGRectGetMinX(screen), CGRectGetMinY(screen))];
    [glare addLineToPoint:CGPointMake(CGRectGetMinX(screen) + screen.size.width * 0.65, CGRectGetMinY(screen))];
    [glare addLineToPoint:CGPointMake(CGRectGetMinX(screen), CGRectGetMinY(screen) + screen.size.height * 0.55)];
    [glare closePath];
    [[UIColor colorWithWhite:1 alpha:0.07] setFill];
    [glare fill];
    CGContextRestoreGState(ctx);

    UIColor *black = [UIColor colorWithRed:0.01 green:0.01 blue:0.02 alpha:1];
    if (form == MiOSDeviceFormFactorDynamicIsland) {
        CGFloat w = pw * 0.30, ih = pw * 0.085;
        [black setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMidX(screen) - w / 2, CGRectGetMinY(screen) + pw * 0.04, w, ih)
                                    cornerRadius:ih / 2] fill];
    } else if (form == MiOSDeviceFormFactorNotch) {
        CGFloat w = pw * 0.46, nh = pw * 0.075;
        CGContextSaveGState(ctx);
        [screenPath addClip];
        [black setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMidX(screen) - w / 2, CGRectGetMinY(screen) - nh, w, nh * 2)
                                    cornerRadius:nh * 0.7] fill];
        CGContextRestoreGState(ctx);
    } else {
        // Home button + earpiece on the bezels.
        CGFloat bottomBezelMid = (CGRectGetMaxY(screen) + CGRectGetMaxY(r)) / 2;
        CGFloat br = pw * 0.075;
        UIBezierPath *button = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(CGRectGetMidX(r) - br, bottomBezelMid - br, br * 2, br * 2)];
        [[UIColor colorWithWhite:0.06 alpha:1] setFill];
        [button fill];
        [MiOSAdjust(finish, 0.05) setStroke];
        button.lineWidth = MAX(pw * 0.012, 0.6);
        [button stroke];

        CGFloat topBezelMid = (CGRectGetMinY(r) + CGRectGetMinY(screen)) / 2;
        [[UIColor colorWithWhite:0.18 alpha:1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(CGRectGetMidX(r) - pw * 0.09, topBezelMid - pw * 0.012, pw * 0.18, pw * 0.024)
                                    cornerRadius:pw * 0.012] fill];
        [self drawDotAt:CGPointMake(CGRectGetMidX(r) - pw * 0.16, topBezelMid) radius:pw * 0.02 color:[UIColor colorWithWhite:0.15 alpha:1]];
    }
}

@end
