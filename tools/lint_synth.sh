#!/bin/sh
# Lint + generic synthesis with Yosys (no Quartus). Fails on: elaboration errors, undriven/multiply-driven nets or combinational loops reported by
# `check -assert`, inferred latches, or a missing top. Writes results/synth_report.json. The LUT4 count is a GENERIC ABC mapping estimate; it is NOT
# a Quartus fit, says nothing about timing closure, and the Fmax / resource numbers must come from Quartus on a machine that has it.
set -eu
cd "$(dirname "$0")/.."
TOP=${TOP:-de2_115_top}
mkdir -p results sim/build
LOG=sim/build/yosys_lint.log
# 1) Icarus with all warnings, no timescale noise (the regression runner already treats warnings as errors per testbench)
iverilog -g2005 -Wall -Wno-timescale -o sim/build/lint.vvp rtl/*.v 2>sim/build/iverilog_lint.txt || { cat sim/build/iverilog_lint.txt; exit 1; }
if [ -s sim/build/iverilog_lint.txt ]; then echo "iverilog warnings:"; cat sim/build/iverilog_lint.txt; exit 1; fi
# 2) Yosys: elaborate, structural checks, latch scan, generic synthesis to LUT4 + flip-flops
yosys -l "$LOG" -q -p "read_verilog rtl/*.v; hierarchy -check -top $TOP; proc; check -assert; flatten; opt_clean; tee -q -o results/synth_stat_raw.json stat -json; \
  synth -top $TOP -flatten; abc -lut 4; opt_clean; tee -q -o results/synth_stat_lut4.json stat -json" >/dev/null
if grep -qi "latch inferred" "$LOG"; then echo "latch inferred:"; grep -i "latch inferred" "$LOG"; exit 1; fi
python3 - <<'PY'
import json
def stat(p):
    with open(p) as fh: d = json.load(fh)
    return d["design"] if "design" in d else d
raw, lut = stat("results/synth_stat_raw.json"), stat("results/synth_stat_lut4.json")
cells = lut.get("num_cells_by_type", lut.get("cells", {}))
flops = sum(v for k, v in cells.items() if "DFF" in k.upper() or "dff" in k)
luts = sum(v for k, v in cells.items() if k.upper().startswith("$_LUT") or "LUT" in k.upper())
mem = {k: v for k, v in cells.items() if "mem" in k.lower()}
latches = sum(v for k, v in cells.items() if "LATCH" in k.upper())
assert latches == 0, f"{latches} latch cell(s) in the netlist"
rep = dict(tool="yosys generic synthesis", top="de2_115_top", lut4_estimate=luts, flip_flops=flops, latches=latches, cell_types=cells, memory_cells=mem,
           note="generic ABC LUT4 mapping, not a Quartus fit; no timing analysis; Cyclone IV EP4CE115 has 114,480 LEs (for scale only)")
with open("results/synth_report.json", "w") as fh: json.dump(rep, fh, indent=1, sort_keys=True)
print(f"lint/synth OK: LUT4 estimate {luts}, flip-flops {flops} (generic Yosys mapping; Quartus not run)")
PY
rm -f results/synth_stat_raw.json results/synth_stat_lut4.json
