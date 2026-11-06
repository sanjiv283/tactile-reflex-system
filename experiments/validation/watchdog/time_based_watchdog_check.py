#!/usr/bin/env python3
"""EVALUATES (does not apply) a time-based watchdog for the model: fault when the gap since the last valid sample reaches WD_CLK=2000 clk,
where a present sample is 104 clk after the previous one and an absent slot adds SLOT_CLK clocks of silence (104 frame-level, 25000 step-level). Patches COPIES of experiments/wokwi/
into experiments/validation/watchdog/build_td/ only. Run from the repository root after run_validation.py / run_watchdog_check.py."""
import os, re, glob, shutil, subprocess, json, collections
W = 'experiments/validation/watchdog'; T = W + '/build_td'; R = W + '/results'
shutil.rmtree(T, ignore_errors=True); os.makedirs(T + '/stim')
run = lambda c: subprocess.run(c, check=True, capture_output=True, text=True).stdout

def patched(slot_clk, window=None):
    h = open('experiments/wokwi/reflex_model.h').read(); n = len(h)
    h = h.replace('seeded, bad, wd, wcnt;', 'seeded, bad, wd, wcnt;\n    uint32_t gap;')
    h = h.replace('= s->wcnt = 0;', '= s->wcnt = 0; s->gap = 0;')
    old = '    if (in.present) s->wd = 0; else if (s->wd < WD_STEPS) s->wd++;\n'
    assert old in h
    # present sample: spacing to the previous one = accumulated silence + one ADC frame (104 clk); absent slot: adds slot_clk of silence
    h = h.replace(old, f'    int wd_hit; if (in.present) {{ wd_hit = s->gap + 104 >= 2000; s->gap = 0; }} else {{ s->gap += {slot_clk}; wd_hit = s->gap >= 2000; }}   /* time-based: WD_CLK=2000 */\n')
    old2 = 's->wd >= WD_STEPS ||'; assert old2 in h; h = h.replace(old2, 'wd_hit ||')
    if window: h = re.sub(r'#define PRED_WIN_STEPS\s+6', f'#define PRED_WIN_STEPS  {window}', h).replace('seeded, bad, wd, wcnt;', 'seeded, bad, wd;\n    uint16_t wcnt;')
    return h

# ---- (a) frame level: 104 clk per slot, compared with the RTL dropout runs
d = T + '/frame'; os.makedirs(d); open(d + '/reflex_model.h', 'w').write(patched(104, 1442)); shutil.copy('experiments/wokwi/force_lut_table.h', d)
run(['gcc', '-Wall', '-Wextra', f'-I{d}', '-o', f'{d}/mf', 'experiments/validation/model_frames.c'])
run(['iverilog', '-g2005', '-o', f'{T}/tb.vvp', 'tb/ad7476_model.v', f'{W}/tb_frames_dropout.v'] + sorted(glob.glob('rtl/*.v')))
word = lambda code, absent=0, fc=0: code | absent << 12 | 1 << 14 | fc << 15
parse = lambda t: [tuple(int(x) for x in l.split(',')[3:]) for l in t.splitlines() if l.startswith('FRM')]
lines = ['absent frames | mismatching frames (time-based model vs RTL)', '-|-']; tot = 0
for k in (1, 2, 3, 10, 18, 19, 20, 21, 25, 40):
    w = [word(400)] * 4 + [word(400, fc=1)] * 3 + [word(400)] * 10 + [word(400, absent=1)] * k + [word(400)] * 8 + [word(400, fc=1)] * 3 + [word(400)] * 5
    f = f'{T}/stim/drop_{k:03d}.hex'; open(f, 'w').write(''.join('%04X\n' % x for x in w))
    m = parse(run([f'{d}/mf', f, 'x'])); r = parse(run(['vvp', f'{T}/tb.vvp', f'+STIM={f}', f'+ID=x']))
    n = sum(a != b for a, b in zip(m, r)); tot += n; lines.append(f'{k} | {n}')
lines.append(f'TOTAL | {tot}')

# ---- (b) step level: 25000 clk per slot, whole scenario set vs the existing step-level RTL log (read-only)
s = T + '/step'; shutil.copytree('experiments/wokwi', s + '/wokwi'); open(s + '/wokwi/reflex_model.h', 'w').write(patched(25000))
shutil.copy('experiments/model_host.c', s + '/model_host.c')
run(['gcc', '-Wall', '-o', f'{s}/mh', f'{s}/model_host.c'])
new = run([f'{s}/mh', 'rtl/force_lut.mem']).splitlines()
old = [l for l in open('experiments/results/model_log.txt').read().splitlines()]
rtl = collections.defaultdict(dict)
for l in open('experiments/results/rtl_log.txt'):
    f = l.strip().split(','); rtl[f[1]][int(f[2])] = (int(f[3]), int(f[4]), int(f[5]))
mm = collections.Counter(); mmold = collections.Counter(); chg = collections.Counter(); sums = {}
for a, b in zip(old, new):
    if a != b: chg[a.split(',')[1] if a.split(',')[0] != 'PARAM' else 'PARAM'] += 1
for src, cnt in ((new, mm), (old, mmold)):
    for l in src:
        f = l.split(',')
        if f[0] == 'LOG' and (int(f[9]), int(f[10]), int(f[11])) != rtl[f[1]][int(f[2])]: cnt[f[1]] += 1
for l in new:
    f = l.split(',')
    if f[0] == 'SUM': sums[f[1]] = f[2]
lines += ['', f'step level: log lines that differ from the current model_log.txt, per scenario: {dict(chg)}', f'step-level model-vs-RTL mismatching steps, current model: {sum(mmold.values())} {dict(mmold)}',
          f'step-level model-vs-RTL mismatching steps, time-based model: {sum(mm.values())} {dict(mm)}', f'scenario PASS/FAIL (time-based model): {sums}']
open(f'{R}/time_based_watchdog_evaluation.md', 'w').write('\n'.join(lines) + '\n'); print('\n'.join(lines))
