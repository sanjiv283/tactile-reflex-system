"""QA for the demo video. Usage: python3 qa.py claims | python3 qa.py media <mp4>"""
import sys, os, re, json, subprocess, wave
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import data
HERE = "/home/user/tactile-reflex-system/demo_video/"
def claims():
    tb, res = data.sim_log(); core = [v for k, v in tb.items() if "replay" not in k]; ok = True
    def chk(name, cond):
        nonlocal ok; ok &= bool(cond); print(("PASS " if cond else "FAIL ") + name)
    chk("175 directed checks over 12 testbenches, 0 failures", sum(v[0] for v in core) == 175 and len(core) == 12 and all(v[1] == 0 for v in tb.values()))
    txt = "\n".join(res)
    chk("replay: 1,800 vectors both modes, 0 safe-state violations, 0 cmd above LUT", len(re.findall(r"vectors=1800", txt)) == 2 and len(re.findall(r"violations: safe_state=0 cmd_above_lut=0", txt)) == 2)
    chk("predictive RTL vs reference model: 4,720 vectors, 0 mismatches", "vectors=4720" in txt and "mismatches=0" in txt)
    chk("logic path 4 cycles, e-stop 5 cycles, input change 105-192", "sample_valid_to_pwm_low_cycles min=4 max=4" in txt and "estop_to_pwm_low_cycles min=5 max=5" in txt and "adc_input_change_to_pwm_low_cycles min=105 max=192" in txt)
    chk("ADC frame 104 clk = 2080 ns", "ADC frame period = 104 clk cycles (2080 ns" in txt)
    tot = [x.strip() for x in data.summary_totals().split("|")]
    chk("experiments: model 159/159, RTL 157/159, baseline 93/159, step mismatches 13/839", tot[1] == "159" and tot[2] == "159/159" and tot[3] == "157/159" and tot[4] == "93/159" and tot[5] == "13/839")
    o = data.trace("trace_override"); f = next(i for i, v in enumerate(o["force_code"]) if v >= 2560)
    chk("override trace: AI class 2 throughout, force limit crossed then safe_state +2 / PWM low +3 clk", set(o["ai_class"]) == {2} and next(i for i, v in enumerate(o["safe_state"]) if v) - f == 2 and next(i for i, v in enumerate(o["pwm_out"]) if i > f - 50 and v == 0) - f == 3)
    e = data.trace("trace_estop"); chk("e-stop trace: safe_state at +4, PWM low at +5 clk", next(i for i, v in enumerate(e["safe_state"]) if v) == 4 and next(i for i, v in enumerate(e["pwm_out"]) if v == 0) == 5)
    m, r = data.v2_logs(); mm, rr = m["S08_fast_ramp"], r["S08_fast_ramp"]
    p = next(i for i in range(21, len(rr)) if rr[i]["safe"]); q = next(i for i in range(21, len(mm)) if mm[i]["code"] >= 2560)
    chk("S08: predictive trip at code 2015 (trip bit 4), limit crossed at 2569, 12 steps = 6.0 ms", mm[p]["code"] == 2015 and (rr[p]["trip"] >> 4) & 1 and mm[q]["code"] == 2569 and q - p == 12)
    m4, r4 = m["S04_hysteresis"], r["S04_hysteresis"]
    chk("S04: 2304 still inhibited, 2303 released", any(m4[i]["code"] == 2304 and r4[i]["safe"] == 1 and i > 100 for i in range(len(m4))) and any(m4[i]["code"] == 2303 and r4[i]["safe"] == 0 for i in range(len(m4))))
    m7, r7 = m["S07_noisy_crossing"], r["S07_noisy_crossing"]; tr = lambda xs: sum(1 for a, b in zip(xs[21:], xs[22:]) if a != b)
    chk("S07: baseline 7 toggles, RTL 1", tr([x["bl_safe"] for x in m7]) == 7 and tr([x["safe"] for x in r7]) == 1)
    a, b = data.frames("ferr_001"), data.frames("ferr_004")
    chk("1 bad frame (after the reset-hold/clear frames 0-6): exactly frame 17 inhibited, sensor_fault never set", [x["frame"] for x in a if x["safe"] and x["frame"] >= 14] == [17] and not any(x["sfault"] for x in a) and [x["frame"] for x in a if x["safe"] and x["frame"] < 14] == [0, 1, 2, 3])
    chk("4 bad frames: fault latched from frame 20 until clear at 29", [x["frame"] for x in b if x["sfault"]] == list(range(20, 29)))
    src = open(data.P + "rtl/fault_handler.v").read(); chk("watchdog WD_CYCLES = 2000", "WD_CYCLES     = 2000" in src)
    drp = [int(x) for x in re.findall(r"clocks_force_to_sensor_fault=(\d+)", open(data.P + "experiments/validation/results_v2/dropout_and_frame_count.txt").read())]; chk("forced-dropout runs 1898-1985 clk", min(drp) == 1898 and max(drp) == 1985)
    fs = open(data.P + "experiments/validation/results_v2/frame_summary.md").read(); chk("577 frame comparisons, 0 differences", "TOTAL | 577 | 0" in fs)
    se = json.load(open(data.P + "experiments/validation/results_v2/step_expansion_result.json")); chk("839 step comparisons, 0 differences", se["steps_compared"] == 839 and se["mismatches"] == 0)
    pr = data.pred()["test"]; chk("pred: 25/25 early, mean lead 5.72 ms, 10/155 false early = 6.5%", pr["early_trip"] == 25 == pr["crossing_episodes"] and pr["lead_ms_mean"] == 5.72 and pr["false_early"] == 10 and pr["noncrossing_episodes"] == 155 and round(pr["false_early_rate"] * 100, 1) == 6.5)
    ml = data.ml(); w = ml["inference_us_tree_walk"]; chk("tree walk mean 11.6, max 96.5 us; accuracy 91.9% vs 85.4%", round(w["mean"], 1) == 11.6 and round(w["max"], 1) == 96.5 and round(ml["accuracy"] * 100, 1) == 91.9 and round(ml["baseline_force_only"]["accuracy"] * 100, 1) == 85.4)
    lut = data.lut(); chk("LUT 180 at idx 0, 60 at idx 96, 0 at idx 160", lut[0] == 180 and lut[96] == 60 and lut[160] == 0)
    g = open(data.P + "rtl/safety_governor.v").read(); chk("governor defaults FORCE_MAX 0xA00=2560, FORCE_REL 0x900=2304", "FORCE_MAX = 12'hA00" in g and "FORCE_REL = 12'h900" in g)
    c = open(data.P + "rtl/input_conditioning.v").read(); chk("RAIL_HI 0xFF0", "RAIL_HI = 12'hFF0" in c)
    print("CLAIMS:", "ALL PASS" if ok else "SOME FAILED"); return ok
