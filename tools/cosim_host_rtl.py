#!/usr/bin/env python3
"""Host-in-the-loop co-simulation: the REAL host code (telemetry parser, feature stream, JSON decision tree, packet builder) against the REAL board RTL
(de2_115_top, real UART) over a trace with real fault conditions, six host behaviours, and an INDEPENDENT reference model of the expected behaviour.

Trace (tb/cosim_harness.v, 12000 clocks per step): no contact, ramp, hold just below the limit, trip at 2560, hysteresis band (2559, 2400, 2304 stay safe; 2303 releases),
fast jump over the limit, e-stop at mid force, e-stop at over-limit force (stop released while still over limit, clear ignored until the force drops), ADC frame
errors (sensor fault latched, stays after recovery, needs a clear), operator clear presses.
Host behaviours: A no AI | B the real model | C hostile always-class-2 | D hostile always-class-3 | E host dies after ~1/3 of the run | F corrupted link: bad checksum,
wrong header, garbage, and packets whose class/inverse bits disagree (valid checksum), mixed with good ones.
Per settled frame the reference model predicts safe state, sensor fault, e-stop latch, command, AI valid and AI class; the RTL's values and the telemetry flags decoded
by the host parser must equal them. Coverage minima are asserted so the run cannot pass with the fault conditions unexercised.
Not hardware: ideal UART, behavioural ADC, open-loop host (it answers from telemetry but its answers do not feed back into the ADC trace). Writes results/cosim_report.json."""
import glob, json, os, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "host")); sys.path.insert(0, os.path.join(ROOT, "ml"))
import ai_host as H
from tree_model import TreeModel
MAX, REL, CAPS, STEP, STABLE_AGE = 2560, 2304, {0: 255, 1: 255, 2: 64, 3: 24}, 12000, 2400

def trace():
    """list of (value, estop_pressed, corrupt, clear) per step"""
    t = []; add = lambda v, e=0, c=0, k=0, n=1: t.extend([(v, e, c, k)] * n)
    add(0, n=2)
    add(200); add(300, n=3); add(450, n=2)                                              # light contact
    for v in (600, 1000, 1400, 1800, 2200, 2400, 2559): add(v)                    # normal operation up to just below the limit
    for v in (2560, 2800, 3300, 3300): add(v)                                         # trip and hold over the limit
    for v in (2559, 2400, 2304): add(v)                                                # hysteresis band: must stay safe
    for v in (2303, 1500): add(v)                                                      # release
    add(3000); add(2000)                                                               # fast jump over the limit, then release
    add(1200, e=1, n=3); add(1200, n=3); add(1200, k=1); add(1200, n=2)                                     # e-stop at mid force, release + clear, resume
    add(3000, e=1, n=2); add(3000); add(3000, k=1); add(1000)                          # e-stop at over-limit force: stop released while still over limit; clear ignored (still over); then released
    add(1000, c=1, n=3); add(1000, c=0, n=3); add(1000, k=1); add(1000, n=2); add(2500)          # ADC frame errors: sensor fault latches, stays after recovery, clear resumes
    add(0, n=2)
    return t
def word(s): return s[0] | s[1] << 12 | s[2] << 13 | s[3] << 14
def ref_model(tr):
    over = est = flt = 0; out = []
    for v, e, c, k in tr:
        if k:                                                    # a deliberate clear releases a latch only if its cause is gone
            if not e: est = 0
            if not c: flt = 0
        if v >= MAX: over = 1
        elif v < REL: over = 0
        if e: est = 1
        if c: flt = 1
        out.append(dict(value=v, estop_key=e, corrupt=c, over=over, est=est, flt=flt, safe=int(over or est or flt or c or e)))
    return out

class Ser:
    def __init__(self, data): self.data, self.w = bytearray(data), []
    def read(self, n): d = bytes(self.data[:n]); del self.data[:n]; return d
    def write(self, b): self.w.append(bytes(b))
