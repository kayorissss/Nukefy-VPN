"""Render tray icons: dark plate + white mark + a status dot in the corner.

The previous set was the bare logo on a transparent background with the dot
clipped into the corner, which in a 16 px tray slot read as "just a faint
logo, no badge at all". Here every icon is a full dark plate (so it is visible
on light and dark taskbars), the dot sits inside the plate and only exists in
states that actually have something to report:

    tray_ok    — connected            (green)
    tray_warn  — connecting           (amber)
    tray_bad   — error                (red)
    tray_idle  — nothing running      (no dot at all)

Pure standard library, same codecs as make_icons.py:

    python3 tools/make_tray_status_icons.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_icons import (_inside_rounded, luminance, mask_curve, read_png,  # noqa: E402
                        resize_mask, write_ico, write_png)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'assets', 'icons', 'tray_icon.png')
OUT = os.path.join(ROOT, 'assets', 'icons')

PLATE = (13, 14, 18)
STATES = {
    'ok': (46, 229, 157),
    'warn': (255, 196, 0),
    'bad': (255, 77, 109),
    'idle': None,
}
SIZES = (16, 24, 32, 48)
PNG_SIZE = 128


def build_logo_mask(w, h, ch, px):
    """White-on-transparent mark -> 0..255 coverage, ignoring the plate."""
    mask = bytearray(w * h)
    for y in range(h):
        row = y * w
        for x in range(w):
            o = (row + x) * ch
            alpha = px[o + 3]
            if alpha == 0:
                continue
            # Source mark is white on transparency: alpha is the coverage.
            mask[row + x] = alpha
    return mask


def render(size, logo_mask, sw, sh, dot):
    plate_r = size * 0.22
    inner = int(size * 0.66)
    inner = max(inner, 8)
    glyph = resize_mask(logo_mask, sw, sh, inner, inner)
    off = (size - inner) // 2
    dot_r = size * 0.135 if dot else 0
    dot_cx, dot_cy = size * 0.765, size * 0.765

    rgba = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            o = (y * size + x) * 4
            inside = _inside_rounded(x, y, size, size, plate_r)
            if not inside:
                continue  # transparent outside the rounded plate
            r, g, b, a = PLATE[0], PLATE[1], PLATE[2], 255
            # glyph
            gx, gy = x - off, y - off
            if 0 <= gx < inner and 0 <= gy < inner:
                t = glyph[gy * inner + gx] / 255.0
                if t > 0:
                    r = int(round(r + (255 - r) * t))
                    g = int(round(g + (255 - g) * t))
                    b = int(round(b + (255 - b) * t))
            # status dot with a plate-coloured ring so it stays readable
            if dot:
                dx, dy = x - dot_cx, y - dot_cy
                d2 = dx * dx + dy * dy
                if d2 <= (dot_r + max(1.0, size * 0.045)) ** 2:
                    if d2 <= dot_r * dot_r:
                        r, g, b = dot
                    else:
                        r, g, b = PLATE
            rgba[o], rgba[o + 1], rgba[o + 2], rgba[o + 3] = r, g, b, a
    return bytes(rgba)


def main():
    w, h, ch, px = read_png(SRC)
    mask = build_logo_mask(w, h, ch, px)

    for name, dot in STATES.items():
        with open(os.path.join(OUT, f'_frame_{name}.png'), 'wb') as _:
            pass
        png = render(PNG_SIZE, mask, w, h, dot)
        write_png(os.path.join(OUT, f'tray_{name}.png'), PNG_SIZE, PNG_SIZE, png)
        frames = []
        for size in SIZES:
            path = os.path.join(OUT, f'_frame_{name}.png')
            write_png(path, size, size, render(size, mask, w, h, dot))
            with open(path, 'rb') as fh:
                frames.append((size, fh.read()))
        write_ico(os.path.join(OUT, f'tray_{name}.ico'), frames)
        os.remove(os.path.join(OUT, f'_frame_{name}.png'))
        print('wrote tray_%s (.png %d, .ico %s)' % (name, PNG_SIZE, ','.join(str(s) for s in SIZES)))

    # Legacy aliases from the first tray generation: keep them in sync so an
    # older build that still asks for tray_on / tray_error keeps working.
    for legacy, modern in {'on': 'ok', 'connecting': 'warn', 'error': 'bad', 'off': 'idle'}.items():
        for ext in ('png', 'ico'):
            src = os.path.join(OUT, f'tray_{modern}.{ext}')
            dst = os.path.join(OUT, f'tray_{legacy}.{ext}')
            with open(src, 'rb') as fh:
                data = fh.read()
            with open(dst, 'wb') as fh:
                fh.write(data)


if __name__ == '__main__':
    main()
