# Latency-Optimal Tactile Reflex System

AI-assisted, deterministic FPGA tactile controller for robotic gripper actuation.
The PL (FPGA) path ADC -> conditioning -> fixed LUT -> Safety Governor -> PWM is independent of the AI/ML path.
The AI class (from the PS) can only lower the command and is ignored when invalid or when a hard limit trips.

## Layout
| Path | Content |
|---|---|
| `rtl/` | Synthesizable Verilog: `adc_interface`, `input_conditioning`, `force_lut` (+ `force_lut.mem`), `safety_governor`, `pwm_generator`, `fault_handler`, `ai_control_interface`, `tactile_reflex_top` |
| `tb/` | Testbenches (one per module, a system testbench, and a replay of ML outputs through the RTL) |
| `ml/` | Simulated dataset generator, decision-tree training and evaluation |
| `tools/` | LUT generator, trace plotting |
| `results/` | Logs, metrics, confusion matrix, waveforms (generated) |
| `docs/` | SDG alignment, circuit diagram, presentation |

## Run everything
```
pip install numpy scikit-learn matplotlib pandas
sim/run_all.sh        # needs iverilog
```

## Notes
- The ML dataset is SIMULATED (`ml/gen_sim_data.py`). Replace it with recorded FSR data using the same feature pipeline.
- Latency figures in `results/sim_log.txt` are RTL-simulation clock-cycle counts (100 MHz clock assumed) with an ideal behavioural ADC model.
- Inference timings in `results/ml_results.json` were taken on the development host, not the target processor.
