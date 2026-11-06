"""Shared drawing toolkit for the Tactile Reflex demo video (PIL only). 1920x1080, dark engineering theme."""
import math, os, re
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
W, H = 1920, 1080
BG0, BG1 = (6, 10, 22), (13, 21, 41)
CY, AM, RD, GN, VI = (34, 211, 238), (251, 191, 36), (244, 63, 94), (52, 211, 153), (167, 139, 250)
TXT, DIM, PANEL, EDGE, WHITE = (226, 232, 240), (122, 138, 160), (14, 22, 40), (46, 60, 84), (255, 255, 255)
F = "/usr/share/fonts/opentype/inter/"
FONTS = {"r": F + "Inter-Regular.otf", "m": F + "Inter-Medium.otf", "sb": F + "Inter-SemiBold.otf", "b": F + "Inter-Bold.otf",
         "d": F + "InterDisplay-Bold.otf", "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
         "monob": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"}
_fc = {}
def font(kind, size):
    k = (kind, int(size))
    if k not in _fc: _fc[k] = ImageFont.truetype(FONTS[kind], int(size))
    return _fc[k]

def rgba(c, a=255): return (c[0], c[1], c[2], int(a))
def lerp(a, b, t): return a + (b - a) * t
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease(t): t = clamp(t); return t * t * (3 - 2 * t)
def prog(t, t0, dur): return clamp((t - t0) / dur) if dur > 0 else (1.0 if t >= t0 else 0.0)

def new_layer(): return Image.new("RGBA", (W, H), (0, 0, 0, 0))
def ss_layer(fn, scale=2):
    """Supersampled (anti-aliased) layer: fn(draw, s) draws in coordinates multiplied by s."""
    im = Image.new("RGBA", (W * scale, H * scale), (0, 0, 0, 0)); fn(ImageDraw.Draw(im), scale)
    return im.resize((W, H), Image.LANCZOS)
def glow(layer, radius=14, strength=1.0):
    g = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0: g.putalpha(g.getchannel("A").point(lambda v: min(255, int(v * strength))))
    return Image.alpha_composite(g, layer)
def with_alpha(layer, a):
    if a >= 0.999: return layer
    out = layer.copy(); out.putalpha(layer.getchannel("A").point(lambda v: int(v * a))); return out

_bg = None
def background():
    global _bg
    if _bg is None:
        im = Image.new("RGB", (W, H)); px = ImageDraw.Draw(im)
        for y in range(H):
            t = y / H; px.line([(0, y), (W, y)], fill=tuple(int(lerp(BG0[i], BG1[i], t)) for i in range(3)))
        ov = ImageDraw.Draw(im, "RGBA")
        for x in range(0, W, 60): ov.line([(x, 0), (x, H)], fill=(60, 90, 140, 14))
        for y in range(0, H, 60): ov.line([(0, y), (W, y)], fill=(60, 90, 140, 14))
        for x in range(0, W, 240):
            for y in range(0, H, 240): ov.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(34, 211, 238, 45))
        v = Image.new("L", (W, H), 0); vd = ImageDraw.Draw(v); vd.ellipse([-300, -250, W + 300, H + 250], fill=255)
        v = v.filter(ImageFilter.GaussianBlur(220)); dark = Image.new("RGB", (W, H), (2, 4, 10))
        _bg = Image.composite(im, dark, v)
    return _bg.copy()

def text(d, xy, s, kind="r", size=32, fill=TXT, anchor="la"):
    d.text(xy, s, font=font(kind, size), fill=fill, anchor=anchor)
