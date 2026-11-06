#!/usr/bin/env python3
"""Characterise how much ADC output delay the RTL tolerates IN SIMULATION, with the MISO synchroniser (the RTL as it is) and without it (the earlier wiring).
The behavioural ADC model has zero output delay; this tool builds a temporary copy of the model that delays every MISO update by DLY ns after the SCLK falling edge
(and the first bit after the chip-select falling edge) and runs tb_top against it. A run PASSES when all of tb_top's assertions pass.

WHAT THIS IS: the RTL's own sampling-window margin, measured against an idealised delay. WHAT IT IS NOT: a statement about the real AD7476A. The real part's
output delay and the board / pin delays are UNKNOWN here (datasheet unobtainable, no scope), so the numbers below are NOT evidence of hardware safety in either direction.
Why the synchroniser costs margin: the first data bit is sampled 3 clocks (60 ns) after chip-select falls without it, but only 1 clock (20 ns) with it; later bits 6 clocks
(120 ns) versus 4 clocks (80 ns). The first bit carries the frame-error indication.
Usage: python3 tools/adc_timing_sweep.py [--delays 0,20,22,60,62] [--json results/adc_timing_sweep.json]"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(p):
    with open(os.path.join(ROOT, p)) as fh: return fh.read()
def build(variant, d):
    os.makedirs(os.path.join(d, "rtl")); os.makedirs(os.path.join(d, "results"))
    for f in glob.glob(os.path.join(ROOT, "rtl", "*")): shutil.copy(f, os.path.join(d, "rtl"))
    if variant == "without_synchroniser":
        p = os.path.join(d, "rtl", "tactile_reflex_top.v"); t = read("rtl/tactile_reflex_top.v"); assert ".adc_miso(ms[1])" in t
        with open(p, "w") as fh: fh.write(t.replace(".adc_miso(ms[1])", ".adc_miso(adc_miso)"))
def run_one(args):
    variant, dly = args; d = tempfile.mkdtemp(prefix="adcsweep_")
    try:
        build(variant, d); m = read("tb/ad7476_model.v")
        m = m.replace("module ad7476_model (", "module ad7476_model #(parameter real DLY = 0.0) (").replace("idx = 15; miso = frame[15]; end", "idx = 15; #(DLY) miso = frame[15]; end").replace("begin idx = idx - 1; miso = frame[idx]; end", "begin idx = idx - 1; #(DLY) miso = frame[idx]; end")
        assert m.count("#(DLY)") == 2
        tb = read("tb/tb_top.v"); assert "ad7476_model adc (" in tb
        with open(os.path.join(d, "model.v"), "w") as fh: fh.write(m)
        with open(os.path.join(d, "tb.v"), "w") as fh: fh.write(tb.replace("ad7476_model adc (", f"ad7476_model #(.DLY({dly}.0)) adc ("))
        shutil.copy(os.path.join(ROOT, "tb", "safety_monitor.v"), os.path.join(d, "mon.v"))
        subprocess.run(["iverilog", "-g2005", "-Wno-timescale", "-o", os.path.join(d, "a.vvp"), "model.v", "mon.v", "tb.v"] + sorted(glob.glob(os.path.join(d, "rtl", "*.v"))), cwd=d, capture_output=True, text=True, check=True)
        r = subprocess.run(["vvp", "a.vvp"], cwd=d, capture_output=True, text=True, timeout=120)
        m2 = re.search(r"TB tb_top: (PASS (\d+) FAIL (\d+)|TIMEOUT)", r.stdout); fails = [re.sub(r"@\d+", "@t", l)[:100] for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if not m2: return variant, dly, dict(result="NO SUMMARY", failing=fails)
        return variant, dly, dict(result="TIMEOUT" if m2.group(1) == "TIMEOUT" else ("PASS" if m2.group(3) == "0" else "FAIL"), assertions_failed=int(m2.group(3) or 0), failing=sorted(set(fails))[:3])
    finally: shutil.rmtree(d, ignore_errors=True)
def sweep(delays):
    jobs = [(v, d) for v in ("with_synchroniser", "without_synchroniser") for d in delays]
    with ThreadPoolExecutor(4) as ex: res = list(ex.map(run_one, jobs))
    out = dict(delays_ns=delays, results={v: {} for v in ("with_synchroniser", "without_synchroniser")})
    for v, d, r in res: out["results"][v][str(d)] = r
    for v in out["results"]:
        ds = sorted(delays); first_fail = next((d for d in ds if out["results"][v][str(d)]["result"] != "PASS"), None)
        passes = [d for d in ds if out["results"][v][str(d)]["result"] == "PASS" and (first_fail is None or d < first_fail)]
        out["results"][v]["largest_passing_ns"] = max(passes) if passes else None; out["results"][v]["smallest_failing_ns"] = first_fail
    out["caveat"] = "simulation of the RTL against an idealised delayed model; says nothing about the real AD7476A, whose timing is unverified (H-16 stays an open hardware blocker)"
    return out
if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--delays", default="0,10,20,22,30,40,50,60,62,70,80,100"); ap.add_argument("--json", default=os.path.join(ROOT, "results", "adc_timing_sweep.json"))
    a = ap.parse_args(); out = sweep([int(x) for x in a.delays.split(",")])
    with open(a.json, "w") as fh: json.dump(out, fh, indent=1, sort_keys=True)
    for v, r in out["results"].items(): print(f"{v:22s} largest passing delay {r['largest_passing_ns']} ns, smallest failing {r['smallest_failing_ns']} ns  " + " ".join(f"{d}:{r[str(d)]['result'][0]}" for d in out["delays_ns"]))
    print(out["caveat"])
