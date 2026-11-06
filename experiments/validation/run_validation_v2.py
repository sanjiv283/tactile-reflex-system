#!/usr/bin/env python3
"""Frame-granular model-vs-RTL validation. Run from the repository root: python3 experiments/validation/run_validation.py
V2 copy: writes only under experiments/validation/results_v2/ and build_v2/. Existing files are not modified."""
import os, re, subprocess, json, collections
V = 'experiments/validation'; R = f'{V}/results_v2'; B = f'{V}/build_v2'
os.makedirs(R, exist_ok=True); os.makedirs(B + '/stim', exist_ok=True)
run = lambda c, **k: subprocess.run(c, check=True, capture_output=True, text=True, **k).stdout

def word(code, ferr=0, es=1, fc=0): return code | ferr << 13 | es << 14 | fc << 15
def pattern(n_bad, bad_code=400, ferr=1):
    w = [word(400)] * 4 + [word(400, fc=1)] * 3 + [word(400)] * 10      # reset hold, operator clear, settle
    w += [word(bad_code, ferr=ferr)] * n_bad + [word(400)] * 8           # invalid burst, then valid frames
    w += [word(400, fc=1)] * 3 + [word(400)] * 5                         # operator clear, recovery
    return w
PATS = collections.OrderedDict()
for n in (1, 2, 3, 4, 5, 20, 240): PATS[f'ferr_{n:03d}'] = pattern(n)
for n in (1, 4): PATS[f'rail_{n:03d}'] = pattern(n, bad_code=4095, ferr=0)
for k, w in PATS.items():
    open(f'{B}/stim/{k}.hex', 'w').write(''.join('%04X\n' % x for x in w))

# model with the prediction window = 1442 frames (150000 clk / 104 clk per frame) so frame k == model step k
hdr = open('experiments/wokwi/reflex_model.h').read()
hdr2 = re.sub(r'#define PRED_WIN_STEPS\s+6', '#define PRED_WIN_STEPS  1442', hdr); assert hdr2 != hdr
# wcnt is uint8_t in the original header, so a window > 255 can never be reached: widen it in this COPY only
hdr3 = '#define SLOT_CLK 104\n' + hdr2.replace('seeded, bad, wcnt;', 'seeded, bad;\n    uint16_t wcnt;'); assert hdr3 != hdr2; hdr2 = hdr3
open(f'{B}/reflex_model.h', 'w').write(hdr2)
run(['cp', 'experiments/wokwi/force_lut_table.h', B + '/'])
run(['gcc', '-Wall', '-Wextra', f'-I{B}', '-o', f'{B}/model_frames', f'{V}/model_frames.c'])
run(['iverilog', '-g2005', '-o', f'{B}/tb_frames.vvp', 'tb/ad7476_model.v', f'{V}/tb_frames.v'] + sorted(__import__('glob').glob('rtl/*.v')))

def parse(txt):
    d = collections.defaultdict(list)
    for l in txt.splitlines():
        if l.startswith('FRM'): f = l.split(','); d[f[1]].append(tuple(int(x) for x in f[3:]))
    return d
mod, rtl = collections.defaultdict(list), collections.defaultdict(list)
for k in PATS:
    mod.update(parse(run([f'{B}/model_frames', f'{B}/stim/{k}.hex', k])))
    rtl.update(parse(run(['vvp', f'{B}/tb_frames.vvp', f'+STIM={B}/stim/{k}.hex', f'+ID={k}', '+MODE=0'])))
open(f'{R}/frame_rtl_log.txt', 'w').write('\n'.join(f'FRM,{k},{i},' + ','.join(map(str, r)) for k in rtl for i, r in enumerate(rtl[k])) + '\n')
open(f'{R}/frame_model_log.txt', 'w').write('\n'.join(f'FRM,{k},{i},' + ','.join(map(str, r)) for k in mod for i, r in enumerate(mod[k])) + '\n')
mm = []
for k in PATS:
    assert len(mod[k]) == len(rtl[k]) == len(PATS[k]), (k, len(mod[k]), len(rtl[k]))
    for i, (m, r) in enumerate(zip(mod[k], rtl[k])):
        if m != r: mm.append(dict(pattern=k, frame=i, model=dict(zip(('safe','cmd','trip','sfault','estop'), m)), rtl=dict(zip(('safe','cmd','trip','sfault','estop'), r))))
json.dump(mm, open(f'{R}/frame_mismatches.json', 'w'), indent=1)
extra = ''.join(run(['vvp', f'{B}/tb_frames.vvp', f'+MODE={m}']) for m in (1, 2))
open(f'{R}/dropout_and_frame_count.txt', 'w').write(extra)
rep = ['pattern | frames | mismatching frames', '-|-|-'] + [f"{k} | {len(PATS[k])} | {sum(1 for x in mm if x['pattern'] == k)}" for k in PATS]
rep.append(f'TOTAL | {sum(len(v) for v in PATS.values())} | {len(mm)}')
open(f'{R}/frame_summary.md', 'w').write('\n'.join(rep) + '\n\n' + extra)
print('\n'.join(rep)); print(extra)
for x in mm[:40]: print(x)