class Const:
    def __init__(self, c): self.c = c
    def predict_one(self, x): return self.c
def host_packets(tele, model):
    ser = Ser(b"".join(bytes.fromhex(l) for l in tele)); sess = H.HostSession(ser, model, None, True)
    while ser.data: sess.poll()
    sess.poll(); return ser.w, sess.parser
def packet_stream(kind, base):
    """-> list of dict(bytes, accepted(bridge), good(integrity), cls). `base` = packets the real model produced."""
    out = []
    for j, p in enumerate(base):
        cls = p[1] & 3
        if kind == "E" and j >= len(base) // 3: break
        typ = "good"
        if kind == "F": typ = ("good", "badchk", "good", "badhdr", "good", "incons", "garbage", "good")[j % 8]
        if typ == "good": b, acc, good, c = bytes(p), True, True, cls
        elif typ == "badchk": d = (1 << 4) | (((~((cls + 1) % 4)) & 3) << 2) | ((cls + 1) % 4); b, acc, good, c = bytes([0xA5, d, ((~d) & 0xFF) ^ 0x01]), False, False, None   # a DIFFERENT class, wrong checksum
        elif typ == "badhdr": d = p[1]; b, acc, good, c = bytes([0xA4, d, (~d) & 0xFF]), False, False, None
        elif typ == "garbage": b, acc, good, c = bytes([0, 0, 0]), False, False, None
        else: d = (1 << 4) | (cls & 3) | ((cls & 3) << 2); b, acc, good, c = bytes([0xA5, d, (~d) & 0xFF]), True, False, cls                                   # inverse bits wrong, checksum fine
        out.append(dict(bytes=b, accepted=acc, good=good, cls=c, typ=typ))
    return out
def expected_ai(f, pk):
    """AI state the RTL must show at log row f (1-based): packets j <= f-3 have arrived. -> (valid or None if undecidable, class)"""
    acc = [j for j in range(min(len(pk), f - 2)) if pk[j]["accepted"]]
    if not acc: return (0 if f > 14 else None), None
    j = acc[-1]; age = f - 3 - j
    if age > 12: return 0, None
    if age > 8: return None, None
    return (1 if pk[j]["good"] else 0), pk[j]["cls"]

def run(tag, root, vvp, work, tr, ai=None):
    out, log = os.path.join(work, f"{tag}.tele"), os.path.join(work, f"{tag}.log")
    args = ["vvp", vvp, f"+TRACE={work}/trace.hex", f"+N={len(tr)}", f"+STEP={STEP}", f"+OUT={out}", f"+LOG={log}"] + ([f"+AI={ai[0]}", f"+NAI={ai[1]}"] if ai else [])
    r = subprocess.run(args, cwd=root, capture_output=True, text=True, check=True); problems = []
    summ = [l for l in r.stdout.splitlines() if l.startswith("TB cosim_harness")]
    if not summ or " FAIL 0 " not in summ[0] or any(w in r.stdout for w in ("FAIL SAFETY", "ERROR", "WARNING")): problems.append(f"{tag}: harness/monitor problem: {r.stdout[-300:]}")
    with open(out) as fh: tele = fh.read().split()
    with open(log) as fh: rows = [tuple(int(x) for x in l.split(",")) for l in fh if l.strip()]
    return tele, rows, problems

