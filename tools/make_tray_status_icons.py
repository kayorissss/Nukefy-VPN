"""Render tray icons with a status dot (pure python, reuses make_icons codecs)."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from make_icons import read_png, write_png, write_ico  # noqa: E402

BASE = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icons', 'tray_icon.png')
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icons')

STATES = {
    'on': (76, 217, 100),
    'connecting': (255, 204, 0),
    'off': (140, 140, 140),
    'error': (255, 77, 79),
}


def main():
    w, h, _ch, rgba = read_png(BASE)
    cx, cy = w - 1, h - 1
    ring_r = max(6, int(min(w, h) * 0.30))
    dot_r = max(4, int(ring_r * 0.72))
    for name, (r, g, b) in STATES.items():
        px = bytearray(rgba)
        for y in range(h):
            for x in range(w):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                if d2 <= ring_r * ring_r:
                    i = (y * w + x) * 4
                    if d2 <= dot_r * dot_r:
                        px[i:i + 4] = bytes((r, g, b, 255))
                    else:
                        px[i:i + 4] = bytes((255, 255, 255, 255))
        data = bytes(px)
        write_png(os.path.join(OUT, f'tray_{name}.png'), w, h, data)
        tmp = os.path.join(OUT, f'_tray_{name}.png')
        write_png(tmp, w, h, data)
        with open(tmp, 'rb') as fh:
            png = fh.read()
        os.remove(tmp)
        write_ico(os.path.join(OUT, f'tray_{name}.ico'), [(w, png)])
        print('wrote', name)


if __name__ == '__main__':
    main()
