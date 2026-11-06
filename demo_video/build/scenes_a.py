import re, math
from common import *
from scene_base import Scene, blit
import data

# ---------------------------------------------------------------- Scene 1: intro
class S1(Scene):
    def build(self):
        o = data.trace("trace_override"); self.tr = o
        def chip(d, s):
            cx, cy, r = 960 * s, 245 * s, 62 * s
            for i in range(-3, 4):
                for sx in (-1, 1):
                    d.line([(cx + sx * r, cy + i * 17 * s), (cx + sx * (r + 26 * s), cy + i * 17 * s)], fill=rgba(CY, 200), width=int(4 * s))
                    d.line([(cx + i * 17 * s, cy + sx * r), (cx + i * 17 * s, cy + sx * (r + 26 * s))], fill=rgba(CY, 200), width=int(4 * s))
            d.rounded_rectangle([cx - r, cy - r, cx + r, cy + r], 14 * s, fill=rgba((10, 24, 46)), outline=rgba(CY), width=int(4 * s))
            d.rounded_rectangle([cx - r + 18 * s, cy - r + 18 * s, cx + r - 18 * s, cy + r - 18 * s], 8 * s, outline=rgba(CY, 120), width=int(2 * s))
            d.text((cx, cy), "FPGA", font=font("monob", int(26 * s)), fill=rgba(CY), anchor="mm")
        self.chip = glow(ss_layer(chip), 18, 1.2)
        self.title_layer = glow(self._title(), 22, 0.9)
        # real trace strips (force, safe_state, pwm) from results/trace_override.csv
        x0, x1 = 360, 1560; self.x0, self.x1 = x0, x1
        n = len(o["cycle"]); sx = lambda i: x0 + (x1 - x0) * i / (n - 1)
        def strips(d, s):
            rows = [("FORCE CODE", 625, CY, [(v - 900) / (2900 - 900) for v in o["force_code"]]), ("SAFE STATE", 705, RD, [float(v) for v in o["safe_state"]]), ("PWM OUT", 785, GN, [float(v) for v in o["pwm_out"]])]
            for name, yb, col, vals in rows:
                d.text((x0 - 24 * s, (yb - 28) * s), name, font=font("sb", int(18 * s)), fill=rgba(DIM), anchor="ra")
                d.line([(x0 * s, yb * s), (x1 * s, yb * s)], fill=rgba(EDGE), width=int(2 * s))
                pts = [(sx(i) * s, (yb - 4 - vals[i] * 56) * s) for i in range(n)]
                d.line(pts, fill=rgba(col), width=int(4 * s), joint="curve")
            ym = 625 - 4 - (2560 - 900) / (2900 - 900) * 56
            for xx in range(int(x0), int(x1), 18): d.line([(xx * s, ym * s), ((xx + 9) * s, ym * s)], fill=rgba(RD, 150), width=int(2 * s))
            d.text((x1 * s + 14 * s, ym * s), "FORCE_MAX", font=font("sb", int(17 * s)), fill=rgba(RD), anchor="lm")
        self.strips = ss_layer(strips)
    def _title(self):
        def f(d, s):
            d.text((W / 2 * s, 420 * s), "TACTILE REFLEX SYSTEM", font=font("d", int(118 * s)), fill=rgba(WHITE), anchor="mm")
        return ss_layer(f)
    def draw(self, base, t):
        k0, k1, k2, k3 = [self.t0(i) for i in range(4)]
        a0 = prog(t, 0.3, 0.5)
        blit(base, self.chip, ease(a0))
        w = ease(prog(t, k0, 1.5))
        if w > 0:
            m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rectangle([0, 0, int(160 + (W - 320) * w), H], fill=255); m = m.filter(ImageFilter.GaussianBlur(24))
            lay = self.title_layer.copy(); lay.putalpha(ImageChops.multiply(lay.getchannel("A"), m)); blit(base, lay, 1.0)
        d = ImageDraw.Draw(base)
        a = self.appear(t, 1, 0.8)
        if a > 0:
            lay = new_layer(); ImageDraw.Draw(lay).text((W / 2, 525), "A deterministic, FPGA-based safety reflex for robotic gripping", font=font("m", 38), fill=rgba(TXT), anchor="mm"); blit(base, lay, a)
        a = self.appear(t, 2, 0.8)
        if a > 0:
            p = self.bp(t, 2, 4.0)
            m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rectangle([0, 545, int(self.x0 - 340 + (self.x1 - self.x0 + 520) * p), H], fill=255)
            lay = self.strips.copy(); lay.putalpha(ImageChops.multiply(lay.getchannel("A"), m)); blit(base, lay, a)
            lay = new_layer(); ImageDraw.Draw(lay).text((W / 2, 828), "REAL RTL SIMULATION TRACE  ·  results/trace_override.csv", font=font("sb", 18), fill=rgba(DIM), anchor="mm"); blit(base, lay, a)
        a = self.appear(t, 3, 0.7)
        if a > 0:
            lay = new_layer(); dd = ImageDraw.Draw(lay)
            rrect(dd, [560, 858, 1360, 912], 16, fill=(40, 28, 8, 235), outline=rgba(AM), width=2)
            dd.text((960, 885), "SIMULATION ONLY  ·  NO PHYSICAL HARDWARE TESTED", font=font("b", 26), fill=rgba(AM), anchor="mm"); blit(base, lay, a)

