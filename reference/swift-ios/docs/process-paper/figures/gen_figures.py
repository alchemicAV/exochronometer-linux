#!/usr/bin/env python3
"""
Figure generator for the Exochronometer process paper — PRINT / LIGHT edition.

Every geometric quantity is a direct port of the shipping app's math:
  - indicator angle      -> TimeFrame.degree  (0 deg at top, clockwise)
  - vertex placement     -> GeometryMath.nodeDegrees / GeometryOverlayView.nodePoints
  - shape catalogue      -> GeometryMath.buildShapeList (3..8, {n/k}, gcd==1)
  - activation / "peak"  -> FadeMath.opacity  (cos window, fadeFraction 0.03)
  - logo emblem          -> Tools/GenerateAppIcon.swift (all shapes, dot at top)

Output: dark-ink-on-white line-art SVGs, inverted from the app's on-screen
white-on-black so the document prints cleanly to PDF.
"""
import math
import os
from datetime import datetime, timedelta

OUT = os.path.dirname(os.path.abspath(__file__))

# ---- app constants -------------------------------------------------------
FADE_FRACTION = 0.03            # FadeMath default -> 10.8 deg half-window
TROPICAL_YEAR_DAYS = 365.24219  # TimeFrame.tropicalYearDays
SOLSTICE = datetime(2014, 12, 21, 23, 3)  # PhaseEpoch.decemberSolstice

# ---- print palette (inverted) -------------------------------------------
BG = "#ffffff"       # paper white — cheapest ink, cleanest PDF
INK = "#1b2026"      # cool near-black line-art
ACCENT = "#2f5d84"   # meridian blue — the live/travelling indicator
HALO = "#ffffff"     # ring that lifts the indicator off crossing lines


# ---- ported math ---------------------------------------------------------
def gcd(a, b):
    a, b = abs(a), abs(b)
    while b:
        a, b = b, a % b
    return a


def deg_to_point(cx, cy, r, degree):
    rad = math.radians(degree - 90)          # 0 deg at top, clockwise
    return (cx + r * math.cos(rad), cy + r * math.sin(rad))


def circular_distance(a, b):
    d = a - b
    if d > 180:
        d -= 360
    if d < -180:
        d += 360
    return abs(d)


def opacity(current_deg, target_deg, fade_fraction=FADE_FRACTION):
    window = fade_fraction * 360.0
    dist = circular_distance(current_deg, target_deg)
    if dist > window:
        return 0.0
    return math.cos((dist / window) * (math.pi / 2))


def shape_opacity(current_deg, divisions, fade_fraction=FADE_FRACTION):
    best = 0.0
    for i in range(divisions):
        best = max(best, opacity(current_deg, i * 360.0 / divisions, fade_fraction))
    return best


def star_path(divisions, skip):
    edges, visited = [], set()
    for start in range(divisions):
        if start in visited:
            continue
        cur = start
        while cur not in visited:
            visited.add(cur)
            nxt = (cur + skip) % divisions
            edges.append((cur, nxt))
            cur = nxt
    return edges


def catalog(min_div=3, max_div=8, include_stars=True):
    shapes = []
    for div in range(min_div, max_div + 1):
        for skip in range(1, div):
            if skip >= div / 2:
                continue
            if gcd(div, skip) != 1:
                continue
            is_reg = (skip == 1)
            if not include_stars and not is_reg:
                continue
            shapes.append((div, skip, is_reg))
    return shapes


# ---- svg helpers ---------------------------------------------------------
def svg_header(w, h):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" '
        f'width="{w}" height="{h}" font-family="ui-monospace,Menlo,Consolas,monospace">\n'
        f'  <rect x="0" y="0" width="{w}" height="{h}" fill="{BG}"/>\n'
    )


def circle(cx, cy, r, op=0.5, sw=1.4):
    return (f'  <circle cx="{cx}" cy="{cy}" r="{r}" fill="none" '
            f'stroke="{INK}" stroke-opacity="{op}" stroke-width="{sw}"/>\n')


def line(p0, p1, op, sw=1.1, cap="butt"):
    return (f'  <line x1="{p0[0]:.2f}" y1="{p0[1]:.2f}" x2="{p1[0]:.2f}" y2="{p1[1]:.2f}" '
            f'stroke="{INK}" stroke-opacity="{op:.3f}" stroke-width="{sw}" '
            f'stroke-linecap="{cap}"/>\n')


