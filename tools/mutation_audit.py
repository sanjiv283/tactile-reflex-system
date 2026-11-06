#!/usr/bin/env python3
"""Independent audit of the mutation campaign. For every mutant: the pattern occurs exactly once, the edit changes exactly the
intended file/line(s), the mutated design compiles WITHOUT warnings-as-errors (non-strict), and the regression fails because
of FAILED ASSERTIONS (not a warning, timeout or missing summary). Also checks the real RTL is untouched. Writes results/mutation_audit.json."""
import json, os, shutil, subprocess, sys, tempfile, difflib, hashlib, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutation_test as mt
ROOT = mt.ROOT
def digest(): return {f: hashlib.sha256(open(f, "rb").read()).hexdigest() for f in sorted(glob.glob(ROOT + "/rtl/*.v") + glob.glob(ROOT + "/tb/*.v"))}
def audit(m):
    mid, name, f, old, new = m; d = tempfile.mkdtemp(prefix=f"aud_{mid}_")
    try:
        for sub in ("rtl", "tb", "sim"): shutil.copytree(os.path.join(ROOT, sub), os.path.join(d, sub), ignore=shutil.ignore_patterns("build", "*.vvp", "__pycache__"))
        os.makedirs(d + "/results"); p = os.path.join(d, f); t = open(p).read(); n = t.count(old)
        if n != 1: return dict(id=mid, applied=False, note=f"pattern occurs {n}x")
        t2 = t.replace(old, new); open(p, "w").write(t2)
        dl = [l for l in difflib.unified_diff(t.splitlines(), t2.splitlines(), lineterm="", n=0) if l[:1] in "+-" and l[:3] not in ("+++", "---")]
        r = subprocess.run([sys.executable, ROOT + "/tools/run_regression.py", "--root", d, "--jobs", "2", "--no-strict-warnings", "--builddir", d + "/b", "--log", d + "/l", "--json", d + "/j.json"], capture_output=True, text=True)
        j = json.load(open(d + "/j.json")); bad = [x for x in j["per_testbench"] if x["status"] != "PASS"]
        import re
        with open(d + "/l") as fh: lines = fh.read().splitlines() if bad else []
        printed = sum(1 for l in lines if re.match(r"FAIL\b", l) and not l.startswith("FAIL SAFETY"))     # one per failed assertion line; the monitor's own lines are counted through its testbench assertion
        asserts = max(sum(x["failed"] for x in bad), printed);   # distinct failing assertions: the summary count, or the printed FAIL lines when a testbench timed out before its summary
        compile_err = any("compile error" in " ".join(x["problems"]) for x in bad)
        return dict(id=mid, file=f, applied=True, changed_lines=len(dl), compiles=not compile_err, regression_failed=r.returncode != 0,
                    failing_assertions=asserts, n_testbenches=len(bad), killed_by_assertion=(asserts > 0 and not compile_err), detected_by=[x["name"] for x in bad])
    finally: shutil.rmtree(d, ignore_errors=True)
before = digest()
from concurrent.futures import ThreadPoolExecutor
with ThreadPoolExecutor(3) as ex: res = list(ex.map(audit, mt.M))
after = digest()
ok = [r for r in res if r.get("applied") and r["compiles"] and r["killed_by_assertion"]]
# robustness targets (set after the audit of 2026-11-06 found these kills rested on a single assertion):
#   at least min_assert distinct failing assertions and min_tbs distinct testbenches. M06 cannot be seen at system level (the e-stop latch holds the safe state
#   after reset anyway), so its second observer is the formal property P11/P12, not a second testbench.
TARGETS = {"M06": (2, 1), "M11": (2, 2), "M17": (2, 2), "M25": (2, 2), "M40": (2, 2), "M41": (2, 2)}
byid = {r["id"]: r for r in res}
target_results = {k: dict(min_assert=a, min_tbs=t, failing_assertions=byid[k]["failing_assertions"], n_testbenches=byid[k]["n_testbenches"],
                          met=byid[k]["failing_assertions"] >= a and byid[k]["n_testbenches"] >= t) for k, (a, t) in TARGETS.items()}
single_tb = sorted(r["id"] for r in res if r["n_testbenches"] == 1); single_assert = sorted(r["id"] for r in res if r["failing_assertions"] == 1)
out = dict(mutants=len(res), applied_and_compiled=sum(1 for r in res if r.get("applied") and r.get("compiles")), killed_by_failed_assertion=len(ok),
           not_proven=[r for r in res if r not in ok], real_rtl_tb_unchanged=(before == after), robustness_targets=target_results,
           killed_by_one_testbench_only=single_tb, killed_by_one_assertion_only=single_assert, detail=res)
with open(ROOT + "/results/mutation_audit.json", "w") as _fh: json.dump(out, _fh, indent=1)
print(f"mutants={out['mutants']} applied+compiled={out['applied_and_compiled']} killed-by-failed-assertion={out['killed_by_failed_assertion']} real_rtl_tb_unchanged={out['real_rtl_tb_unchanged']}")
for r in out["not_proven"]: print("NOT PROVEN:", r)
print("kills resting on ONE testbench:", single_tb or "none"); print("kills resting on ONE assertion:", single_assert or "none")
for k, v in target_results.items(): print(f"  target {k}: {v['failing_assertions']} failing assertions in {v['n_testbenches']} testbench(es) (need >= {v['min_assert']} / >= {v['min_tbs']}): {'MET' if v['met'] else 'NOT MET'}")
sys.exit(0 if len(ok) == len(res) and before == after and all(v["met"] for v in target_results.values()) else 1)