# ---------------------------------------------------------------- Scene 2: problem
class S2(Scene):
    def build(self):
        ml = data.ml()["inference_us_tree_walk"]; self.ml = ml
        def cards(d, s):
            for (x0, tt, sub, col) in ((120, "UNDERSTAND", "what is the gripper touching?", CY), (1000, "REACT", "force is too high: stop now", RD)):
                d.rounded_rectangle([x0 * s, 170 * s, (x0 + 800) * s, 330 * s], 22 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.text(((x0 + 40) * s, 215 * s), tt, font=font("d", int(52 * s)), fill=rgba(col), anchor="lm")
                d.text(((x0 + 40) * s, 285 * s), sub, font=font("m", int(30 * s)), fill=rgba(TXT), anchor="lm")
        self.cards = ss_layer(cards)
        def chips(d, s):
            for i, tx in enumerate(("OS scheduling", "serial / network communication", "model inference time")):
                x = 120 + i * 600
                d.rounded_rectangle([x * s, 400 * s, (x + 560) * s, 470 * s], 35 * s, fill=rgba((40, 28, 8)), outline=rgba(AM), width=int(2 * s))
                d.text(((x + 280) * s, 435 * s), tx, font=font("sb", int(28 * s)), fill=rgba(AM), anchor="mm")
            d.text((960 * s, 503 * s), "each adds latency that varies from run to run", font=font("m", int(30 * s)), fill=rgba(DIM), anchor="mm")
        self.chips = ss_layer(chips)
        # log-scale bars
        import math as m
        vals = [("hardware logic path  (sample valid → PWM low, RTL simulation)", 0.08, GN), ("decision tree walk · mean  (development host)", ml["mean"], CY), ("decision tree walk · p99", ml["p99"], CY), ("decision tree walk · max measured", ml["max"], CY)]
        lo, hi = 0.05, 200.0; X0, X1 = 180, 1700; self.vals = vals
        def lx(v): return X0 + (X1 - X0) * (m.log10(v) - m.log10(lo)) / (m.log10(hi) - m.log10(lo))
        def bars(d, s):
            d.rounded_rectangle([120 * s, 548 * s, 1800 * s, 850 * s], 18 * s, fill=rgba(PANEL), outline=rgba(EDGE), width=int(2 * s))
            for tick in (0.1, 1, 10, 100):
                d.line([(lx(tick) * s, 566 * s), (lx(tick) * s, 780 * s)], fill=rgba(EDGE), width=int(2 * s))
                d.text((lx(tick) * s, 786 * s), f"{tick:g} µs", font=font("sb", int(20 * s)), fill=rgba(DIM), anchor="ma")
            for i, (lab, v, col) in enumerate(vals):
                y = 576 + i * 50
                d.rounded_rectangle([X0 * s, y * s, lx(v) * s, (y + 22) * s], 7 * s, fill=rgba(col, 230))
                d.text((X0 * s + 4 * s, (y + 36) * s), f"{lab}:  {v:.1f} µs" if v >= 1 else f"{lab}:  80 ns", font=font("sb", int(21 * s)), fill=rgba(TXT), anchor="lm")
        self.bars = ss_layer(bars)
        def split(d, s):
            d.rounded_rectangle([120 * s, 600 * s, 920 * s, 860 * s], 22 * s, fill=rgba(PANEL), outline=rgba(CY), width=int(3 * s))
            d.rounded_rectangle([1000 * s, 600 * s, 1800 * s, 860 * s], 22 * s, fill=rgba(PANEL), outline=rgba(GN), width=int(3 * s))
            d.text((160 * s, 650 * s), "THE AI ADVISES", font=font("d", int(44 * s)), fill=rgba(CY), anchor="lm")
            d.text((160 * s, 720 * s), "classifies contact, predicts excess force", font=font("m", int(28 * s)), fill=rgba(TXT), anchor="lm")
            d.text((160 * s, 780 * s), "can only LOWER the command", font=font("b", int(30 * s)), fill=rgba(AM), anchor="lm")
            d.text((1040 * s, 650 * s), "HARDWARE PROTECTS", font=font("d", int(44 * s)), fill=rgba(GN), anchor="lm")
            d.text((1040 * s, 720 * s), "fixed logic, same behaviour every time", font=font("m", int(28 * s)), fill=rgba(TXT), anchor="lm")
            d.text((1040 * s, 780 * s), "hard limits IGNORE the AI", font=font("b", int(30 * s)), fill=rgba(AM), anchor="lm")
        self.split = ss_layer(split)
        self.note = None
    def draw(self, base, t):
        blit(base, self.cards, self.appear(t, 0, 0.7))
        blit(base, self.chips, self.appear(t, 1, 0.7))
        a2 = self.appear(t, 2, 0.6)
        if a2 > 0:
            lay = self.bars.copy(); blit(base, lay, a2)
            lay = new_layer(); ImageDraw.Draw(lay).text((960, 822), "development-host timings (exclude the serial link)  ·  hardware figure from RTL simulation at 50 MHz  ·  log scale", font=font("r", 19), fill=rgba(DIM), anchor="mm"); blit(base, lay, a2)
        a3 = self.appear(t, 3, 0.6)
        if a3 > 0:
            cover = new_layer(); ImageDraw.Draw(cover).rectangle([100, 535, 1820, 870], fill=rgba(BG1)); blit(base, cover, a3)
            blit(base, self.split, a3)

# ---------------------------------------------------------------- Scene 3: architecture
class S3(Scene):
    # block geometry (x0,y0,x1,y1)
    B = dict(fsr=(70, 170, 330, 270), adc=(70, 330, 330, 440),
             adcif=(400, 300, 640, 420), cond=(690, 300, 930, 420), lut=(980, 300, 1220, 420), gov=(1270, 300, 1510, 420), pwm=(1560, 300, 1800, 420),
             fault=(1000, 500, 1240, 590), aiif=(690, 500, 930, 590), estop=(1000, 690, 1240, 770), lap=(690, 690, 930, 770),
             drv=(1560, 520, 1800, 610), mot=(1560, 690, 1800, 770))
    def build(self):
        B = self.B; self.layers = {}
        def block(name, label, sub, col=CY, ext=False):
            x0, y0, x1, y1 = B[name]
            def f(d, s):
                rrect(d, [x0 * s, y0 * s, x1 * s, y1 * s], 16 * s, fill=rgba((10, 20, 38) if not ext else (24, 20, 12)), outline=rgba(col), width=int(3 * s))
                kind = "monob" if not ext else "b"; sz = 20 if not ext else 22
                while text_w(label, kind, sz * s) > (x1 - x0 - 26) * s and sz > 12: sz -= 1
                d.text(((x0 + x1) / 2 * s, (y0 + (y1 - y0) * (0.38 if sub else 0.5)) * s), label, font=font(kind, int(sz * s)), fill=rgba(WHITE), anchor="mm")
                if sub: d.text(((x0 + x1) / 2 * s, (y0 + (y1 - y0) * 0.72) * s), sub, font=font("r", int(17 * s)), fill=rgba(DIM), anchor="mm")
            self.layers[name] = glow(ss_layer(f), 10, 0.7)
        block("fsr", "FSR 402 + 10 kΩ divider", None, AM, True); block("adc", "AD7476A ADC", "12-bit, SPI", AM, True)
        block("adcif", "adc_interface", "16-clock SPI frame"); block("cond", "input_conditioning", "flags invalid reads"); block("lut", "force_lut", "256-entry duty table")
        block("gov", "safety_governor", "limits · hysteresis · trip", RD); block("pwm", "pwm_generator", "12-bit counter, kill")
        block("fault", "fault_handler", "latched e-stop · faults", RD); block("aiif", "ai_control_interface", "checked, advisory", VI)
        block("estop", "E-STOP (NC contact)", None, RD, True); block("lap", "Laptop: decision tree", "UART · advisory only", VI, True)
        block("drv", "DRV8871 driver", None, AM, True); block("mot", "DC motor", None, AM, True)
        P = lambda n, side: self._pt(n, side)
        self.arrows = {  # name -> (points, color, appear beat)
            "a_fsr_adc": ([P("fsr", "b"), P("adc", "t")], AM, 0), "a_adc_if": ([P("adc", "r"), (360, P("adc", "r")[1]), (360, P("adcif", "l")[1]), P("adcif", "l")], AM, 1),
            "a_if_cond": ([P("adcif", "r"), P("cond", "l")], CY, 2), "a_cond_lut": ([P("cond", "r"), P("lut", "l")], CY, 3), "a_lut_gov": ([P("lut", "r"), P("gov", "l")], CY, 4),
            "a_gov_pwm": ([P("gov", "r"), P("pwm", "l")], RD, 5), "a_pwm_drv": ([P("pwm", "b"), P("drv", "t")], AM, 5), "a_drv_mot": ([P("drv", "b"), P("mot", "t")], AM, 5),
            "a_fault_gov": ([P("fault", "t"), (1120, 470), (1340, 470), (1340, 420)], RD, 6), "a_estop_fault": ([P("estop", "t"), P("fault", "b")], RD, 6),
            "a_ai_gov": ([P("aiif", "t"), (810, 470), (1440, 470), (1440, 420)], VI, 7), "a_lap_ai": ([P("lap", "t"), P("aiif", "b")], VI, 7)}
        def arr(pts, col):
            return glow(ss_layer(lambda d, s: arrow(d, [(x * s, y * s) for x, y in pts], col, int(4 * s), 18 * s)), 6, 0.6)
        self.arrow_layers = {k: arr(p, c) for k, (p, c, _) in self.arrows.items()}
        def region(d, s):
            rrect(d, [370 * s, 255 * s, 1830 * s, 640 * s], 22 * s, outline=rgba(CY, 160), width=int(3 * s))
            d.text((400 * s, 262 * s), "FPGA  ·  Terasic DE2-115 (Cyclone IV E)  ·  50 MHz", font=font("sb", int(21 * s)), fill=rgba(CY), anchor="la")
        self.region = ss_layer(region)
        self.dot = dot_sprite(WHITE, 8)
        self.main_path = [P("adc", "r"), (360, P("adc", "r")[1]), (360, P("adcif", "l")[1]), P("adcif", "r"), P("cond", "r"), P("lut", "r"), P("gov", "r"), P("pwm", "r")]
        self.stamp = None
    def _pt(self, n, side):
        x0, y0, x1, y1 = self.B[n]
        return {"l": (x0, (y0 + y1) / 2), "r": (x1, (y0 + y1) / 2), "t": ((x0 + x1) / 2, y0), "b": ((x0 + x1) / 2, y1)}[side]
    def draw(self, base, t):
        order = [("fsr", 0), ("adc", 0), ("adcif", 1), ("cond", 2), ("lut", 3), ("gov", 4), ("pwm", 5), ("drv", 5), ("mot", 5), ("fault", 6), ("estop", 6), ("aiif", 7), ("lap", 7)]
        blit(base, self.region, 1.0)
        lg = new_layer(); dl = ImageDraw.Draw(lg); x = 330
        for col, lab in ((AM, "external / analog"), (CY, "FPGA datapath"), (RD, "safety"), (VI, "advisory AI")):
            dl.rounded_rectangle([x, 122, x + 22, 144], 5, fill=rgba(col)); dl.text((x + 34, 133), lab, font=font("sb", 20), fill=rgba(TXT), anchor="lm"); x += 70 + text_w(lab, "sb", 20) + 40
        blit(base, lg, self.appear(t, 0, 0.8))
        for k, (pts, c, b) in self.arrows.items(): blit(base, self.arrow_layers[k], self.appear(t, b, 0.5, 0.25))
        for n, b in order: blit(base, self.layers[n], self.appear(t, b, 0.5))
        # travelling pulse over the main path while beats 1..5 are spoken
        c = self.cur(t)
        if self.t0(1) <= t <= self.t1(5) + 0.5:
            allowed = {1: 3, 2: 4, 3: 5, 4: 6}.get(c, 7)          # path points 0..allowed belong to blocks already on screen
            sub = self.main_path[:allowed + 1]; u = ((t - self.t0(1)) / 1.6) % 1.0
            paste_center(base, self.dot, path_point(sub, u))
        a = self.appear(t, 8, 0.6)
        if a > 0:
            lay = new_layer(); dd = ImageDraw.Draw(lay)
            rrect(dd, [370, 796, 1550, 850], 16, fill=(40, 28, 8, 235), outline=rgba(AM), width=2)
            dd.text((960, 823), "PROTOTYPE DESIGN  ·  NO PHYSICAL VALIDATION IN THIS WORK", font=font("b", 26), fill=rgba(AM), anchor="mm"); blit(base, lay, a)

# ---------------------------------------------------------------- Scene 4: RTL walkthrough (real source lines)
class S4(Scene):
    SPEC = [  # (file, [(first,last),...], font size, line height, [(line, fraction-of-beat when highlighted)])
        ("rtl/adc_interface.v", [(41, 50)], 24, 30, [(41, .10), (42, .22), (43, .30), (44, .38), (49, .58), (50, .72)]),
        ("rtl/input_conditioning.v", [(15, 24)], 24, 30, [(19, .15), (22, .35)]),
        ("rtl/force_lut.v", [(14, 24)], 23, 29, [(14, .08), (15, .16), (24, .40)]),
        ("rtl/safety_governor.v", [(61, 62), (69, 69), (80, 82)], 26, 38, [(61, .05), (62, .08), (69, .22), (80, .70), (81, .76)]),
        ("rtl/pwm_generator.v", [(13, 21)], 24, 30, [(17, .12), (18, .28), (19, .50)])]
    def build(self):
        self.panels = []
        for fn, rng, size, lh, hl in self.SPEC:
            groups = data.code_lines(fn, rng); rows = []
            for gi, g in enumerate(groups):
                if gi: rows.append(None)
                rows += g
            nts = "real source · " + ", ".join(f"lines {a}-{b}" if a != b else f"line {a}" for a, b in rng)
            layer, pos, bottom = code_panel(rows, fn, 108, size, lh, nts); self.panels.append((layer, pos, bottom, hl))
        # lookup-table curve from the real force_lut.mem
        lut = data.lut(); self.lut = lut
        def curve(d, s, top):
            box = (180, top + 22, 1740, 780); px, py = plot_axes(d, s, box, (0, 4095), (0, 200), [0, 512, 1024, 1536, 2048, 2560, 3072, 3584, 4095], [0, 60, 120, 180], "force code (ADC counts)", "PWM duty command", lambda v: f"{int(v)}", lambda v: f"{int(v)}")
            pts = [(px(i * 16) * s, py(lut[i]) * s) for i in range(256)]; d.line(pts, fill=rgba(CY), width=int(5 * s), joint="curve")
            d.line([(px(2560) * s, box[1] * s), (px(2560) * s, box[3] * s)], fill=rgba(RD), width=int(3 * s))
            d.text((px(2560) * s + 10 * s, box[1] * s + 18 * s), "FORCE_MAX 2560 → duty 0", font=font("sb", int(21 * s)), fill=rgba(RD), anchor="la")
            d.text((px(120) * s, py(180) * s - 14 * s), "180: no contact (approach drive)", font=font("sb", int(21 * s)), fill=rgba(CY), anchor="ls")
            d.text((px(1536) * s + 12 * s, py(60) * s - 14 * s), "60: hold level (index 96)", font=font("sb", int(21 * s)), fill=rgba(CY), anchor="ls")
            return px, py, box
        self._curve = curve
        self.vis = {}
        top = self.panels[2][2]
        im = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0)); d = ImageDraw.Draw(im); px, py, box = curve(d, 2, top)
        self.vis[2] = (im.resize((W, H), Image.LANCZOS), box)
        self._spi(); self._thresh(); self._or(); self._pwm()
    def _spi(self):
        top = self.panels[0][2] + 14; self.spi_top = top
        def f(d, s):
            card(d, [70 * s, top * s, 1850 * s, 820 * s], None)
            x0, x1 = 200, 1760; cw = (x1 - x0) / 16
            d.text((96 * s, (top + 22) * s), "CS_N", font=font("monob", int(21 * s)), fill=rgba(DIM), anchor="lm")
            d.text((96 * s, (top + 78) * s), "SCLK", font=font("monob", int(21 * s)), fill=rgba(DIM), anchor="lm")
            d.text((96 * s, (top + 146) * s), "MISO", font=font("monob", int(21 * s)), fill=rgba(DIM), anchor="lm")
            ycs = top + 22; d.line([(x0 * s, (ycs - 14) * s), (x0 * s, (ycs + 14) * s), (x1 * s, (ycs + 14) * s), (x1 * s, (ycs - 14) * s)], fill=rgba(AM), width=int(4 * s))
            yh, yl = top + 62, top + 96; pts = [(x0 * s - 40 * s, yh * s)]
            for i in range(16):
                a = x0 + i * cw; pts += [(a * s, yh * s), (a * s, yl * s), ((a + cw / 2) * s, yl * s), ((a + cw / 2) * s, yh * s)]
            pts += [(x1 * s, yh * s)]; d.line(pts, fill=rgba(CY), width=int(4 * s))
            labels = ["0", "0", "0", "0"] + [f"D{11 - i}" for i in range(12)]
            for i, lb in enumerate(labels):
                a = x0 + i * cw; zero = i < 4
                d.rounded_rectangle([(a + 4) * s, (top + 120) * s, (a + cw - 4) * s, (top + 170) * s], 8 * s, fill=rgba((26, 34, 54) if zero else (10, 50, 64)), outline=rgba(DIM if zero else CY), width=int(2 * s))
                d.text(((a + cw / 2) * s, (top + 145) * s), lb, font=font("monob", int(21 * s)), fill=rgba(DIM if zero else WHITE), anchor="mm")
                d.line([((a + 2) * s, (yl + 4) * s), ((a + 2) * s, (top + 118) * s)], fill=rgba(GN, 120), width=int(2 * s))
            d.text(((x0 + 2 * cw) * s, (top + 186) * s), "4 leading zeros: a non-zero bit sets frame_err", font=font("sb", int(21 * s)), fill=rgba(DIM), anchor="ma")
            d.text(((x0 + 10 * cw) * s, (top + 186) * s), "12 data bits → sample[11:0]", font=font("sb", int(21 * s)), fill=rgba(CY), anchor="ma")
            d.text((x0 * s, (top + 22) * s), "", font=font("r", 10), fill=rgba(DIM))
            d.line([(x0 * s, (top + 232) * s), (x1 * s, (top + 232) * s)], fill=rgba(AM), width=int(3 * s))
            for xx in (x0, x1): d.line([(xx * s, (top + 222) * s), (xx * s, (top + 242) * s)], fill=rgba(AM), width=int(3 * s))
            d.text((960 * s, (top + 268) * s), "16 bits × 6 clk (SCLK = 50 MHz / 6 = 8.33 MHz)  +  8 clk gap  =  104 clk  =  2.08 µs", font=font("b", int(28 * s)), fill=rgba(AM), anchor="mm")
            d.text((960 * s, (top + 308) * s), "then:  sample_valid pulses for one cycle", font=font("m", int(24 * s)), fill=rgba(TXT), anchor="mm")
        self.spi = ss_layer(f)
    def _thresh(self):
        top = self.panels[1][2] + 14
        def f(d, s):
            card(d, [70 * s, top * s, 1850 * s, 820 * s], None)
            x0, x1, y = 200, 1720, top + 80; px = lambda v: x0 + (x1 - x0) * v / 4095
            d.rounded_rectangle([x0 * s, (y - 28) * s, px(4080) * s, (y + 28) * s], 8 * s, fill=rgba(CY, 200))
            d.rounded_rectangle([px(4080) * s, (y - 28) * s, x1 * s, (y + 28) * s], 8 * s, fill=rgba(RD, 230))
            for v, lab, col in ((0, "0", DIM), (2560, "2560  FORCE_MAX", RD), (4080, "4080 = 0xFF0  RAIL_HI", RD), (4095, "4095", DIM)):
                d.line([(px(v) * s, (y - 44) * s), (px(v) * s, (y + 44) * s)], fill=rgba(col), width=int(3 * s))
                if v == 4095: d.text((px(v) * s, (y - 58) * s), lab, font=font("sb", int(21 * s)), fill=rgba(col), anchor="ra")
                else: d.text((px(v) * s, (y + 56) * s), lab, font=font("sb", int(21 * s)), fill=rgba(col), anchor="ma" if v < 4000 else "ra")
            chips = [("frame error:  any of the 4 leading bits ≠ 0", AM), ("railed / shorted:  sample ≥ 0xFF0", RD), ("→ adc_invalid → governor trip", GN)]
            for i, (tx, col) in enumerate(chips):
                x = 120 + i * 590; d.rounded_rectangle([x * s, (top + 190) * s, (x + 560) * s, (top + 260) * s], 34 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.text(((x + 280) * s, (top + 225) * s), tx, font=font("sb", int(24 * s)), fill=rgba(col), anchor="mm")
        self.thresh = ss_layer(f)
    def _or(self):
        top = self.panels[3][2] + 14; self.or_top = top
        names = [("force_over_n", "force ≥ FORCE_MAX\n(hysteresis latch)"), ("sensor_fault", "latched sensor fault"), ("estop_active", "emergency stop"), ("adc_invalid", "invalid reading"), ("~armed", "not yet armed"), ("pred_trip", "predicted over-force")]
        self.or_names = names
        def f(d, s):
            card(d, [70 * s, top * s, 1850 * s, 820 * s], None)
            for i, (n, sub) in enumerate(names):
                x = 100 + i * 235; d.rounded_rectangle([x * s, (top + 30) * s, (x + 215) * s, (top + 150) * s], 14 * s, fill=rgba(PANEL), outline=rgba(EDGE), width=int(2 * s))
                d.text(((x + 107) * s, (top + 62) * s), n, font=font("monob", int(21 * s)), fill=rgba(WHITE), anchor="mm")
                for j, ln in enumerate(sub.split("\n")): d.text(((x + 107) * s, (top + 100 + j * 24) * s), ln, font=font("r", int(17 * s)), fill=rgba(DIM), anchor="mm")
                d.line([((x + 107) * s, (top + 150) * s), ((x + 107) * s, (top + 190) * s), (1140 * s, (top + 190) * s)], fill=rgba(EDGE), width=int(3 * s))
            d.ellipse([1090 * s, (top + 165) * s, 1190 * s, (top + 245) * s], fill=rgba((26, 20, 40)), outline=rgba(AM), width=int(3 * s)); d.text((1140 * s, (top + 205) * s), "OR", font=font("b", int(30 * s)), fill=rgba(AM), anchor="mm")
            d.line([(1190 * s, (top + 205) * s), (1330 * s, (top + 205) * s)], fill=rgba(RD), width=int(4 * s)); arrow(d, [(1330 * s, (top + 205) * s), (1400 * s, (top + 205) * s)], rgba(RD), int(4 * s), 18 * s)
            d.rounded_rectangle([1400 * s, (top + 150) * s, 1830 * s, (top + 270) * s], 16 * s, fill=rgba((40, 12, 20)), outline=rgba(RD), width=int(3 * s))
            d.text((1615 * s, (top + 190) * s), "safe_state <= trip", font=font("monob", int(24 * s)), fill=rgba(WHITE), anchor="mm")
            d.text((1615 * s, (top + 232) * s), "cmd_out <= trip ? 0 : ai_cmd", font=font("monob", int(21 * s)), fill=rgba(TXT), anchor="mm")
        self.orl = ss_layer(f)
        def lit(i):
            def g(d, s):
                x = 100 + i * 235; d.rounded_rectangle([x * s, (top + 30) * s, (x + 215) * s, (top + 150) * s], 14 * s, outline=rgba(RD), width=int(5 * s)); d.line([((x + 107) * s, (top + 150) * s), ((x + 107) * s, (top + 190) * s), (1140 * s, (top + 190) * s)], fill=rgba(RD), width=int(4 * s))
            return glow(ss_layer(g), 8, 0.9)
        self.lits = [lit(i) for i in range(6)]
    def _pwm(self):
        top = self.panels[4][2] + 14; self.pwm_top = top
        def f(d, s):
            card(d, [70 * s, top * s, 1850 * s, 820 * s], None)
            x0, x1 = 230, 1780; yc0, yc1 = top + 36, top + 150; yo0, yo1 = top + 200, top + 245
            px = lambda c: x0 + (x1 - x0) * c / 8192; py = lambda v: yc1 - (yc1 - yc0) * v / 4095
            d.text((96 * s, (yc0 + 75) * s), "cnt[11:0]", font=font("monob", int(21 * s)), fill=rgba(DIM), anchor="lm")
            d.text((96 * s, (yo0 + 25) * s), "pwm_out", font=font("monob", int(21 * s)), fill=rgba(DIM), anchor="lm")
            pts = []
            for per in range(2): pts += [(px(per * 4096) * s, py(0) * s), (px((per + 1) * 4096) * s, py(4095) * s)]
            d.line(pts, fill=rgba(VI), width=int(3 * s))
            th = 180 * 16; d.line([(x0 * s, py(th) * s), (x1 * s, py(th) * s)], fill=rgba(AM), width=int(3 * s))
            d.text((x1 * s, (py(th) - 6) * s), "duty_active = 180 → threshold 180 × 16 = 2880", font=font("sb", int(20 * s)), fill=rgba(AM), anchor="rs")
            kill_c = 4096 + 1700; pts = [(x0 * s, yo1 * s)]
            def hi(c0, c1): return [(px(c0) * s, yo1 * s), (px(c0) * s, yo0 * s), (px(c1) * s, yo0 * s), (px(c1) * s, yo1 * s)]
            pts += hi(0, th)[:] ; pts += hi(4096, kill_c)[:]; pts += [(x1 * s, yo1 * s)]
            d.line(pts, fill=rgba(GN), width=int(4 * s))
            d.line([(px(kill_c) * s, (top + 30) * s), (px(kill_c) * s, (yo1 + 20) * s)], fill=rgba(RD), width=int(3 * s))
            d.text((px(kill_c) * s + 12 * s, (top + 70) * s), "kill = safe_state → pwm_out low on the next clock", font=font("sb", int(22 * s)), fill=rgba(RD), anchor="la")
            d.text((960 * s, (yo1 + 44) * s), "illustration computed from the RTL equation  pwm_out <= (cnt[11:4] < duty_active) & ~kill   ·   period = 4096 clk = 82 µs (12.2 kHz)", font=font("r", int(20 * s)), fill=rgba(DIM), anchor="mm")
        self.pwm = ss_layer(f)
    def draw(self, base, t):
        c = self.cur(t)
        if c < 0: return
        c = min(c, 4)
        layer, pos, bottom, hl = self.panels[c]
        a = self.appear(t, c, 0.4)
        # highlights under the text
        hl_layer = new_layer(); hd = ImageDraw.Draw(hl_layer)
        p = self.bp(t, c)
        for ln, fr in hl:
            if p >= fr and ln in pos:
                y0, y1 = pos[ln]; k = ease(prog(p, fr, 0.06)); hd.rectangle([84, y0 - 1, 1836, y1 + 1], fill=(34, 211, 238, int(52 * k)), outline=None)
                hd.rectangle([84, y0 - 1, 90, y1 + 1], fill=(34, 211, 238, int(255 * k)))
        pl = new_layer(); ImageDraw.Draw(pl).rounded_rectangle([70, 108, 1850, bottom], 16, fill=rgba((8, 14, 28)), outline=rgba(EDGE), width=2)
        blit(base, pl, a); blit(base, hl_layer, a)
        blit(base, self._text_only(c), a)
        if c == 0:
            p0 = ease(prog(p, 0.0, 0.5)); lay = self.spi
            m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rectangle([0, 0, int(70 + 1780 * clamp(self.bp(t, 0, 5.0) * 1.0)), H], fill=255)
            L = lay.copy(); L.putalpha(ImageChops.multiply(L.getchannel("A"), m)); blit(base, L, a)
        elif c == 1: blit(base, self.thresh, ease(prog(p, 0.12, 0.25)))
        elif c == 2:
            im, box = self.vis[2]; m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rectangle([0, 0, int(box[0] + (box[2] - box[0] + 60) * clamp(prog(p, 0.1, 0.6))), H], fill=255)
            L = im.copy(); L.putalpha(ImageChops.multiply(L.getchannel("A"), m)); blit(base, L, a)
        elif c == 3:
            blit(base, self.orl, ease(prog(p, 0.05, 0.2)))
            for i in range(6):
                fr = 0.22 + i * 0.10
                if p >= fr: blit(base, self.lits[i], ease(prog(p, fr, 0.08)))
        elif c == 4: blit(base, self.pwm, ease(prog(p, 0.08, 0.25)))
    def _text_only(self, c):
        if not hasattr(self, "_to"): self._to = {}
        if c not in self._to:
            fn, rng, size, lh, hl = self.SPEC[c]; groups = data.code_lines(fn, rng); rows = []
            for gi, g in enumerate(groups):
                if gi: rows.append(None)
                rows += g
            nts = "real source · " + ", ".join(f"lines {a}-{b}" if a != b else f"line {a}" for a, b in rng)
            lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay); y0 = 108
            d.text((96, y0 + 23), fn, font=font("monob", 21), fill=rgba(CY), anchor="lm"); d.text((1826, y0 + 23), nts, font=font("sb", 17), fill=rgba(DIM), anchor="rm")
            y = y0 + 46
            for r in rows:
                if r is None: d.text((96, y + 10), "...   (lines omitted)", font=font("mono", 17), fill=rgba(DIM), anchor="lm"); y += 22; continue
                ln, tx = r; d.text((130, y + lh / 2), f"{ln:>3}", font=font("mono", size), fill=rgba((80, 96, 124)), anchor="rm"); x = 160
                for run, col in highlight_runs(tx):
                    d.text((x, y + lh / 2), run, font=font("mono", size), fill=rgba(col), anchor="lm"); x += font("mono", size).getlength(run)
                y += lh
            self._to[c] = lay
        return self._to[c]
