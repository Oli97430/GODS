"""
SCALAR DESCENT — canvas generator
Museum-quality scientific-diagram composition, A4 @ 300 DPI
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, random, os

# ── SETUP ──────────────────────────────────────────────────────────────────────
W, H = 2480, 3508
FONT_DIR = (
    r"C:\Users\Olivier\AppData\Roaming\Claude\local-agent-mode-sessions"
    r"\skills-plugin\7a9fbf20-a9e3-4529-b66d-e62944d4bc49"
    r"\f116ffeb-e6cc-4085-9864-7d57055553c4\skills\canvas-design\canvas-fonts"
)
OUT = r"C:\Users\Olivier\Documents\gods\scalar_descent.png"

rng = random.Random(42)

# ── PALETTE ────────────────────────────────────────────────────────────────────
BG        = (4,   8,  18)
C_GOLD    = (188, 158, 90)
C_TEXT    = (92, 128, 160)
C_DIM     = (48,  72,  98)
C_WHITE   = (220, 236, 248)
C_AXIS    = (28,  52,  82)

# Five rings: outer → inner (RGBA, alpha used only for reference — we'll blend manually)
RING_DATA = [
    # (radius, rgb_color, line_width, dash, gap, n_minor, n_major)
    (1080, (26,  50,  82),  1, 16, 7,  180, 36),   # galaxy
    ( 800, (28,  58,  95),  1, 22, 8,  144, 24),   # system
    ( 565, (50,  98, 142),  2, 28, 9,  120, 20),   # orbital
    ( 365, (95, 155, 195),  2, 18, 6,   96, 16),   # descent
    ( 175, (162, 208, 232), 3,  0,  0,  72, 12),   # surface (solid)
]

SCALE_METERS = ["10²² m", "10¹³ m", "10⁷ m", "10³ m", "10⁰ m"]
SCALE_NAMES  = [
    "GALACTIC FIELD",
    "STELLAR SYSTEM",
    "ORBITAL APPROACH",
    "ATMOSPHERIC LAYER",
    "SURFACE DATUM",
]

CX, CY = W // 2, int(H * 0.405)

# ── FONTS ──────────────────────────────────────────────────────────────────────
def ttf(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)

f_title  = ttf("Jura-Light.ttf",           58)
f_sub    = ttf("Jura-Light.ttf",           24)
f_mono   = ttf("JetBrainsMono-Regular.ttf",26)
f_mono_s = ttf("JetBrainsMono-Regular.ttf",20)
f_mono_x = ttf("JetBrainsMono-Regular.ttf",19)
f_ibm    = ttf("IBMPlexMono-Regular.ttf",  22)

# ── HELPERS ────────────────────────────────────────────────────────────────────
def dashed_circle(draw, cx, cy, r, color, width=1, dash=20, gap=8):
    """Draw a dashed circle via short line segments."""
    circ = int(2 * math.pi * r)
    period = dash + gap
    pts = []
    for i in range(circ + 1):
        a = 2 * math.pi * i / circ - math.pi / 2
        in_dash = (i % period) < dash
        if in_dash:
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        else:
            if len(pts) >= 2:
                draw.line(pts, fill=color, width=width)
            pts = []
    if len(pts) >= 2:
        draw.line(pts, fill=color, width=width)

def solid_circle(draw, cx, cy, r, color, width=1):
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=width)

def tick_marks(draw, cx, cy, r, color, n_minor, n_major, maj_len=22, min_len=9,
               width=1, inward=True):
    per = n_minor // n_major
    for i in range(n_minor):
        a = 2 * math.pi * i / n_minor - math.pi / 2
        is_maj = (i % per == 0)
        tlen = maj_len if is_maj else min_len
        lw   = width + (1 if is_maj else 0)
        r0 = r - tlen if inward else r
        r1 = r       if inward else r + tlen
        x0, y0 = cx + r0 * math.cos(a), cy + r0 * math.sin(a)
        x1, y1 = cx + r1 * math.cos(a), cy + r1 * math.sin(a)
        draw.line([(x0, y0), (x1, y1)], fill=color, width=lw)

def draw_text_centered(draw, x, y, text, font, fill):
    bb = font.getbbox(text)
    draw.text((x - (bb[2] - bb[0]) // 2, y - (bb[3] - bb[1]) // 2),
              text, font=font, fill=fill)

def draw_tracked(draw, x, y, text, font, fill, spacing=10):
    """Draw text with extra letter spacing."""
    for ch in text:
        bb = font.getbbox(ch)
        draw.text((x, y), ch, font=font, fill=fill)
        x += (bb[2] - bb[0]) + spacing
    return x

def tracked_width(text, font, spacing=10):
    w = 0
    for ch in text:
        bb = font.getbbox(ch)
        w += (bb[2] - bb[0]) + spacing
    return w - spacing

# ── BASE IMAGE ─────────────────────────────────────────────────────────────────
img  = Image.new('RGB', (W, H), BG)
draw = ImageDraw.Draw(img)

# ── STAR FIELD ─────────────────────────────────────────────────────────────────
STAR_PALETTE = [
    (42,  65,  90),  # faintest
    (72, 105, 138),
    (115, 152, 185),
    (168, 195, 218),
    (205, 222, 238),  # brightest
]
for _ in range(2400):
    t     = rng.random() ** 0.55        # bias outward
    r_s   = t * max(W, H) * 0.78
    a_s   = rng.uniform(0, 2 * math.pi)
    sx    = int(W / 2 + r_s * math.cos(a_s))
    sy    = int(H / 2 + r_s * math.sin(a_s))
    if not (2 < sx < W - 2 and 2 < sy < H - 2):
        continue
    dcx = math.hypot(sx - CX, sy - CY)
    if dcx < RING_DATA[0][0] * 0.7:   # keep center clear
        continue
    fade = min(1.0, (dcx - RING_DATA[0][0] * 0.7) / (RING_DATA[0][0] * 0.5))
    w_i  = [max(0, 45 - 10 * i) for i in range(5)]
    sc   = rng.choices(STAR_PALETTE, weights=[45, 30, 16, 7, 2])[0]
    # Scale brightness by fade
    sc   = tuple(int(c * (0.3 + 0.7 * fade)) for c in sc)
    sz   = rng.choices([1, 2, 3], weights=[70, 24, 6])[0]
    if sz == 1:
        draw.point((sx, sy), fill=sc)
    else:
        draw.ellipse([sx - sz//2, sy - sz//2, sx + sz//2, sy + sz//2], fill=sc)

# A few 4-pointed sparkles for the brightest stars
for _ in range(18):
    dcx_min = RING_DATA[0][0]
    r_s  = dcx_min * (1.05 + rng.random() * 0.6)
    a_s  = rng.uniform(0, 2 * math.pi)
    sx   = int(W / 2 + r_s * math.cos(a_s))
    sy   = int(H / 2 + r_s * math.sin(a_s))
    if not (10 < sx < W - 10 and 10 < sy < H - 10):
        continue
    arm  = rng.randint(8, 18)
    stub = 2
    sc   = STAR_PALETTE[rng.randint(3, 4)]
    draw.line([(sx - arm, sy), (sx + arm, sy)], fill=sc, width=1)
    draw.line([(sx, sy - arm), (sx, sy + arm)], fill=sc, width=1)
    draw.ellipse([sx - stub, sy - stub, sx + stub, sy + stub], fill=C_WHITE)

# ── RADIAL AXIS LINES ──────────────────────────────────────────────────────────
for deg in [0, 90, 180, 270]:
    a   = math.radians(deg - 90)
    far = int(RING_DATA[0][0] * 1.12)
    nea = int(RING_DATA[4][0] * 0.55)
    draw.line([(CX + nea * math.cos(a), CY + nea * math.sin(a)),
               (CX + far * math.cos(a), CY + far * math.sin(a))],
              fill=C_AXIS, width=1)

# Central cross-hair
cs = 44
draw.line([(CX - cs, CY), (CX + cs, CY)], fill=C_DIM, width=1)
draw.line([(CX, CY - cs), (CX, CY + cs)], fill=C_DIM, width=1)

# ── RINGS ──────────────────────────────────────────────────────────────────────
for i, (r, col, lw, dash, gap, n_min, n_maj) in enumerate(RING_DATA):
    # Outer ring: solid, very faint
    if i == 0:
        solid_circle(draw, CX, CY, r, col, width=lw)
        tick_marks(draw, CX, CY, r, col, n_min, n_maj,
                   maj_len=18, min_len=7, inward=False)
    # Inner ring: solid, brightest
    elif i == 4:
        solid_circle(draw, CX, CY, r, col, width=lw)
        tick_marks(draw, CX, CY, r, col, n_min, n_maj,
                   maj_len=20, min_len=8, inward=True)
        # Second, slightly larger ring (double-ring for surface)
        solid_circle(draw, CX, CY, r + 6, col, width=1)
    else:
        dashed_circle(draw, CX, CY, r, col, width=lw, dash=dash, gap=gap)
        tick_marks(draw, CX, CY, r, col, n_min, n_maj,
                   maj_len=20, min_len=8, inward=(i % 2 == 0))

# ── SCALE ANNOTATIONS ─────────────────────────────────────────────────────────
# Labels cascade diagonally at 45° NE — connector tick → name / metric
lbl_ang = math.radians(-45)   # upper-right of center
for i, (r, col, *_) in enumerate(RING_DATA):
    blend = tuple(int(c * 0.55 + t * 0.45) for c, t in zip(col, C_TEXT))
    dim2  = tuple(int(c * 0.5 + d * 0.5) for c, d in zip(col, C_DIM))

    # Point on the ring at 45° NE
    rx0 = CX + int(r * math.cos(lbl_ang))
    ry0 = CY + int(r * math.sin(lbl_ang))
    # Extend outward for connector
    tick_ext = 30
    rx1 = CX + int((r + tick_ext) * math.cos(lbl_ang))
    ry1 = CY + int((r + tick_ext) * math.sin(lbl_ang))
    draw.line([(rx0, ry0), (rx1, ry1)], fill=blend, width=1)

    draw.text((rx1 + 8, ry1 - 15), SCALE_NAMES[i],  font=f_mono_x, fill=blend)
    draw.text((rx1 + 8, ry1 +  2), SCALE_METERS[i], font=f_mono_x, fill=dim2)

# ── DESCENT SPIRAL (gold) ──────────────────────────────────────────────────────
spiral_pts = []
n_turns = 2.6          # 2.6 full rotations during descent
n_steps = 600
for k in range(n_steps):
    t  = k / (n_steps - 1)              # 0 → 1
    r_sp = RING_DATA[0][0] * (1 - t * 0.98)   # outermost → near center
    a_sp = -math.pi / 2 + t * n_turns * 2 * math.pi   # CW spiral
    x_sp = CX + r_sp * math.cos(a_sp)
    y_sp = CY + r_sp * math.sin(a_sp)
    spiral_pts.append((x_sp, y_sp))

# Draw spiral in segments — bright at outer, fading to center
seg_size = 25
for s in range(0, len(spiral_pts) - seg_size, seg_size // 2):
    t_mid = (s + seg_size / 2) / len(spiral_pts)
    # Outer = bright gold; inner = dim (the center glow takes over)
    alpha = int(255 * max(0.08, 0.72 * (1 - t_mid) ** 0.7))
    seg   = spiral_pts[s : s + seg_size + 1]
    c_seg = tuple(int(c * alpha / 255) for c in C_GOLD)
    if len(seg) >= 2:
        draw.line(seg, fill=c_seg, width=2)

# ── GLOW COMPOSITE ────────────────────────────────────────────────────────────
glow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
gd   = ImageDraw.Draw(glow)

glow_layers = [
    (320, (170, 145, 82,   3)),
    (200, (182, 158, 92,   7)),
    (120, (195, 172, 105, 16)),
    ( 65, (210, 188, 128, 30)),
    ( 32, (225, 208, 158, 58)),
    ( 14, (238, 226, 192, 110)),
    (  5, (248, 242, 225, 185)),
    (  2, (255, 250, 242, 255)),
]
for gr, gc in glow_layers:
    gd.ellipse([CX - gr, CY - gr, CX + gr, CY + gr], fill=gc)

glow_soft = glow.filter(ImageFilter.GaussianBlur(48))

# Composite (additive-style: clamp channel-wise)
img_rgba = img.convert('RGBA')
glow_arr = glow_soft.load()
base_arr = img_rgba.load()
for py in range(max(0, CY - 400), min(H, CY + 400)):
    for px in range(max(0, CX - 400), min(W, CX + 400)):
        gr2, gg2, gb2, ga2 = glow_arr[px, py]
        br, bg, bb, ba = base_arr[px, py]
        fa = ga2 / 255.0
        nr = min(255, int(br + gr2 * fa))
        ng = min(255, int(bg + gg2 * fa))
        nb = min(255, int(bb + gb2 * fa))
        base_arr[px, py] = (nr, ng, nb, 255)

img = img_rgba.convert('RGB')
draw = ImageDraw.Draw(img)

# Hard center dot
draw.ellipse([CX - 5, CY - 5, CX + 5, CY + 5], fill=C_WHITE)
draw.ellipse([CX - 2, CY - 2, CX + 2, CY + 2], fill=(255, 252, 245))

# ── CORNER REGISTRATION MARKS ─────────────────────────────────────────────────
margin = 108
cs2, cr = 32, 20
for (rx, ry) in [(margin, margin), (W - margin, margin),
                 (margin, H - margin), (W - margin, H - margin)]:
    draw.line([(rx - cs2, ry), (rx + cs2, ry)], fill=C_DIM, width=1)
    draw.line([(rx, ry - cs2), (rx, ry + cs2)], fill=C_DIM, width=1)
    draw.ellipse([rx - cr, ry - cr, rx + cr, ry + cr], outline=C_DIM, width=1)
    # Small tick marks on the circle
    for tick_a in [0, 90, 180, 270]:
        ta = math.radians(tick_a)
        t0x = rx + int(cr * math.cos(ta)); t0y = ry + int(cr * math.sin(ta))
        t1x = rx + int((cr + 6) * math.cos(ta)); t1y = ry + int((cr + 6) * math.sin(ta))
        draw.line([(t0x, t0y), (t1x, t1y)], fill=C_DIM, width=1)

# ── BORDER FRAME ──────────────────────────────────────────────────────────────
fm = 82
draw.rectangle([fm, fm, W - fm, H - fm], outline=C_DIM, width=1)
# Double frame (inner)
fi = fm + 14
draw.rectangle([fi, fi, W - fi, H - fi], outline=(22, 38, 58), width=1)

# ── TITLE BLOCK ──────────────────────────────────────────────────────────────
title = "SCALAR  DESCENT"
spacing = 14
tw = tracked_width(title, f_title, spacing)
tx = (W - tw) // 2
ty = fi + 42
draw_tracked(draw, tx, ty, title, f_title, C_TEXT, spacing)

# Thin rule below title
rule_y = ty + 75
rule_hw = 200
draw.line([(W//2 - rule_hw, rule_y), (W//2 + rule_hw, rule_y)],
          fill=C_DIM, width=1)
# Small tick at midpoint
draw.line([(W//2, rule_y - 6), (W//2, rule_y + 6)], fill=C_DIM, width=1)

# Subtitle
sub  = "nested observation system"
sw   = tracked_width(sub, f_sub, 6)
draw_tracked(draw, (W - sw)//2, rule_y + 16, sub, f_sub, C_DIM, 6)

# ── VERTICAL MARGIN LABELS ────────────────────────────────────────────────────
def vertical_label(text, fnt, fill, x, y_mid, direction=1):
    """Render vertical text by rotating a temp image."""
    bb  = fnt.getbbox(text)
    tw2 = bb[2] - bb[0] + 8
    th2 = bb[3] - bb[1] + 8
    tmp = Image.new('RGBA', (tw2, th2), (0, 0, 0, 0))
    ImageDraw.Draw(tmp).text((-bb[0] + 4, -bb[1] + 4), text, font=fnt, fill=(*fill, 255))
    rot = tmp.rotate(90 * direction, expand=True)
    px  = x - rot.size[0] // 2
    py  = y_mid - rot.size[1] // 2
    img.paste(rot, (px, py), rot)

vertical_label("SCALE  ·  THRESHOLD  ·  DESCENT", f_ibm, C_DIM,
               fm + 38, H // 2, direction=1)
vertical_label("CATALOGUE REF.  42.0000", f_ibm, C_DIM,
               W - fm - 38, H // 2, direction=-1)

draw = ImageDraw.Draw(img)  # refresh after paste

# ── BOTTOM ANNOTATION STRIP ──────────────────────────────────────────────────
by   = H - fi - 62
mid  = W // 2

# Thin rule above bottom annotations
draw.line([(fi + 20, by - 16), (W - fi - 20, by - 16)], fill=C_DIM, width=1)

# Left: coordinates
draw.text((fi + 30, by), "θ  0.000°  φ  0.000°", font=f_mono_x, fill=C_DIM)
draw.text((fi + 30, by + 22), "Δ  1.0 × 10²² m", font=f_mono_x, fill=C_DIM)

# Center: observation index
obs = "OBSERVATION  I"
ow  = f_mono_s.getbbox(obs)[2]
draw_text_centered(draw, mid, by + 11, obs, f_mono_s, C_TEXT)

# Seed reference (small, below obs)
seed_txt = "seed : 0000042"
stw = f_mono_x.getbbox(seed_txt)[2]
draw_text_centered(draw, mid, by + 34, seed_txt, f_mono_x, C_DIM)

# Right: scale sequence arrow
seq = "G → S → O → A → D"
sw2 = f_mono_x.getbbox(seq)[2]
draw.text((W - fi - 30 - sw2, by), seq, font=f_mono_x, fill=C_DIM)
draw.text((W - fi - 30 - sw2 + 4, by + 22), "galactic to datum",
          font=f_mono_x, fill=(32, 52, 75))

# ── GROUND HORIZON (lower void) ───────────────────────────────────────────────
# A single, faint horizontal mark below the rings — the destination implied by the descent
gh_y     = CY + RING_DATA[0][0] + int((H - fi - 62 - (CY + RING_DATA[0][0])) * 0.55)
gh_half  = 260
gh_col   = (30, 52, 76)
draw.line([(W//2 - gh_half, gh_y), (W//2 + gh_half, gh_y)], fill=gh_col, width=1)
# Tiny center tick on the horizon line
draw.line([(W//2, gh_y - 8), (W//2, gh_y + 8)], fill=gh_col, width=1)
# Flanking micro-ticks at thirds
for dx in [-gh_half // 3, gh_half // 3]:
    draw.line([(W//2 + dx, gh_y - 4), (W//2 + dx, gh_y + 4)], fill=gh_col, width=1)
# Label
hl_text = "0.000 m"
htw = f_mono_x.getbbox(hl_text)[2]
draw.text(((W - htw)//2, gh_y + 14), hl_text, font=f_mono_x, fill=gh_col)

# ── SAVE ──────────────────────────────────────────────────────────────────────
img.save(OUT, "PNG", dpi=(300, 300))
print(f"Saved: {OUT}")
