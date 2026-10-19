"""Check quartus/TactileReflexive.sdc against the real ports of quartus/TactileReflexive.v (no Quartus needed).

Every get_ports pattern in the SDC must name a port of the wrapper (and an index inside its range), create_clock must be on an
input, and no false path may target outputs (that would hide output timing paths). Exit status 1 on any problem.
Usage: python3 check_sdc_ports.py [wrapper.v] [constraints.sdc]
"""
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
v_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "TactileReflexive.v")
s_path = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "TactileReflexive.sdc")

ports = {}   # name -> (direction, high, low)
for line in re.sub(r"//.*", "", open(v_path).read()).splitlines():
    m = re.match(r"\s*(input|output|inout)\s+(?:wire\s+)?(?:\[(\d+):(\d+)\])?\s*(\w+)", line)
    if m:
        d, hi, lo, name = m.groups()
        ports[name] = (d, int(hi) if hi else 0, int(lo) if lo else 0)

problems = []
sdc = [re.sub(r"#.*", "", l).strip() for l in open(s_path).read().splitlines()]
sdc = [l for l in sdc if l]
n_patterns = 0
for line in sdc:
    for body in re.findall(r"get_ports\s*\{([^}]*)\}", line):
        for pat in body.split():
            n_patterns += 1
            m = re.fullmatch(r"(\w+)(?:\[(\*|\d+)\])?", pat)
            if not m or m.group(1) not in ports:
                problems.append(f"pattern '{pat}' matches no wrapper port")
                continue
            d, hi, lo = ports[m.group(1)]
            idx = m.group(2)
            if idx is None and hi != lo:
                problems.append(f"'{pat}' names a vector port without an index")
            elif idx not in (None, "*") and not lo <= int(idx) <= hi:
                problems.append(f"'{pat}' index outside [{hi}:{lo}]")
    if line.startswith("create_clock"):
        m = re.search(r"get_ports\s*\{(\w+)\}", line)
        if not m or ports.get(m.group(1), ("",))[0] != "input":
            problems.append("create_clock is not on an input port")
        if not re.search(r"-period\s+20(\.0+)?\b", line):
            problems.append("create_clock period is not 20 ns (50 MHz)")
    if line.startswith("set_false_path") and re.search(r"\s-to\b", line):
        problems.append("a false path targets outputs: " + line)
if not any(l.startswith("create_clock") for l in sdc):
    problems.append("no create_clock")
for p in problems:
    print("PROBLEM:", p)
print(f"checked {n_patterns} get_ports patterns against {len(ports)} wrapper ports: "
      + ("FAILED" if problems else "all match, no output false paths"))
sys.exit(1 if problems else 0)
