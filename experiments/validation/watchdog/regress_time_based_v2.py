#!/usr/bin/env python3
"""V2: frame-level watchdog dropout regression for the time-based model (experiments/wokwi/reflex_model.h compiled with SLOT_CLK=104),
compared with the RTL (tb_frames_dropout.v). Run from the repo root. Writes only experiments/validation/watchdog/{build_v2,results_v2}/."""
import os, re, glob, subprocess, json
W = 'experiments/validation/watchdog'; B = W + '/build_v2'; R = W + '/results_v2'; os.makedirs(B + '/stim', exist_ok=True); os.makedirs(R, exist_ok=True)
run = lambda c: subprocess.run(c, check=True, capture_output=True, text=True).stdout
h = open('experiments/wokwi/reflex_model.h').read()
h = '#define SLOT_CLK 104\n' + re.sub(r'#define PRED_WIN_STEPS\s+6', '#define PRED_WIN_STEPS  1442', h).replace('seeded, bad, wcnt;', 'seeded, bad;\n    uint16_t wcnt;')
open(B + '/reflex_model.h', 'w').write(h); run(['cp', 'experiments/wokwi/force_lut_table.h', B + '/'])
run(['gcc', '-Wall', '-Wextra', f'-I{B}', '-o', B + '/mf', 'experiments/validation/model_frames.c'])
run(['iverilog', '-g2005', '-o', B + '/tb.vvp', 'tb/ad7476_model.v', W + '/tb_frames_dropout.v'] + sorted(glob.glob('rtl/*.v')))
word = lambda c, a=0, f=0: c | a << 12 | 1 << 14 | f << 15
parse = lambda t: [tuple(int(x) for x in l.split(',')[3:]) for l in t.splitlines() if l.startswith('FRM')]
rows = ['absent frames | RTL first sensor_fault slot | model first sensor_fault slot | mismatching frames', '-|-|-|-']; tot = 0; detail = {}
for k in (1, 2, 3, 10, 18, 19, 20, 21, 25, 40):
    w = [word(400)] * 4 + [word(400, f=1)] * 3 + [word(400)] * 10 + [word(400, a=1)] * k + [word(400)] * 8 + [word(400, f=1)] * 3 + [word(400)] * 5
    f = f'{B}/stim/d{k:03d}.hex'; open(f, 'w').write(''.join('%04X\n' % x for x in w))
    m = parse(run([B + '/mf', f, 'x'])); r = parse(run(['vvp', B + '/tb.vvp', f'+STIM={f}', '+ID=x']))
    first = lambda rows_: next((i - 16 for i, x in enumerate(rows_) if i >= 17 and x[3]), None)   # 1-based slot of the dropout (stimulus word 17 is the first absent)
    bad = [dict(frame=i, model=a, rtl=b) for i, (a, b) in enumerate(zip(m, r)) if a != b]; detail[k] = bad; tot += len(bad)
    rows.append(f'{k} | {first(r)} | {first(m)} | {len(bad)}')
rows.append(f'TOTAL | | | {tot}'); open(R + '/dropout_regression.md', 'w').write('\n'.join(rows) + '\n'); json.dump(detail, open(R + '/dropout_mismatches.json', 'w'), indent=1); print('\n'.join(rows))
