#!/usr/bin/env python3
"""Reproducibility check: regenerate every derived artifact in a TEMPORARY copy of the repository and compare it with the committed one.
Nothing in the working tree is modified. Exit status 1 if any deterministic artifact differs.
Compared: rtl/force_lut.mem, tb/replay_vectors.mem, tb/pred_vectors.mem (byte-identical); results/ml_results.json and results/pred_results.json
(every field except the machine-dependent inference timings); results/tree.json (byte-identical, if present)."""
import json, os, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BYTES = ["rtl/force_lut.mem", "tb/replay_vectors.mem", "tb/pred_vectors.mem", "results/tree.json", "results/tree.txt", "tb/host_link_bytes.mem", "tb/host_link_expect.mem"]
JSONS = ["results/ml_results.json", "results/pred_results.json", "results/ml_validation.json"]
COPY = ["rtl", "tb", "ml", "tools", "results", "host"]

def main():
    tmp = tempfile.mkdtemp(prefix="artifact_check_"); bad = []
    try:
        for d in COPY: shutil.copytree(os.path.join(ROOT, d), os.path.join(tmp, d), ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        for cmd in (["tools/gen_lut.py"], ["ml/train_eval.py"], ["ml/pred_eval.py"], ["tools/gen_host_link_vectors.py"], ["ml/validate.py"]):
            r = subprocess.run([sys.executable] + cmd, cwd=tmp, capture_output=True, text=True, env=env)
            if r.returncode != 0: print(f"generator failed: {' '.join(cmd)}\n{r.stderr[-400:]}"); return 1
        for f in BYTES:
            a, b = os.path.join(ROOT, f), os.path.join(tmp, f)
            if not os.path.exists(a) and not os.path.exists(b): continue
            same = os.path.exists(a) and os.path.exists(b) and open(a, "rb").read() == open(b, "rb").read()
            print(f"{'IDENTICAL' if same else 'DIFFERS  '} {f}"); 
            if not same: bad.append(f)
        for f in JSONS:
            a = json.load(open(os.path.join(ROOT, f))); b = json.load(open(os.path.join(tmp, f)))
            keys = [k for k in a if not k.startswith("inference_us")]
            same = all(a.get(k) == b.get(k) for k in keys) and sorted(a) == sorted(b)
            print(f"{'IDENTICAL' if same else 'DIFFERS  '} {f} (all fields except inference timing)")
            if not same: bad.append(f)
    finally: shutil.rmtree(tmp, ignore_errors=True)
    print("ARTIFACTS REPRODUCE" if not bad else f"ARTIFACT MISMATCH: {bad}"); return 1 if bad else 0
if __name__ == "__main__": sys.exit(main())
