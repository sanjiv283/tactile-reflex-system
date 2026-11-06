"""Stacked strip charts drawn from real data, as supersampled RGBA layers."""
from common import *
def strip_chart(strips, box, xr, xticks, xlabel, xfmt=lambda v: f"{v:g}", gap=16, s=2):
    """strips: dicts(label, xs, ys, color, ymin, ymax, h, yticks, yfmt, hlines=[(v,color,label)], kind='step'|'line', fill=False).
    Returns (layer, px, info) where info[i] = dict(box, py)."""
    x0, y0, x1, y1 = box; tot = sum(st["h"] for st in strips); avail = (y1 - y0) - gap * (len(strips) - 1)
    px = lambda v: x0 + (x1 - x0) * (v - xr[0]) / (xr[1] - xr[0])
    info = []; y = y0
    for st in strips:
        h = avail * st["h"] / tot; info.append(dict(box=(x0, y, x1, y + h), py=(lambda yy, y=y, h=h, st=st: y + h - h * (yy - st["ymin"]) / (st["ymax"] - st["ymin"])))); y += h + gap
    def draw(d, sc):
        for st, inf in zip(strips, info):
            bx = inf["box"]; py = inf["py"]
            d.rounded_rectangle([bx[0] * sc, bx[1] * sc, bx[2] * sc, bx[3] * sc], 8 * sc, fill=rgba((9, 15, 30)), outline=rgba(EDGE), width=int(2 * sc))
            for v in xticks: d.line([(px(v) * sc, bx[1] * sc), (px(v) * sc, bx[3] * sc)], fill=rgba(EDGE, 110), width=int(1.5 * sc))
            for v in st.get("yticks", []):
                d.line([(bx[0] * sc, py(v) * sc), (bx[2] * sc, py(v) * sc)], fill=rgba(EDGE, 110), width=int(1.5 * sc))
                d.text(((bx[0] - 10) * sc, py(v) * sc), st.get("yfmt", lambda q: f"{q:g}")(v), font=font("r", int(17 * sc)), fill=rgba(DIM), anchor="rm")
            d.text((bx[0] * sc + 12 * sc, bx[1] * sc + 8 * sc), st["label"], font=font("sb", int(19 * sc)), fill=rgba(st["color"]), anchor="la")
            for v, col, lab in st.get("hlines", []):
                for xx in range(int(bx[0]), int(bx[2]), 20): d.line([(xx * sc, py(v) * sc), ((xx + 10) * sc, py(v) * sc)], fill=rgba(col, 220), width=int(2.5 * sc))
                d.text(((bx[2] - 10) * sc, (py(v) + 6) * sc), lab, font=font("sb", int(17 * sc)), fill=rgba(col), anchor="ra")
            pts = []
            for i, (xv, yv) in enumerate(zip(st["xs"], st["ys"])):
                if st.get("kind", "step") == "step" and i > 0: pts.append((px(xv) * sc, py(st["ys"][i - 1]) * sc))
                pts.append((px(xv) * sc, py(yv) * sc))
            if st.get("kind", "step") == "step": pts.append((px(xr[1]) * sc, py(st["ys"][-1]) * sc))
            pts = [(min(max(x, bx[0] * sc), bx[2] * sc), y_) for x, y_ in pts]
            d.line(pts, fill=rgba(st["color"]), width=int(4 * sc), joint="curve")
        for v in xticks: d.text((px(v) * sc, (y1 + 8) * sc), xfmt(v), font=font("r", int(19 * sc)), fill=rgba(DIM), anchor="ma")
        d.text(((x0 + x1) / 2 * sc, (y1 + 38) * sc), xlabel, font=font("sb", int(20 * sc)), fill=rgba(DIM), anchor="ma")
    return glow_light(ss_layer(draw, s)), px, info
def glow_light(layer): return layer
def vmarker(px_x, y0, y1, color, label, side="r", dy=0, size=21, dashed=True, dx=0):
    def f(d, s):
        if dashed:
            y = y0
            while y < y1: d.line([(px_x * s, y * s), (px_x * s, min(y + 10, y1) * s)], fill=rgba(color), width=int(3 * s)); y += 18
        else: d.line([(px_x * s, y0 * s), (px_x * s, y1 * s)], fill=rgba(color), width=int(3 * s))
        for i, ln in enumerate(label.split("\n")):
            d.text(((px_x + dx + (12 if side == "r" else -12)) * s, (y0 + 8 + dy + i * (size + 5)) * s), ln, font=font("b", int(size * s)), fill=rgba(color), anchor="la" if side == "r" else "ra")
    return ss_layer(f)
def chip(text, color, size=24, pad=22, h=52):
    w = int(text_w(text, "b", size) + pad * 2)
    def f(d, s):
        d.rounded_rectangle([0, 0, w * s, h * s], h / 2 * s, fill=rgba(PANEL), outline=rgba(color), width=int(3 * s)); d.text((w / 2 * s, h / 2 * s), text, font=font("b", int(size * s)), fill=rgba(color), anchor="mm")
    im = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0)); f(ImageDraw.Draw(im), 2); return im.resize((w, h), Image.LANCZOS)
def wipe(layer, x_left, x_right_at, y0=0, y1=H):
    m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rectangle([0, y0, int(x_right_at), y1], fill=255)
    out = layer.copy(); out.putalpha(ImageChops.multiply(out.getchannel("A"), m)); return out
