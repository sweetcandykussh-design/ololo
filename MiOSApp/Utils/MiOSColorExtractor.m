#import "MiOSColorExtractor.h"

@implementation MiOSColorExtractor

+ (UIColor *)dominantColorFromImage:(UIImage *)image {
    if (!image) return nil;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;

    NSInteger sampleSize = 16;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = calloc(sampleSize * sampleSize * 4, sizeof(unsigned char));

    CGContextRef context = CGBitmapContextCreate(rawData, sampleSize, sampleSize, 8,
                                                  sampleSize * 4, colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(rawData);
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, sampleSize, sampleSize), cgImage);
    CGContextRelease(context);

    CGFloat totalR = 0, totalG = 0, totalB = 0;
    NSInteger validPixels = 0;

    for (NSInteger i = 0; i < sampleSize * sampleSize; i++) {
        NSInteger idx = i * 4;
        CGFloat r = rawData[idx] / 255.0;
        CGFloat g = rawData[idx + 1] / 255.0;
        CGFloat b = rawData[idx + 2] / 255.0;
        CGFloat a = rawData[idx + 3] / 255.0;

        if (a < 0.5) continue;

        CGFloat max = fmax(r, fmax(g, b));
        CGFloat min = fmin(r, fmin(g, b));
        CGFloat saturation = (max == 0) ? 0 : (max - min) / max;
        CGFloat brightness = max;

        if (saturation < 0.15 || brightness < 0.1 || brightness > 0.95) continue;

        totalR += r;
        totalG += g;
        totalB += b;
        validPixels++;
    }

    free(rawData);

    if (validPixels == 0) {
        return [UIColor colorWithRed:0.0 green:0.82 blue:0.95 alpha:1.0];
    }

    CGFloat avgR = totalR / validPixels;
    CGFloat avgG = totalG / validPixels;
    CGFloat avgB = totalB / validPixels;

    CGFloat maxComp = fmax(avgR, fmax(avgG, avgB));
    if (maxComp > 0) {
        CGFloat boost = fmin(1.0 / maxComp, 1.6);
        avgR = fmin(avgR * boost, 1.0);
        avgG = fmin(avgG * boost, 1.0);
        avgB = fmin(avgB * boost, 1.0);
    }

    return [UIColor colorWithRed:avgR green:avgG blue:avgB alpha:1.0];
}

+ (UIColor *)normalizedColorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
    CGFloat h, s, v, a;
    UIColor *c = [UIColor colorWithRed:r green:g blue:b alpha:1.0];
    [c getHue:&h saturation:&s brightness:&v alpha:&a];
    // Keep accents vivid enough to read on the dark UI without going neon.
    s = fmin(fmax(s, 0.55), 0.95);
    v = fmin(fmax(v, 0.80), 1.0);
    return [UIColor colorWithHue:h saturation:s brightness:v alpha:1.0];
}

+ (NSArray<UIColor *> *)paletteFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return @[];

    enum { sampleSize = 24, binCount = 12 };
    unsigned char *raw = calloc(sampleSize * sampleSize * 4, 1);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(raw, sampleSize, sampleSize, 8, sampleSize * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) {
        free(raw);
        return @[];
    }
    CGContextDrawImage(ctx, CGRectMake(0, 0, sampleSize, sampleSize), cgImage);
    CGContextRelease(ctx);

    CGFloat weight[binCount] = {0};
    CGFloat sumR[binCount] = {0}, sumG[binCount] = {0}, sumB[binCount] = {0};

    for (NSInteger i = 0; i < sampleSize * sampleSize; i++) {
        CGFloat a = raw[i * 4 + 3] / 255.0;
        if (a < 0.5) continue;
        CGFloat r = raw[i * 4] / 255.0 / a;
        CGFloat g = raw[i * 4 + 1] / 255.0 / a;
        CGFloat b = raw[i * 4 + 2] / 255.0 / a;
        CGFloat h, s, v, alpha;
        [[UIColor colorWithRed:fmin(r, 1) green:fmin(g, 1) blue:fmin(b, 1) alpha:1] getHue:&h saturation:&s brightness:&v alpha:&alpha];
        if (s < 0.25 || v < 0.2) continue;

        NSInteger bin = (NSInteger)floor(h * binCount) % binCount;
        CGFloat w = s * v;
        weight[bin] += w;
        sumR[bin] += r * w;
        sumG[bin] += g * w;
        sumB[bin] += b * w;
    }
    free(raw);

    NSInteger top = -1;
    for (NSInteger i = 0; i < binCount; i++) {
        if (weight[i] > 0 && (top < 0 || weight[i] > weight[top])) top = i;
    }
    if (top < 0) return @[];

    NSMutableArray<UIColor *> *palette = [NSMutableArray array];
    [palette addObject:[self normalizedColorWithRed:sumR[top] / weight[top]
                                              green:sumG[top] / weight[top]
                                               blue:sumB[top] / weight[top]]];

    // Secondary: strongest bin at least 60° of hue away and carrying a real share of the icon.
    NSInteger second = -1;
    for (NSInteger i = 0; i < binCount; i++) {
        NSInteger distance = labs(i - top);
        distance = MIN(distance, binCount - distance);
        if (distance < 2 || weight[i] < weight[top] * 0.15) continue;
        if (second < 0 || weight[i] > weight[second]) second = i;
    }
    if (second >= 0) {
        [palette addObject:[self normalizedColorWithRed:sumR[second] / weight[second]
                                                  green:sumG[second] / weight[second]
                                                   blue:sumB[second] / weight[second]]];
    }
    return palette;
}

