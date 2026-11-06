#!/usr/bin/env python3
"""Fails if HAZARD_ANALYSIS.md cites something that does not exist: a testbench (tb_*), a mutant (Mnn, must be KILLED in results/mutation_report.json),
a safety-monitor invariant (S1..), a formal property (P1..), or a repository file. Also requires every requirement row to cite evidence."""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(p):
    with open(os.path.join(ROOT, p)) as fh: return fh.read()
def main(doc="HAZARD_ANALYSIS.md"):
    text = read(doc); bad = []
    tbs = {l.split("|")[3].strip() for l in read("sim/testbenches.txt").splitlines() if l.strip() and not l.lstrip().startswith("#") and l.count("|") == 3}
    rep = json.loads(read("results/mutation_report.json")); status = {m["id"]: m["status"] for m in rep["mutants"]}
    inv_s = set(re.findall(r"//\s+(S\d)\b", read("tb/safety_monitor.v"))); inv_p = set(re.findall(r"//\s+(P\d+)\b", read("formal/gov_props.v"))); inv_w = set(re.findall(r"//\s+(W\d)\b", read("formal/pwm_props.v")))
    for t in sorted(set(re.findall(r"\btb_\w+", text))):
        if t not in tbs: bad.append(f"unknown testbench {t}")
    for m in sorted(set(re.findall(r"\bM\d\d\b", text))):
        if status.get(m) != "KILLED": bad.append(f"mutant {m}: {status.get(m, 'not in report')} (must be KILLED)")
    for s in sorted(set(re.findall(r"\bS\d\b", text))):
        if s not in inv_s: bad.append(f"unknown safety-monitor invariant {s}")
    for w in sorted(set(re.findall(r"\bW\d\b", text))):
        if w not in inv_w: bad.append(f"unknown formal property {w}")
    for p in sorted(set(re.findall(r"\bP\d+\b", text))):
        if p not in inv_p: bad.append(f"unknown formal property {p}")
    for f in sorted(set(re.findall(r"`([\w./-]+/[\w./-]+|[\w-]+\.(?:py|v|md|sh|json))`", text))):
        if not os.path.exists(os.path.join(ROOT, f)): bad.append(f"missing file {f}")
    for row in re.findall(r"^\| (R-\d+) \|(.*)$", text, re.M):
        if not re.search(r"\btb_\w+|\bM\d\d\b|\bS\d\b|\bP\d+\b|\bW\d\b|tools/|tests/", row[1]): bad.append(f"{row[0]}: no evidence cited")
    hz = re.findall(r"^\| (H-\d+) \|", text, re.M); rq = re.findall(r"^\| (R-\d+) \|", text, re.M)
    cited = set(re.findall(r"\bM\d\d\b", text)); uncited = sorted(set(status) - cited)
    print(f"traceability: {len(hz)} hazards, {len(rq)} requirements, {len(cited)} mutants cited (uncited: {', '.join(uncited) or 'none'}) -> " + ("OK" if not bad else f"{len(bad)} PROBLEM(S)"))
    for b in bad: print("  PROBLEM:", b)
    return 1 if bad else 0
if __name__ == "__main__": sys.exit(main())
