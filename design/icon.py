"""Source of truth for the tether-link icon (the inchworm on macOS's Personal Hotspot link glyph).

`icon-source.svg` is the layered, hand-editable drawing (strokes + masks) kept for reference and
future edits; this script is what generates the shipped assets from the same geometry.

Builds the final silhouette as one filled shape (strokes, woven link gaps, legs, face, antennae)
with Shapely, then writes the Android vector drawables and an SVG preview. Android vectors can't
use SVG masks, which is why the gaps are computed here rather than drawn.

    nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.shapely ])' -c python3 design/icon.py
"""
import math
from pathlib import Path
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/src/main/res"
LINK = 14  # half the link stroke (28)
FACE = 7.5  # half the face stroke (15; heavier reads too bold light-on-dark)
GAP = 10   # link-crossing gap; the eye keeps the same clearance from the head outline
RES_PTS = 48  # points per quarter circle when sampling curves


def arc(cx, cy, r, a0, a1):
    n = max(4, int(abs(a1 - a0) / 90 * RES_PTS))
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def quad(p0, p1, p2, n=64):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(n + 1))]


def stroke(points, half, cap="round"):
    return LineString(points).buffer(half, cap_style=cap, join_style="round", quad_segs=RES_PTS)


def link(c0, c1, r=62):
    # Stadium-shaped ring: centreline is a capsule with cap centres c0, c1.
    spine = LineString([c0, c1])
    return spine.buffer(r + LINK, quad_segs=RES_PTS).difference(spine.buffer(r - LINK, quad_segs=RES_PTS))


tail, head = link((112, 232), (218, 232)), link((232, 300), (338, 300))
# Weave: the head passes over the tail at the head's left cap, the tail over the head at the
# tail's right cap; the link underneath loses a band GAP wider than the stroke on each side.
tail = tail.difference(stroke(arc(232, 300, 62, 125, 245), LINK + GAP, cap="flat"))
head = head.difference(stroke(arc(218, 232, 62, -55, 55), LINK + GAP, cap="flat"))

# Antennae lean forward, rooted on the head stroke's centreline.
ra = math.radians(-62)
antennae = [
    stroke(quad((330, 238), (350, 176), (376, 152)), 11), Point(376, 152).buffer(17, quad_segs=RES_PTS),
    stroke(quad((338 + 62 * math.cos(ra), 300 + 62 * math.sin(ra)), (410, 200), (444, 186)), 11), Point(444, 186).buffer(17, quad_segs=RES_PTS),
]

# Legs: rectangle + semicircle, sides meeting the body square-on.
legs = [box(x - 17, 360, x + 17, 376 + 20 - 17).union(Point(x, 376 + 20 - 17).buffer(17, quad_segs=RES_PTS)) for x in (252, 302, 352)]

# Happy eye: a ^ whose peak sits GAP (plus a small optical drop) below the head's inner top edge (y 252).
EYE_DROP = 4
ey = 252 + GAP + 16 + FACE + EYE_DROP
eye = stroke([(322, ey), (338, ey - 16), (354, ey)], FACE)
# Mouth: anchored in the head stroke's centreline, leaves the inner edge flat, curls up 50 degrees.
my, mr = 330, 34
mx = 338 + math.sqrt((62 - LINK) ** 2 - (my - 300) ** 2)
anchor = 338 + math.sqrt(62 ** 2 - (my - 300) ** 2)
mouth = stroke([(anchor, my)] + arc(mx, my - mr, mr, 90, 140), FACE)

shape = unary_union([tail, head, eye, mouth, *antennae, *legs]).simplify(0.05)


def path_data(geom, scale, dx, dy, ndigits=2):
    polys = getattr(geom, "geoms", [geom])
    out = []
    for poly in polys:
        for ring in [poly.exterior, *poly.interiors]:
            pts = [(round(x * scale + dx, ndigits), round(y * scale + dy, ndigits)) for x, y in ring.coords[:-1]]
            out.append("M" + " L".join(f"{x:g},{y:g}" for x, y in pts) + "Z")
    return "".join(out)


minx, miny, maxx, maxy = shape.bounds
cx, cy = (minx + maxx) / 2, (miny + maxy) / 2


def vector(size_dp, extent, color, name):
    # Fit the silhouette's bounding-box diagonal into `extent` of a size_dp viewport, centred.
    scale = extent / math.hypot(maxx - minx, maxy - miny)
    d = path_data(shape, scale, size_dp / 2 - cx * scale, size_dp / 2 - cy * scale)
    (RES / "drawable").mkdir(parents=True, exist_ok=True)
    (RES / "drawable" / name).write_text(
        f'<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="{size_dp}dp" android:height="{size_dp}dp"\n'
        f'    android:viewportWidth="{size_dp}" android:viewportHeight="{size_dp}">\n'
        f'    <path android:fillType="evenOdd" android:fillColor="{color}" android:pathData="{d}" />\n'
        f'</vector>\n'
    )


# Adaptive icon: 108dp canvas, everything inside the 66dp safe circle.
vector(108, 66, "@color/icon_fg", "ic_launcher_foreground.xml")
# System-colour variant: fill follows the wallpaper palette (see icon_colors.xml).
vector(108, 66, "@color/icon_system_fg", "ic_launcher_foreground_system.xml")
# Status-bar icon: white silhouette, tinted by the system.
vector(24, 23, "#FFFFFFFF", "ic_stat_tether.xml")

# Two launcher icons, picked at runtime by enabling one of two activity aliases: the purple
# colourway and one built from the wallpaper's dynamic colours.
(RES / "mipmap-anydpi").mkdir(parents=True, exist_ok=True)
for name, bg, fg in (("ic_launcher", "icon_bg", "ic_launcher_foreground"), ("ic_launcher_system", "icon_system_bg", "ic_launcher_foreground_system")):
    (RES / "mipmap-anydpi" / f"{name}.xml").write_text(
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        f'    <background android:drawable="@color/{bg}" />\n'
        f'    <foreground android:drawable="@drawable/{fg}" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
# xav.ie's palette (src/styles/global.css): the purple and the yellow from its dark theme.
BG, FG = "#281336", "#FFF17B"
# The system colourway uses the wallpaper's accent tones: light container with dark ink by day,
# flipped at night.
for folder, sys_bg, sys_fg in (("values", "system_accent1_100", "system_accent1_700"), ("values-night", "system_accent1_800", "system_accent1_100")):
    (RES / folder).mkdir(parents=True, exist_ok=True)
    (RES / folder / "icon_colors.xml").write_text(
        "<resources>\n"
        f'    <color name="icon_bg">#FF{BG[1:]}</color>\n'
        f'    <color name="icon_fg">#FF{FG[1:]}</color>\n'
        f'    <color name="icon_system_bg">@android:color/{sys_bg}</color>\n'
        f'    <color name="icon_system_fg">@android:color/{sys_fg}</color>\n'
        "</resources>\n"
    )

# Preview for the README: what a launcher shows (the middle 72dp of the 108dp canvas, masked
# to a circle), so the proportions match the home screen.
scale = 512 * 66 / 72 / math.hypot(maxx - minx, maxy - miny)
d = path_data(shape, scale, 256 - cx * scale, 256 - cy * scale)
(ROOT / "design/icon.svg").write_text(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><circle cx="256" cy="256" r="256" fill="{BG}"/>'
    f'<path fill-rule="evenodd" fill="{FG}" d="{d}"/></svg>\n'
)
print(f"bounds {shape.bounds}, {len(d)} chars of path data")
