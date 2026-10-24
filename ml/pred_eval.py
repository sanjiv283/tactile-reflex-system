"""Slope-predictive pre-limit: integer reference model of rtl/safety_governor.v (PRED_* parameters), evaluated on the
SIMULATED episodes. Parameters are chosen on training episodes only; test-episode numbers are reported.
trip(t) = delta >= MIN and force + K*delta >= FORCE_MAX, delta = rise over the last window (snapshot every W samples).
Also writes tb/pred_vectors.mem (W=1) so the RTL can be checked against this model."""
import json, os, sys, itertools
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from gen_sim_data import episode
FORCE_MAX = 0xA00

def trips(f, W, K, MIN):
    f = [int(round(x)) for x in f]; out = []; snap = 0; delta = 0; seeded = False
    for t, x in enumerate(f):
        if t % W == 0:
            delta = (x - snap) if seeded else 0; snap = x; seeded = True
        out.append(delta >= MIN and x + K * delta >= FORCE_MAX)
    return out

def evaluate(eps, W, K, MIN):
    lead, crossing, early, nonc, fp = [], 0, 0, 0, 0
    for f in eps:
        tr = trips(f, W, K, MIN); fi = [int(round(x)) for x in f]
        cross = next((t for t, x in enumerate(fi) if x >= FORCE_MAX), None)
        first = next((t for t, v in enumerate(tr) if v), None)
        if cross is not None:
            crossing += 1
            if first is not None and first < cross: early += 1; lead.append(cross - first)
        else:
            nonc += 1; fp += first is not None
    return dict(crossing_episodes=crossing, early_trip=early, lead_ms_mean=float(np.mean(lead)) if lead else 0.0,
                lead_ms_median=float(np.median(lead)) if lead else 0.0, noncrossing_episodes=nonc, false_early=fp,
                false_early_rate=fp / max(nonc, 1))

rng = np.random.default_rng(0)
eps = [episode(rng)[0] for _ in range(600)]            # same generator and seed as ml/gen_sim_data.build()
train, test = eps[:420], eps[420:]
best = None
for W, K, MIN in itertools.product([3, 5, 10], [1, 2, 3], [60, 90, 150]):
    r = evaluate(train, W, K, MIN)
    if r["false_early_rate"] <= 0.10 and (best is None or r["lead_ms_mean"] * r["early_trip"] >= best[0]):
        best = (r["lead_ms_mean"] * r["early_trip"], W, K, MIN)
_, W, K, MIN = best
res = dict(chosen=dict(window_ms=W, lookahead_windows=K, min_delta_counts=MIN, force_max=FORCE_MAX, selected_on="training episodes, false-early rate <= 10%"),
           train=evaluate(train, W, K, MIN), test=evaluate(test, W, K, MIN), source="SIMULATED")
json.dump(res, open("results/pred_results.json", "w"), indent=2)
# RTL cross-check vectors: window = 1 sample, same K and MIN
r2 = np.random.default_rng(1)
syn = []
for slope in [20, 60, 100, 149, 150, 151, 200, 300, 500, -100, 75, 180]:    # synthetic ramps, up and down, noisy
    x = 500 if slope > 0 else 3200
    for _ in range(60): syn.append(int(np.clip(x + r2.normal(0, 10), 0, 4000))); x += slope
seq = syn + [int(round(x)) for e in test[:10] for x in e]
exp = trips(seq, 1, K, MIN)
with open("tb/pred_vectors.mem", "w") as fh:
    for x, e in zip(seq, exp): fh.write(f"{(int(e) << 12) | x:04X}\n")
print(json.dumps(res, indent=1)); print("vectors:", len(seq), "expected trips:", sum(exp), "K,MIN =", K, MIN)