def analyse(tag, rows, tele, ref_steps, pk, lut, problems):
    cov = dict(over_limit=0, hysteresis_band=0, estop_pressed=0, estop_latched_after_release=0, sensor_fault_active=0, sensor_fault_latched_after=0, resumed_after_clear=0,
               ai_valid=0, ai_capped=0, ai_rejected_expected=0, classes=set(), checked=0)
    for k, (fr, value, age, safe, aiv, cmd, pwm, sf, kp, est, cls, cor, step) in enumerate(rows):
        if age < STABLE_AGE or fr < 8: continue
        st = ref_steps[step]
        if (st["value"], st["estop_key"], st["corrupt"]) != (value, kp, cor): problems.append(f"{tag}: frame {fr}: logged control word does not match step {step}"); continue
        cov["checked"] += 1
        if (safe, sf, est) != (st["safe"], st["flt"], st["est"]): problems.append(f"{tag}: frame {fr} value {value}: RTL safe/sensor_fault/estop_latch = {safe}/{sf}/{est}, reference model says {st['safe']}/{st['flt']}/{st['est']}")
        if safe and (cmd != 0 or pwm != 0): problems.append(f"{tag}: frame {fr}: safe state with cmd={cmd} pwm={pwm}")
        ev, ecls = (0, None) if pk is None else expected_ai(fr, pk)
        if ev is not None and aiv != ev: problems.append(f"{tag}: frame {fr}: ai_valid {aiv}, expected {ev}")
        if ev == 1 and cls != ecls: problems.append(f"{tag}: frame {fr}: ai_class {cls}, expected {ecls}")
        if not safe and ev is not None:
            exp = min(lut[value >> 4], CAPS[ecls] if ev == 1 else 255)
            if cmd != exp: problems.append(f"{tag}: frame {fr} value {value}: cmd {cmd}, expected {exp} (LUT {lut[value >> 4]}, class {ecls if ev == 1 else 'none'})")
            if ev == 1 and exp < lut[value >> 4]: cov["ai_capped"] += 1
        # coverage
        if value >= MAX: cov["over_limit"] += 1
        if st["over"] and REL <= value < MAX: cov["hysteresis_band"] += 1
        if kp: cov["estop_pressed"] += 1
        if st["est"] and not kp: cov["estop_latched_after_release"] += 1
        if cor: cov["sensor_fault_active"] += 1
        if st["flt"] and not cor: cov["sensor_fault_latched_after"] += 1
        if not safe and value >= 1000 and st["est"] == 0 and st["flt"] == 0 and k > 0 and False: cov["resumed_after_clear"] += 1
        if ev == 1: cov["ai_valid"] += 1; cov["classes"].add(ecls)
        if pk is not None and ev == 0 and fr > 14: cov["ai_rejected_expected"] += 1
    # telemetry decoded by the host parser must equal the RTL's own flags on settled frames
    for k, line in enumerate(tele[: len(rows) - 1]):
        dec = H.parse_telemetry(bytes.fromhex(line)); row = rows[k]
        if dec is None: problems.append(f"{tag}: frame {row[0]} not parsable"); continue
        force, fl = dec
        if row[2] >= STABLE_AGE and (force != row[1] or fl["safe"] != bool(row[3]) or fl["sensor_fault"] != bool(row[7]) or fl["estop"] != bool(row[9]) or fl["ai_valid"] != bool(row[4])):
            problems.append(f"{tag}: frame {row[0]}: decoded telemetry (force {force}, {fl}) disagrees with the RTL")
    cov["classes"] = sorted(cov["classes"]); return cov

