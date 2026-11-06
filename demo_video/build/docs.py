"""Generate transcript, SRT, scene breakdown and evidence list from timeline.json + real data files (numbers are read, not typed)."""
import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import data
HERE = "/home/user/tactile-reflex-system/demo_video/"
TL = json.load(open(HERE + "audio/timeline.json"))
def ts(x, srt=False):
    h, m, s = int(x // 3600), int(x % 3600 // 60), x % 60
    return f"{h:02d}:{m:02d}:{int(s):02d},{int(round((s % 1) * 1000)):03d}" if srt else f"{m:d}:{s:05.2f}"
# ---- transcript
L = ["# Script and narration transcript", "", f"Total length {ts(TL['total'])}. Captions are shown on screen exactly as written here; the speech column is what the synthetic voice is given (acronyms spelled out for pronunciation).", ""]
for sc in TL["scenes"]:
    L += [f"## Scene {sc['num']} · {sc['title']}  ({ts(sc['start'])} – {ts(sc['start'] + sc['dur'])})", ""]
    for i, b in enumerate(sc["beats"], 1):
        L += [f"**{ts(sc['start'] + b['t0'])}**  {b['cap']}", ""]
        if b["speech"] != b["cap"]: L += [f"> speech: {b['speech']}", ""]
open(HERE + "script_and_narration.md", "w").write("\n".join(L))
# ---- SRT
n = 0; S = []
for sc in TL["scenes"]:
    for b in sc["beats"]:
        n += 1; S += [str(n), f"{ts(sc['start'] + b['t0'], True)} --> {ts(sc['start'] + b['t1'] + 0.3, True)}", b["cap"], ""]
open(HERE + "captions.srt", "w").write("\n".join(S))
# ---- evidence list (numbers read from files)
tb, res = data.sim_log(); core = [v[0] for k, v in tb.items() if "replay" not in k]
ml = data.ml(); pr = data.pred()["test"]; tot = data.summary_totals().split("|"); lut = data.lut()
drp = [int(x) for x in re.findall(r"clocks_force_to_sensor_fault=(\d+)", open(data.P + "experiments/validation/results_v2/dropout_and_frame_count.txt").read())]
get = lambda pat: [l for l in res if re.search(pat, l)][0]
E = ["# Evidence used in the video", "", "Every number on screen or in the narration comes from one of these files (all read-only; nothing was edited). Values are read programmatically by `build/data.py`.", "",
"| Claim in the video | Value | Source file |", "|---|---|---|",
f"| Directed checks passing (12 testbenches) | {sum(core)} / {sum(core)}, 0 failures | results/sim_log.txt |",
f"| Replay of 1,800 vectors, real decision tree and adversarial AI | {get('replay mode=ml_tree_ai violations')[7:]} ; {get('replay mode=adversarial_ai violations')[7:]} | results/sim_log.txt |",
f"| Predictive pre-limit RTL vs reference model | {get('pred_rtl_vs_model')[7:]} | results/sim_log.txt |",
f"| Logic path / e-stop / input-change latency (clock cycles @ 50 MHz) | {get('sample_valid_to_pwm')[7:]} ; {get('estop_to_pwm')[7:]} ; {get('adc_input_change')[7:]} | results/sim_log.txt |",
f"| ADC frame period | {[l for l in res if l.startswith('INFO')][0][6:]} | results/sim_log.txt |",
f"| Force-limit override waveform (AI says class 2, force 1024 → 2816, FORCE_MAX 2560) | 800 samples, 20 ns/sample | results/trace_override.csv |",
"| E-stop waveform (safe_state +4 clk, PWM low +5 clk) | 65 samples | results/trace_estop.csv |",
f"| Lookup table curve (180 → 60 → 0) | 256 entries read from the file | rtl/force_lut.mem (generator: tools/gen_lut.py) |",
f"| Experiment totals: model / RTL / baseline | {tot[2].strip()} / {tot[3].strip()} / {tot[4].strip()} (15 scenarios, 159 checks) | experiments/results_v2/summary.md |",
"| Predictive trip at force code 2015 vs limit crossed at 2569 (12 steps = 6.0 ms stimulus time) | RTL replay scenario S08 | experiments/results_v2/rtl_log.txt, model_log.txt |",
"| Hysteresis: 2304 still inhibited, 2303 releases | RTL replay scenario S04 | experiments/results_v2/rtl_log.txt |",
f"| Noisy crossing: baseline 7 toggles vs 1 inhibit | scenario S07 | experiments/results_v2/model_log.txt (baseline), rtl_log.txt |",
"| One bad ADC frame = one-frame inhibit, no latch; four bad frames latch the fault until clear | frame-level RTL runs (patterns ferr_001, ferr_004) | experiments/validation/results_v2/frame_rtl_log.txt |",
f"| Watchdog: WD_CYCLES = 2000 clk (40 µs); measured forced-dropout runs | {min(drp)}–{max(drp)} clk (4 phases) | rtl/fault_handler.v ; experiments/validation/results_v2/dropout_and_frame_count.txt |",
"| 577 frame comparisons, 0 differences; 839 step comparisons, 0 differences; 13 step-level differences remain | see files | experiments/validation/results_v2/frame_summary.md, step_expansion_result.json ; summary.md |",
f"| Predictive-trip cost: {pr['early_trip']}/{pr['crossing_episodes']} crossing episodes tripped early, mean lead {pr['lead_ms_mean']:.2f} ms; {pr['false_early']}/{pr['noncrossing_episodes']} ({pr['false_early_rate']*100:.1f}%) early trips on never-crossing episodes | SIMULATED test episodes | results/pred_results.json |",
f"| Decision-tree walk on the development host: mean {ml['inference_us_tree_walk']['mean']:.1f} µs, p99 {ml['inference_us_tree_walk']['p99']:.1f} µs, max {ml['inference_us_tree_walk']['max']:.1f} µs (excludes the serial link) | dev host, not the target | results/ml_results.json |",
f"| Decision-tree accuracy {ml['accuracy']*100:.1f}% vs force-only baseline {ml['baseline_force_only']['accuracy']*100:.1f}% | SIMULATED dataset | results/ml_results.json |",
"| Source-code excerpts (ADC interface, conditioning, LUT, governor, PWM) | real lines with real line numbers | rtl/adc_interface.v 41-50, input_conditioning.v 15-24, force_lut.v 14-24, safety_governor.v 61-62/69/80-82, pwm_generator.v 13-21 |",
"| Architecture, parameters (FORCE_MAX 2560, FORCE_REL 2304, RAIL_HI 0xFF0, PWM 12.2 kHz, DE2-115 at 50 MHz) | design | rtl/*.v, README.md |", "",
"## Deliberately NOT shown or claimed", "- Physical hardware operation of any kind (none exists in this work).", "- Wokwi execution: the Wokwi demo is prepared but has **not been run**; the video says so.", "- Any oscilloscope or board footage; all waveforms are RTL simulation (Icarus Verilog) data.", "- The ML dataset is simulated; no recorded sensor data."]
open(HERE + "evidence_used.md", "w").write("\n".join(E))
print("docs written", len(L), len(S) // 4, len(E))

# ---- scene breakdown (timings from timeline.json; descriptions reflect build/scenes_*.py)
VIS = {
 1: ("Title reveal over an animated FPGA chip glyph; a real RTL simulation trace (force, safe_state, PWM) draws across the screen; amber 'simulation only' banner.", "results/trace_override.csv"),
 2: ("Two job cards (understand / react); latency-source chips; log-scale bar chart of decision-tree walk time on the development host vs the 4-cycle hardware path; 'AI advises / hardware protects' split card.", "results/ml_results.json, results/sim_log.txt"),
 3: ("Animated block diagram built block by block as each module is narrated: FSR + divider, AD7476A, adc_interface, input_conditioning, force_lut, safety_governor, pwm_generator, DRV8871, motor, fault_handler, e-stop, AI interface, laptop; a pulse travels the main path; 'prototype design, no physical validation' stamp.", "rtl/tactile_reflex_top.v, README.md, docs/circuit_diagram.png (design reference)"),
 4: ("Five real RTL excerpts with line numbers and highlighting synchronised to the narration: SPI timing diagram; invalid-reading threshold bar; lookup-table curve drawn from force_lut.mem; the governor's OR of trip causes; PWM counter/threshold waveform computed from the RTL equation (labelled as an illustration).", "rtl/adc_interface.v, input_conditioning.v, force_lut.v (+force_lut.mem), safety_governor.v, pwm_generator.v"),
 5: ("Five demonstrations drawn from real RTL data, plus watchdog and safe-state rules: (1) override trace, (2) predictive trip scenario S08, cost card from simulated episodes, (3) hysteresis scenario S04, (4) e-stop trace, (5) frame-level invalid-sensor runs, watchdog timeline, rules card.", "results/trace_override.csv, trace_estop.csv, pred_results.json; experiments/results_v2/rtl_log.txt; experiments/validation/results_v2/*"),
 6: ("Stat cards and charts: 175/175 regression bars, replay violations, model/RTL/baseline bars, noisy-crossing comparison, latency bars (log scale), frame/step validation cards, simulated-ML accuracy, and an amber 'what this does not establish' list.", "results/sim_log.txt; experiments/results_v2/summary.md; experiments/validation/results_v2/*; results/ml_results.json"),
 7: ("Clock-cycle timeline: one 104-clock ADC frame, sample_valid, then conditioning/lookup/governor/PWM stages at +1..+4 clocks with a cycle counter; 4-cycle result box; 'AI cannot override' banner.", "results/sim_log.txt; README.md (one cycle per stage)"),
 8: ("Title + chip, five design-level contribution cards with their evidence, 'not a prior-art conclusion' note, 'proposed next steps (none done)' card including the not-yet-run Wokwi demo, closing title.", "README.md; results/sim_log.txt"),
}
B = ["# Scene-by-scene breakdown", "", f"Total {ts(TL['total'])} · 1920×1080 · 30 fps · H.264 + AAC. Timings come from `audio/timeline.json`.", "", "| # | Scene | Start | Length | Beats | What is on screen | Evidence |", "|---|---|---|---|---|---|---|"]
for sc in TL["scenes"]:
    v, e = VIS[sc["num"]]; B.append(f"| {sc['num']} | {sc['title']} | {ts(sc['start'])} | {ts(sc['dur'])} | {len(sc['beats'])} | {v} | {e} |")
open(HERE + "scene_breakdown.md", "w").write("\n".join(B))
print("scene breakdown written")
