"""Build the Cave Count display font used by the main calorie total.

The font is intentionally tiny: tabular numerals plus a comma. Its uneven,
broad outlines are drawn from scratch for Cave Cals. Rebuilding requires:

    python3 -m pip install fonttools shapely
"""

from pathlib import Path
from shapely.geometry import LineString, Point
from shapely.ops import unary_union
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "App/Fonts/CaveCount-Regular.otf"
UNITS_PER_EM = 1_000
DIGIT_ADVANCE = 570


def stroke(points, widths=96, closed=False):
    """Create a subtly irregular broad marker stroke around a centerline."""
    if isinstance(widths, (int, float)):
        widths = [float(widths)] * len(points)
    pieces = []
    pairs = list(zip(points, points[1:]))
    if closed:
        pairs.append((points[-1], points[0]))
    for index, (start, end) in enumerate(pairs):
        width = (widths[index] + widths[(index + 1) % len(widths)]) / 2
        pieces.append(LineString([start, end]).buffer(width / 2, quad_segs=3, cap_style=1, join_style=1))
    for point, width in zip(points, widths):
        pieces.append(Point(point).buffer(width / 2, quad_segs=4))
    return unary_union(pieces)


def loop(points, widths=96):
    return stroke(points, widths, closed=True)


def union(*pieces):
    return unary_union(pieces)


GLYPHS = {
    # The asymmetry is deliberate: it gives the large total the same handmade
    # confidence as the Cave Cals wordmark without bringing its fine texture
    # into a UI number that must remain immediately readable.
    "zero": loop([(287, 785), (151, 738), (92, 575), (102, 303), (161, 111),
                  (294, 55), (421, 123), (474, 329), (459, 596), (397, 746)],
                 [102, 98, 92, 101, 108, 94, 103, 96, 106, 99]),
    "one": union(
        stroke([(178, 650), (282, 782), (307, 742), (293, 91)], [88, 101, 96, 106]),
        stroke([(188, 83), (405, 78)], [91, 101]),
    ),
    "two": stroke([(100, 620), (135, 726), (263, 789), (398, 756), (458, 654),
                   (425, 535), (321, 422), (188, 282), (102, 111), (454, 91)],
                  [91, 100, 107, 95, 103, 92, 99, 96, 105, 96]),
    "three": stroke([(105, 697), (209, 784), (353, 775), (441, 684), (416, 568),
                     (313, 488), (407, 440), (456, 319), (417, 170), (291, 72), (125, 119)],
                    [92, 101, 96, 104, 91, 100, 94, 108, 96, 105, 93]),
    "four": union(
        stroke([(392, 75), (401, 787)], [104, 95]),
        stroke([(365, 768), (102, 325), (472, 337)], [96, 106, 93]),
    ),
    "five": stroke([(446, 766), (137, 770), (111, 480), (235, 519), (371, 486),
                    (450, 380), (436, 220), (330, 100), (168, 75), (93, 126)],
                   [99, 108, 94, 102, 91, 107, 97, 103, 92, 101]),
    "six": union(
        stroke([(421, 724), (334, 788), (210, 730), (125, 589), (98, 388),
                (111, 194), (222, 72), (366, 89), (455, 219), (426, 376),
                (304, 451), (151, 407)],
               [91, 101, 94, 106, 97, 104, 93, 108, 96, 102, 90, 99]),
        stroke([(118, 386), (145, 111)], [91, 101]),
    ),
    "seven": stroke([(91, 763), (467, 778), (369, 602), (292, 433), (229, 254), (204, 72)],
                    [99, 107, 93, 102, 95, 106]),
    "eight": union(
        loop([(283, 790), (161, 746), (119, 635), (168, 516), (290, 470),
              (409, 523), (446, 647), (397, 750)],
             [96, 104, 91, 100, 108, 94, 103, 93]),
        loop([(285, 472), (143, 416), (98, 259), (155, 104), (294, 54),
              (427, 112), (466, 268), (415, 420)],
             [101, 92, 106, 96, 103, 91, 107, 95]),
    ),
    "nine": union(
        loop([(278, 785), (151, 735), (107, 596), (154, 461), (286, 411),
              (418, 470), (459, 613), (404, 746)],
             [101, 93, 107, 96, 104, 91, 106, 97]),
        stroke([(445, 624), (434, 364), (381, 167), (270, 65), (153, 91)],
               [92, 104, 96, 106, 94]),
    ),
    "comma": stroke([(158, 101), (137, 24), (89, -93)], [104, 96, 86]),
}


def draw_ring(pen, bounds, inset=70):
    x1, y1, x2, y2 = bounds
    pen.moveTo((x1, y1)); pen.lineTo((x2, y1)); pen.lineTo((x2, y2)); pen.lineTo((x1, y2)); pen.closePath()
    pen.moveTo((x1 + inset, y1 + inset)); pen.lineTo((x1 + inset, y2 - inset))
    pen.lineTo((x2 - inset, y2 - inset)); pen.lineTo((x2 - inset, y1 + inset)); pen.closePath()


def geometry_to_charstring(geometry, width):
    pen = T2CharStringPen(width, None)
    polygons = [geometry] if geometry.geom_type == "Polygon" else list(geometry.geoms)
    for polygon in polygons:
        contours = [polygon.exterior, *polygon.interiors]
        for contour in contours:
            points = [(round(x), round(y)) for x, y in list(contour.coords)[:-1]]
            if len(points) < 3:
                continue
            pen.moveTo(points[0])
            for point in points[1:]:
                pen.lineTo(point)
            pen.closePath()
    return pen.getCharString(private=None, globalSubrs=None)


def build():
    glyph_order = [".notdef", "space", "comma", "zero", "one", "two", "three", "four",
                   "five", "six", "seven", "eight", "nine"]
    widths = {name: (DIGIT_ADVANCE, 20) for name in glyph_order}
    widths["space"] = (280, 0)
    widths["comma"] = (250, 20)

    charstrings = {}
    notdef_pen = T2CharStringPen(DIGIT_ADVANCE, None)
    draw_ring(notdef_pen, (70, 0, 500, 800))
    charstrings[".notdef"] = notdef_pen.getCharString(private=None, globalSubrs=None)
    charstrings["space"] = T2CharStringPen(widths["space"][0], None).getCharString(private=None, globalSubrs=None)
    for name, geometry in GLYPHS.items():
        charstrings[name] = geometry_to_charstring(geometry, widths[name][0])

    builder = FontBuilder(UNITS_PER_EM, isTTF=False)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap({
        ord(" "): "space", ord(","): "comma",
        **{ord(character): name for character, name in zip("0123456789", glyph_order[3:])},
    })
    builder.setupHorizontalMetrics(widths)
    builder.setupHorizontalHeader(ascent=900, descent=-180)
    builder.setupNameTable({
        "familyName": "Cave Count",
        "styleName": "Regular",
        "uniqueFontIdentifier": "Cave Cals:Cave Count Regular:2026",
        "fullName": "Cave Count Regular",
        "psName": "CaveCount-Regular",
        "version": "Version 1.000",
    })
    builder.setupOS2(
        sTypoAscender=900, sTypoDescender=-180, sTypoLineGap=0,
        usWinAscent=900, usWinDescent=180,
        sxHeight=500, sCapHeight=800,
    )
    builder.setupPost(keepGlyphNames=True)
    builder.setupCFF(
        "CaveCount-Regular",
        {"FullName": "Cave Count Regular", "FamilyName": "Cave Count", "Weight": "Regular"},
        charstrings,
        {},
    )
    builder.setupMaxp()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    builder.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build()