def text_w(s, kind, size): return font(kind, size).getlength(s)
def wrap(s, kind, size, width):
    words, lines, cur = s.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if text_w(t, kind, size) <= width: cur = t
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    return lines
def rrect(d, box, r=16, fill=None, outline=None, width=2): d.rounded_rectangle(box, r, fill=fill, outline=outline, width=width)
def arrow(d, pts, color=CY, width=4, head=16, s=1):
    d.line(pts, fill=color, width=width, joint="curve")
    (x0, y0), (x1, y1) = pts[-2], pts[-1]; a = math.atan2(y1 - y0, x1 - x0)
    d.polygon([(x1, y1), (x1 - head * math.cos(a - .42), y1 - head * math.sin(a - .42)), (x1 - head * math.cos(a + .42), y1 - head * math.sin(a + .42))], fill=color)
def path_point(pts, t):
    seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]; tot = sum(seg); d = clamp(t) * tot
    for i, L in enumerate(seg):
        if d <= L or i == len(seg) - 1:
            u = d / L if L else 0; return (lerp(pts[i][0], pts[i + 1][0], u), lerp(pts[i][1], pts[i + 1][1], u))
        d -= L
def dot_sprite(color=CY, r=10):
    im = Image.new("RGBA", (r * 8, r * 8), (0, 0, 0, 0)); d = ImageDraw.Draw(im); c = r * 4
    d.ellipse([c - r, c - r, c + r, c + r], fill=rgba(color)); return glow(im, r * 1.4, 1.4)
def paste_center(base, sprite, xy):
    base.alpha_composite(sprite, (int(xy[0] - sprite.width / 2), int(xy[1] - sprite.height / 2)))

def header(base, title, num):
    d = ImageDraw.Draw(base)
    x = 70
    for ch in "TACTILE REFLEX SYSTEM": d.text((x, 42), ch, font=font("sb", 22), fill=CY); x += text_w(ch, "sb", 22) + 3.5
    d.text((W - 70, 42), f"{num:02d}  ·  {title}", font=font("sb", 22), fill=DIM, anchor="ra")
    d.line([(70, 86), (W - 70, 86)], fill=EDGE, width=2)
    d.text((70, H - 38), "SIMULATION ONLY  ·  NO PHYSICAL HARDWARE DEMONSTRATED", font=font("sb", 15), fill=(190, 150, 60), anchor="lm")

def caption(base, s):
    if not s: return
    d = ImageDraw.Draw(base, "RGBA"); lines = wrap(s, "sb", 34, 1640); lh = 48
    h = len(lines) * lh + 26; y0 = H - 70 - h; w = max(text_w(l, "sb", 34) for l in lines) + 70
    d.rounded_rectangle([(W - w) / 2, y0, (W + w) / 2, y0 + h], 18, fill=(4, 8, 18, 215), outline=(40, 56, 82, 255), width=2)
    for i, l in enumerate(lines): d.text((W / 2, y0 + 13 + i * lh + lh / 2), l, font=font("sb", 34), fill=WHITE, anchor="mm")

def card(d, box, title=None, accent=CY, fill=PANEL, tsize=22):
    rrect(d, box, 18, fill=fill, outline=EDGE, width=2)
    if title: d.text((box[0] + 24, box[1] + 18), title, font=font("sb", tsize), fill=accent)

def nice_ticks(lo, hi, n=5):
    span = hi - lo; raw = span / n; mag = 10 ** math.floor(math.log10(raw)); 
    for m in (1, 2, 2.5, 5, 10):
        if raw <= m * mag: step = m * mag; break
    t = math.ceil(lo / step) * step; out = []
    while t <= hi + 1e-9: out.append(t); t += step
    return out

