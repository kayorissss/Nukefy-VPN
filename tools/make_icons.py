#!/usr/bin/env python3
"""Regenerate every Nukefy icon as a single filled black-and-white mark.

The previous icon set shipped six colour variants whose rounded corners leaked
white (RGB artefacts) or transparency (tray PNG), which is exactly what users
see as "white corners".  This script derives one luminance mask from the
original artwork and re-renders it:

  * full-bleed dark square with a white glyph (corners filled, no white),
  * a white-on-transparent variant for the tray / Android monochrome slot,
  * every density the Android and Windows builds reference.

Only the standard library is used so the icons can be regenerated anywhere:

    python3 tools/make_icons.py
"""
import os
import struct
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'assets', 'icons', 'app_icon.png')

BG = (14, 14, 16)
CORNER_RATIO = 0.215


# ── PNG decoding ────────────────────────────────────────────────────────────
def read_png(path):
    data = open(path, 'rb').read()
    pos = 8
    idat = b''
    w = h = bd = ct = None
    while pos < len(data):
        (ln,) = struct.unpack('>I', data[pos:pos + 4])
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    i = 0
    for y in range(h):
        f = raw[i]
        i += 1
        line = bytearray(raw[i:i + stride])
        i += stride
        if f == 1:
            for x in range(ch, stride):
                line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, bytes(out)


def write_png(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ, payload):
        return struct.pack('>I', len(payload)) + typ + payload + \
            struct.pack('>I', zlib.crc32(typ + payload) & 0xffffffff)

    with open(path, 'wb') as fh:
        fh.write(b'\x89PNG\r\n\x1a\n')
        fh.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
        fh.write(chunk(b'IDAT', comp))
        fh.write(chunk(b'IEND', b''))


def write_ico(path, frames):
    header = struct.pack('<HHH', 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    entries = b''
    body = b''
    for size, png in frames:
        edge = 0 if size >= 256 else size
        entries += struct.pack('<BBBBHHII', edge, edge, 0, 0, 1, 32, len(png), offset)
        body += png
        offset += len(png)
    with open(path, 'wb') as fh:
        fh.write(header + entries + body)


# ── image helpers ───────────────────────────────────────────────────────────
def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def mask_curve(lum):
    """0 on the dark background, 1 on the glyph, smooth grey on its glow."""
    t = (lum - 62.0) / 68.0
    if t <= 0:
        return 0.0
    if t >= 1:
        return 1.0
    return t * t * (3 - 2 * t)


def _inside_rounded(x, y, w, h, r):
    cx = min(max(x, r), w - 1 - r)
    cy = min(max(y, r), h - 1 - r)
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def resize_mask(mask, sw, sh, dw, dh):
    if sw == dw and sh == dh:
        return mask
    out = bytearray(dw * dh)
    for dy in range(dh):
        y0 = dy * sh // dh
        y1 = max(y0 + 1, (dy + 1) * sh // dh)
        for dx in range(dw):
            x0 = dx * sw // dw
            x1 = max(x0 + 1, (dx + 1) * sw // dw)
            acc = n = 0
            for y in range(y0, y1):
                row = y * sw
                for x in range(x0, x1):
                    acc += mask[row + x]
                    n += 1
            out[dy * dw + dx] = acc // n
    return out


def main():
    w, h, ch, px = read_png(SRC)
    radius = CORNER_RATIO * w
    mask = bytearray(w * h)
    for y in range(h):
        base = y * w
        for x in range(w):
            if not _inside_rounded(x, y, w, h, radius):
                continue  # white corner of the source artefact: not glyph
            o = (base + x) * ch
            mask[base + x] = int(round(255 * mask_curve(luminance(px[o], px[o + 1], px[o + 2]))))

    def render(size, mode):
        m = resize_mask(mask, w, h, size, size)
        rgba = bytearray(size * size * 4)
        for i in range(size * size):
            t = m[i] / 255.0
            o = i * 4
            if mode == 'solid':
                rgba[o] = int(round(BG[0] + (255 - BG[0]) * t))
                rgba[o + 1] = int(round(BG[1] + (255 - BG[1]) * t))
                rgba[o + 2] = int(round(BG[2] + (255 - BG[2]) * t))
                rgba[o + 3] = 255
            else:
                rgba[o] = rgba[o + 1] = rgba[o + 2] = 255
                rgba[o + 3] = m[i]
        return bytes(rgba)

    def png_bytes(rgba, size):
        tmp = os.path.join(ROOT, 'build', '_icon_frame.png')
        os.makedirs(os.path.dirname(tmp), exist_ok=True)
        write_png(tmp, size, size, rgba)
        with open(tmp, 'rb') as fh:
            return fh.read()

    icons = os.path.join(ROOT, 'assets', 'icons')
    os.makedirs(icons, exist_ok=True)
    write_png(os.path.join(icons, 'app_icon.png'), 512, 512, render(512, 'solid'))
    write_png(os.path.join(icons, 'tray_icon.png'), 512, 512, render(512, 'alpha'))

    frames = [(size, png_bytes(render(size, 'solid'), size)) for size in (16, 24, 32, 48, 64, 128, 256)]
    write_ico(os.path.join(icons, 'app_icon.ico'), frames)
    win = os.path.join(ROOT, 'windows', 'runner', 'resources')
    os.makedirs(win, exist_ok=True)
    write_ico(os.path.join(win, 'app_icon.ico'), frames)

    for name, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
        folder = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'mipmap-' + name)
        os.makedirs(folder, exist_ok=True)
        write_png(os.path.join(folder, 'ic_launcher.png'), size, size, render(size, 'solid'))

    for name, size in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
        folder = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'mipmap-' + name)
        os.makedirs(folder, exist_ok=True)
        inner = int(size * 0.62)
        glyph = render(inner, 'alpha')
        rgba = bytearray(size * size * 4)
        off = (size - inner) // 2
        for y in range(inner):
            src = y * inner * 4
            dst = ((y + off) * size + off) * 4
            rgba[dst:dst + inner * 4] = glyph[src:src + inner * 4]
        write_png(os.path.join(folder, 'ic_launcher_foreground.png'), size, size, bytes(rgba))

    print('icons regenerated')


if __name__ == '__main__':
    main()
