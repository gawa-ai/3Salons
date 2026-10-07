#!/usr/bin/env python3
"""Builds the Shahina Ahmed brand assets as pure-vector SVG (text converted to paths).

Typefaces (both SIL Open Font License 1.1, which permits use in logos):
  * Cormorant Garamond  - display serif (Christian Thalmann)
  * Manrope             - descriptor sans (Mikhail Sharanda)
Font files are read from google/fonts (ofl/cormorantgaramond, ofl/manrope).

Outputs (brand/svg/):
  shahina-ahmed-lockup.svg         stacked lockup, charcoal on transparent
  shahina-ahmed-lockup-light.svg   stacked lockup, ivory (for dark backgrounds)
  shahina-ahmed-wordmark.svg       one-line wordmark for headers
  shahina-ahmed-wordmark-light.svg
  sa-monogram.svg / sa-monogram-light.svg / sa-monogram-filled.svg
  favicon.svg
"""
import pathlib, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

FONTS = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/home/claude/google/fonts/ofl")
OUT = pathlib.Path(__file__).parent / "svg"
OUT.mkdir(exist_ok=True)

CHARCOAL = "#1F1B18"
IVORY = "#F7F2EA"
BRONZE = "#7E5E3F"
BRONZE_LIGHT = "#C9A97F"

def instance(path, wght):
    f = TTFont(path)
    return instantiateVariableFont(f, {"wght": wght}, inplace=False)

serif = instance(FONTS / "cormorantgaramond/CormorantGaramond[wght].ttf", 500)
serif_semibold = instance(FONTS / "cormorantgaramond/CormorantGaramond[wght].ttf", 600)
serif_italic = instance(FONTS / "cormorantgaramond/CormorantGaramond-Italic[wght].ttf", 500)
sans = instance(FONTS / "manrope/Manrope[wght].ttf", 600)
# Signature script for the salon name (Pinyon Script, SIL OFL). Set PINYON=/path/to/PinyonScript-Regular.ttf
import os
NAME = "Shahina Ahmed"


def text_paths(font, text, size, tracking_em=0.0, x0=0.0, baseline=0.0, kerning=True):
    """Returns (svg path data, advance width, (xmin, ymin, xmax, ymax)) for text set at `size` px."""
    upm = font["head"].unitsPerEm
    scale = size / upm
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    hmtx = font["hmtx"]
    kern = {}
    if kerning and "kern" in font:
        for t in font["kern"].kernTables:
            kern.update(t.kernTable)
    x = x0
    d_all = []
    bounds = [1e9, 1e9, -1e9, -1e9]
    prev = None
    for ch in text:
        g = cmap.get(ord(ch))
        if g is None:
            raise SystemExit(f"glyph missing for {ch!r}")
        if prev is not None:
            x += kern.get((prev, g), 0) * scale
        pen = SVGPathPen(gs)
        # font units (y up) -> svg (y down), placed at baseline
        tpen = TransformPen(pen, (scale, 0, 0, -scale, x, baseline))
        gs[g].draw(tpen)
        bp = BoundsPen(gs)
        gs[g].draw(TransformPen(bp, (scale, 0, 0, -scale, x, baseline)))
        if bp.bounds:
            bx0, by0, bx1, by1 = bp.bounds
            bounds = [min(bounds[0], bx0), min(bounds[1], by0), max(bounds[2], bx1), max(bounds[3], by1)]
        d = pen.getCommands()
        if d:
            d_all.append(d)
        x += hmtx[g][0] * scale + tracking_em * size
        prev = g
    width = x - x0 - tracking_em * size  # no trailing tracking
    return " ".join(d_all), width, bounds


def svg(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.1f} {h:.1f}" '
            f'width="{w:.0f}" height="{h:.0f}" role="img" aria-label="{title}">\n'
            f'<title>{title}</title>\n{body}\n</svg>\n')


def write(name, content):
    (OUT / name).write_text(content)
    print("wrote", name)


# ------------------------------------------------------------------ name = traced from her own logo (brand/trace_name.py)
import json
TR = json.loads((pathlib.Path(__file__).parent / "name_path.json").read_text())

