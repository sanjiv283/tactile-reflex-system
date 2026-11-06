#!/bin/sh
# Full local flow, from the repository root:  sh sim/run_all.sh
# 1) regenerate the LUT and ML/predictor artifacts, 2) run the RTL regression (tools/run_regression.py, which fails on ANY
# problem: compile error, missing summary line, failing assertion, timeout, ...), 3) render the figures.
# Needs: iverilog, python3 with numpy scikit-learn matplotlib pandas (see requirements.txt).
set -eu
cd "$(dirname "$0")/.."
mkdir -p results sim/build
python3 tools/gen_lut.py
python3 ml/train_eval.py > results/ml_log.txt
python3 ml/pred_eval.py > results/pred_log.txt
python3 ml/validate.py > results/ml_validation_log.txt
python3 tools/gen_host_link_vectors.py
python3 tools/cdc_check.py
python3 tools/check_pins.py
python3 tools/check_wokwi.py
sh tools/lint_synth.sh
sh tools/formal_check.sh
python3 -W error::ResourceWarning -m unittest discover -s tests
python3 host/ai_host.py --selftest
python3 tools/adc_timing_sweep.py --delays 0,20,22,60,62
python3 tools/run_regression.py            # exits non-zero if any testbench is missing, failing or vacuous (set -e stops the script)
python3 tools/plot_traces.py
python3 tools/render_log.py
echo "ALL TESTBENCHES PASSED"
