# Latency-Optimal Tactile Reflex System

AI-assisted, deterministic FPGA tactile controller for robotic gripper actuation.
The PL (FPGA) path ADC -> conditioning -> fixed LUT -> Safety Governor -> PWM is independent of the AI/ML path.
The AI class (from the PS) can only lower the command and is ignored when invalid or when a hard limit trips.

## Layout
| Path | Content |
|---|---|
| `rtl/` | Synthesizable Verilog: `adc_interface`, `input_conditioning`, `force_lut` (+ `force_lut.mem`), `safety_governor`, `pwm_generator`, `fault_handler`, `ai_control_interface`, `tactile_reflex_top`, plus the UART link (`uart_rx`, `uart_tx`, `ai_uart_bridge`, `telemetry_tx`) and the board wrapper `de2_115_top` |
| `tb/` | Testbenches (18 listed in `sim/testbenches.txt`: per module, system, board wrapper, UART framing, reset/debounce, host link, replay), `safety_monitor.v`, co-simulation harness |
| `ml/` | Simulated dataset generator, decision-tree training/evaluation/validation, JSON model format (`tree_model.py`), real-data pipeline (`real_data_pipeline.py`) |
| `host/` | Laptop side: AI packets out, telemetry in, CSV logging (`ai_host.py`) |
| `constraints/` | DE2-115 SDC, pin file (**not verified**, see below), GPIO map |
| `tools/` | LUT generator, regression runner, mutation testing + audit, CDC/lint/formal checks, pin checker, Quartus project generator, calibration, artifact/experiment reproducibility checks, co-simulation, completion score |
| `tests/` | Python unit tests (runner, host, model format, real-data pipeline, calibration, pins, Quartus generator, co-simulation) |
| `formal/` | Bounded formal properties (Yosys `sat`) |
| `experiments/`, `paper/`, `demo_video/` | Scenario/validation experiments, the paper draft, the demo video (all simulation) |
| `results/` | Logs, metrics, confusion matrix, waveforms (generated) |
| `docs/` | SDG alignment, circuit diagram, presentation |

## Run everything
```
python3 -m venv .venv && .venv/bin/pip install -r requirements-lock.txt     # exact versions (Python 3.13); requirements.txt has ranges
sh sim/run_all.sh        # needs iverilog and yosys: LUT, ML, CDC, pins, lint/synth, formal, unit tests, regression, plots
```
Everything else (mutation campaign, reproducibility checks, co-simulation, traceability) is listed in `REPRODUCIBILITY_GUIDE.md`.

## Notes
- The ML dataset is SIMULATED (`ml/gen_sim_data.py`). Replace it with recorded FSR data using the same feature pipeline.
- Latency figures in `results/sim_log.txt` are RTL-simulation clock-cycle counts (50 MHz clock, as on the DE2-115) with an ideal behavioural ADC model.
- Inference timings in `results/ml_results.json` were taken on the development host, not the target processor.

## Target board: Terasic DE2-115 (Cyclone IV E EP4CE115F29C7, 50 MHz)
No ARM processor, so the AI/ML runs on a laptop over the board's RS-232 port (115200 8N1).
- FPGA to laptop: 3-byte telemetry about every 1 ms (`0x5A`, flags + force[11:8], force[7:0]).
- Laptop to FPGA: 3-byte AI packet `0xA5, DATA, ~DATA`. Advice only: ignored if invalid, stale (10 ms) or when a hard limit trips.
- Onboard controls: KEY3 reset (asynchronous assert, synchronised release), KEY1 fault clear (debounced, one event per deliberate press, a held key never clears), KEY0 e-stop (pressed = stop; fast path, not debounced). External NC e-stop on `ESTOP_EXT_N`
  (contact to 3.3 V, 10 kOhm pull-down; tie the pin to 3.3 V on the bench if no button is fitted).
- LEDR0 safe state, LEDR1 sensor fault, LEDR2 e-stop, LEDR3 AI overridden, LEDR7:4 trip reason, LEDG0 AI valid, LEDG1 PWM.
- ADC (Pmod AD1 / AD7476A), PWM and debug pins use the 40-pin 3.3 V GPIO header. **The pin file is not verified**: 24 of 41 port bits have no location, and none of the others was checked
  against the board. `python3 tools/check_pins.py --reference <Terasic DE2_115.qsf> --emit constraints/de2_115_from_reference.qsf` builds a file whose every pin comes from Terasic's own file.
- Quartus: `python3 tools/make_quartus_project.py --pins ... --reference ...` writes `quartus_build/` (refuses unverified pins unless `--allow-unverified-pins`). Quartus has never been run on this project.
- `python3 host/ai_host.py --selftest` checks the packet format and features without hardware; `--port COM3 --log run.csv` runs the loop.

## Status (read this before relying on anything)
* **Simulation only.** No hardware, Quartus build, Wokwi run or real sensor data exists. Hardware validation: 0 %. See `HARDWARE_VALIDATION_GUIDE.md`, `HAZARD_ANALYSIS.md`.
* Verified in simulation: 19 testbenches / 4,640 assertions (688 directed + 3,952 per-vector replay evaluations), 49-mutant campaign (all detected, audited), safety-invariant monitor, formal proofs of the governor and PWM modules for every state (not the slope predictor), CDC check over every boundary input, host-in-the-loop co-simulation (six host behaviours, independent reference model), 74 Python tests.
* **Open ADC timing hazard (H-16):** the MISO synchroniser leaves the first data bit a 20 ns sampling window in simulation (60 ns without it); the real ADC's timing is unverified, so no timing guarantee is claimed. A decision on that structure is pending.
* Other open safety items: e-stop acts only through the FPGA (no hardware supply cut), configuration-time and stuck-PWM behaviour, uncalibrated thresholds, unverified pins. See `FINAL_PROJECT_AUDIT.md`, `FINAL_RELEASE_READINESS_AUDIT.md`.
* Progress and percentages: `PROJECT_COMPLETION_TRACKER.md`.

## Design-level novelty (technical description, not a prior-art or patentability conclusion)
1. AI is advisory only: it can lower the command, never raise it (checked by replaying an always-wrong AI through the RTL).
2. Slope-predictive pre-limit in fixed-function hardware (`safety_governor`, `PRED_*` parameters, no ML):
   trips when `force + K * (rise per window) >= FORCE_MAX`. `ml/pred_eval.py` is the integer reference model;
   `tb/tb_pred_governor.v` compares the RTL with it on 4,720 vectors, `tb/tb_pred_system.v` runs it through the full path.
   On the SIMULATED test episodes it trips about 5.7 ms before the hard limit and also trips early on 6.5% of episodes that never reach it.
3. Self-checking AI link (packet checksum, class/inverse check, heartbeat timeout, automatic FPGA-only fallback).
4. Instant PWM kill and a latched, fail-safe (normally-closed) e-stop on a 4 to 5 cycle path.
5. T_FPGA, T_ML and jitter reported separately.