def plot_axes(d, s, box, xr, yr, xticks, yticks, xlabel="", ylabel="", xfmt=lambda v: f"{v:g}", yfmt=lambda v: f"{v:g}", grid=True):
    """Draw axes/grid into a supersampled draw `d` (scale s). Returns (px, py) mapping functions in 1x pixel coordinates."""
    x0, y0, x1, y1 = box
    px = lambda v: x0 + (x1 - x0) * (v - xr[0]) / (xr[1] - xr[0]); py = lambda v: y1 - (y1 - y0) * (v - yr[0]) / (yr[1] - yr[0])
    for v in xticks:
        if grid: d.line([(px(v) * s, y0 * s), (px(v) * s, y1 * s)], fill=rgba(EDGE, 150), width=int(1.5 * s))
        d.text((px(v) * s, (y1 + 8) * s), xfmt(v), font=font("r", int(19 * s)), fill=rgba(DIM), anchor="ma")
    for v in yticks:
        if grid: d.line([(x0 * s, py(v) * s), (x1 * s, py(v) * s)], fill=rgba(EDGE, 150), width=int(1.5 * s))
        d.text(((x0 - 10) * s, py(v) * s), yfmt(v), font=font("r", int(19 * s)), fill=rgba(DIM), anchor="rm")
    d.rectangle([x0 * s, y0 * s, x1 * s, y1 * s], outline=rgba(EDGE), width=int(2 * s))
    if xlabel: d.text(((x0 + x1) / 2 * s, (y1 + 38) * s), xlabel, font=font("sb", int(20 * s)), fill=rgba(DIM), anchor="ma")
    if ylabel: d.text((x0 * s, (y0 - 10) * s), ylabel, font=font("sb", int(20 * s)), fill=rgba(DIM), anchor="ls")
    return px, py

KW = {"module", "input", "output", "wire", "reg", "always", "if", "else", "begin", "end", "case", "endcase", "posedge", "parameter", "localparam", "assign", "default", "initial", "endmodule", "integer", "negedge", "signed"}
def highlight_runs(line):
    """Tiny Verilog tokenizer -> [(text, color)]."""
    out = []; i = 0
    while i < len(line):
        if line.startswith("//", i): out.append((line[i:], (100, 170, 120))); break
        m = re.match(r"\d*'[bdhBDH][0-9a-fA-F_]+|\b\d+\b", line[i:])
        if m: out.append((m.group(0), AM)); i += len(m.group(0)); continue
        m = re.match(r"[A-Za-z_]\w*", line[i:])
        if m:
            w = m.group(0); out.append((w, VI if w in KW else TXT)); i += len(w); continue
        out.append((line[i], (160, 175, 200))); i += 1
    return out
def code_panel(rows, fname, y0, size, lh, notes=""):
    """rows: [(lineno, text)] or None for an 'omitted lines' separator. Returns (layer, {lineno: (y_top, y_bottom)}, bottom_y)."""
    import re as _re
    rows_h = [(22 if r is None else lh) for r in rows]; hgt = 46 + sum(rows_h) + 22
    pos = {}
    def f(d, s):
        rrect(d, [70 * s, y0 * s, 1850 * s, (y0 + hgt) * s], 16 * s, fill=rgba((8, 14, 28)), outline=rgba(EDGE), width=int(2 * s))
        d.text((96 * s, (y0 + 23) * s), fname, font=font("monob", int(21 * s)), fill=rgba(CY), anchor="lm")
        if notes: d.text((1826 * s, (y0 + 23) * s), notes, font=font("sb", int(17 * s)), fill=rgba(DIM), anchor="rm")
        y = y0 + 46; cw = font("mono", int(size * s)).getlength("M")
        for r in rows:
            if r is None:
                d.text((96 * s, (y + 10) * s), "...   (lines omitted)", font=font("mono", int(17 * s)), fill=rgba(DIM), anchor="lm"); y += 22; continue
            ln, tx = r; pos[ln] = (y, y + lh)
            d.text((130 * s, (y + lh / 2) * s), f"{ln:>3}", font=font("mono", int(size * s)), fill=rgba((80, 96, 124)), anchor="rm")
            x = 160 * s
            for run, col in highlight_runs(tx.replace("\t", "    ")):
                d.text((x, (y + lh / 2) * s), run, font=font("mono", int(size * s)), fill=rgba(col), anchor="lm"); x += font("mono", int(size * s)).getlength(run)
            y += lh
    return ss_layer(f, 1) if False else _text_layer(f), pos, y0 + hgt
def _text_layer(fn):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); fn(ImageDraw.Draw(im), 1); return im