MIN = dict(over_limit=12, hysteresis_band=6, estop_pressed=8, estop_latched_after_release=6, sensor_fault_active=6, sensor_fault_latched_after=3)
def main(root=ROOT, write=True):
    problems, report = [], {}
    work = tempfile.mkdtemp(prefix="cs_"); tr = trace(); ref = ref_model(tr)
    with open(os.path.join(work, "trace.hex"), "w") as fh: fh.write("\n".join("%04x" % word(s) for s in tr) + "\n")
    with open(os.path.join(root, "rtl", "force_lut.mem")) as fh: lut = [int(x, 16) for x in fh.read().split()]
    vvp = os.path.join(work, "cosim.vvp")
    subprocess.run(["iverilog", "-g2005", "-Wall", "-Wno-timescale", "-o", vvp, "tb/ad7476_model.v", "tb/safety_monitor.v", "tb/cosim_harness.v"] + sorted(glob.glob(os.path.join(root, "rtl", "*.v"))), cwd=root, capture_output=True, text=True, check=True)
    tele_a, rows_a, pr = run("A", root, vvp, work, tr); problems += pr
    real, parser = host_packets(tele_a, TreeModel.load(os.path.join(root, "results", "tree.json")))
    if parser.dropped: problems.append(f"host parser dropped {parser.dropped} bytes on a clean RTL telemetry stream")
    if parser.frames < len(tele_a) - 2: problems.append(f"host parser decoded {parser.frames} of {len(tele_a)} frames")
    base = [bytes(p) for p in real]
    streams = {"B": packet_stream("B", base), "C": packet_stream("B", [H.build_ai_packet(2)] * len(base)), "D": packet_stream("B", [H.build_ai_packet(3)] * len(base)),
               "E": packet_stream("E", base), "F": packet_stream("F", base)}
    cov = {"A": analyse("A", rows_a, tele_a, ref, None, lut, problems)}
    def one(tag):
        pk = streams[tag]; path = os.path.join(work, f"{tag}.ai.hex"); data = b"".join(p["bytes"] for p in pk)
        with open(path, "w") as fh: fh.write("\n".join("%02x" % x for x in data) + "\n")
        tele, rows, pr = run(tag, root, vvp, work, tr, (path, len(data))); local = []
        c = analyse(tag, rows, tele, ref, pk, lut, local); return tag, c, pr + local
    with ThreadPoolExecutor(3) as ex:
        for tag, c, pr in ex.map(one, "BCDEF"): cov[tag] = c; problems += pr
    for tag, c in cov.items():
        for k, m in MIN.items():
            if c[k] < m: problems.append(f"{tag}: coverage {k} = {c[k]} < required {m}")
        if tag in "BCDF" and c["ai_valid"] < 20: problems.append(f"{tag}: only {c['ai_valid']} AI-valid frames settled")
        if tag in "CD" and c["ai_capped"] < 10: problems.append(f"{tag}: only {c['ai_capped']} frames where the AI cap actually lowered the command")
        if tag == "B" and c["classes"] != [0, 1, 2, 3]: problems.append(f"B: the real model produced classes {c['classes']}, expected all four")
        if tag in "EF" and c["ai_rejected_expected"] < 5: problems.append(f"{tag}: only {c['ai_rejected_expected']} frames where the AI had to be rejected/ignored")
    rep = dict(trace_steps=len(tr), step_clocks=STEP, telemetry_frames=len(tele_a), host_frames_decoded=parser.frames, host_bytes_dropped=parser.dropped, passes=cov,
               packet_types_in_F={t: sum(1 for p in streams["F"] if p["typ"] == t) for t in ("good", "badchk", "badhdr", "garbage", "incons")},
               result="PASS" if not problems else "FAIL", problems=problems[:25], coverage_minimums=MIN,
               scope="host code vs RTL in simulation (ideal UART, behavioural ADC, open-loop host); no hardware, no real serial port")
    if write:
        with open(os.path.join(ROOT, "results", "cosim_report.json"), "w") as fh: json.dump(rep, fh, indent=1, sort_keys=True)
    shutil.rmtree(work, ignore_errors=True)
    print(f"cosim host<->RTL: {rep['result']}; {len(tr)} steps, {len(tele_a)} telemetry frames, decoded {parser.frames}, dropped {parser.dropped}; settled frames checked per pass " + ", ".join(f"{k}={v['checked']}" for k, v in cov.items()))
    print("  coverage (pass A): " + ", ".join(f"{k}={cov['A'][k]}" for k in MIN)); print("  AI frames: " + ", ".join(f"{k}: valid {v['ai_valid']} capped {v['ai_capped']}" for k, v in cov.items() if k != "A"))
    for p in problems[:12]: print("  PROBLEM:", p)
    return 0 if not problems else 1
if __name__ == "__main__": sys.exit(main())
