"""Regenerates lib/ui/widgets/world_map_data.dart.

The dotted world map on the home screen is not an image: it is a rasterised
land mask plus one land centroid per country, both generated from Natural
Earth 1:110m (public domain) as packaged by world-atlas.

    curl -sLO https://registry.npmjs.org/world-atlas/-/world-atlas-2.0.2.tgz
    tar xzf world-atlas-2.0.2.tgz package/land-110m.json package/countries-110m.json
    pip install pycountry
    python3 tool/gen_world_map.py package/land-110m.json package/countries-110m.json

Only the generated Dart file is committed; this script is kept so the mask can
be regenerated (different grid, different crop) without another source.
"""
"""Build the dotted-world-map data used by the app.

In:  /tmp/package/land-110m.json, /tmp/package/countries-110m.json (world-atlas,
     Natural Earth 1:110m, public domain)
Out: lib/ui/widgets/world_map_data.dart

The mask is rasterised with a scanline fill (even-odd) so a 170x74 grid of dots
takes under a second to produce.
"""
import json, math, sys

COLS, ROWS = 170, 74
LON0, LON1 = -180.0, 180.0
LAT0, LAT1 = 84.0, -56.0   # top, bottom (equirectangular, land-friendly crop)


def load(path):
    return json.load(open(path))


def decode_arcs(topo):
    tr = topo.get('transform')
    sx, sy = (tr['scale'] if tr else (1, 1))
    tx, ty = (tr['translate'] if tr else (0, 0))
    arcs = []
    for arc in topo['arcs']:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)
    return arcs


def ring_points(arcs, idxs):
    pts = []
    for i in idxs:
        if i >= 0:
            seg = arcs[i]
        else:
            seg = list(reversed(arcs[~i]))
        if pts and seg and pts[-1] == seg[0]:
            pts.extend(seg[1:])
        else:
            pts.extend(seg)
    return pts


def polygons_of(geom, arcs):
    t = geom['type']
    out = []
    if t == 'Polygon':
        out.append([ring_points(arcs, r) for r in geom['arcs']])
    elif t == 'MultiPolygon':
        for poly in geom['arcs']:
            out.append([ring_points(arcs, r) for r in poly])
    return out


def rasterise(rings):
    """Even-odd scanline fill -> set of (row, col)."""
    edges = []
    for ring in rings:
        for a, b in zip(ring, ring[1:] + ring[:1]):
            if a[1] != b[1]:
                edges.append((a, b))
    rows = []
    for r in range(ROWS):
        lat = LAT1 + (LAT0 - LAT1) * (r + 0.5) / ROWS
        xs = []
        for (x1, y1), (x2, y2) in edges:
            if (y1 > lat) != (y2 > lat):
                t = (lat - y1) / (y2 - y1)
                xs.append(x1 + t * (x2 - x1))
        xs.sort()
        filled = [False] * COLS
        for i in range(0, len(xs) - 1, 2):
            lo, hi = xs[i], xs[i + 1]
            c0 = max(0, int(math.ceil((lo - LON0) / (LON1 - LON0) * COLS - 0.5)))
            c1 = min(COLS - 1, int(math.floor((hi - LON0) / (LON1 - LON0) * COLS - 0.5)))
            for c in range(c0, c1 + 1):
                filled[c] = True
        rows.append(''.join('#' if f else '.' for f in filled))
    return rows


def ring_area(ring):
    s = 0.0
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        s += x1 * y2 - x2 * y1
    return abs(s) / 2.0


def main():
    land_path = sys.argv[1] if len(sys.argv) > 1 else '/tmp/package/land-110m.json'
    countries_path = sys.argv[2] if len(sys.argv) > 2 else '/tmp/package/countries-110m.json'
    land = load(land_path)
    arcs = decode_arcs(land)
    rings = []
    for g in land['objects']['land']['geometries']:
        for poly in polygons_of(g, arcs):
            rings.extend(poly)
    rows = rasterise(rings)
    filled = sum(r.count('#') for r in rows)
    print(f'land cells: {filled} / {COLS * ROWS}', file=sys.stderr)

    # country centroids (largest ring of each country by planar area)
    countries = load(countries_path)
    carcs = decode_arcs(countries)
    try:
        import pycountry
    except ImportError:
        pycountry = None
    points = {}
    for g in countries['objects']['countries']['geometries']:
        polys = polygons_of(g, carcs)
        if not polys:
            continue
        best = max((p[0] for p in polys), key=ring_area)
        a = ring_area(best)
        if a <= 0:
            continue
        cx = cy = 0.0
        for (x1, y1), (x2, y2) in zip(best, best[1:] + best[:1]):
            cross = x1 * y2 - x2 * y1
            cx += (x1 + x2) * cross
            cy += (y1 + y2) * cross
        cx /= 6 * (a if a else 1)
        cy /= 6 * (a if a else 1)
        # recompute with sign preserved for centroid correctness
        signed = 0.0
        sx = sy = 0.0
        for (x1, y1), (x2, y2) in zip(best, best[1:] + best[:1]):
            cross = x1 * y2 - x2 * y1
            signed += cross
            sx += (x1 + x2) * cross
            sy += (y1 + y2) * cross
        if signed == 0:
            continue
        cx, cy = sx / (3 * signed), sy / (3 * signed)
        num = g.get('id')
        code = None
        if pycountry and num:
            try:
                c = pycountry.countries.get(numeric=str(num).zfill(3))
                code = c.alpha_2 if c else None
            except Exception:
                code = None
        if not code:
            continue
        points[code] = (round(cy, 2), round(cx, 2))
    print(f'countries: {len(points)}', file=sys.stderr)

    # France/Norway/etc. centroids land badly when a country owns far-away
    # islands; those are cosmetic and left as computed.
    lines = []
    lines.append('// GENERATED FILE — do not edit by hand.')
    lines.append('// Source: world-atlas 2.0.2 (Natural Earth 1:110m, public domain) +')
    lines.append('// ISO 3166 via pycountry. Regenerate with tool/gen_world_map.py.')
    lines.append('')
    lines.append('/// Land raster: one line per row of dots, `#` = land.')
    lines.append(f'const int kWorldMapColumns = {COLS};')
    lines.append(f'const int kWorldMapRows = {ROWS};')
    lines.append('const double kWorldMapLonMin = %.1f;' % LON0)
    lines.append('const double kWorldMapLonMax = %.1f;' % LON1)
    lines.append('const double kWorldMapLatTop = %.1f;' % LAT0)
    lines.append('const double kWorldMapLatBottom = %.1f;' % LAT1)
    lines.append('const String kWorldMapMask =')
    for i, r in enumerate(rows):
        sep = ';' if i == len(rows) - 1 else ''
        lines.append("    '%s'%s" % (r, sep))
    lines.append('')
    lines.append('/// Approximate land centroid per ISO-3166 alpha-2 code: (lat, lon).')
    lines.append('const Map<String, (double, double)> kCountryCentroids = {')
    for code in sorted(points):
        lat, lon = points[code]
        lines.append("  '%s': (%.2f, %.2f)," % (code, lat, lon))
    lines.append('};')
    open('/home/user/Nukefy-VPN/lib/ui/widgets/world_map_data.dart', 'w').write('\n'.join(lines) + '\n')


main()
