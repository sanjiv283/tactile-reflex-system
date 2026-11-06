#!/usr/bin/env python3
"""Formal checks with Yosys `sat` (no sby needed). Three result classes, reported separately in results/formal_report.json:

  PROVEN        properties W1-W6 (pwm_props.v) and P1-P15 (gov_props.v). Each is a one-step relation of the transition function, checked from a FREE initial
                state (every register arbitrary, inputs free every clock): no counterexample means it holds in every state the modules can ever reach, for all
                input sequences. This includes every counter value of the 4,096-clock PWM period. It is a proof about THESE two modules only.
  BOUNDED       none is claimed by this script. (An earlier reset-anchored 14-clock check was vacuous for the PWM kill and has been replaced.)
  NOT ESTABLISHED  everything else: the slope predictor, the LUT, fault handling, debounce, UART, host, timing, analogue behaviour; plus any mutant listed below as 'not refuted'.

The checks need to see internal registers (counter, active duty, armed, force latch). tools/formal_check.py therefore builds INSTRUMENTED COPIES of
pwm_generator.v and safety_governor.v in a temporary directory: the only change is extra output ports wired to existing registers.
Negative controls: every governor/PWM mutant of tools/mutation_test.py is run through the same check; the table says which the formal check refutes.
Exit 1 if a property fails on the real RTL, or a mutant listed in MUST_REFUTE is not refuted."""
import json, os, re, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import mutation_test as mt
# mutants the formal properties are required to refute (others are reported as "not refuted" = covered by simulation only)
MUST_REFUTE = {"M01", "M02", "M03", "M04", "M05", "M06", "M08", "M09", "M10", "M11", "M13", "M42", "M43", "M44", "M45", "M46", "M47", "M48", "M49"}
EXPECT_NOT_REFUTED = {"M07", "M12"}      # predictor: not asserted formally
DEPTH = 5
def read(p):
    with open(os.path.join(ROOT, p)) as fh: return fh.read()
def instrument_gov(t):
    t, n = re.subn(r"(output reg\s+ai_overridden)([^\n]*)\n\);", r"\1,\2\n    output wire        dbg_armed,\n    output wire        dbg_force_over\n);", t, count=1); assert n == 1
    return t.replace("endmodule", "    assign dbg_armed = armed; assign dbg_force_over = force_over;\nendmodule")
def instrument_pwm(t):
    t, n = re.subn(r"(output reg\s+pwm_out)\n\);", r"\1,\n    output wire [11:0] dbg_cnt,\n    output wire [7:0]  dbg_da\n);", t, count=1); assert n == 1
    return t.replace("endmodule", "    assign dbg_cnt = cnt; assign dbg_da = duty_active;\nendmodule")
def run(files, top, params=()):
    cmd = f"read_verilog -formal {' '.join(files)}; " + "".join(f"chparam -set {k} {v} {top}; " for k, v in params) + \
          f"prep -top {top}; flatten; async2sync; dffunmap; sat -seq {DEPTH} -prove-asserts -verify"
    r = subprocess.run(["yosys", "-p", cmd], capture_output=True, text=True); o = r.stdout + r.stderr
    if r.returncode == 0 and "SUCCESS" in o: return "holds"
    if "proof did fail" in o or "model found" in o: return "REFUTED"
    return "TOOLERROR: " + o[-300:]
def check(gov_text, pwm_text, d):
    g, p = os.path.join(d, "g.v"), os.path.join(d, "p.v")
    with open(g, "w") as fh: fh.write(instrument_gov(gov_text))
    with open(p, "w") as fh: fh.write(instrument_pwm(pwm_text))
    res = {"W1-W6 (PWM)": run([p, os.path.join(ROOT, "formal", "pwm_props.v")], "pwm_props")}
    for pe in (0, 1): res[f"P1-P{15 if pe == 0 else 14} (governor + PWM, PRED_EN={pe})"] = run([g, p, os.path.join(ROOT, "formal", "gov_props.v")], "gov_props", [("PRED_EN", pe)])
    return res
def main():
    gov, pwm = read("rtl/safety_governor.v"), read("rtl/pwm_generator.v"); out = dict(depth=DEPTH, mutants={}); bad = []
    with tempfile.TemporaryDirectory() as d:
        base = check(gov, pwm, d); out["real_rtl"] = base
        for k, v in base.items():
            print(f"PROVEN (all states, free initial state) {k}" if v == "holds" else f"FAIL on the real RTL: {k}: {v}"); 
            if v != "holds": bad.append(k)
        for m in mt.M:
            mid, name, f, old, new = m
            if f not in ("rtl/safety_governor.v", "rtl/pwm_generator.v"): continue
            g2, p2 = (gov.replace(old, new), pwm) if f.endswith("governor.v") else (gov, pwm.replace(old, new))
            assert (g2 != gov) or (p2 != pwm), mid
            r = check(g2, p2, d); ref = [k for k, v in r.items() if v == "REFUTED"]; tool = [k for k, v in r.items() if v.startswith("TOOLERROR")]
            out["mutants"][mid] = dict(name=name, refuted_by=ref, status="refuted" if ref else "not refuted")
            if tool: bad.append(f"{mid}: tool error"); 
            if mid in MUST_REFUTE and not ref: bad.append(f"{mid} must be refuted but is not")
            if mid in EXPECT_NOT_REFUTED and ref: print(f"note: {mid} is now refuted (update EXPECT_NOT_REFUTED)")
    n = len(out["mutants"]); r = sum(1 for v in out["mutants"].values() if v["status"] == "refuted")
    out["summary"] = dict(mutants=n, refuted=r, not_refuted=sorted(k for k, v in out["mutants"].items() if v["status"] != "refuted"))
    out["classes"] = dict(proven="W1-W6, P1-P15 (see formal/*.v), for every state and input of safety_governor and pwm_generator", bounded="none claimed",
                          not_established="slope predictor (M07, M12), LUT, fault_handler, debounce/reset sync, UART, host, timing, analogue behaviour, any multi-clock liveness")
    with open(os.path.join(ROOT, "results", "formal_report.json"), "w") as fh: json.dump(out, fh, indent=1, sort_keys=True)
    print(f"formal-vs-mutants: {r} of {n} governor/PWM mutants refuted; not refuted: {out['summary']['not_refuted']}")
    for b in bad: print("  PROBLEM:", b)
    return 1 if bad else 0
if __name__ == "__main__": sys.exit(main())
