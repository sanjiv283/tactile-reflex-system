#!/bin/sh
# V2 (time-based watchdog model). Writes only experiments/results_v2/. Reproduce the experiments from the repository root: model log, RTL replay of the same stimulus, dataset.
# Needs gcc, iverilog/vvp, python3 (stdlib only). Writes only under experiments/results_v2/ (experiments/results/ is untouched).
set -e
cd "$(dirname "$0")/.."
R=experiments/results_v2; mkdir -p $R/stim
# (LUT table regeneration omitted: experiments/wokwi/force_lut_table.h is left untouched; model_host verifies it against rtl/force_lut.mem)
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