def name_g(ink, width, x, y):
    k = width / TR["w"]
    return f'<path fill="{ink}" transform="translate({x:.2f} {y:.2f}) scale({k:.5f})" d="{TR["d"]}"/>', TR["h"] * k

def lockup(ink, accent):
    pad = 24; w_name = 620
    g, nh = name_g(ink, w_name, pad, pad)
    W = w_name + pad * 2
    rule_y = pad + nh + 36
    H = rule_y + 6 + pad
    cx = W / 2; half = w_name * 0.2; dm = 6
    body = (g + "\n"
            f'<g fill="none" stroke="{accent}" stroke-width="1.6">'
            f'<line x1="{cx - half:.1f}" y1="{rule_y:.1f}" x2="{cx - dm - 10:.1f}" y2="{rule_y:.1f}"/>'
            f'<line x1="{cx + dm + 10:.1f}" y1="{rule_y:.1f}" x2="{cx + half:.1f}" y2="{rule_y:.1f}"/></g>\n'
            f'<path fill="{accent}" d="M{cx:.1f} {rule_y - dm:.1f}L{cx + dm:.1f} {rule_y:.1f}L{cx:.1f} {rule_y + dm:.1f}L{cx - dm:.1f} {rule_y:.1f}Z"/>')
    return svg(W, H, body, "Shahina Ahmed")

write("shahina-ahmed-lockup.svg", lockup(CHARCOAL, BRONZE))
write("shahina-ahmed-lockup-light.svg", lockup(IVORY, BRONZE_LIGHT))

def wordmark(ink, accent):
    pad = 6; w_name = 420
    g, nh = name_g(ink, w_name, pad, pad)
    return svg(w_name + pad * 2, nh + pad * 2, g, "Shahina Ahmed")

write("shahina-ahmed-wordmark.svg", wordmark(CHARCOAL, BRONZE))
write("shahina-ahmed-wordmark-light.svg", wordmark(IVORY, BRONZE_LIGHT))


# ------------------------------------------------------------------ SA monogram
def monogram(ink, ring, bg=None, size=256, ring_w=2.2, inner=True, scale=1.0, a_font=None):
    c = size / 2
    a_font = a_font or serif
    # italic S sweeps across an upright A
    a_size = size * 0.66 * scale
    s_size = size * 0.75 * scale
    _, wa, ba = text_paths(a_font, "A", a_size)
    _, ws, bs = text_paths(serif_italic, "S", s_size)
    ax = c - (ba[0] + ba[2]) / 2 + size * 0.075
    ay = c - (ba[1] + ba[3]) / 2
    sx = c - (bs[0] + bs[2]) / 2 - size * 0.085
    sy = c - (bs[1] + bs[3]) / 2
    d_a, _, _ = text_paths(a_font, "A", a_size, 0, ax, ay)
    d_s, _, _ = text_paths(serif_italic, "S", s_size, 0, sx, sy)
    r = size / 2 - ring_w * 2
    parts = []
    if bg:
        parts.append(f'<circle cx="{c}" cy="{c}" r="{size / 2:.1f}" fill="{bg}"/>')
    if ring_w:
        parts.append(f'<circle cx="{c}" cy="{c}" r="{r:.1f}" fill="none" stroke="{ring}" stroke-width="{ring_w}"/>')
    if inner:
        parts.append(f'<circle cx="{c}" cy="{c}" r="{r - ring_w * 3.2:.1f}" fill="none" stroke="{ring}" stroke-width="{ring_w * 0.45:.2f}" opacity="0.7"/>')
    parts.append(f'<path fill="{ink}" opacity="0.92" d="{d_a}"/>')
    parts.append(f'<path fill="{ring}" d="{d_s}"/>')
    return svg(size, size, "\n".join(parts), "SA monogram")

write("sa-monogram.svg", monogram(CHARCOAL, BRONZE))
write("sa-monogram-light.svg", monogram(IVORY, BRONZE_LIGHT))
write("sa-monogram-filled.svg", monogram(IVORY, BRONZE_LIGHT, bg=CHARCOAL))
write("favicon.svg", monogram(IVORY, BRONZE_LIGHT, bg=CHARCOAL, size=64, ring_w=0, inner=False, scale=1.18, a_font=serif_semibold))
