#!/usr/bin/env python3
"""Consistency of the prepared Wokwi sketch with the current RTL (the sketch itself has NOT been run on Wokwi; that needs a wokwi.com login).
Checks: (1) every #define mirrored from the RTL equals the RTL parameter default, (2) the sketch's LUT table equals rtl/force_lut.mem,
(3) experiments/wokwi_single_v2/sketch_single.ino is exactly what make_single_v2.py generates from its sources, (4) the host build of the same
model (experiments/model_host.c, gcc -Wall -Wextra -Werror) compiles and reproduces experiments/results_v2/model_log.txt byte for byte."""
import os, re, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def read(p):
    with open(os.path.join(ROOT, p)) as fh: return fh.read()
def param(file, name):
    m = re.search(r"parameter\s+(?:\[[^\]]*\]\s*)?%s\s*=\s*([^,\s/]+)" % name, read(file)); v = m.group(1)
    if "'h" in v: return int(v.split("'h")[-1], 16)
    if "'d" in v: return int(v.split("'d")[-1])
    return int(v)
def main():
    bad = []; ino = read("experiments/wokwi_single_v2/sketch_single.ino")
    pairs = [("FORCE_MAX", "rtl/safety_governor.v", "FORCE_MAX"), ("FORCE_REL", "rtl/safety_governor.v", "FORCE_REL"), ("PRED_K", "rtl/safety_governor.v", "PRED_K"),
             ("PRED_MIN_DELTA", "rtl/safety_governor.v", "PRED_MIN_DELTA"), ("RAIL_HI", "rtl/input_conditioning.v", "RAIL_HI"),
             ("INVALID_LIMIT", "rtl/fault_handler.v", "INVALID_LIMIT"), ("WD_CLK", "rtl/fault_handler.v", "WD_CYCLES")]
    for d, f, p in pairs:
        m = re.search(r"#define\s+%s\s+(0x[0-9A-Fa-f]+|\d+)" % d, ino)
        if not m: bad.append(f"#define {d} not found in the sketch"); continue
        if int(m.group(1), 0) != param(f, p): bad.append(f"{d}: sketch {int(m.group(1), 0)} != RTL {f}:{p} {param(f, p)}")
    lut = [int(x, 16) for x in read("rtl/force_lut.mem").split()]
    m = re.search(r"RM_LUT_INIT\s*\{([^}]*)\}", ino); sk = [int(x, 16) for x in m.group(1).replace("\n", "").split(",") if x.strip()] if m else []
    if sk != lut: bad.append(f"sketch LUT ({len(sk)} entries) differs from rtl/force_lut.mem ({len(lut)} entries)")
    t = tempfile.mkdtemp()
    try:
        shutil.copytree(os.path.join(ROOT, "experiments"), os.path.join(t, "experiments"), ignore=shutil.ignore_patterns("build*", "results*", "validation"))
        subprocess.run([sys.executable, "experiments/wokwi_single_v2/make_single_v2.py"], cwd=t, check=True, capture_output=True)
        with open(os.path.join(t, "experiments/wokwi_single_v2/sketch_single.ino")) as fh: regen = fh.read()
        if regen != ino: bad.append("sketch_single.ino is not what make_single_v2.py generates from experiments/wokwi/*")
        exe = os.path.join(t, "model_host")
        c = subprocess.run(["gcc", "-Wall", "-Wextra", "-Werror", "-o", exe, os.path.join(ROOT, "experiments", "model_host.c")], capture_output=True, text=True)
        if c.returncode: bad.append("model_host.c: " + c.stderr[:200])
        else:
            r = subprocess.run([exe, os.path.join(ROOT, "rtl", "force_lut.mem")], capture_output=True, text=True, cwd=ROOT)
            if r.returncode: bad.append("model_host exited non-zero (model LUT differs from rtl/force_lut.mem?)")
            if r.stdout != read("experiments/results_v2/model_log.txt"): bad.append("model_host output differs from experiments/results_v2/model_log.txt")
    finally: shutil.rmtree(t, ignore_errors=True)
    print("wokwi sketch consistency: " + ("OK (constants, LUT, generated file, host model log) - sketch NOT run on Wokwi" if not bad else f"{len(bad)} PROBLEM(S)"))
    for b in bad: print("  PROBLEM:", b)
    return 1 if bad else 0
if __name__ == "__main__": sys.exit(main())
