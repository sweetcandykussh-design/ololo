#!/usr/bin/env python3
"""Generate the miOS app icon: a pixel-art little-devil mascot on a dark neon plate.

Pure stdlib (hand-written PNG), no PIL required.
"""
import struct, zlib, os


def create_png(width, height, pixels):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    raw = b''
    for y in range(height):
        raw += b'\x00'
        for x in range(width):
            r, g, b, a = pixels[y * width + x]
            raw += struct.pack('BBBB', r, g, b, a)

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    return sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


# Devil-head pixel grid (matches MiOSMascotRenderer): A body, E eye, M mouth, . transparent.
GRID = [
    ".A.......A.",
    ".AA.....AA.",
    "..AA...AA..",
    "..AAAAAAA..",
    ".AAAAAAAAA.",
    "AAAAAAAAAAA",
    "AAAAAAAAAAA",
    "AAEEAAAEEAA",
    "AAEEAAAEEAA",
    "AAAAAAAAAAA",
    ".AAAMMMAAA.",
    "..AAAAAAA..",
]

# Brand colours: violet -> cyan body blend, white glowing eyes, dark mouth.
BODY_TOP = (150, 110, 255)
BODY_BOT = (70, 200, 240)
EYE = (255, 255, 255)
MOUTH = (40, 20, 70)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def build(SIZE):
    pixels = [(10, 9, 17, 255)] * (SIZE * SIZE)
    # dark diagonal gradient background
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * SIZE)
            r = int(26 - 14 * t)
            g = int(23 - 13 * t)
            b = int(43 - 25 * t)
            pixels[y * SIZE + x] = (r, g, b, 255)

    rows = len(GRID)
    cols = len(GRID[0])
    margin = int(SIZE * 0.17)
    area = SIZE - margin * 2
    cell = area // max(rows, cols)
    gw, gh = cell * cols, cell * rows
    ox = (SIZE - gw) // 2
    oy = (SIZE - gh) // 2
    gap = max(1, cell // 12)

    def put(px, py, color):
        if 0 <= px < SIZE and 0 <= py < SIZE:
            pixels[py * SIZE + px] = color

    # soft eye glow pass
    for gy, row in enumerate(GRID):
        for gx, ch in enumerate(row):
            if ch != 'E':
                continue
            cx = ox + gx * cell + cell // 2
            cy = oy + gy * cell + cell // 2
            rad = int(cell * 1.1)
            for dy in range(-rad, rad):
                for dx in range(-rad, rad):
                    d = (dx * dx + dy * dy) ** 0.5
                    if d > rad:
                        continue
                    a = max(0.0, 1.0 - d / rad) * 0.5
                    px, py = cx + dx, cy + dy
                    if 0 <= px < SIZE and 0 <= py < SIZE:
                        base = pixels[py * SIZE + px]
                        glow = (150, 120, 255)
                        pixels[py * SIZE + px] = (
                            min(255, int(base[0] + glow[0] * a)),
                            min(255, int(base[1] + glow[1] * a)),
                            min(255, int(base[2] + glow[2] * a)),
                            255,
                        )

    # pixel blocks
    for gy, row in enumerate(GRID):
        for gx, ch in enumerate(row):
            if ch == '.':
                continue
            if ch == 'E':
                color = EYE + (255,)
            elif ch == 'M':
                color = MOUTH + (255,)
            else:
                color = lerp(BODY_TOP, BODY_BOT, gy / (rows - 1)) + (255,)
            for dy in range(gap, cell - gap):
                for dx in range(gap, cell - gap):
                    put(ox + gx * cell + dx, oy + gy * cell + dy, color)

    return pixels


out_dir = os.path.dirname(os.path.abspath(__file__))
for size, name in [(180, 'AppIcon60x60@3x.png'), (120, 'AppIcon60x60@2x.png')]:
    with open(os.path.join(out_dir, name), 'wb') as f:
        f.write(create_png(size, size, build(size)))
    print("wrote", name)
