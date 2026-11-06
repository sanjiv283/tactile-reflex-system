#!/usr/bin/env python3
"""RTL regression runner that cannot report a false PASS.

For every testbench in sim/testbenches.txt it compiles with Icarus Verilog, runs it with a timeout, and requires:
  * a clean compile (and, by default, zero compiler warnings other than the harmless timescale-inheritance notice),
  * vvp to exit with status 0,
  * EXACTLY ONE summary line  "TB <name>: PASS <p> FAIL <f> VECTORS <n> [NOTE text]",
  * FAIL == 0 and PASS >= 1 (a testbench that executed no assertion is rejected),
  * no line starting with FAIL / MISMATCH / TIMEOUT / ERROR in its output.
Exit status is non-zero if anything is wrong. Writes results/sim_log.txt (same line format as before), and a deterministic JSON summary.
Usage: python3 tools/run_regression.py [--only id,id] [--timeout 600] [--jobs 4] [--manifest FILE] [--root DIR] [--no-strict-warnings]
"""
import argparse, glob, json, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

SUMMARY = re.compile(r"^TB (\S+): (PASS (\d+) FAIL (\d+)|TIMEOUT)(.*)$")
BAD_LINE = re.compile(r"^(FAIL|MISMATCH|TIMEOUT|ERROR)\b")
KEEP = re.compile(r"^(TB|FAIL|RESULT|INFO|MISMATCH)")
TIMESCALE_NOISE = re.compile(r"timescale|inherited")

def load_manifest(path):
    entries = []
    with open(path) as fh: lines = fh.read().splitlines()
    for ln in lines:
        ln = ln.split("#", 1)[0].strip()
        if not ln: continue
        f = [x.strip() for x in ln.split("|")]
        if len(f) != 4: raise ValueError(f"bad manifest line: {ln!r}")
        entries.append(dict(id=f[0], tb=f[1], plusargs=f[2].split() if f[2] else [], expect=f[3]))
    ids = [e["id"] for e in entries]
    if len(set(ids)) != len(ids): raise ValueError("duplicate ids in manifest")
    return entries

def run_testbench(e, root, builddir, timeout, strict_warnings):
    """Returns a result dict. Never raises for DUT problems: every problem becomes status FAIL with reasons."""
    t0 = time.time(); problems = []; out = ""; summary = None
    vvp_file = os.path.join(builddir, e["id"] + ".vvp"); os.makedirs(builddir, exist_ok=True)
    rtl = sorted(glob.glob(os.path.join(root, "rtl", "*.v")))
    cmd = ["iverilog", "-g2005", "-Wall", "-Wno-timescale", "-o", vvp_file, os.path.join(root, "tb", "ad7476_model.v"), os.path.join(root, "tb", "safety_monitor.v"), os.path.join(root, e["tb"])] + rtl
    c = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
    warns = [l for l in c.stderr.splitlines() if l.strip() and not TIMESCALE_NOISE.search(l)]
    if c.returncode != 0:
        problems.append("compile error: " + " | ".join(warns[:3]))
    else:
        if warns and strict_warnings: problems.append("compiler warnings: " + " | ".join(warns[:3]))
        try:
            r = subprocess.run(["vvp", vvp_file] + e["plusargs"], cwd=root, capture_output=True, text=True, timeout=timeout)
            out = r.stdout + r.stderr
            if r.returncode != 0: problems.append(f"vvp exit status {r.returncode}")
        except subprocess.TimeoutExpired as ex:
            out = (ex.stdout or b"").decode(errors="replace") if isinstance(ex.stdout, bytes) else (ex.stdout or ""); problems.append(f"timeout after {timeout}s")
        sums = [m for m in (SUMMARY.match(l) for l in out.splitlines()) if m]
        if len(sums) != 1: problems.append(f"expected exactly 1 summary line, found {len(sums)}")
        else:
            m = sums[0]; summary = m
            if m.group(2) != "TIMEOUT" and not re.search(r"\bVECTORS \d+\b", m.group(5)): problems.append("summary lacks the standard 'VECTORS <n>' field")
            if m.group(1) != e["expect"]: problems.append(f"summary names '{m.group(1)}', manifest expects '{e['expect']}'")
            if m.group(2) == "TIMEOUT": problems.append("testbench reported TIMEOUT")
            else:
                p, f = int(m.group(3)), int(m.group(4))
                if f: problems.append(f"{f} assertion(s) failed")
                if p < 1: problems.append("no assertion executed (PASS 0)")
        for l in out.splitlines():
            if BAD_LINE.match(l) and not SUMMARY.match(l): problems.append("output line: " + l[:100]); break
    res = dict(id=e["id"], name=e["expect"], status="FAIL" if problems else "PASS", problems=problems,
               passed=int(summary.group(3)) if summary and summary.group(3) else 0, failed=int(summary.group(4)) if summary and summary.group(4) else 0,
               extra=(summary.group(5).strip() if summary else ""), log=[l for l in out.splitlines() if KEEP.match(l)], seconds=round(time.time() - t0, 1))
    return res

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--manifest"); ap.add_argument("--only"); ap.add_argument("--timeout", type=int, default=600); ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--no-strict-warnings", action="store_true"); ap.add_argument("--log"); ap.add_argument("--json"); ap.add_argument("--builddir")
    a = ap.parse_args(argv); root = a.root
    entries = load_manifest(a.manifest or os.path.join(root, "sim", "testbenches.txt"))
    if a.only: want = set(a.only.split(",")); entries = [e for e in entries if e["id"] in want]; assert entries, "no testbench matches --only"
    builddir = a.builddir or os.path.join(root, "sim", "build")
    with ThreadPoolExecutor(a.jobs) as ex: results = list(ex.map(lambda e: run_testbench(e, root, builddir, a.timeout, not a.no_strict_warnings), entries))
    log = a.log or os.path.join(root, "results", "sim_log.txt"); os.makedirs(os.path.dirname(log), exist_ok=True)
    with open(log, "w") as fh:
        for r in results:
            for l in r["log"]: fh.write(l + "\n")
    print(f"{'testbench':24s} {'status':6s} {'PASS':>6s} {'FAIL':>5s}  details")
    for r in results:
        print(f"{r['name']:24s} {r['status']:6s} {r['passed']:6d} {r['failed']:5d}  {r['extra'] or ''}{' <-- ' + '; '.join(r['problems']) if r['problems'] else ''}  ({r['seconds']}s)")
    nf = sum(1 for r in results if r["status"] != "PASS")
    summ = dict(testbenches=len(results), passed_testbenches=len(results) - nf, failed_testbenches=nf, assertions_passed=sum(r["passed"] for r in results), assertions_failed=sum(r["failed"] for r in results),
                per_testbench=[dict(name=r["name"], status=r["status"], passed=r["passed"], failed=r["failed"], extra=r["extra"], problems=r["problems"]) for r in results])
    jp = a.json or os.path.join(root, "results", "regression_summary.json")
    with open(jp, "w") as jf: json.dump(summ, jf, indent=1)
    print(f"\n{summ['testbenches']} testbenches, {summ['passed_testbenches']} passed, {nf} failed; assertions passed={summ['assertions_passed']} failed={summ['assertions_failed']}")
    print("REGRESSION PASSED" if nf == 0 else "REGRESSION FAILED"); return 0 if nf == 0 else 1

if __name__ == "__main__": sys.exit(main())