def media(mp4):
    pr = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", mp4], capture_output=True, text=True).stdout)
    v = [s for s in pr["streams"] if s["codec_type"] == "video"][0]; a = [s for s in pr["streams"] if s["codec_type"] == "audio"][0]
    print(f"video {v['codec_name']} {v['width']}x{v['height']} {v['r_frame_rate']} frames={v.get('nb_frames')} dur={float(v['duration']):.3f}s | audio {a['codec_name']} {a['sample_rate']}Hz ch={a['channels']} dur={float(a['duration']):.3f}s | file {os.path.getsize(mp4)/1e6:.1f} MB")
    tl = json.load(open(HERE + "audio/timeline.json")); print(f"timeline total {tl['total']:.3f}s  video-audio delta {abs(float(v['duration']) - float(a['duration'])) * 1000:.0f} ms  video-vs-timeline delta {abs(float(v['duration']) - tl['total']) * 1000:.0f} ms")
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", mp4, "-ac", "1", "-ar", "16000", "-f", "s16le", "-"], capture_output=True).stdout
    x = np.frombuffer(raw, np.int16).astype(np.float32) / 32768; sr = 16000; hop = 160
    env = np.sqrt(np.convolve(x * x, np.ones(hop) / hop, "same"))[::hop]; thr_hi = np.percentile(env, 40) + 0.35 * (np.percentile(env, 97) - np.percentile(env, 40))
    late = []; onsets = 0
    for sc in tl["scenes"]:
        for b in sc["beats"]:
            t0 = sc["start"] + b["t0"]; i0 = int((t0 - 0.35) * 100); i1 = int((t0 + 0.6) * 100); seg = env[i0:i1]
            idx = np.argmax(seg > thr_hi) if (seg > thr_hi).any() else None
            if idx is None: late.append((sc["id"], b["t0"], "no speech energy")); continue
            onset = (i0 + idx) / 100; onsets += 1; late.append((sc["id"], b["t0"], round(onset - t0, 2)))
    offs = [d for _, _, d in late if isinstance(d, float)]
    print(f"speech onsets found {len(offs)}/{sum(len(s['beats']) for s in tl['scenes'])}; onset minus scripted start: mean {np.mean(offs):+.3f}s  min {min(offs):+.3f}s  max {max(offs):+.3f}s")
    bad = [l for l in late if not isinstance(l[2], float) or abs(l[2]) > 0.30]; print("beats outside ±0.30 s:", bad if bad else "none")
    clip = int((np.abs(x) > 0.999).sum()); print("clipped samples:", clip, " peak:", round(float(np.abs(x).max()), 3))
    sil = []; 
    for sc in tl["scenes"]:
        g = sc["start"]; 
    return not bad
if __name__ == "__main__":
    if sys.argv[1] == "claims": sys.exit(0 if claims() else 1)
    else: sys.exit(0 if media(sys.argv[2]) else 1)
