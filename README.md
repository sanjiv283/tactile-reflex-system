# Latency-Optimal Tactile Reflex System

AI-assisted, deterministic FPGA tactile controller for robotic gripper actuation.
The PL (FPGA) path ADC -> conditioning -> fixed LUT -> Safety Governor -> PWM is independent of the AI/ML path.
The AI class (from the PS) can only lower the command and is ignored when invalid or when a hard limit trips.

## Layout
| Path | Content |
|---|---|
| `rtl/` | Synthesizable Verilog: `adc_interface`, `input_conditioning`, `force_lut` (+ `force_lut.mem`), `safety_governor`, `pwm_generator`, `fault_handler`, `ai_control_interface`, `tactile_reflex_top`, plus the UART link (`uart_rx`, `uart_tx`, `ai_uart_bridge`, `telemetry_tx`) and the board wrapper `de2_115_top` |
| `tb/` | Testbenches (one per module, a system testbench, and a replay of ML outputs through the RTL) |
| `ml/` | Simulated dataset generator, decision-tree training and evaluation |
| `host/` | Laptop side: AI packets out, telemetry in, CSV logging (`ai_host.py`) |
| `constraints/` | DE2-115 SDC and a pin template (GPIO pins to be filled in) |
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
- Latency figures in `results/sim_log.txt` are RTL-simulation clock-cycle counts (50 MHz clock, as on the DE2-115) with an ideal behavioural ADC model.
- Inference timings in `results/ml_results.json` were taken on the development host, not the target processor.

## Target board: Terasic DE2-115 (Cyclone IV E EP4CE115F29C7, 50 MHz)
No ARM processor, so the AI/ML runs on a laptop over the board's RS-232 port (115200 8N1).
- FPGA to laptop: 3-byte telemetry about every 1 ms (`0x5A`, flags + force[11:8], force[7:0]).
- Laptop to FPGA: 3-byte AI packet `0xA5, DATA, ~DATA`. Advice only: ignored if invalid, stale (10 ms) or when a hard limit trips.
- Onboard controls: KEY3 reset, KEY1 fault clear, KEY0 e-stop (pressed = stop). External NC e-stop on `ESTOP_EXT_N`
  (contact to 3.3 V, 10 kOhm pull-down; tie the pin to 3.3 V on the bench if no button is fitted).
- LEDR0 safe state, LEDR1 sensor fault, LEDR2 e-stop, LEDR3 AI overridden, LEDR7:4 trip reason, LEDG0 AI valid, LEDG1 PWM.
- ADC (Pmod AD1 / AD7476A), PWM and debug pins use the 40-pin 3.3 V GPIO header. Fill in the GPIO pin locations in
  `constraints/de2_115.qsf` from the DE2-115 user manual; the onboard pins in that file are also unverified, so cross-check them.
- Quartus: create the project in the repository root, set `de2_115_top` as top level, add every file in `rtl/`, import the QSF and SDC.
- `python3 host/ai_host.py --selftest` checks the packet format and features without hardware; `--port COM3 --log run.csv` runs the loop.

Status: RTL simulated (all testbenches pass) and checked with a generic yosys synthesis run. Quartus synthesis, timing closure
and board bring-up have not been run.
