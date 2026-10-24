#!/bin/sh
# Run every testbench from the repository root. Needs iverilog + python3 (numpy, scikit-learn, matplotlib).
set -e
cd "$(dirname "$0")/.."
mkdir -p results sim/build
python3 tools/gen_lut.py
python3 ml/train_eval.py > results/ml_log.txt
: > results/sim_log.txt
for t in adc_interface input_conditioning force_lut safety_governor pwm_generator fault_handler ai_control_interface top; do
  iverilog -g2005 -o sim/build/$t.vvp tb/ad7476_model.v tb/tb_$t.v rtl/*.v
  vvp sim/build/$t.vvp | grep -E "^(TB|FAIL|RESULT|INFO)" | tee -a results/sim_log.txt
done
iverilog -g2005 -o sim/build/replay.vvp tb/ad7476_model.v tb/tb_replay.v rtl/*.v
vvp sim/build/replay.vvp | grep -E "^(TB|FAIL|RESULT)" | tee -a results/sim_log.txt
vvp sim/build/replay.vvp +ADVERSARIAL | grep -E "^(TB|FAIL|RESULT)" | tee -a results/sim_log.txt
python3 tools/plot_traces.py
if grep -qE "FAIL [1-9]|^FAIL|TIMEOUT" results/sim_log.txt; then echo "SOME TESTS FAILED"; exit 1; fi
echo "ALL TESTBENCHES PASSED"
