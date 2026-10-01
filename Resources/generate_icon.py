#!/usr/bin/env python3
"""Generate pixel-art miOS app icon."""
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

SIZE = 180
pixels = [(20, 20, 30, 255)] * (SIZE * SIZE)

# gradient background
for y in range(SIZE):
    for x in range(SIZE):
        t = x / SIZE
        s = y / SIZE
        r = int(0 + 90 * t + 50 * s)
        g = int(180 * (1 - t * 0.3) - 40 * s)
        b = int(220 + 35 * t - 20 * s)
        pixels[y * SIZE + x] = (min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)), 255)

# pixel grid pattern - a cartoon apple made of pixels
PX = 8
GRID = [
    "...........",
    "....CCC....",
    "...CCCCC...",
    ".AAAAAAAAA.",
    "AAAAAAAAAAA",
    "AAAAAAAAAAA",
    "AABBAAABBAA",
    "AAAAAAAAAAA",
    "AAAAAAAAAAA",
    ".AAAAAAAAA.",
    "..AAAAAAA..",
    "...AAAAA...",
    "....AAA....",
]

colors = {
    'A': (255, 255, 255, 240),
    'B': (0, 210, 240, 255),
    'C': (100, 220, 140, 255),
    '.': None,
}

ox = (SIZE - len(GRID[0]) * PX) // 2
oy = (SIZE - len(GRID) * PX) // 2 + 10

for gy, row in enumerate(GRID):
    for gx, ch in enumerate(row):
        c = colors.get(ch)
        if not c:
            continue
        for dy in range(PX):
            for dx in range(PX):
                px = ox + gx * PX + dx
                py = oy + gy * PX + dy
                if 0 <= px < SIZE and 0 <= py < SIZE:
                    pixels[py * SIZE + px] = c

# text "miOS" at bottom in tiny pixel font
text_y = SIZE - 28
text_pixels = [
    # m
    [(0,0),(1,0),(3,0),(4,0), (0,1),(1,1),(2,1),(3,1),(4,1), (0,2),(2,2),(4,2), (0,3),(4,3)],
    # i
    [(7,0), (7,2),(7,3)],
    # O
    [(10,0),(11,0),(12,0), (9,1),(13,1), (9,2),(13,2), (10,3),(11,3),(12,3)],
    # S
    [(16,0),(17,0),(18,0), (15,1), (16,2),(17,2),(18,2), (19,3), (15,3),(16,3),(17,3)],
]

text_ox = SIZE // 2 - 10 * 2
for letter in text_pixels:
    for (lx, ly) in letter:
        for dy in range(3):
            for dx in range(3):
                px = text_ox + lx * 3 + dx
                py = text_y + ly * 4 + dy
                if 0 <= px < SIZE and 0 <= py < SIZE:
                    pixels[py * SIZE + px] = (255, 255, 255, 255)

out_dir = os.path.dirname(os.path.abspath(__file__))
png_data = create_png(SIZE, SIZE, pixels)
with open(os.path.join(out_dir, 'AppIcon60x60@3x.png'), 'wb') as f:
    f.write(png_data)

# Also generate 2x
SIZE2 = 120
pixels2 = [(20, 20, 30, 255)] * (SIZE2 * SIZE2)
for y in range(SIZE2):
    for x in range(SIZE2):
        sx = int(x * SIZE / SIZE2)
        sy = int(y * SIZE / SIZE2)
        pixels2[y * SIZE2 + x] = pixels[sy * SIZE + sx]

png_data2 = create_png(SIZE2, SIZE2, pixels2)
with open(os.path.join(out_dir, 'AppIcon60x60@2x.png'), 'wb') as f:
    f.write(png_data2)

print("Icons generated.")
