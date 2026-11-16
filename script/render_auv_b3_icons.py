#!/usr/bin/env python3
"""Regenerate AUV's B3 icon sizes from Assets/AppIcon.png and the Windows AppMark.svg.

Usage: python3 script/render_auv_b3_icons.py <out-dir>
Writes Windows browser-extension icons, Safari toolbar/extension icons and a contact
sheet. AppMark.svg is rendered with the same subset AppBrandIcon.cs supports (circle;
path with M/L/C/Z; fill or round-capped stroke). Requires Pillow. AppIcon.ico is not
produced here: windows/scripts/generate-native-icon.ps1 builds it with WPF on Windows."""
import os, re, sys, xml.etree.ElementTree as ET
from PIL import Image, ImageDraw

def flatten(d):
    toks = re.findall(r'[MLCZmlcz]|-?\d*\.?\d+', d)
    subpaths, cur, pos, i, cmd = [], [], (0, 0), 0, None
    while i < len(toks):
        t = toks[i]
        if t in 'MLCZ':
            cmd = t; i += 1
            if t == 'Z':
                if cur: subpaths.append((cur, True)); cur = []
                continue
        nums = lambda n: [float(x) for x in toks[i:i+n]]
        if cmd == 'M':
            if cur: subpaths.append((cur, False))
            x, y = nums(2); i += 2; cur = [(x, y)]; pos = (x, y); cmd = 'L'
        elif cmd == 'L':
            x, y = nums(2); i += 2; cur.append((x, y)); pos = (x, y)
        elif cmd == 'C':
            x1, y1, x2, y2, x, y = nums(6); i += 6
            x0, y0 = pos
            for k in range(1, 25):
                s = k / 24
                cur.append(((1-s)**3*x0 + 3*(1-s)**2*s*x1 + 3*(1-s)*s*s*x2 + s**3*x,
                            (1-s)**3*y0 + 3*(1-s)**2*s*y1 + 3*(1-s)*s*s*y2 + s**3*y))
            pos = (x, y)
    if cur: subpaths.append((cur, False))
    return subpaths

def render(svg, size, ink, ss=8):
    root = ET.parse(svg).getroot()
    vb = [float(v) for v in root.get('viewBox').split()]
    big = size * ss; k = big / vb[2]
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0)); dr = ImageDraw.Draw(img)
    for el in root:
        tag = el.tag.split('}')[-1]
        fill = el.get('fill') != 'none'
        stroke = el.get('stroke') is not None
        w = float(el.get('stroke-width', 0)) * k
        if tag == 'circle':
            cx, cy, r = (float(el.get(a)) * k for a in ('cx', 'cy', 'r'))
            if fill: dr.ellipse([cx-r, cy-r, cx+r, cy+r], fill=ink)
            if stroke: dr.ellipse([cx-r-w/2, cy-r-w/2, cx+r+w/2, cy+r+w/2], outline=ink, width=max(1, round(w)))
        elif tag == 'path':
            for pts, closed in flatten(el.get('d')):
                P = [(x*k, y*k) for x, y in pts]
                if fill and len(P) > 2: dr.polygon(P, fill=ink)
                if stroke:
                    seq = P + ([P[0]] if closed else [])
                    dr.line(seq, fill=ink, width=max(1, round(w)), joint='curve')
                    for x, y in (seq[0], seq[-1]):
                        dr.ellipse([x-w/2, y-w/2, x+w/2, y+w/2], fill=ink)
    return img.resize((size, size), Image.LANCZOS)

def sheet(svg, out, ink=(0x24, 0x67, 0xD5, 255), sizes=(16, 20, 24, 32, 48, 64, 256)):
    W = sum(max(s, 40) + 24 for s in sizes) + 24
    zooms = [s for s in sizes if s <= 32]
    W = max(W, 24 + len(zooms) * 184)
    rows = []
    for bg in ((246, 246, 246, 255), (40, 40, 42, 255)):
        row = Image.new('RGBA', (W, 300 + 190), bg); x = 24
        for s in sizes:
            row.alpha_composite(render(svg, s, ink), (x, 24)); x += max(s, 40) + 24
        x = 24
        for s in zooms:
            z = render(svg, s, ink).resize((160, 160), Image.NEAREST)
            row.alpha_composite(z, (x, 310)); x += 184
        rows.append(row)
    out_img = Image.new('RGBA', (W, sum(r.height for r in rows)))
    y = 0
    for r in rows: out_img.paste(r, (0, y)); y += r.height
    out_img.save(out)

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = Image.open(os.path.join(ROOT, 'Assets/AppIcon.png')).convert('RGBA')        # B3 1024 full-bleed
MARK = os.path.join(ROOT, 'windows/src/AUV.Windows.App/Assets/AppMark.svg')
OUT = sys.argv[1]
CREAM = (0xFE, 0xF7, 0xEA, 255); NAVY = (0x02, 0x26, 0x68, 255); INK = (0x24, 0x67, 0xD5, 255)

def rounded(img, radius_ratio=0.2, ss=4):
    s = img.width; m = Image.new('L', (s*ss, s*ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, s*ss-1, s*ss-1], radius=int(s*ss*radius_ratio), fill=255)
    out = img.copy(); out.putalpha(m.resize((s, s), Image.LANCZOS)); return out

def art_tile(size):          # the full B3 picture as a rounded tile
    return rounded(ART.resize((size, size), Image.LANCZOS))

def mark_tile(size):         # cream tile with the navy simplified mark, for <= 32 px
    pad = round(size * 0.12)
    tile = Image.new('RGBA', (size, size), CREAM)
    tile.alpha_composite(render(MARK, size - 2*pad, NAVY), (pad, pad))
    return rounded(tile)


os.makedirs(OUT + '/windows-extension', exist_ok=True)
os.makedirs(OUT + '/safari', exist_ok=True)
for s in (16, 32): mark_tile(s).save(f'{OUT}/windows-extension/icon{s}.png')
for s in (48, 128): art_tile(s).save(f'{OUT}/windows-extension/icon{s}.png')
for s in (16, 19, 32, 38, 48): render(MARK, s, INK).save(f'{OUT}/safari/toolbar-{s}.png')
for s in (48, 96, 128, 256, 512): art_tile(s).save(f'{OUT}/safari/extension-{s}.png')

# contact sheet: light and dark bands
items = [('win 16', f'{OUT}/windows-extension/icon16.png'), ('win 32', f'{OUT}/windows-extension/icon32.png'),
         ('win 48', f'{OUT}/windows-extension/icon48.png'), ('win 128', f'{OUT}/windows-extension/icon128.png')] + \
        [(f'tb {s}', f'{OUT}/safari/toolbar-{s}.png') for s in (16, 19, 32, 38, 48)] + \
        [('ext 128', f'{OUT}/safari/extension-128.png')]
W = 24 + sum(max(Image.open(p).width, 32) + 24 for _, p in items)
sheet = Image.new('RGBA', (W, 2 * 200), (0, 0, 0, 255))
for band, bg in enumerate(((246, 246, 246, 255), (40, 40, 42, 255))):
    sheet.paste(Image.new('RGBA', (W, 200), bg), (0, band * 200))
    x = 24
    for _, p in items:
        im = Image.open(p); sheet.alpha_composite(im, (x, band * 200 + 24))
        if im.width <= 19:
            z = im.resize((im.width * 6, im.height * 6), Image.NEAREST)
            sheet.alpha_composite(z, (x, band * 200 + 24 + 40))
        x += max(im.width, 32) + 24
sheet.save(f'{OUT}/b3-icons-contact-sheet.png')
print('ok')
