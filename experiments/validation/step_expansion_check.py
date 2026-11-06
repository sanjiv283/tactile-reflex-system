#!/usr/bin/env python3
"""Decisive test of the granularity explanation: expand every original 500 us step into FRAMES_PER_STEP model samples
(25000 clk / 104 clk = 240.4 frames) and compare the model's end-of-step output with the EXISTING step-level RTL log
(experiments/results/rtl_log.txt, read-only). Run from the repository root after run_validation.py (needs its build dir)."""
import collections, subprocess, json
B = 'experiments/validation/build'; R = 'experiments/validation/results'; FPS = 240
steps = collections.OrderedDict()
for l in open('experiments/results/model_log.txt'):
    f = l.strip().split(',')
    if f[0] == 'LOG': steps.setdefault(f[1], []).append(dict(code=int(f[4]), pres=int(f[5]), ferr=int(f[6]), es=int(f[7]), fc=int(f[8])))
rtl = collections.defaultdict(list)
for l in open('experiments/results/rtl_log.txt'):
    f = l.strip().split(','); rtl[f[1]].append((int(f[3]), int(f[4]), int(f[5])))
mm = []; total = 0; per = {}
for sid, st in steps.items():
    words = []
    for s in st: words += [s['code'] | (1 - s['pres']) << 12 | s['ferr'] << 13 | s['es'] << 14 | s['fc'] << 15] * FPS
    open(f'{B}/stim/exp_{sid}.hex', 'w').write(''.join('%04X\n' % w for w in words))
    out = subprocess.run([f'{B}/model_frames', f'{B}/stim/exp_{sid}.hex', sid], capture_output=True, text=True, check=True).stdout.splitlines()
    n = 0
    for i, r in enumerate(rtl[sid]):
        f = out[(i + 1) * FPS - 1].split(','); m = (int(f[3]), int(f[4]), int(f[5])); total += 1
        if m != r: mm.append(dict(scenario=sid, step=i, expanded_model=dict(zip(('safe', 'cmd', 'trip'), m)), rtl=dict(zip(('safe', 'cmd', 'trip'), r)))); n += 1
    per[sid] = n
json.dump(dict(frames_per_step=FPS, steps_compared=total, mismatches=len(mm), per_scenario=per, detail=mm), open(f'{R}/step_expansion_result.json', 'w'), indent=1)
print(f'frames/step={FPS} steps compared={total} mismatches={len(mm)}'); print(per)
for x in mm: print(x)
