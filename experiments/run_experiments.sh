#!/bin/sh
# Reproduce the experiments from the repository root: model log, RTL replay of the same stimulus, dataset.
# Needs gcc, iverilog/vvp, python3 (stdlib only). Writes only under experiments/results/ (existing results/ is untouched).
set -e
cd "$(dirname "$0")/.."
R=experiments/results; mkdir -p $R/stim
python3 - <<'PY'
rows=[l.strip() for l in open('rtl/force_lut.mem') if l.strip()]
open('experiments/wokwi/force_lut_table.h','w').write("// GENERATED from rtl/force_lut.mem by experiments/run_experiments.sh. Do not edit.\n#define RM_LUT_INIT { "+",".join("0x"+r for r in rows)+" }\n")
PY
gcc -Wall -Wextra -o $R/model_host experiments/model_host.c
$R/model_host rtl/force_lut.mem > $R/model_log.txt          # exits non-zero if the model LUT differs from rtl/force_lut.mem
python3 experiments/analyze.py stim $R/model_log.txt $R/stim
iverilog -g2005 -o $R/tb_experiments.vvp tb/ad7476_model.v experiments/rtl/tb_experiments.v rtl/*.v
: > $R/rtl_log.txt
for f in $R/stim/*.hex; do
  id=$(basename $f .hex)
  vvp $R/tb_experiments.vvp +STIM=$f +ID=$id | grep '^RTL' >> $R/rtl_log.txt
done
python3 experiments/analyze.py report $R/model_log.txt $R/rtl_log.txt $R
iverilog -g2005 -o $R/tb_single_invalid.vvp tb/ad7476_model.v experiments/rtl/tb_single_invalid.v rtl/*.v
vvp $R/tb_single_invalid.vvp | grep -E "^(RTLX|ERROR)" | tee $R/rtl_single_invalid.txt