+ (UIColor *)vibrantColorFromImage:(UIImage *)image {
    if (!image) return nil;
    UIColor *dominant = [self paletteFromImage:image].firstObject;
    if (dominant) return dominant;

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return nil;

    NSInteger sampleSize = 20;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    unsigned char *rawData = calloc(sampleSize * sampleSize * 4, sizeof(unsigned char));

    CGContextRef context = CGBitmapContextCreate(rawData, sampleSize, sampleSize, 8,
                                                  sampleSize * 4, colorSpace,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        free(rawData);
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0, 0, sampleSize, sampleSize), cgImage);
    CGContextRelease(context);

    CGFloat bestR = 0, bestG = 0, bestB = 0;
    CGFloat bestScore = 0;

    for (NSInteger i = 0; i < sampleSize * sampleSize; i++) {
        NSInteger idx = i * 4;
        CGFloat r = rawData[idx] / 255.0;
        CGFloat g = rawData[idx + 1] / 255.0;
        CGFloat b = rawData[idx + 2] / 255.0;
        CGFloat a = rawData[idx + 3] / 255.0;

        if (a < 0.5) continue;

        CGFloat max = fmax(r, fmax(g, b));
        CGFloat min = fmin(r, fmin(g, b));
        CGFloat saturation = (max == 0) ? 0 : (max - min) / max;
        CGFloat brightness = max;

        CGFloat score = saturation * 2.0 + brightness * 0.5;
        if (score > bestScore && saturation > 0.2 && brightness > 0.15) {
            bestScore = score;
            bestR = r;
            bestG = g;
            bestB = b;
        }
    }

    free(rawData);

    if (bestScore == 0) {
        return [self dominantColorFromImage:image];
    }

    CGFloat maxComp = fmax(bestR, fmax(bestG, bestB));
    if (maxComp > 0 && maxComp < 0.7) {
        CGFloat boost = fmin(0.85 / maxComp, 1.8);
        bestR = fmin(bestR * boost, 1.0);
        bestG = fmin(bestG * boost, 1.0);
        bestB = fmin(bestB * boost, 1.0);
    }

    return [UIColor colorWithRed:bestR green:bestG blue:bestB alpha:1.0];
}

+ (UIColor *)accentGradientEndFromColor:(UIColor *)color {
    if (!color) return [UIColor colorWithRed:0.45 green:0.30 blue:1.0 alpha:1.0];

    CGFloat r, g, b, a;
    [color getRed:&r green:&g blue:&b alpha:&a];

    CGFloat hue, sat, bri;
    [color getHue:&hue saturation:&sat brightness:&bri alpha:&a];

    hue = fmod(hue + 0.08, 1.0);
    sat = fmin(sat * 1.2, 1.0);
    bri = fmax(bri * 0.7, 0.3);

    return [UIColor colorWithHue:hue saturation:sat brightness:bri alpha:1.0];
}

@end
