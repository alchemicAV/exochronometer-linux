#!/usr/bin/env python3
"""Inline the generated SVG figures into the paper template -> final HTML."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
FIGDIR = os.path.join(HERE, "figures")

FIGS = {
    "FIG0": "fig0_logo.svg",
    "FIG1": "fig1_circle.svg",
    "FIG2": "fig2_dot_top.svg",
    "FIG3": "fig3_traverse.svg",
    "FIG4": "fig4_geometry_peak.svg",
    "FIG5": "fig5_catalog.svg",
    "FIG6": "fig6_star.svg",
    "FIG7": "fig7_clock.svg",
    "FIG8": "fig8_calendar.svg",
}

with open(os.path.join(HERE, "paper.template.html")) as f:
    html = f.read()

for token, fname in FIGS.items():
    with open(os.path.join(FIGDIR, fname)) as f:
        svg = f.read().strip()
    html = html.replace(f"<!--{token}-->", svg)

out = os.path.join(HERE, "exochronometer-process.html")
with open(out, "w") as f:
    f.write(html)
print("wrote", out, f"({len(html)} bytes)")
