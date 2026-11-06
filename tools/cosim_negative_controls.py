#!/usr/bin/env python3
"""Negative controls for the co-simulation: apply single-edit mutants (tools/mutation_test.py) to a temporary copy of the repository and require
tools/cosim_host_rtl.py to FAIL. Shows which injected faults the host-in-the-loop run really detects. Writes results/cosim_negative_controls.json.
Usage: python3 tools/cosim_negative_controls.py [M08,M09,...]   (default: DEFAULT)"""
import contextlib, io, json, os, shutil, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import mutation_test as mt, cosim_host_rtl as C
# faults a host-in-the-loop run should see: AI caps, AI link integrity/heartbeat/checksum, telemetry header, force limit, hysteresis, e-stop, sensor fault, command zeroing
DEFAULT = ["M02", "M03", "M04", "M08", "M09", "M10", "M19", "M20", "M24", "M25", "M46"]
def run(ids):
    out = {}; byid = {m[0]: m for m in mt.M}
    for mid in ids:
        _, name, f, old, new = byid[mid]; d = tempfile.mkdtemp(prefix="cn_")
        try:
            for sub in ("rtl", "tb"): shutil.copytree(os.path.join(ROOT, sub), os.path.join(d, sub), ignore=shutil.ignore_patterns("build", "*.vvp", "__pycache__"))
            os.makedirs(os.path.join(d, "results")); shutil.copy(os.path.join(ROOT, "results", "tree.json"), os.path.join(d, "results", "tree.json"))
            p = os.path.join(d, f)
            with open(p) as fh: t = fh.read()
            assert t.count(old) == 1, mid
            with open(p, "w") as fh: fh.write(t.replace(old, new))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                try: rc = C.main(root=d, write=False)
                except Exception as e: rc = 1; buf.write(f"exception: {e}")
            first = [l.strip() for l in buf.getvalue().splitlines() if "PROBLEM" in l or "exception" in l][:1]
            out[mid] = dict(name=name, detected=rc != 0, first_problem=first[0][:140] if first else "")
        finally: shutil.rmtree(d, ignore_errors=True)
        print(f"{mid} {'DETECTED' if out[mid]['detected'] else 'NOT DETECTED'}  {name[:48]}  {out[mid]['first_problem'][:90]}", flush=True)
    return out
if __name__ == "__main__":
    ids = sys.argv[1].split(",") if len(sys.argv) > 1 else DEFAULT; res = run(ids)
    with open(os.path.join(ROOT, "results", "cosim_negative_controls.json"), "w") as fh: json.dump(res, fh, indent=1, sort_keys=True)
    miss = [k for k, v in res.items() if not v["detected"]]; print(f"co-simulation detects {len(res) - len(miss)} of {len(res)} injected faults; not detected: {miss or 'none'}"); sys.exit(1 if miss else 0)
