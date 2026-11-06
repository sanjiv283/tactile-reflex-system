"""Loads ONLY real project evidence (read-only). Every number used in the video comes from here."""
import json, re, csv, collections
P = "/home/user/tactile-reflex-system/"
def read(p): return open(P + p, encoding="utf-8").read()

def sim_log():
    tb, res = collections.OrderedDict(), []
    # the video was rendered from the regression log of git commit 96b5025 (12 original testbenches, 175 checks); pinned so its claims stay checkable
    for l in read("demo_video/evidence_snapshot/sim_log_at_render.txt").splitlines():
        m = re.match(r"TB (\w+): PASS (\d+) FAIL (\d+)", l)
        if m: tb[m.group(1)] = (int(m.group(2)), int(m.group(3)))
        if l.startswith("RESULT") or l.startswith("INFO"): res.append(l)
    return tb, res
def trace(name):
    rows = list(csv.DictReader(open(P + f"results/{name}.csv")))
    return {k: [int(r[k]) for r in rows] for k in rows[0]}
def lut(): return [int(x, 16) for x in read("rtl/force_lut.mem").split()]
def ml(): return json.load(open(P + "results/ml_results.json"))
def pred(): return json.load(open(P + "results/pred_results.json"))
def v2_logs():
    model, rtl = collections.defaultdict(list), collections.defaultdict(list)
    for l in read("experiments/results_v2/model_log.txt").splitlines():
        f = l.split(",")
        if f[0] == "LOG": model[f[1]].append(dict(step=int(f[2]), code=int(f[4]), present=int(f[5]), ferr=int(f[6]), estop_n=int(f[7]), fclr=int(f[8]), safe=int(f[9]), cmd=int(f[10]), trip=int(f[11]), bl_safe=int(f[12]), bl_cmd=int(f[13])))
    for l in read("experiments/results_v2/rtl_log.txt").splitlines():
        f = l.split(",")
        rtl[f[1]].append(dict(step=int(f[2]), safe=int(f[3]), cmd=int(f[4]), trip=int(f[5]), sfault=int(f[6]), estop=int(f[7]), lat=int(f[8])))
    return model, rtl
def frames(pattern):
    out = []
    for l in read("experiments/validation/results_v2/frame_rtl_log.txt").splitlines():
        f = l.split(",")
        if f[1] == pattern: out.append(dict(frame=int(f[2]), safe=int(f[3]), cmd=int(f[4]), trip=int(f[5]), sfault=int(f[6]), estop=int(f[7])))
    return out
def code_lines(path, anchors):
    """anchors: list of (first_line, last_line) 1-based ranges from the real file."""
    L = read(path).split("\n"); out = []
    for a, b in anchors:
        grp = [(i + 1, L[i].replace("\t", "    ")) for i in range(a - 1, b)]
        ind = min((len(x) - len(x.lstrip()) for _, x in grp if x.strip()), default=0)
        out.append([(n, x[ind:]) for n, x in grp])
    return out
def summary_totals():
    t = [l for l in read("experiments/results_v2/summary.md").splitlines() if l.startswith("TOTAL")][0]; return t
