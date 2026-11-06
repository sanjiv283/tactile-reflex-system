import json
from PIL import Image
from common import *
class Scene:
    """tl = one entry of audio/timeline.json. Subclasses implement build() and draw(base, t)."""
    def __init__(self, tl):
        self.tl, self.beats, self.dur, self.num, self.title = tl, tl["beats"], tl["dur"], tl["num"], tl["title"]
        self.build()
    def build(self): pass
    def t0(self, k): return self.beats[k]["t0"]
    def t1(self, k): return self.beats[k]["t1"]
    def bp(self, t, k, dur=None):                 # progress through beat k (0..1 over its narration, or `dur` seconds)
        a = self.t0(k); d = (self.t1(k) - a) if dur is None else dur
        return prog(t, a, d)
    def appear(self, t, k, d=0.5, lag=0.0): return ease(prog(t, self.t0(k) + lag, d))
    def cur(self, t):
        c = -1
        for i, b in enumerate(self.beats):
            if t >= b["t0"] - 0.02: c = i
        return c
    def draw(self, base, t): pass
    def frame(self, t, captions=True, fade=True):
        base = background().convert("RGBA"); self.draw(base, t)
        header(base, self.title, self.num)
        c = self.cur(t)
        if captions and c >= 0 and t <= self.beats[c]["t1"] + 0.45: caption(base, self.beats[c]["cap"])
        out = base.convert("RGB")
        f = min(prog(t, 0, 0.5), 1 - prog(t, self.dur - 0.5, 0.5)) if fade else 1.0
        if f < 0.999: out = Image.blend(Image.new("RGB", (W, H), (0, 0, 0)), out, ease(f))
        return out
def blit(base, layer, a=1.0):
    if a <= 0.003: return
    base.alpha_composite(with_alpha(layer, a) if a < 0.999 else layer)
