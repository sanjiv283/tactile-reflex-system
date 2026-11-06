#!/usr/bin/env python3
"""Pipeline for REAL recordings (none exist yet; the repository's only dataset is simulated). Same features, same tree, same JSON export,
but with strict input validation and session-wise evaluation so that a real run cannot be silently mistaken for the simulated one.

Input: one CSV per recording session, columns:   t_s,adc,label
    t_s    seconds, strictly increasing           adc    raw 12-bit ADC counts 0..4095 (what the FPGA sees, i.e. BEFORE any scaling)
    label  0 no contact, 1 light, 2 normal grip, 3 excessive  (operator annotation; an empty cell = unlabelled, excluded from training)
Usage:  python3 ml/real_data_pipeline.py --sessions data/*.csv --source REAL --out-dir results/real [--rate-hz 1000] [--min-per-class 200]
        python3 ml/real_data_pipeline.py --make-template template.csv
The model is written to <out-dir>/tree.json and NEVER over results/tree.json. Nothing here changes the RTL; the FPGA's LUT and hard limits are separate."""
import argparse, csv, glob, hashlib, json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import numpy as np
from gen_sim_data import features, FEATURES, CLASSES
from tree_model import export_tree

class DataError(Exception): pass

def _sha(path):
    with open(path, "rb") as fh: return hashlib.sha256(fh.read()).hexdigest()

def load_session(path, rate_hz, tol=0.25):
    with open(path, newline="") as fh:
        rd = csv.DictReader(fh)
        if rd.fieldnames is None or [c.strip() for c in rd.fieldnames] != ["t_s", "adc", "label"]: raise DataError(f"{path}: header must be exactly t_s,adc,label (got {rd.fieldnames})")
        rows = list(rd)
    if len(rows) < 50: raise DataError(f"{path}: only {len(rows)} rows (need at least 50)")
    t, a, l = [], [], []
    for i, r in enumerate(rows, 2):
        try: tv, av = float(r["t_s"]), float(r["adc"])
        except ValueError: raise DataError(f"{path}:{i}: non-numeric t_s/adc")
        if not (np.isfinite(tv) and np.isfinite(av)): raise DataError(f"{path}:{i}: NaN/inf")
        if not (0 <= av <= 4095): raise DataError(f"{path}:{i}: adc {av} outside 0..4095")
        lab = (r["label"] or "").strip()
        if lab == "": lv = -1
        elif lab in ("0", "1", "2", "3"): lv = int(lab)
        else: raise DataError(f"{path}:{i}: label {lab!r} not in 0..3 or empty")
        t.append(tv); a.append(av); l.append(lv)
    t, a, l = np.array(t), np.array(a), np.array(l)
    if np.any(np.diff(t) <= 0): raise DataError(f"{path}: t_s is not strictly increasing")
    dt = float(np.median(np.diff(t)))
    if abs(1 / dt - rate_hz) > tol * rate_hz: raise DataError(f"{path}: sample rate {1/dt:.1f} Hz differs from --rate-hz {rate_hz} by more than {int(tol*100)}% (the features assume a fixed rate)")
    if np.max(np.diff(t)) > 5 * dt: raise DataError(f"{path}: gap of {np.max(np.diff(t)):.3f} s (> 5 sample periods): recording has dropouts, split or fix it")
    if np.all(a == a[0]): raise DataError(f"{path}: ADC value never changes (sensor stuck / not connected?)")
    return a, l

def run(paths, source, out_dir, rate_hz=1000.0, min_per_class=200, depth=4, seed=0):
    from sklearn.tree import DecisionTreeClassifier
    from sklearn.metrics import accuracy_score, confusion_matrix
    if source not in ("REAL", "SIMULATED_FIXTURE"): raise DataError("--source must be REAL or SIMULATED_FIXTURE")
    if len(paths) < 4: raise DataError("need at least 4 sessions (session-wise train/test split)")
    ses = {}
    for p in paths: ses[p] = load_session(p, rate_hz)
    X, y, g = [], [], []
    for k, p in enumerate(sorted(ses)):
        a, l = ses[p]; X.append(features(a)); y.append(l); g.append(np.full(len(a), k))
    X, y, g = np.vstack(X), np.concatenate(y), np.concatenate(g)
    lab = y >= 0
    counts = np.bincount(y[lab], minlength=4)
    short = [CLASSES[i] for i in range(4) if counts[i] < min_per_class]
    if short: raise DataError(f"too few labelled samples (< {min_per_class}) for: {', '.join(short)}; counts={counts.tolist()}")
    order = sorted(ses); n_test = max(1, len(order) // 4); test_sessions = set(range(len(order) - n_test, len(order)))
    te = np.isin(g, list(test_sessions)) & lab; tr = ~np.isin(g, list(test_sessions)) & lab
    if len(set(y[tr])) < 4 or len(set(y[te])) < 2: raise DataError("train split lacks a class or test split has fewer than 2 classes: add sessions or reorder")
    clf = DecisionTreeClassifier(max_depth=depth, random_state=seed).fit(X[tr], y[tr])
    base = DecisionTreeClassifier(max_depth=depth, random_state=seed).fit(X[tr][:, :1], y[tr])
    p = clf.predict(X[te])
    rep = dict(data_source=source, sessions=len(order), test_sessions=[os.path.basename(order[i]) for i in sorted(test_sessions)],
               rate_hz=rate_hz, labelled_samples=int(lab.sum()), class_counts=counts.tolist(), accuracy=float(accuracy_score(y[te], p)),
               baseline_force_only_accuracy=float(accuracy_score(y[te], base.predict(X[te][:, :1]))),
               confusion=confusion_matrix(y[te], p, labels=[0, 1, 2, 3]).tolist(), features=FEATURES, tree_depth=int(clf.get_depth()),
               inputs_sha256={os.path.basename(k): _sha(k) for k in order},
               warning=("SIMULATED FIXTURE: demonstrates the pipeline only; says nothing about real sensors" if source != "REAL" else
                        "Model is advisory only. The RTL hard limits are independent of it. Re-derive the hardware LUT/limits from the calibration, not from this report."))
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "tree.json"), "w") as fh: json.dump(export_tree(clf, FEATURES, clf.classes_), fh, indent=1)
    with open(os.path.join(out_dir, "real_data_report.json"), "w") as fh: json.dump(rep, fh, indent=1, sort_keys=True)
    return rep

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sessions", nargs="+"); ap.add_argument("--source", default="REAL"); ap.add_argument("--out-dir", default="results/real")
    ap.add_argument("--rate-hz", type=float, default=1000.0); ap.add_argument("--min-per-class", type=int, default=200); ap.add_argument("--make-template")
    a = ap.parse_args()
    if a.make_template:
        with open(a.make_template, "w", newline="") as fh: fh.write("t_s,adc,label\n"); print("wrote header-only template", a.make_template); sys.exit(0)
    if not a.sessions: ap.print_help(); sys.exit(0)
    paths = [p for pat in a.sessions for p in (glob.glob(pat) or [pat])]
    try: r = run(paths, a.source, a.out_dir, a.rate_hz, a.min_per_class)
    except DataError as e: print("DATA ERROR:", e, file=sys.stderr); sys.exit(2)
    print(json.dumps({k: r[k] for k in ("data_source", "sessions", "accuracy", "baseline_force_only_accuracy", "class_counts")}))
