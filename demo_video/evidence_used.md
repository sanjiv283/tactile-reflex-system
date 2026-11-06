# Evidence used in the video

Every number on screen or in the narration comes from one of these files (all read-only; nothing was edited). Values are read programmatically by `build/data.py`.

| Claim in the video | Value | Source file |
|---|---|---|
| Directed checks passing (12 testbenches) | 175 / 175, 0 failures | results/sim_log.txt |
| Replay of 1,800 vectors, real decision tree and adversarial AI | replay mode=ml_tree_ai violations: safe_state=0 cmd_above_lut=0 ; replay mode=adversarial_ai violations: safe_state=0 cmd_above_lut=0 | results/sim_log.txt |
| Predictive pre-limit RTL vs reference model | pred_rtl_vs_model vectors=4720 expected_trips=50 mismatches=0 | results/sim_log.txt |
| Logic path / e-stop / input-change latency (clock cycles @ 50 MHz) | sample_valid_to_pwm_low_cycles min=4 max=4 jitter=0 ; estop_to_pwm_low_cycles min=5 max=5 jitter=0 ; adc_input_change_to_pwm_low_cycles min=105 max=192 jitter=87 | results/sim_log.txt |
| ADC frame period | ADC frame period = 104 clk cycles (2080 ns at 50 MHz) | results/sim_log.txt |
| Force-limit override waveform (AI says class 2, force 1024 → 2816, FORCE_MAX 2560) | 800 samples, 20 ns/sample | results/trace_override.csv |
| E-stop waveform (safe_state +4 clk, PWM low +5 clk) | 65 samples | results/trace_estop.csv |
| Lookup table curve (180 → 60 → 0) | 256 entries read from the file | rtl/force_lut.mem (generator: tools/gen_lut.py) |
| Experiment totals: model / RTL / baseline | 159/159 / 157/159 / 93/159 (15 scenarios, 159 checks) | experiments/results_v2/summary.md |
| Predictive trip at force code 2015 vs limit crossed at 2569 (12 steps = 6.0 ms stimulus time) | RTL replay scenario S08 | experiments/results_v2/rtl_log.txt, model_log.txt |
| Hysteresis: 2304 still inhibited, 2303 releases | RTL replay scenario S04 | experiments/results_v2/rtl_log.txt |
| Noisy crossing: baseline 7 toggles vs 1 inhibit | scenario S07 | experiments/results_v2/model_log.txt (baseline), rtl_log.txt |
| One bad ADC frame = one-frame inhibit, no latch; four bad frames latch the fault until clear | frame-level RTL runs (patterns ferr_001, ferr_004) | experiments/validation/results_v2/frame_rtl_log.txt |
| Watchdog: WD_CYCLES = 2000 clk (40 µs); measured forced-dropout runs | 1898–1985 clk (4 phases) | rtl/fault_handler.v ; experiments/validation/results_v2/dropout_and_frame_count.txt |
| 577 frame comparisons, 0 differences; 839 step comparisons, 0 differences; 13 step-level differences remain | see files | experiments/validation/results_v2/frame_summary.md, step_expansion_result.json ; summary.md |
| Predictive-trip cost: 25/25 crossing episodes tripped early, mean lead 5.72 ms; 10/155 (6.5%) early trips on never-crossing episodes | SIMULATED test episodes | results/pred_results.json |
| Decision-tree walk on the development host: mean 11.6 µs, p99 45.1 µs, max 96.5 µs (excludes the serial link) | dev host, not the target | results/ml_results.json |
| Decision-tree accuracy 91.9% vs force-only baseline 85.4% | SIMULATED dataset | results/ml_results.json |
| Source-code excerpts (ADC interface, conditioning, LUT, governor, PWM) | real lines with real line numbers | rtl/adc_interface.v 41-50, input_conditioning.v 15-24, force_lut.v 14-24, safety_governor.v 61-62/69/80-82, pwm_generator.v 13-21 |
| Architecture, parameters (FORCE_MAX 2560, FORCE_REL 2304, RAIL_HI 0xFF0, PWM 12.2 kHz, DE2-115 at 50 MHz) | design | rtl/*.v, README.md |

## Deliberately NOT shown or claimed
- Physical hardware operation of any kind (none exists in this work).
- Wokwi execution: the Wokwi demo is prepared but has **not been run**; the video says so.
- Any oscilloscope or board footage; all waveforms are RTL simulation (Icarus Verilog) data.
- The ML dataset is simulated; no recorded sensor data.