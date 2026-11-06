#!/usr/bin/env python3
"""Frame-granular watchdog comparison. Run from the repository root: python3 experiments/validation/watchdog/run_watchdog_check.py
Compares the RTL (WD_CYCLES=2000 clk, ADC frame 104 clk) with the model at WD_STEPS = 2 (shipped), 19 and 20 frame slots.
Writes only under experiments/validation/watchdog/."""
import os, re, glob, subprocess, json, collections
W = 'experiments/validation/watchdog'; B = W + '/build'; R = W + '/results'
os.makedirs(B + '/stim', exist_ok=True); os.makedirs(R, exist_ok=True)
run = lambda c: subprocess.run(c, check=True, capture_output=True, text=True).stdout
word = lambda code, absent=0, fc=0: code | absent << 12 | 1 << 14 | fc << 15
def pat(k_absent):
    w = [word(400)] * 4 + [word(400, fc=1)] * 3 + [word(400)] * 10 + [word(400, absent=1)] * k_absent + [word(400)] * 8
    return w + [word(400, fc=1)] * 3 + [word(400)] * 5
KS = (1, 2, 3, 10, 18, 19, 20, 21, 25, 40)
for k in KS: open(f'{B}/stim/drop_{k:03d}.hex', 'w').write(''.join('%04X\n' % x for x in pat(k)))
hdr = open('experiments/wokwi/reflex_model.h').read()
hdr = re.sub(r'#define PRED_WIN_STEPS\s+6', '#define PRED_WIN_STEPS  1442', hdr).replace('seeded, bad, wd, wcnt;', 'seeded, bad, wd;\n    uint16_t wcnt;')
models = {}
for ws in (2, 19, 20):
    d = f'{B}/m{ws}'; os.makedirs(d, exist_ok=True)
    open(f'{d}/reflex_model.h', 'w').write(re.sub(r'#define WD_STEPS\s+2', f'#define WD_STEPS        {ws}', hdr))
    run(['cp', 'experiments/wokwi/force_lut_table.h', d + '/'])
    run(['gcc', '-Wall', '-Wextra', f'-I{d}', '-o', f'{d}/mf', 'experiments/validation/model_frames.c']); models[ws] = d
run(['iverilog', '-g2005', '-o', f'{B}/tb.vvp', 'tb/ad7476_model.v', f'{W}/tb_frames_dropout.v'] + sorted(glob.glob('rtl/*.v')))
def parse(t): return [tuple(int(x) for x in l.split(',')[3:]) for l in t.splitlines() if l.startswith('FRM')]
res = collections.OrderedDict(); lines = ['absent frames | RTL first sensor_fault frame (slots into dropout) | model WD=2 | WD=19 | WD=20 | mismatching frames WD=2 / 19 / 20', '-|-|-|-|-|-']
detail = {}
for k in KS:
    f = f'{B}/stim/drop_{k:03d}.hex'; r = parse(run(['vvp', f'{B}/tb.vvp', f'+STIM={f}', f'+ID=drop_{k:03d}']))
    start = 17; first = lambda rows: next((i - start + 1 for i, x in enumerate(rows) if i >= start and x[3]), None)   # 1-based slot of the dropout; sfault is field 3
    row = {'rtl': first(r)}; mm = {}
    for ws, d in models.items():
        m = parse(run([f'{d}/mf', f, f'drop_{k:03d}'])); row[ws] = first(m)
        mm[ws] = [dict(frame=i, model=dict(zip(('safe','cmd','trip','sfault','estop'), a)), rtl=dict(zip(('safe','cmd','trip','sfault','estop'), b))) for i, (a, b) in enumerate(zip(m, r)) if a != b]
    detail[k] = mm
    lines.append(f"{k} | {row['rtl']} | {row[2]} | {row[19]} | {row[20]} | {len(mm[2])} / {len(mm[19])} / {len(mm[20])}")
open(f'{R}/watchdog_frame_summary.md', 'w').write('\n'.join(lines) + '\n'); json.dump(detail, open(f'{R}/watchdog_mismatches.json', 'w'), indent=1)
print('\n'.join(lines))