def indicator(cx, cy, r, degree, radius=6.5, color=ACCENT):
    """Travelling dot: accent fill on a white halo so it reads over crossings."""
    x, y = deg_to_point(cx, cy, r, degree)
    return (f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="{radius + 2.4}" fill="{HALO}"/>\n'
            f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="{radius}" fill="{color}"/>\n'), (x, y)


def dot(x, y, r=3.0, op=1.0, color=INK):
    return (f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="{r}" fill="{color}" '
            f'fill-opacity="{op:.3f}"/>\n')


def text(x, y, s, size=12, op=0.85, anchor="middle", weight="400", color=INK):
    return (f'  <text x="{x:.2f}" y="{y:.2f}" font-size="{size}" '
            f'fill="{color}" fill-opacity="{op:.3f}" text-anchor="{anchor}" '
            f'font-weight="{weight}" dominant-baseline="middle">{s}</text>\n')


def arc(cx, cy, r, deg0, deg1, op=0.5, sw=1.2, dash=None):
    p0 = deg_to_point(cx, cy, r, deg0)
    p1 = deg_to_point(cx, cy, r, deg1)
    large = 1 if (deg1 - deg0) % 360 > 180 else 0
    d = (f'  <path d="M {p0[0]:.2f} {p0[1]:.2f} A {r} {r} 0 {large} 1 '
         f'{p1[0]:.2f} {p1[1]:.2f}" fill="none" stroke="{INK}" '
         f'stroke-opacity="{op}" stroke-width="{sw}"')
    if dash:
        d += f' stroke-dasharray="{dash}"'
    d += '/>\n'
    return d


def write(name, body):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(body)
    print("wrote", name)


# ---- figure builders -----------------------------------------------------
W = 460
CX = CY = W / 2
R = 168


def fig_logo():
    """Emblem: outer circle + ALL default shapes (regular + star), dot at top.
    Mirrors Tools/GenerateAppIcon.swift, inverted for print."""
    s = svg_header(W, W)
    s += circle(CX, CY, R, op=0.55, sw=1.8)
    for n, k, _reg in catalog(3, 8, include_stars=True):
        verts = [deg_to_point(CX, CY, R, i * 360.0 / n) for i in range(n)]
        for a, b in star_path(n, k):
            s += line(verts[a], verts[b], 0.6, sw=1.5, cap="round")
    # indicator dot at 0deg (top), where every shape shares a vertex
    x, y = deg_to_point(CX, CY, R, 0)
    s += f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="12.5" fill="{HALO}"/>\n'
    s += f'  <circle cx="{x:.2f}" cy="{y:.2f}" r="9.5" fill="{INK}"/>\n'
    s += "</svg>\n"
    write("fig0_logo.svg", s)


def fig_circle():
    s = svg_header(W, W)
    s += circle(CX, CY, R)
    s += "</svg>\n"
    write("fig1_circle.svg", s)


def fig_dot_top():
    s = svg_header(W, W)
    s += circle(CX, CY, R)
    ind, (x, y) = indicator(CX, CY, R, 0)
    s += ind
    s += text(x, y - 22, "start", size=12, op=0.8)
    s += text(CX, CY, "t = 0", size=15, op=0.55)
    s += "</svg>\n"
    write("fig2_dot_top.svg", s)


def fig_traverse():
    deg = 90  # one day -> 06:00
    s = svg_header(W, W)
    s += circle(CX, CY, R)
    s += arc(CX, CY, R, 2, deg - 4, op=0.5, sw=1.6, dash="2 5")
    sx, sy = deg_to_point(CX, CY, R, 0)
    s += dot(sx, sy, r=2.4, op=0.55)
    s += text(sx, sy - 16, "t = 0", size=10, op=0.5)
    ind, (x, y) = indicator(CX, CY, R, deg)
    s += ind
    s += text(x + 30, y, "dot", size=12, op=0.8, anchor="start")
    s += text(CX, CY - 10, "T = one day", size=14, op=0.6)
    s += text(CX, CY + 14, "06:00", size=20, op=0.9)
    s += "</svg>\n"
    write("fig3_traverse.svg", s)


def fig_geometry_peak():
    n = 3
    cur = 120.0
    s = svg_header(W, W)
    s += circle(CX, CY, R)
    verts = [deg_to_point(CX, CY, R, i * 360.0 / n) for i in range(n)]
    op = shape_opacity(cur, n)  # 1.0 on the vertex
    for a in range(n):
        b = (a + 1) % n
        s += line(verts[a], verts[b], min(1.0, op * 0.9 + 0.1), sw=1.4)
    labels = {0: "00:00", 1: "08:00", 2: "16:00"}
    for i in range(n):
        vx, vy = verts[i]
        s += dot(vx, vy, r=3.2, op=0.9)
        lx, ly = deg_to_point(CX, CY, R + 26, i * 360.0 / n)
        s += text(lx, ly, labels[i], size=11, op=0.75)
    ind, (x, y) = indicator(CX, CY, R, cur)
    s += ind
    s += text(CX, CY - 10, "activation", size=12, op=0.5)
    s += text(CX, CY + 12, "1.00 (peak)", size=16, op=0.9)
    s += "</svg>\n"
    write("fig4_geometry_peak.svg", s)


def fig_catalog():
    shapes = [(3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1)]
    cols, rows = 3, 2
    cell = 220
    w = cols * cell
    h = rows * cell + 4
    s = svg_header(w, h)
    r = cell / 2 - 34
    for idx, (n, k) in enumerate(shapes):
        c = idx % cols
        rr = idx // cols
        ccx = c * cell + cell / 2
        ccy = rr * cell + cell / 2 - 6
        s += circle(ccx, ccy, r, op=0.4, sw=1.1)
        verts = [deg_to_point(ccx, ccy, r, i * 360.0 / n) for i in range(n)]
        for a, b in star_path(n, k):
            s += line(verts[a], verts[b], 0.75, sw=1.3)
        for vx, vy in verts:
            s += dot(vx, vy, r=2.6, op=0.9)
        s += text(ccx, ccy + r + 22, f"{{{n}/{k}}} — {n} marks", size=12, op=0.8)
    s += "</svg>\n"
    write("fig5_catalog.svg", s)


def fig_star():
    n, k = 5, 2
    s = svg_header(W, W)
    s += circle(CX, CY, R)
    verts = [deg_to_point(CX, CY, R, i * 360.0 / n) for i in range(n)]
    for a, b in star_path(n, k):
        s += line(verts[a], verts[b], 0.8, sw=1.4)
    order, cur = [0], 0
    for _ in range(n):
        cur = (cur + k) % n
        order.append(cur)
    for i in range(n):
        vx, vy = verts[i]
        s += dot(vx, vy, r=3.2, op=0.9)
        lx, ly = deg_to_point(CX, CY, R + 24, i * 360.0 / n)
        s += text(lx, ly, f"{order.index(i)}", size=12, op=0.75)
    s += text(CX, CY - 10, "{5/2}", size=17, op=0.9)
    s += text(CX, CY + 14, "5 marks / 2 laps", size=12, op=0.6)
    s += "</svg>\n"
    write("fig6_star.svg", s)


def fig_clock():
    frames = [
        ("ONE HOUR", "34:00", 204),
        ("ONE DAY", "16:20", 245),
        ("MOON", "waxing", 156),
        ("ONE YEAR", "spring", 138),
    ]
    cell = 224
    w = 4 * cell
    h = cell + 6
    s = svg_header(w, h)
    r = cell / 2 - 40
    for idx, (label, readout, deg) in enumerate(frames):
        ccx = idx * cell + cell / 2
        ccy = cell / 2 - 4
        s += circle(ccx, ccy, r, op=0.5, sw=1.2)
        verts = [deg_to_point(ccx, ccy, r, i * 120) for i in range(3)]
        opv = shape_opacity(deg, 3)
        for a in range(3):
            b = (a + 1) % 3
            s += line(verts[a], verts[b], max(0.16, opv) * 0.55, sw=1.0)
        ind, (x, y) = indicator(ccx, ccy, r, deg, radius=5.5)
        s += ind
        s += text(ccx, ccy, readout, size=13, op=0.85)
        s += text(ccx, ccy + r + 26, label, size=11, op=0.75)
    s += "</svg>\n"
    write("fig7_clock.svg", s)


def fig_calendar():
    pad = 40
    s = svg_header(W + pad, W + pad)
    cx = cy = (W + pad) / 2
    r = R

    def node_date(degree):
        d = SOLSTICE + timedelta(days=(degree / 360.0) * TROPICAL_YEAR_DAYS)
        return d.strftime("%b %-d")

    s += circle(cx, cy, r)
    n = 5
    verts = [deg_to_point(cx, cy, r, i * 360.0 / n) for i in range(n)]
    for a in range(n):
        b = (a + 1) % n
        s += line(verts[a], verts[b], 0.75, sw=1.3)
    for i in range(n):
        vx, vy = verts[i]
        s += dot(vx, vy, r=3.4, op=0.9)
        lx, ly = deg_to_point(cx, cy, r + 30, i * 360.0 / n)
        s += text(lx, ly, node_date(i * 360.0 / n), size=11, op=0.8)
    today_deg = 40
    ind, (x, y) = indicator(cx, cy, r, today_deg, radius=6)
    s += ind
    s += text(x + 12, y - 12, "today", size=11, op=0.8, anchor="start")
    s += text(cx, cy - 12, "T = one year", size=13, op=0.6)
    s += text(cx, cy + 12, "{5} → 5 dates", size=13, op=0.85)
    s += "</svg>\n"
    write("fig8_calendar.svg", s)


if __name__ == "__main__":
    fig_logo()
    fig_circle()
    fig_dot_top()
    fig_traverse()
    fig_geometry_peak()
    fig_catalog()
    fig_star()
    fig_clock()
    fig_calendar()
    print("done ->", OUT)
