import re, json, math
from common import *
from scene_base import Scene, blit
from charts import strip_chart, vmarker, chip, wipe
import data

CHX0, CHX1 = 200, 1830
def tag(text, sub=None):
    lay = new_layer(); d = ImageDraw.Draw(lay)
    d.text((CHX0 - 130, 112), text, font=font("d", 34), fill=rgba(WHITE), anchor="lm")
    if sub: d.text((1830, 112), sub, font=font("sb", 18), fill=rgba(DIM), anchor="rm")
    return lay

# ---------------------------------------------------------------- Scene 5: safety demonstrations
class S5(Scene):
    def build(self):
        self.items = {}
        # --- 0: force limit / AI override  (results/trace_override.csv, real RTL simulation)
        o = data.trace("trace_override"); n = len(o["cycle"]); xs = [i * 0.02 for i in range(n)]
        f = next(i for i, v in enumerate(o["force_code"]) if v >= 2560); sf = next(i for i, v in enumerate(o["safe_state"]) if v); pw = next(i for i, v in enumerate(o["pwm_out"]) if i > f - 50 and v == 0)
        self.ov = dict(f=f, sf=sf, pw=pw)
        st = [dict(label="force code (after conditioning)", xs=xs, ys=o["force_code"], color=CY, ymin=800, ymax=3200, h=3, yticks=[1024, 2048, 2816], hlines=[(2560, RD, "FORCE_MAX 2560")], yfmt=lambda v: f"{int(v)}"),
              dict(label="AI class  (2 = normal grip)", xs=xs, ys=o["ai_class"], color=VI, ymin=-0.3, ymax=3.3, h=1.6, yticks=[0, 2], yfmt=lambda v: f"{int(v)}"),
              dict(label="safe_state", xs=xs, ys=o["safe_state"], color=RD, ymin=-0.2, ymax=1.9, h=1.4, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label="pwm_out", xs=xs, ys=o["pwm_out"], color=GN, ymin=-0.2, ymax=1.9, h=1.4, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
        L, px, info = strip_chart(st, (CHX0, 165, CHX1, 700), (0, 16), list(range(0, 17, 2)), "time (µs) · RTL simulation, 50 MHz clock", lambda v: f"{int(v)}")
        mk = vmarker(px(f * 0.02), 165, 700, AM, f"force reaches the limit\nsafe_state  +{sf - f} clk ({(sf - f) * 20} ns)\nPWM low  +{pw - f} clk ({(pw - f) * 20} ns)", "r", 78)
        self.items[0] = dict(tag=tag("1 · FORCE LIMIT, AI OVERRIDDEN", "results/trace_override.csv  ·  real RTL simulation"), layer=L, px=px, xr=(0, 16), marks=[(px(f * 0.02), mk, 0.0)], chips=[("AI said: normal grip  →  OVERRIDDEN by the governor", RD, (CHX0 + 360, 778))])
        # --- 1: predictive trip (experiments/results_v2, RTL replay, scenario S08)
        m, r = data.v2_logs(); mm, rr = m["S08_fast_ramp"], r["S08_fast_ramp"]
        s0, s1 = 15, 60; steps = list(range(s0, s1 + 1)); xs = [s * 0.5 for s in steps]
        first_p = next(i for i in range(21, len(rr)) if rr[i]["safe"]); first_over = next(i for i in range(21, len(mm)) if mm[i]["code"] >= 2560)
        self.pred = dict(p=first_p, o=first_over, pc=mm[first_p]["code"], oc=mm[first_over]["code"])
        st = [dict(label="force code (replay stimulus)", xs=xs, ys=[mm[s]["code"] for s in steps], color=CY, ymin=800, ymax=3000, h=3, yticks=[1000, 2000, 2560], hlines=[(2560, RD, "FORCE_MAX 2560")], yfmt=lambda v: f"{int(v)}"),
              dict(label="RTL safe_state", xs=xs, ys=[rr[s]["safe"] for s in steps], color=RD, ymin=-0.2, ymax=1.9, h=1.3, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label="trip reason: predicted over-force (bit 4)", xs=xs, ys=[(rr[s]["trip"] >> 4) & 1 for s in steps], color=AM, ymin=-0.2, ymax=1.9, h=1.3, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label="trip reason: force limit (bit 0)", xs=xs, ys=[rr[s]["trip"] & 1 for s in steps], color=VI, ymin=-0.2, ymax=1.9, h=1.3, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
        L, px, info = strip_chart(st, (CHX0, 165, CHX1, 700), (s0 * .5, s1 * .5), list(range(8, 31, 2)), "time (ms) · each replay step = 500 µs · scenario S08", lambda v: f"{int(v)}")
        a = vmarker(px(first_p * .5), 165, 700, AM, f"predictive trip @ {self.pred['pc']}", "l", 0, 21); b = vmarker(px(first_over * .5), 165, 700, RD, f"limit crossed @ {self.pred['oc']}", "l", 0, 21)
        self.items[1] = dict(tag=tag("2 · PREDICTIVE TRIP", "experiments/results_v2/rtl_log.txt  ·  RTL replay, scenario S08"), layer=L, px=px, xr=(s0 * .5, s1 * .5), marks=[(px(first_p * .5), a, 0.0), (px(first_over * .5), b, 0.0)],
                         chips=[(f"{first_over - first_p} steps = {(first_over - first_p) * .5:.1f} ms earlier (stimulus time)", AM, (CHX0 + 700, 778))])
        # --- 2: cost of prediction (results/pred_results.json, SIMULATED episodes)
        pr = data.pred()["test"]; self.pr = pr
        def stats(d, s):
            for i, (big, lab, sub, col) in enumerate(((f"{pr['early_trip']} / {pr['crossing_episodes']}", "crossing episodes tripped early", f"mean lead {pr['lead_ms_mean']:.2f} ms before the hard limit", GN),
                                                       (f"{pr['false_early']} / {pr['noncrossing_episodes']}", "never-crossing episodes also tripped", f"{pr['false_early_rate'] * 100:.1f} % early trips: the price of prediction", AM))):
                x = 130 + i * 880; d.rounded_rectangle([x * s, 190 * s, (x + 820) * s, 560 * s], 24 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.text(((x + 410) * s, 330 * s), big, font=font("d", int(130 * s)), fill=rgba(col), anchor="mm")
                d.text(((x + 410) * s, 440 * s), lab, font=font("sb", int(34 * s)), fill=rgba(WHITE), anchor="mm"); d.text(((x + 410) * s, 495 * s), sub, font=font("m", int(28 * s)), fill=rgba(TXT), anchor="mm")
            d.text((960 * s, 640 * s), "SIMULATED test episodes  ·  results/pred_results.json  ·  test split", font=font("sb", int(24 * s)), fill=rgba(AM), anchor="mm")
        self.items[2] = dict(tag=tag("2 · PREDICTIVE TRIP: THE COST", None), layer=ss_layer(stats), static=True)
        # --- 3: hysteresis (scenario S04)
        mm, rr = m["S04_hysteresis"], r["S04_hysteresis"]; s0, s1 = 60, 131; steps = list(range(s0, s1 + 1)); xs = [s * .5 for s in steps]
        hold = next(i for i in range(len(mm)) if mm[i]["code"] == 2304 and rr[i]["safe"] == 1 and i > 100); rel = next(i for i in range(hold, len(mm)) if mm[i]["code"] == 2303 and rr[i]["safe"] == 0)
        self.hy = dict(hold=hold, rel=rel)
        st = [dict(label="force code (replay stimulus)", xs=xs, ys=[mm[s]["code"] for s in steps], color=CY, ymin=2200, ymax=2800, h=3, yticks=[2304, 2560, 2700], hlines=[(2560, RD, "FORCE_MAX 2560"), (2304, AM, "FORCE_REL 2304")], yfmt=lambda v: f"{int(v)}"),
              dict(label="RTL safe_state", xs=xs, ys=[rr[s]["safe"] for s in steps], color=RD, ymin=-0.2, ymax=1.9, h=1.5, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
        L, px, info = strip_chart(st, (CHX0, 165, CHX1, 700), (s0 * .5, s1 * .5), list(range(30, 66, 5)), "time (ms) · each replay step = 500 µs · scenario S04", lambda v: f"{int(v)}")
        a = vmarker(px(hold * .5), 165, 700, AM, "2304: still inhibited", "l", 40); b = vmarker(px(rel * .5), 165, 700, GN, "2303: released", "r", 40)
        self.items[3] = dict(tag=tag("3 · HYSTERESIS AND RECOVERY", "experiments/results_v2/rtl_log.txt  ·  RTL replay, scenario S04"), layer=L, px=px, xr=(s0 * .5, s1 * .5), marks=[(px(hold * .5), a, 0.0), (px(rel * .5), b, 0.0)], chips=[])
        # --- 4: emergency stop (results/trace_estop.csv)
        e = data.trace("trace_estop"); n = len(e["cycle"]); xs = list(range(n))
        sf = next(i for i, v in enumerate(e["safe_state"]) if v); pw = next(i for i, v in enumerate(e["pwm_out"]) if v == 0)
        self.es = dict(sf=sf, pw=pw)
        st = [dict(label="estop_n", xs=xs, ys=e["estop_n"], color=AM, ymin=-0.2, ymax=1.9, h=1.3, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label=f"force code = {e['force_code'][0]}  (no contact: not a force event)", xs=xs, ys=e["force_code"], color=CY, ymin=0, ymax=3000, h=1.3, yticks=[0, 2560], yfmt=lambda v: f"{int(v)}"),
              dict(label="safe_state", xs=xs, ys=e["safe_state"], color=RD, ymin=-0.2, ymax=1.9, h=1.4, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label="pwm_out", xs=xs, ys=e["pwm_out"], color=GN, ymin=-0.2, ymax=1.9, h=1.4, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
        L, px, info = strip_chart(st, (CHX0, 165, CHX1, 700), (0, n - 1), list(range(0, n, 8)), "clock cycles since the e-stop press (1 cycle = 20 ns at 50 MHz)", lambda v: f"{int(v)}")
        a = vmarker(px(sf), 165, 700, AM, f"safe_state  +{sf} clk  ({sf * 20} ns)", "r", 30); b = vmarker(px(pw), 165, 700, GN, f"PWM low  +{pw} clk  ({pw * 20} ns)", "r", 64)
        self.items[4] = dict(tag=tag("4 · EMERGENCY STOP", "results/trace_estop.csv  ·  real RTL simulation"), layer=L, px=px, xr=(0, n - 1), marks=[(px(sf), a, 0.0), (px(pw), b, 0.0)], chips=[("latched until an operator clears it", RD, (CHX0 + 560, 778))])
        # --- 5: invalid sensor input (validation/results_v2/frame_rtl_log.txt, frame-level RTL run)
        self.items[5] = dict(tag=tag("5 · INVALID SENSOR INPUT", "experiments/validation/results_v2/frame_rtl_log.txt  ·  frame-level RTL run"), double=True)
        for key, pat, bx, ttl in (("L", "ferr_001", (CHX0, 215, 960, 640), "ONE bad ADC frame"), ("R", "ferr_004", (1030, 215, 1830, 640), "FOUR consecutive bad frames")):
            fr = data.frames(pat); f0, f1 = 14, 34; xs = list(range(f0, f1 + 1)); rows = [x for x in fr if f0 <= x["frame"] <= f1]
            st = [dict(label="safe_state", xs=xs, ys=[x["safe"] for x in rows], color=RD, ymin=-0.2, ymax=1.9, h=1, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
                  dict(label="sensor_fault", xs=xs, ys=[x["sfault"] for x in rows], color=AM, ymin=-0.2, ymax=1.9, h=1, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
            L, px, info = strip_chart(st, bx, (f0, f1), list(range(15, 35, 5)), "ADC frame index (104 clk each)", lambda v: f"{int(v)}")
            self.items[5][key] = dict(layer=L, px=px, ttl=ttl, box=bx)
        i5 = self.items[5]
        i5["marks"] = [(i5["L"]["px"](17), vmarker(i5["L"]["px"](17), 215, 640, AM, "1 bad frame\n= 1 frame inhibit\n(104 clk)", "r", 8, 19, True, 52), "L"), (i5["R"]["px"](17), vmarker(i5["R"]["px"](17), 215, 640, AM, "×4 bad", "r", 8, 19), "R"),
                       (i5["R"]["px"](20), vmarker(i5["R"]["px"](20), 215, 640, RD, "fault latched", "r", 225, 19), "R"), (i5["R"]["px"](29), vmarker(i5["R"]["px"](29), 215, 640, GN, "operator clear", "l", 225, 19), "R")]
        # --- 6: watchdog (RTL parameter WD_CYCLES=2000; measured forced-dropout runs)
        drp = [int(x) for x in re.findall(r"clocks_force_to_sensor_fault=(\d+)", open(data.P + "experiments/validation/results_v2/dropout_and_frame_count.txt").read())]; self.drp = drp
        def wd(d, s):
            d.rounded_rectangle([130 * s, 190 * s, 1790 * s, 600 * s], 22 * s, fill=rgba(PANEL), outline=rgba(EDGE), width=int(2 * s))
            x0, x1 = 220, 1700; px = lambda c: x0 + (x1 - x0) * c / 2200; y = 400
            d.line([(x0 * s, y * s), (x1 * s, y * s)], fill=rgba(DIM), width=int(3 * s))
            for c in range(0, 2200, 104): d.line([(px(c) * s, (y - 14) * s), (px(c) * s, (y + 14) * s)], fill=rgba(GN, 200 if c == 0 else 70), width=int(3 * s))
            d.text((px(0) * s, (y + 36) * s), "last valid sample", font=font("sb", int(21 * s)), fill=rgba(GN), anchor="ma")
            d.text((px(1000) * s, (y - 56) * s), "no further samples arrive", font=font("sb", int(24 * s)), fill=rgba(DIM), anchor="mm")
            d.line([(px(2000) * s, (y - 120) * s), (px(2000) * s, (y + 80) * s)], fill=rgba(RD), width=int(4 * s))
            d.text((px(2000) * s - 14 * s, (y - 150) * s), "WD_CYCLES = 2000 clk = 40 µs  →  sensor_fault latched", font=font("b", int(26 * s)), fill=rgba(RD), anchor="rm")
            for c in drp: d.ellipse([(px(c) - 9) * s, (y - 9) * s, (px(c) + 9) * s, (y + 9) * s], fill=rgba(AM))
            d.text((px(1940) * s, (y + 72) * s), f"measured in RTL (forced dropout, 4 phases): {min(drp)}–{max(drp)} clk", font=font("sb", int(22 * s)), fill=rgba(AM), anchor="ra")
            d.text((960 * s, 540 * s), "dots: measured clocks from the dropout to the fault (the last sample's timing varies by phase)", font=font("r", int(20 * s)), fill=rgba(DIM), anchor="mm")
        self.items[6] = dict(tag=tag("5 · INVALID SENSOR INPUT: WATCHDOG", "rtl/fault_handler.v WD_CYCLES  ·  experiments/validation/results_v2"), layer=ss_layer(wd), static=True)
        # --- 7: safe-state rules
        def rules(d, s):
            rows = [("PWM forced low on the next clock", "pwm_out <= (cnt[11:4] < duty_active) & ~kill", RD), ("Faults and the e-stop are latched", "an operator clear is required, and the cause must be gone", AM), ("After reset: safe until the first valid sample", "the governor stays 'not armed' until real data arrives", CY)]
            for i, (a, b, col) in enumerate(rows):
                y = 190 + i * 150; d.rounded_rectangle([160 * s, y * s, 1760 * s, (y + 120) * s], 22 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.ellipse([200 * s, (y + 35) * s, 250 * s, (y + 85) * s], fill=rgba(col)); d.text((225 * s, (y + 60) * s), str(i + 1), font=font("d", int(28 * s)), fill=rgba(BG0), anchor="mm")
                d.text((290 * s, (y + 42) * s), a, font=font("b", int(36 * s)), fill=rgba(WHITE), anchor="lm"); d.text((290 * s, (y + 88) * s), b, font=font("mono", int(24 * s)) if i == 0 else font("m", int(26 * s)), fill=rgba(TXT), anchor="lm")
        self.items[7] = dict(tag=tag("SAFE-STATE BEHAVIOUR", "rtl/safety_governor.v · rtl/fault_handler.v · rtl/pwm_generator.v"), layer=ss_layer(rules), static=True)
    def draw(self, base, t):
        c = self.cur(t)
        if c < 0: return
        it = self.items[c]; a = self.appear(t, c, 0.5); blit(base, it["tag"], a)
        if it.get("static"): blit(base, it["layer"], a); return
        p = clamp((t - self.t0(c) - 0.5) / max(0.5, (self.t1(c) - self.t0(c)) * 0.55))
        if it.get("double"):
            for key in ("L", "R"):
                sub = it[key]; bx = sub["box"]; px = sub["px"]; lay = wipe(sub["layer"], bx[0], bx[0] + (bx[2] - bx[0] + 4) * p); blit(base, lay, a)
                lg = new_layer(); ImageDraw.Draw(lg).text(((bx[0] + bx[2]) / 2, bx[1] - 30), sub["ttl"], font=font("b", 26), fill=rgba(WHITE), anchor="mm"); blit(base, lg, a)
            for x, mk, key in it["marks"]:
                sub = it[key]; frac = (x - sub["box"][0]) / (sub["box"][2] - sub["box"][0])
                if p >= frac: blit(base, mk, ease(prog(p, frac, 0.04)) * a)
            return
        x0 = it["px"](it["xr"][0]); x1 = it["px"](it["xr"][1]); cx = x0 + (x1 - x0) * p
        blit(base, wipe(it["layer"], x0, cx), a)
        for x, mk, _ in it["marks"]:
            if cx >= x: blit(base, mk, ease(prog(cx - x, 0, 40)) * a)
        for text_, col, (cx_, cy_) in it.get("chips", []):
            if p > 0.9: blit_chip = chip(text_, col, 26); base.alpha_composite(with_alpha(blit_chip, ease(prog(p, 0.9, 0.1)) * a), (cx_, cy_ - 0))

# ---------------------------------------------------------------- Scene 6: results
class S6(Scene):
    def build(self):
        tb, res = data.sim_log(); core = [(k, v) for k, v in tb.items() if "replay" not in k]; self.core = core
        self.tot = sum(v[0] for k, v in core)
        def b0(d, s):
            d.text((960 * s, 180 * s), f"{self.tot} / {self.tot}", font=font("d", int(150 * s)), fill=rgba(GN), anchor="mm")
            d.text((960 * s, 285 * s), "directed checks pass  ·  12 testbenches  ·  0 failures", font=font("sb", int(34 * s)), fill=rgba(WHITE), anchor="mm")
            mx = max(v[0] for k, v in core)
            for i, (k, v) in enumerate(core):
                col, row = divmod(i, 6); x = 150 + col * 880; y = 350 + row * 70
                d.text((x * s, (y + 22) * s), k.replace("tb_", ""), font=font("mono", int(22 * s)), fill=rgba(TXT), anchor="lm")
                d.rounded_rectangle([(x + 300) * s, (y + 6) * s, (x + 300 + 460 * v[0] / mx) * s, (y + 38) * s], 8 * s, fill=rgba(GN, 220)); d.text(((x + 770) * s, (y + 22) * s), f"{v[0]}", font=font("b", int(24 * s)), fill=rgba(WHITE), anchor="lm")
            d.text((960 * s, 790 * s), "results/sim_log.txt  ·  existing RTL regression (Icarus Verilog), reproduced", font=font("r", int(22 * s)), fill=rgba(DIM), anchor="mm")
        self.l0 = ss_layer(b0)
        rp = {}
        for l in res:
            m = re.match(r"RESULT replay mode=(\w+) vectors=(\d+) over_limit_samples=(\d+)", l)
            if m: rp[m.group(1)] = (int(m.group(2)), int(m.group(3)))
        viol = [re.search(r"safe_state=(\d+) cmd_above_lut=(\d+)", l).groups() for l in res if "violations:" in l]; self.rp, self.viol = rp, viol
        def b1(d, s):
            for i, (key, ttl, col) in enumerate((("ml_tree_ai", "REAL DECISION TREE", CY), ("adversarial_ai", "ADVERSARIAL AI: always says \"normal grip\"", RD))):
                x = 130 + i * 880; d.rounded_rectangle([x * s, 190 * s, (x + 820) * s, 640 * s], 24 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.text(((x + 410) * s, 250 * s), ttl, font=font("b", int(30 * s)), fill=rgba(col), anchor="mm")
                d.text(((x + 410) * s, 360 * s), "0", font=font("d", int(150 * s)), fill=rgba(GN), anchor="mm"); d.text(((x + 410) * s, 460 * s), "safe-state violations", font=font("sb", int(32 * s)), fill=rgba(WHITE), anchor="mm")
                v = rp[key]; d.text(((x + 410) * s, 530 * s), f"{v[0]} vectors replayed  ·  {v[1]} over the force limit", font=font("m", int(26 * s)), fill=rgba(TXT), anchor="mm")
                d.text(((x + 410) * s, 580 * s), f"commands above the lookup-table value: {viol[i][1]}", font=font("m", int(26 * s)), fill=rgba(TXT), anchor="mm")
            d.text((960 * s, 700 * s), "results/sim_log.txt  ·  tb_replay and tb_replay_adversarial", font=font("r", int(22 * s)), fill=rgba(DIM), anchor="mm")
        self.l1 = ss_layer(b1)
        tot = data.summary_totals().split("|"); mdl, rtl, bas = [x.strip() for x in tot[2:5]]; self.cmp = (mdl, rtl, bas)
        def b2(d, s):
            vals = [("software model", mdl, CY), ("RTL (real Verilog)", rtl, GN), ("threshold-only baseline", bas, AM)]
            d.text((960 * s, 170 * s), "15 scenarios · 159 checks · identical stimulus", font=font("b", int(34 * s)), fill=rgba(WHITE), anchor="mm")
            for i, (lab, v, col) in enumerate(vals):
                a, b = [int(x) for x in v.split("/")]; y = 250 + i * 130
                d.text((150 * s, (y + 40) * s), lab, font=font("sb", int(30 * s)), fill=rgba(TXT), anchor="lm")
                d.rounded_rectangle([600 * s, (y + 8) * s, (600 + 1000) * s, (y + 72) * s], 12 * s, fill=rgba((20, 28, 48))); d.rounded_rectangle([600 * s, (y + 8) * s, (600 + 1000 * a / b) * s, (y + 72) * s], 12 * s, fill=rgba(col, 230))
                d.text((1640 * s, (y + 40) * s), f"{a}/{b}", font=font("d", int(40 * s)), fill=rgba(col), anchor="lm")
            d.text((960 * s, 665 * s), "RTL misses 2: a stimulus lasting ~240 ADC frames instead of one (scenario S06a)  ·  baseline misses are by design", font=font("m", int(24 * s)), fill=rgba(DIM), anchor="mm")
            d.text((960 * s, 705 * s), "experiments/results_v2/summary.md", font=font("r", int(22 * s)), fill=rgba(DIM), anchor="mm")
        self.l2 = ss_layer(b2)
        # noisy crossing (S07): baseline vs RTL
        m, r = data.v2_logs(); mm, rr = m["S07_noisy_crossing"], r["S07_noisy_crossing"]; s0, s1 = 40, 140; steps = list(range(s0, s1 + 1)); xs = [x * .5 for x in steps]
        tr = lambda xs_: sum(1 for a, b in zip(xs_[21:], xs_[22:]) if a != b); self.tb, self.tr_ = tr([x["bl_safe"] for x in mm]), tr([x["safe"] for x in rr])
        st = [dict(label="force code (noisy ±8 counts, slow rise)", xs=xs, ys=[mm[s]["code"] for s in steps], color=CY, ymin=2440, ymax=2680, h=2.4, yticks=[2560, 2304][:1], hlines=[(2560, RD, "FORCE_MAX 2560")], yfmt=lambda v: f"{int(v)}", kind="line"),
              dict(label=f"threshold-only baseline: {self.tb} toggles", xs=xs, ys=[mm[s]["bl_safe"] for s in steps], color=AM, ymin=-0.2, ymax=1.9, h=1.2, yticks=[0, 1], yfmt=lambda v: f"{int(v)}"),
              dict(label=f"hysteresis design (RTL): {self.tr_} inhibit", xs=xs, ys=[rr[s]["safe"] for s in steps], color=GN, ymin=-0.2, ymax=1.9, h=1.2, yticks=[0, 1], yfmt=lambda v: f"{int(v)}")]
        L, px, info = strip_chart(st, (CHX0, 165, CHX1, 700), (s0 * .5, s1 * .5), list(range(20, 36, 2)), "time (ms) · each replay step = 500 µs · scenario S07", lambda v: f"{int(v)}")
        self.l3, self.px3, self.xr3 = L, px, (s0 * .5, s1 * .5)
        self.l3tag = tag("NOISY CROSSING NEAR THE LIMIT", "experiments/results_v2  ·  model log (baseline) and RTL log")
        # latency bars (results/sim_log.txt RESULT lines)
        lat = {}
        for l in res:
            m_ = re.match(r"RESULT (\w+) min=(\d+) max=(\d+)", l)
            if m_: lat[m_.group(1)] = (int(m_.group(2)), int(m_.group(3)))
        frame = int(re.search(r"= (\d+) clk", [l for l in res if l.startswith("INFO")][0]).group(1)); self.lat, self.adc_frame = lat, frame
        ml = data.ml()["inference_us_tree_walk"]
        rows = [("sample valid → PWM low", lat["sample_valid_to_pwm_low_cycles"], GN), ("e-stop → PWM low", lat["estop_to_pwm_low_cycles"], RD), ("one ADC frame (SPI)", (frame, frame), CY), ("ADC input change → PWM low", lat["adc_input_change_to_pwm_low_cycles"], CY)]
        def b4(d, s):
            lo, hi = 3, 300; X0, X1 = 520, 1380; lx = lambda c: X0 + (X1 - X0) * (math.log10(c) - math.log10(lo)) / (math.log10(hi) - math.log10(lo))
            for tk in (4, 10, 100, 200):
                d.line([(lx(tk) * s, 200 * s), (lx(tk) * s, 640 * s)], fill=rgba(EDGE, 150), width=int(2 * s)); d.text((lx(tk) * s, 652 * s), f"{tk} clk", font=font("sb", int(20 * s)), fill=rgba(DIM), anchor="ma")
            for i, (lab, (a, b), col) in enumerate(rows):
                y = 215 + i * 105; d.text((140 * s, (y + 25) * s), lab, font=font("sb", int(28 * s)), fill=rgba(TXT), anchor="lm")
                d.rounded_rectangle([lx(a) * s - (6 * s if a == b else 0), (y + 4) * s, lx(b) * s + (6 * s if a == b else 0), (y + 46) * s], 8 * s, fill=rgba(col, 230))
                txt = f"{a} clk = {a * 20} ns" if a == b else f"{a}–{b} clk = {a * 20 / 1000:.2f}–{b * 20 / 1000:.2f} µs"
                d.text((max(lx(b), lx(a)) * s + 20 * s, (y + 25) * s), txt, font=font("b", int(26 * s)), fill=rgba(WHITE), anchor="lm")
            d.text((960 * s, 700 * s), "RTL simulation at 50 MHz (1 clk = 20 ns)  ·  the input-change figure is dominated by waiting for the next ADC frame  ·  log scale", font=font("r", int(21 * s)), fill=rgba(DIM), anchor="mm")
            d.text((960 * s, 735 * s), "results/sim_log.txt", font=font("r", int(21 * s)), fill=rgba(DIM), anchor="mm")
        self.l4 = ss_layer(b4)
        fs = open(data.P + "experiments/validation/results_v2/frame_summary.md").read(); self.fr_tot = int(re.search(r"TOTAL \| (\d+) \| (\d+)", fs).group(1)); self.fr_mm = int(re.search(r"TOTAL \| (\d+) \| (\d+)", fs).group(2))
        se = json.load(open(data.P + "experiments/validation/results_v2/step_expansion_result.json")); self.se = se
        step_mm = int(data.summary_totals().split("|")[5].strip().split("/")[0])
        def b5(d, s):
            cards = [(f"{self.fr_tot}", "frame-by-frame comparisons", f"{self.fr_mm} differences · model vs RTL · 9 fault patterns", GN), (f"{se['steps_compared']}", "step comparisons after 240× expansion", f"{se['mismatches']} differences · same stimulus granularity", GN), (f"{step_mm}", "step-level differences remain", "explained by granularity, NOT removed", AM)]
            for i, (big, lab, sub, col) in enumerate(cards):
                x = 110 + i * 585; d.rounded_rectangle([x * s, 200 * s, (x + 555) * s, 600 * s], 24 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.text(((x + 277) * s, 320 * s), big, font=font("d", int(110 * s)), fill=rgba(col), anchor="mm"); d.text(((x + 277) * s, 420 * s), lab, font=font("sb", int(27 * s)), fill=rgba(WHITE), anchor="mm")
                for j, ln in enumerate(wrap(sub, "m", 24, 480)): d.text(((x + 277) * s, (475 + j * 32) * s), ln, font=font("m", int(24 * s)), fill=rgba(TXT), anchor="mm")
            d.text((960 * s, 665 * s), "experiments/validation/results_v2  ·  the model is a separate software re-implementation, written by the same author as the RTL", font=font("r", int(21 * s)), fill=rgba(DIM), anchor="mm")
        self.l5 = ss_layer(b5)
        mlr = data.ml(); self.acc, self.base = mlr["accuracy"], mlr["baseline_force_only"]["accuracy"]
        def b6(d, s):
            for i, (lab, v, col) in enumerate((("decision tree (force + features)", self.acc, CY), ("force-only baseline", self.base, AM))):
                y = 270 + i * 140; d.text((150 * s, (y + 45) * s), lab, font=font("sb", int(30 * s)), fill=rgba(TXT), anchor="lm")
                d.rounded_rectangle([700 * s, (y + 8) * s, 1600 * s, (y + 82) * s], 12 * s, fill=rgba((20, 28, 48))); d.rounded_rectangle([700 * s, (y + 8) * s, (700 + 900 * v) * s, (y + 82) * s], 12 * s, fill=rgba(col, 230))
                d.text((1640 * s, (y + 45) * s), f"{v * 100:.1f} %", font=font("d", int(44 * s)), fill=rgba(col), anchor="lm")
            d.rounded_rectangle([500 * s, 560 * s, 1420 * s, 625 * s], 16 * s, fill=rgba((40, 28, 8)), outline=rgba(AM), width=int(2 * s)); d.text((960 * s, 592 * s), "SIMULATED DATASET  ·  advisory path only  ·  results/ml_results.json", font=font("b", int(26 * s)), fill=rgba(AM), anchor="mm")
        self.l6 = ss_layer(b6)
        lim = ["No physical hardware: FPGA, sensor, driver and motor were never run together", "Inputs are synthetic code sequences; the ADC is a behavioural model", "The AI dataset is simulated; no recorded sensor data", f"{step_mm} step-level model-vs-RTL differences remain (explained, not removed)", "Software model and RTL come from the same author's reading of the design", "The Wokwi software demo has NOT been run: it is unvalidated"]
        def b7(d, s):
            d.rounded_rectangle([160 * s, 160 * s, 1760 * s, 730 * s], 24 * s, fill=rgba((26, 20, 10)), outline=rgba(AM), width=int(3 * s))
            d.text((960 * s, 215 * s), "WHAT THIS DOES NOT ESTABLISH", font=font("d", int(44 * s)), fill=rgba(AM), anchor="mm")
            for i, tx in enumerate(lim):
                y = 290 + i * 70; d.ellipse([210 * s, (y - 9) * s, 228 * s, (y + 9) * s], fill=rgba(AM)); d.text((250 * s, y * s), tx, font=font("m", int(30 * s)), fill=rgba(TXT), anchor="lm")
        self.l7 = ss_layer(b7)
    def draw(self, base, t):
        c = self.cur(t)
        if c < 0: return
        a = self.appear(t, c, 0.5)
        if c == 3:
            blit(base, self.l3tag, a); p = clamp((t - self.t0(3) - 0.5) / max(.5, (self.t1(3) - self.t0(3)) * .6)); x0 = self.px3(self.xr3[0]); x1 = self.px3(self.xr3[1]); blit(base, wipe(self.l3, x0, x0 + (x1 - x0) * p), a); return
        L = {0: self.l0, 1: self.l1, 2: self.l2, 4: self.l4, 5: self.l5, 6: self.l6, 7: self.l7}[c]
        if c == 0: blit(base, L, a)
        else: blit(base, L, a)

# ---------------------------------------------------------------- Scene 7: end-to-end workflow
class S7(Scene):
    def build(self):
        x0, x1 = 200, 1720; self.x0, self.x1 = x0, x1; frame = 104
        self.px = lambda c: x0 + (760 - x0) * c / frame
        def base_l(d, s):
            y = 300; px = self.px
            d.rounded_rectangle([x0 * s, (y - 40) * s, px(frame) * s, (y + 40) * s], 12 * s, fill=rgba((10, 50, 64)), outline=rgba(CY), width=int(3 * s))
            d.text(((x0 + px(frame)) / 2 * s, y * s), "one ADC frame: 104 clk = 2.08 µs", font=font("b", int(28 * s)), fill=rgba(WHITE), anchor="mm")
            d.line([(px(frame) * s, (y - 80) * s), (px(frame) * s, (y + 180) * s)], fill=rgba(GN), width=int(4 * s)); d.text((px(frame) * s, (y - 100) * s), "sample_valid", font=font("monob", int(26 * s)), fill=rgba(GN), anchor="mm")
        self.base_l = ss_layer(base_l)
        st = [("input_conditioning", 1, CY), ("force_lut", 2, CY), ("safety_governor", 3, RD), ("pwm_generator", 4, GN)]; self.st = st
        def stages(i):
            def f(d, s):
                y = 480; xs = 760
                for j, (n, k, col) in enumerate(st[:i]):
                    bx = xs + j * 270; d.rounded_rectangle([bx * s, y * s, (bx + 250) * s, (y + 100) * s], 16 * s, fill=rgba((10, 20, 38)), outline=rgba(col), width=int(3 * s))
                    d.text(((bx + 125) * s, (y + 34) * s), n, font=font("monob", int(20 * s)), fill=rgba(WHITE), anchor="mm"); d.text(((bx + 125) * s, (y + 72) * s), f"+{k} clk = {k * 20} ns", font=font("b", int(24 * s)), fill=rgba(col), anchor="mm")
                    if j: arrow(d, [((bx - 20) * s, (y + 50) * s), (bx * s, (y + 50) * s)], rgba(col), int(3 * s), 12 * s)
            return glow(ss_layer(f), 8, 0.6)
        self.stages = [stages(i) for i in range(5)]
        def out(d, s):
            d.rounded_rectangle([420 * s, 650 * s, 1500 * s, 760 * s], 20 * s, fill=rgba((40, 12, 20)), outline=rgba(RD), width=int(3 * s))
            d.text((960 * s, 692 * s), "4 clock cycles = 80 ns after a valid sample: PWM is low", font=font("b", int(34 * s)), fill=rgba(WHITE), anchor="mm"); d.text((960 * s, 733 * s), "if any limit is exceeded  ·  zero jitter on this path in simulation", font=font("m", int(24 * s)), fill=rgba(TXT), anchor="mm")
        self.out = ss_layer(out)
        def ai(d, s):
            d.rounded_rectangle([420 * s, 790 * s, 1500 * s, 850 * s], 16 * s, fill=rgba((16, 12, 34)), outline=rgba(VI), width=int(3 * s)); d.text((960 * s, 820 * s), "the AI can advise, but it cannot override", font=font("b", int(28 * s)), fill=rgba(VI), anchor="mm")
        self.ai = ss_layer(ai); self.dot = dot_sprite(WHITE, 9)
    def draw(self, base, t):
        blit(base, self.base_l, self.appear(t, 0, 0.6))
        if t >= self.t0(1):
            n = int(clamp((t - self.t0(1)) / (self.t1(1) - self.t0(1))) * 4.999)
            blit(base, self.stages[min(4, max(1, n + 1 if t < self.t1(1) else 4))], 1.0)
        if t >= self.t0(2): blit(base, self.out, self.appear(t, 2, 0.6)); blit(base, self.ai, self.appear(t, 2, 0.6, 2.0))
        # clock-cycle counter
        if t >= self.t0(1):
            cyc = int(clamp((t - self.t0(1)) / (self.t1(1) - self.t0(1))) * 4.0 + 0.0001)
            lay = new_layer(); ImageDraw.Draw(lay).text((1300, 420), f"cycles since sample_valid:  {cyc if t < self.t1(1) else 4}", font=font("monob", 30), fill=rgba(GN), anchor="mm"); blit(base, lay, 1.0)

# ---------------------------------------------------------------- Scene 8: closing
class S8(Scene):
    def build(self):
        cards = [("AI is advisory only", "always-wrong-AI replay: 1,800 vectors, 0 violations", VI), ("Slope-predictive pre-limit in plain hardware", "RTL = reference model on 4,720 vectors, 0 mismatches", AM),
                 ("Self-checking AI link", "checksum · class/inverse check · heartbeat timeout · FPGA-only fallback", CY), ("Instant PWM kill, latched fail-safe stop", "4–5 cycle path in simulation", RD), ("T_FPGA, T_ML and jitter reported separately", "never blended into one number", GN)]
        def cd(d, s):
            for i, (a, b, col) in enumerate(cards):
                y = 160 + i * 112; d.rounded_rectangle([150 * s, y * s, 1770 * s, (y + 96) * s], 18 * s, fill=rgba(PANEL), outline=rgba(col), width=int(3 * s))
                d.ellipse([180 * s, (y + 30) * s, 216 * s, (y + 66) * s], fill=rgba(col)); d.text((250 * s, (y + 32) * s), a, font=font("b", int(32 * s)), fill=rgba(WHITE), anchor="lm"); d.text((250 * s, (y + 70) * s), b, font=font("m", int(23 * s)), fill=rgba(TXT), anchor="lm")
            d.text((960 * s, 750 * s), "design-level technical descriptions  ·  not a prior-art or patentability conclusion", font=font("sb", int(24 * s)), fill=rgba(DIM), anchor="mm")
        self.cards = ss_layer(cd)
        nxt = [("Quartus synthesis and timing", "not run"), ("board bring-up on the DE2-115", "not run"), ("recorded FSR sensor data", "not collected"), ("Wokwi software demo", "prepared, NOT yet run")]
        def nx(d, s):
            d.text((960 * s, 190 * s), "PROPOSED NEXT STEPS", font=font("d", int(54 * s)), fill=rgba(AM), anchor="mm"); d.text((960 * s, 255 * s), "none of these has been done", font=font("sb", int(28 * s)), fill=rgba(DIM), anchor="mm")
            for i, (a, b) in enumerate(nxt):
                y = 320 + i * 100; d.rounded_rectangle([360 * s, y * s, 1560 * s, (y + 80) * s], 18 * s, fill=rgba((26, 20, 10)), outline=rgba(AM), width=int(3 * s)); d.text((400 * s, (y + 40) * s), a, font=font("b", int(32 * s)), fill=rgba(WHITE), anchor="lm"); d.text((1520 * s, (y + 40) * s), b, font=font("sb", int(26 * s)), fill=rgba(AM), anchor="rm")
        self.nx = ss_layer(nx)
        def title(d, s):
            d.text((960 * s, 480 * s), "TACTILE REFLEX SYSTEM", font=font("d", int(104 * s)), fill=rgba(WHITE), anchor="mm"); d.text((960 * s, 575 * s), "an FPGA safety reflex  ·  tested in simulation", font=font("m", int(38 * s)), fill=rgba(CY), anchor="mm")
        self.title_layer = glow(ss_layer(title), 20, 0.8)
        def chipg(d, s):
            cx, cy, r = 960 * s, 300 * s, 54 * s
            for i in range(-3, 4):
                for sx in (-1, 1):
                    d.line([(cx + sx * r, cy + i * 15 * s), (cx + sx * (r + 22 * s), cy + i * 15 * s)], fill=rgba(CY, 200), width=int(4 * s)); d.line([(cx + i * 15 * s, cy + sx * r), (cx + i * 15 * s, cy + sx * (r + 22 * s))], fill=rgba(CY, 200), width=int(4 * s))
            d.rounded_rectangle([cx - r, cy - r, cx + r, cy + r], 12 * s, fill=rgba((10, 24, 46)), outline=rgba(CY), width=int(4 * s)); d.text((cx, cy), "FPGA", font=font("monob", int(24 * s)), fill=rgba(CY), anchor="mm")
        self.chipg = glow(ss_layer(chipg), 16, 1.2)
    def draw(self, base, t):
        c = self.cur(t)
        if c == 0 or c < 0:
            blit(base, self.chipg, self.appear(t, 0, 0.8)); blit(base, self.title_layer, self.appear(t, 0, 1.0)); return
        if c in (1, 2): blit(base, self.cards, self.appear(t, 1, 0.8))
        if c == 3:
            out = ease(prog(t, self.t1(3) + 1.0, 0.7)); tail = ease(prog(t, self.t1(3) + 1.9, 1.2))
            blit(base, self.nx, self.appear(t, 3, 0.8) * (1 - out))
            if tail > 0: blit(base, self.chipg, tail); blit(base, self.title_layer, tail)
