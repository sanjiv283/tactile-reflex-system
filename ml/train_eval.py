"""Train and evaluate the lightweight model on the SIMULATED dataset. Writes results/ and tb/replay_vectors.mem."""
import json, time, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.metrics import accuracy_score, precision_recall_fscore_support, confusion_matrix
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from gen_sim_data import build, CLASSES, FEATURES

X, y, g, f = build()
test_ep = set(range(420, 600))                 # split by episode: no sample from a test episode is seen in training
te = np.isin(g, list(test_ep)); tr = ~te
clf = DecisionTreeClassifier(max_depth=4, random_state=0).fit(X[tr], y[tr])
base = DecisionTreeClassifier(max_depth=4, random_state=0).fit(X[tr][:, :1], y[tr])   # force-only baseline

def evaluate(model, Xt):
    p = model.predict(Xt)
    pr, rc, f1, _ = precision_recall_fscore_support(y[te], p, labels=[0, 1, 2, 3], zero_division=0)
    return p, dict(accuracy=accuracy_score(y[te], p), precision=pr.tolist(), recall=rc.tolist(), f1=f1.tolist(),
                   confusion=confusion_matrix(y[te], p, labels=[0, 1, 2, 3]).tolist())
pred, res = evaluate(clf, X[te])
_, res_base = evaluate(base, X[te][:, :1])

# inference time: single-sample prediction by walking the fitted tree in pure Python (what the PS would run)
T = clf.tree_
def walk(x):
    n = 0
    while T.children_left[n] != -1:
        n = T.children_left[n] if x[T.feature[n]] <= T.threshold[n] else T.children_right[n]
    return int(np.argmax(T.value[n]))
assert all(walk(x) == p for x, p in zip(X[te][:200], pred[:200]))
xs = X[te][:2000]; times = []
for x in xs:
    t = time.perf_counter_ns(); walk(x); times.append(time.perf_counter_ns() - t)
t_sk = []
for x in xs[:300]:
    t = time.perf_counter_ns(); clf.predict(x.reshape(1, -1)); t_sk.append(time.perf_counter_ns() - t)
us = np.array(times) / 1e3
res["inference_us_tree_walk"] = dict(mean=float(us.mean()), median=float(np.median(us)), p99=float(np.percentile(us, 99)), max=float(us.max()), n=len(us))
res["inference_us_sklearn_predict"] = dict(median=float(np.median(t_sk) / 1e3), n=len(t_sk))
res["baseline_force_only"] = res_base
res["data"] = dict(source="SIMULATED", episodes_train=420, episodes_test=180, samples_train=int(tr.sum()), samples_test=int(te.sum()),
                   features=FEATURES, tree_depth=int(clf.get_depth()), leaves=int(clf.get_n_leaves()),
                   timing_platform="development host (not the target processor)")
os.makedirs("results", exist_ok=True)
json.dump(res, open("results/ml_results.json", "w"), indent=2)
open("results/tree.txt", "w").write(export_text(clf, feature_names=FEATURES))

cm = np.array(res["confusion"])
fig, ax = plt.subplots(figsize=(5.2, 4.4)); ax.imshow(cm, cmap="Blues")
for i in range(4):
    for j in range(4): ax.text(j, i, cm[i, j], ha="center", va="center", color="white" if cm[i, j] > cm.max() / 2 else "black", fontsize=12)
ax.set_xticks(range(4)); ax.set_yticks(range(4)); ax.set_xticklabels(["0", "1", "2", "3"]); ax.set_yticklabels(["0", "1", "2", "3"])
ax.set_xlabel("Predicted class"); ax.set_ylabel("True class"); ax.set_title("Confusion matrix (SIMULATED test set)")
fig.tight_layout(); fig.savefig("results/confusion_matrix.png", dpi=200)

# replay vectors for the RTL testbench: test-episode ADC counts + the model's class, stride 2, {class[13:12], adc[11:0]}
idx = np.where(te)[0][::2][:1800]
with open("tb/replay_vectors.mem", "w") as fh:
    for i in idx: fh.write(f"{(int(pred[np.where(np.where(te)[0] == i)[0][0]]) << 12) | int(round(f[i])):04X}\n")
print(json.dumps({k: res[k] for k in ["accuracy", "precision", "recall", "confusion", "inference_us_tree_walk"]}, indent=1))
print("baseline force-only accuracy:", round(res_base["accuracy"], 4))
