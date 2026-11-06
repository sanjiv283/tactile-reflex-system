#!/usr/bin/env python3
"""stim: write per-scenario stimulus hex files from the model log.  report: build dataset + summary from model and RTL logs."""
import sys, json, csv, collections

def parse_model(path):
    sc = collections.OrderedDict(); params = {}
    for line in open(path):
        f = line.strip().split(',')
        if f[0] == 'PARAM': params = dict(x.split('=') for x in f[1:])
        elif f[0] == 'LOG':
            d = sc.setdefault(f[1], {'log': [], 'chk': [], 'sum': None})
            d['log'].append(dict(step=int(f[2]), t_us=int(f[3]), code=int(f[4]), present=int(f[5]), ferr=int(f[6]), estop_n=int(f[7]), fclr=int(f[8]),
                                 safe=int(f[9]), cmd=int(f[10]), trip=int(f[11]), bl_safe=int(f[12]), bl_cmd=int(f[13]), event=f[14]))
        elif f[0] == 'CHK':
            sc[f[1]]['chk'].append(dict(seg=f[2], kind=f[3], expected=int(f[4]), observed=int(f[5]), ok=f[6] == 'PASS',
                                        baseline_observed=int(f[7]), baseline_ok=f[8] == 'PASS', s0=int(f[9]), s1=int(f[10])))
        elif f[0] == 'SUM':
            sc[f[1]]['sum'] = dict(ok=f[2] == 'PASS', checks=int(f[3]), passed=int(f[4]), first_over=int(f[5]), first_safe=int(f[6]),
                                   lat_steps=int(f[7]), transitions=int(f[8]), bl_transitions=int(f[9]), bl_passed=int(f[10]), stim_start=int(f[11]))
    return params, sc

def parse_rtl(path):
    r = collections.defaultdict(list)
    for line in open(path):
        f = line.strip().split(',')
        r[f[1]].append(dict(step=int(f[2]), safe=int(f[3]), cmd=int(f[4]), trip=int(f[5]), sfault=int(f[6]), estop=int(f[7]), lat=int(f[8])))
    return r

if sys.argv[1] == 'stim':
    _, _, mlog, out = sys.argv
    for sid, d in parse_model(mlog)[1].items():
        with open(f'{out}/{sid}.hex', 'w') as fh:
            for s in d['log']:
                fh.write('%04X\n' % (s['code'] | s['present'] << 12 | s['ferr'] << 13 | s['estop_n'] << 14 | s['fclr'] << 15))
    sys.exit(0)

_, _, mlog, rlog, out = sys.argv
params, sc = parse_model(mlog); rtl = parse_rtl(rlog)

def rtl_check(c, rows, d):
    """Re-evaluate a model expectation on the RTL's outputs over the same step range."""
    k = c['kind']; a, b = c['s0'], c['s1']
    if k == 'first_safe' or k == 'end_safe': return rows[a]['safe']
    if k == 'any_safe': return int(any(r['safe'] for r in rows[a:b + 1]))
    if k.startswith('trip_mask_'): m = int(k.split('_')[2]); return int((rows[b]['trip'] & m) == m)
    if k == 'cmd_nonzero': return int(rows[b]['cmd'] != 0)
    if k == 'trip_precedes_limit':
        s = d['sum']; ss = s['stim_start']; over = s['first_over'] + ss if s['first_over'] >= 0 else None
        fs = next((r['step'] for r in rows[ss:] if r['safe']), None)
        return int(fs is not None and over is not None and fs < over)
    raise ValueError(k)

records, flat = [], []
for sid, d in sc.items():
    rows = rtl[sid]; assert len(rows) == len(d['log']), (sid, len(rows), len(d['log']))
    mism = [dict(step=m['step'], model=dict(safe=m['safe'], cmd=m['cmd'], trip=m['trip']), rtl=dict(safe=r['safe'], cmd=r['cmd'], trip=r['trip']))
            for m, r in zip(d['log'], rows) if (m['safe'], m['cmd'], m['trip']) != (r['safe'], r['cmd'], r['trip'])]
    for c in d['chk']: c['rtl_observed'] = rtl_check(c, rows, d); c['rtl_ok'] = c['rtl_observed'] == c['expected']
    s = d['sum']; ss = s['stim_start']
    rtl_first = next((r['step'] - ss for r in rows[ss:] if r['safe']), None)
    over_abs = s['first_over'] + ss if s['first_over'] >= 0 else None
    rtl_lat_cycles = rows[over_abs]['lat'] if over_abs is not None and rows[over_abs]['lat'] >= 0 else None
    rec = dict(scenario_id=sid, parameters=params,
               input_sequence=[[x['code'], x['present'], x['ferr'], x['estop_n'], x['fclr']] for x in d['log']],
               input_columns=['adc_code', 'sample_present', 'frame_error', 'estop_n', 'fault_clear'],
               checks=d['chk'], model_pass=s['ok'], model_checks=s['checks'], model_passed=s['passed'],
               rtl_checks_passed=sum(c['rtl_ok'] for c in d['chk']), baseline_checks_passed=s['bl_passed'],
               model_first_over_step=s['first_over'], model_first_safe_step=s['first_safe'], model_latency_steps=s['lat_steps'],
               model_latency_ms=s['lat_steps'] * int(params['SAMPLE_US']) / 1000.0,
               rtl_first_safe_step=rtl_first, rtl_trip_latency_cycles_at_first_over_step=rtl_lat_cycles,
               model_safe_transitions=s['transitions'], baseline_safe_transitions=s['bl_transitions'],
               rtl_safe_transitions=sum(1 for p, q in zip(rows[ss - 1:], rows[ss:]) if p['safe'] != q['safe']),
               model_vs_rtl_steps=len(rows), model_vs_rtl_mismatches=len(mism), model_vs_rtl_mismatch_detail=mism[:20])
    records.append(rec)
    for c in d['chk']: flat.append(dict(scenario_id=sid, **{k: c[k] for k in ('seg', 'kind', 'expected', 'observed', 'ok', 'baseline_observed', 'baseline_ok', 'rtl_observed', 'rtl_ok')}))
json.dump(records, open(f'{out}/dataset.json', 'w'), indent=1)
with open(f'{out}/dataset.jsonl', 'w') as fh:
    for r in records: fh.write(json.dumps(r) + '\n')
with open(f'{out}/checks.csv', 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(flat[0])); w.writeheader(); w.writerows(flat)
tot = lambda key: sum(r[key] for r in records)
lines = ['scenario | checks | model | RTL | baseline | model-vs-RTL step mismatches | model lat (steps) | model/baseline safe transitions | RTL transitions', '-|-|-|-|-|-|-|-|-']
for r in records:
    n = len(r['checks'])
    lines.append(f"{r['scenario_id']} | {n} | {r['model_passed']}/{n} | {r['rtl_checks_passed']}/{n} | {r['baseline_checks_passed']}/{n} | "
                 f"{r['model_vs_rtl_mismatches']}/{r['model_vs_rtl_steps']} | {r['model_latency_steps']} | {r['model_safe_transitions']}/{r['baseline_safe_transitions']} | {r['rtl_safe_transitions']}")
n = sum(len(r['checks']) for r in records)
lines.append(f"TOTAL | {n} | {tot('model_passed')}/{n} | {tot('rtl_checks_passed')}/{n} | {tot('baseline_checks_passed')}/{n} | {tot('model_vs_rtl_mismatches')}/{tot('model_vs_rtl_steps')} | | |")
open(f'{out}/summary.md', 'w').write('\n'.join(lines) + '\n'); print('\n'.join(lines))
