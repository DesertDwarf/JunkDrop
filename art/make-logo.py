"""Draws JunkDrop's 400x400 CurseForge logo: a leather sack with a red arrow curling out of it and
pointing down. Drawn from basic shapes, so it uses no game art.

Usage:  py -m pip install pillow   then   py art/make-logo.py art/curseforge-icon-400.png
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "curseforge-icon-400.png"
S = 4  # draw at 4x, then shrink for smooth edges
W = 400 * S


def px(v):
    return int(round(v * S))


def box(x0, y0, x1, y1):
    return [px(x0), px(y0), px(x1), px(y1)]


# Background: a dark, slightly lighter at the top.
bg = Image.new("RGB", (W, W))
d = ImageDraw.Draw(bg)
for y in range(W):
    t = y / W
    d.line([(0, y), (W, y)], fill=(int(40 - 22 * t), int(40 - 22 * t), int(52 - 26 * t)))

# The sack, as one mask so a single outline wraps the whole shape.
CX = 150  # horizontal centre of the sack
sack = Image.new("L", (W, W), 0)
s = ImageDraw.Draw(sack)
s.ellipse(box(CX - 112, 196, CX + 112, 374), fill=255)  # a wide, slumped belly
s.polygon([(px(CX - 30), px(168)), (px(CX + 30), px(168)), (px(CX + 66), px(222)), (px(CX - 66), px(222))], fill=255)  # neck
s.ellipse(box(CX - 66, 124, CX + 66, 180), fill=255)  # gathered top
s.ellipse(box(CX - 82, 136, CX - 22, 184), fill=255)  # left ruffle
s.ellipse(box(CX + 22, 136, CX + 82, 184), fill=255)  # right ruffle

outline = sack.filter(ImageFilter.MaxFilter(px(7) | 1))  # grows the mask a few pixels each way
canvas = bg.copy()
canvas.paste((38, 22, 10), mask=outline)

# Leather: a vertical gradient with a lighter patch on the upper left for roundness.
leather = Image.new("RGB", (W, W))
ld = ImageDraw.Draw(leather)
for y in range(W):
    t = y / W
    ld.line([(0, y), (W, y)], fill=(int(176 - 56 * t), int(118 - 40 * t), int(62 - 24 * t)))
shine = Image.new("L", (W, W), 0)
ImageDraw.Draw(shine).ellipse(box(CX - 92, 226, CX - 14, 316), fill=95)
shine = shine.filter(ImageFilter.GaussianBlur(px(16)))
leather.paste((226, 170, 104), mask=ImageChops.multiply(shine, sack))
canvas.paste(leather, mask=sack)

# A drawstring cord around the neck, tied in a knot with two hanging tails.
rope = Image.new("L", (W, W), 0)
rd = ImageDraw.Draw(rope)
rd.line([(px(CX - 62), px(196)), (px(CX), px(206)), (px(CX + 62), px(196))], fill=255, width=px(13), joint="curve")
for tail in ([(CX + 20, 204), (CX + 36, 244)], [(CX + 24, 204), (CX + 62, 232)]):
    rd.line([(px(x), px(y)) for x, y in tail], fill=255, width=px(9))
    rd.ellipse(box(tail[1][0] - 7, tail[1][1] - 7, tail[1][0] + 7, tail[1][1] + 7), fill=255)
rd.ellipse(box(CX + 8, 192, CX + 36, 220), fill=255)  # the knot
canvas.paste((38, 22, 10), mask=rope.filter(ImageFilter.MaxFilter(px(5) | 1)))
canvas.paste((222, 184, 118), mask=rope)

# The dark mouth of the sack, where the arrow comes out.
mouth = Image.new("L", (W, W), 0)
ImageDraw.Draw(mouth).ellipse(box(CX - 46, 130, CX + 46, 168), fill=255)
canvas.paste((22, 12, 6), mask=mouth)


def bezier(p0, p1, p2, p3, n=400):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


# The arrow: leaves the mouth, loops up and over to the right, and ends pointing down.
path = bezier((CX, 146), (CX, -6), (336, -6), (336, 246))
WIDTH = 30
arrow = Image.new("L", (W, W), 0)
ad = ImageDraw.Draw(arrow)
for x, y in path:
    ad.ellipse(box(x - WIDTH / 2, y - WIDTH / 2, x + WIDTH / 2, y + WIDTH / 2), fill=255)
ad.polygon([(px(336 - 46), px(244)), (px(336 + 46), px(244)), (px(336), px(334))], fill=255)

# A red glow behind the arrow.
glow = arrow.filter(ImageFilter.GaussianBlur(px(18)))
glow = glow.point(lambda v: min(255, int(v * 1.6)))
red_glow = Image.new("RGB", (W, W), (255, 40, 30))
canvas.paste(red_glow, mask=glow.point(lambda v: int(v * 0.75)))

# The arrow itself: dark edge, red body, lighter core.
canvas.paste((60, 6, 6), mask=arrow.filter(ImageFilter.MaxFilter(px(5) | 1)))
canvas.paste((226, 36, 28), mask=arrow)
core = Image.new("L", (W, W), 0)
cored = ImageDraw.Draw(core)
for x, y in path[:-30]:
    cored.ellipse(box(x - 5, y - 5, x + 5, y + 5), fill=255)
core = core.filter(ImageFilter.GaussianBlur(px(2)))
canvas.paste((255, 104, 84), mask=ImageChops.multiply(core, arrow).point(lambda v: int(v * 0.8)))

final = canvas.resize((400, 400), Image.LANCZOS)
final.save(OUT)
print("saved", OUT, final.size)
