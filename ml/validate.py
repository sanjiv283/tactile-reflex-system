"""Validation of the SIMULATED-data model beyond a single train/test split. Deterministic (fixed seeds); no timing.
Writes results/ml_validation.json. Everything here is simulation: it shows the pipeline behaves sensibly, not that a real sensor would."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from sklearn.tree import DecisionTreeClassifier
from sklearn.model_selection import GroupKFold
from sklearn.metrics import accuracy_score, recall_score, confusion_matrix
from gen_sim_data import build, features, FEATURES, CLASSES

FORCE_MAX = 2560
X, y, g, f = build()
test_ep = np.arange(420, 600); te = np.isin(g, test_ep); tr = ~te
def fit(Xa, ya, depth=4): return DecisionTreeClassifier(max_depth=depth, random_state=0).fit(Xa, ya)
out = dict(data="SIMULATED", note="all numbers come from the synthetic episode generator; not real sensor data")

# 1) leakage control: the train/test split is by episode
assert not (set(g[tr]) & set(g[te])), "episode appears in both train and test"
out["split"] = dict(train_episodes=int(len(set(g[tr]))), test_episodes=int(len(set(g[te]))), overlap=0)

# 2) grouped 5-fold cross-validation over all 600 episodes (model vs force-only baseline)
cv = dict(model=[], baseline=[], excessive_recall=[], excessive_as_normal=[])
for a, b in GroupKFold(5).split(X, y, g):
    m = fit(X[a], y[a]); p = m.predict(X[b]); cv["model"].append(accuracy_score(y[b], p))
    cv["baseline"].append(accuracy_score(y[b], fit(X[a][:, :1], y[a]).predict(X[b][:, :1])))
    ex = y[b] == 3; cv["excessive_recall"].append(float((p[ex] == 3).mean())); cv["excessive_as_normal"].append(float((p[ex] == 2).mean()))
out["grouped_5fold_cv"] = {k: dict(mean=float(np.mean(v)), std=float(np.std(v)), folds=[float(x) for x in v]) for k, v in cv.items()}

# 3) bootstrap confidence interval over held-out EPISODES (not samples: samples within an episode are correlated)
m = fit(X[tr], y[tr]); p = m.predict(X[te]); eps = np.unique(g[te]); rng = np.random.default_rng(1)
per_ep = {e: (int((p[g[te] == e] == y[te][g[te] == e]).sum()), int((g[te] == e).sum())) for e in eps}
accs = []
for _ in range(2000):
    pick = rng.choice(eps, len(eps)); accs.append(sum(per_ep[e][0] for e in pick) / sum(per_ep[e][1] for e in pick))
out["heldout_accuracy"] = dict(point=float(accuracy_score(y[te], p)), ci95_episode_bootstrap=[float(np.percentile(accs, 2.5)), float(np.percentile(accs, 97.5))])

# 4) label-shuffle control: with labels shuffled per episode the model must fall to roughly the majority rate
ys = y.copy(); r = np.random.default_rng(2)
for e in np.unique(g[tr]): idx = np.where(g == e)[0]; ys[idx] = r.permutation(y[idx])
out["label_shuffle_control"] = dict(accuracy=float(accuracy_score(y[te], fit(X[tr], ys[tr]).predict(X[te]))), majority_rate=float(np.bincount(y[te]).max() / te.sum()))

# 5) depth sweep with grouped CV: is depth 4 a reasonable choice?
sweep = {}
for d in range(1, 9):
    sweep[d] = float(np.mean([accuracy_score(y[b], fit(X[a], y[a], d).predict(X[b])) for a, b in GroupKFold(5).split(X, y, g)]))
out["depth_sweep_cv_accuracy"] = sweep

# 6) robustness: extra measurement noise on the held-out force traces (features recomputed causally)
rob = {}
for sigma in (0, 10, 20, 40, 80):
    r = np.random.default_rng(3); Xn = np.vstack([features(np.clip(f[g == e] + r.normal(0, sigma, (g == e).sum()), 0, 4095)) for e in eps])
    yn = np.concatenate([y[g == e] for e in eps]); rob[str(sigma)] = float(accuracy_score(yn, m.predict(Xn)))
out["extra_noise_sigma_counts_accuracy"] = rob

# 7) what matters for safety: the AI can only LOWER the command; the hard limit is the real protection
ex = y[te] == 3; below = f[te] < FORCE_MAX
out["safety_view"] = dict(
    excessive_samples=int(ex.sum()), excessive_recall=float((p[ex] == 3).mean()), excessive_predicted_normal=float((p[ex] == 2).mean()),
    excessive_samples_below_hard_limit=int((ex & below).sum()), excessive_below_limit_predicted_not_excessive=int((ex & below & (p != 3)).sum()),
    note="a missed 'excessive' call leaves the command at the LUT value; the hard force limit (and slope predictor) still apply independently of the AI")
out["per_class_recall_heldout"] = {CLASSES[i]: float(recall_score(y[te], p, labels=[i], average=None)[0]) for i in range(4)}
os.makedirs("results", exist_ok=True)
with open("results/ml_validation.json", "w") as fh: json.dump(out, fh, indent=1, sort_keys=True)
cvm = out["grouped_5fold_cv"]
print(f"grouped 5-fold CV accuracy {cvm['model']['mean']:.3f} +/- {cvm['model']['std']:.3f}  (force-only baseline {cvm['baseline']['mean']:.3f})")
print(f"held-out accuracy {out['heldout_accuracy']['point']:.3f}, 95% CI (episode bootstrap) {out['heldout_accuracy']['ci95_episode_bootstrap'][0]:.3f}..{out['heldout_accuracy']['ci95_episode_bootstrap'][1]:.3f}")
print(f"label-shuffle control accuracy {out['label_shuffle_control']['accuracy']:.3f} (majority {out['label_shuffle_control']['majority_rate']:.3f})")
print("depth sweep:", {k: round(v, 3) for k, v in sweep.items()}); print("noise robustness:", rob)
print("excessive-force recall", round(out["safety_view"]["excessive_recall"], 3), "| excessive samples below the hard limit:", out["safety_view"]["excessive_samples_below_hard_limit"])
