# ADHRC – Stage 1 (FPGA core, board-independent)

## Files
| File | Purpose |
|---|---|
| rtl/servo_pwm_generator.v | 50 Hz servo pulse, width in µs, glitch-free (latched per frame) |
| rtl/lut_engine.v | 64-entry force→pulse LUT, two banks, 1-clock lookup, atomic swap |
| rtl/safety_governor.v | Hard clamp, over-force (hysteresis), sensor range fault, ADC timeout, e-stop, grip enable |
| rtl/reflex_top.v | Wires it together; button synchronizers |
| tb/tb_reflex_top.v | Self-checking testbench (prints PASS/FAIL) |
| python/lut_gen.py | 3 parameters → validated 64-entry LUT hex file |
| rtl/adc_spi_interface.v | MCP3008 SPI master (mode 0, 17-clock single-ended frame) |
| tb/mcp3008_model.v | **Simulation-only** MCP3008 model with datasheet timing checks |
| tb/tb_adc_spi_interface.v | Self-checking ADC interface testbench |
| tb/tb_adc_bad_param.v | Negative test: must **fail** to compile (SCLK too fast) |
| run_sim.sh | Runs all tests; exits nonzero on any failure |
| rtl/reflex_top_spi.v | **Stage 2 top**: adc_spi_interface + unchanged reflex_top, continuous sampling of channel 0 |
| tb/tb_reflex_top_spi.v | Stage 2 integration testbench (real MCP3008 model, real ADC timeout) |
| tb/tb_governor_boundary.v | Safety-governor threshold boundaries: 899/900, 799/800, 1014/1015 |

## Run the simulation (no board needed)
**EDA Playground (browser):** edaplayground.com → paste `tb_reflex_top.v` in the left
(testbench) pane, add the four `rtl/` files in the right pane (+ button), select
*Icarus Verilog 12*, tick *Open EPWave after run*, click Run.

**Laptop:** install Icarus Verilog + GTKWave, then
```
iverilog -o sim rtl/*.v tb/tb_reflex_top.v
vvp sim
gtkwave dump.vcd
```
Expected last line: `=== DONE: 0 error(s) ===`

Run everything at once (Icarus Verilog installed): `sh run_sim.sh`
It ends with `ALL TESTS PASSED` and exit code 0, or `SOME TESTS FAILED` and exit code 1.

**EDA Playground, one testbench at a time** (two testbenches in one run clash):
- Stage 1: testbench pane `tb_reflex_top.v`; design pane the four core `rtl/` files.
- ADC: testbench pane `tb_adc_spi_interface.v`; design pane `adc_spi_interface.v`
  and `mcp3008_model.v`. Never add `tb_adc_bad_param.v` to a normal run.

## What the waveforms should look like
- **servo_out:** one high pulse per frame. Width: 2000 µs at no force, getting
  shorter as adc_value rises, 1000 µs (open) in any fault.
- **adc_valid:** short pulse every 50 µs (fake ADC in the testbench).
- **dbg_cmd_toggle:** flips 2 clocks after every adc_valid. This is the pin you
  will probe on the oscilloscope for the FPGA latency measurement.
- **fault_led:** `0001` over-force, `0010` sensor range, `0100` ADC timeout,
  `1000` e-stop. Only over-force clears by itself; the rest need reset.

## Simulation shortcuts (testbench only)
1 MHz clock and a 2.5 ms frame instead of 20 ms, so the sim runs in seconds.
The real design uses the board clock (`CLK_HZ`) and 20 ms.

## Placeholders – NOT final values
`FORCE_MAX`, `FORCE_RESUME`, `ADC_FAULT_HI` and the default LUT curve are
placeholders. They get replaced with numbers from the Week-2 FSR calibration.

## Known limitation
With FSR-to-3.3 V and 10 kΩ-to-ground, a broken FSR wire reads 0, which looks
the same as "no force". The governor can't detect that case; mention it in the report.

## ADC interface (MCP3008) – timing assumptions
- SPI mode 0. MOSI changes on falling SCLK; MISO sampled on rising SCLK through a
  2-flop synchronizer. Frame: start, SGL=1, D2 D1 D0, null bit, B9..B0 (17 clocks).
- `SCLK_HZ` default 1 MHz, allowed 10 kHz–1.35 MHz (1.35 MHz is the datasheet limit
  at 2.7 V, so it is safe at 3.3 V). Real SCLK is rounded *down*, never above the setting.
- Needs `CLK_HZ >= 16 × SCLK_HZ`; invalid settings stop compilation.
- Theoretical (simulated, not measured) conversion period: `35·HALF + 1` clocks
  → about 17.5 µs at 100 MHz / 1 MHz (≈57 kS/s).
- `frame_err`: null bit read as 1 → no `data_valid`. With the MISO pull-up enabled,
  a disconnected MISO is detected this way; the safety governor's ADC timeout then
  trips because no valid samples arrive. MISO stuck **low** reads as 0 = "no force"
  and is **not** detectable.
- Source impedance: the FSR divider can be up to ~10 kΩ. If readings look low or noisy
  on hardware, try a lower `SCLK_HZ` (e.g. 500 kHz) and compare (Week 2 check).

## Stage 2 – SPI ADC integrated with the reflex core
`reflex_top_spi.v` wires `adc_spi_interface` (channel fixed to 0, `start = ~busy`) to the
unchanged `reflex_top` (`data` -> `adc_value`, `data_valid` -> `adc_valid`). Same clock, so no
clock-domain crossing. Only `data_valid` (frame with null bit = 0) feeds the governor's ADC
timeout; requests and `frame_err` frames never do, so a dead or disconnected ADC trips the
existing timeout fault (~57 samples per 1000 us window at 100 MHz / 1 MHz).
- `ADC_TIMEOUT_US` in `reflex_top_spi.v` is a copy of the governor default (1000): change both.
- The wrapper refuses to compile if fewer than 4 samples fit in the timeout window
  (e.g. SCLK_HZ = 10 kHz would trip a healthy sensor).
- Run only the integration test on EDA Playground: testbench pane `tb_reflex_top_spi.v`;
  design pane the four core `rtl/` files + `adc_spi_interface.v` + `reflex_top_spi.v` +
  `mcp3008_model.v` (about 29 ms simulated; slower than the others).
- Latency CS rise -> `dbg_cmd_toggle` is 2 clocks in simulation only; real hardware adds I/O delays.
- Not yet done: synthesis/timing, pin constraints (board model not confirmed), pull-up on MISO,
  hardware measurements.

## Regression suite (`run_sim.sh`)
`sh run_sim.sh` runs the default suite (about 30 s) and prints a per-test summary
(reflex, boundary, adc, adc_27m, spi_top, bad_param); `sh run_sim.sh --extended` also runs
`spi_top_20ms`: the integration test at 100 MHz with the real 20 ms servo frame (about 3 min).
Exit status is nonzero if any test fails. Generated files (`sim_*`, `*.log`, `*.vcd`) are in `.gitignore`.

### Running the governor boundary test (`tb/tb_governor_boundary.v`)
It drives `reflex_top` directly (no SPI) and uses only the four Stage 1 RTL modules.
- Local: `iverilog -g2005 -o sim_boundary rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v tb/tb_governor_boundary.v && vvp -n sim_boundary`
  (or just `sh run_sim.sh`, which runs it as `boundary`).
- EDA Playground: testbench pane `tb_governor_boundary.v`; design pane the four core `rtl/` files
  (`reflex_top.v`, `lut_engine.v`, `safety_governor.v`, `servo_pwm_generator.v`).
- Expected: 16 `PASS` lines and a last line `=== DONE: 0 error(s) ===`.

### Extended integration test (100 MHz clock, real 20 ms servo frame)
The default `spi_top` test uses a 2.5 ms servo frame to stay fast. The extended run uses the real
20 ms frame and takes about 3 minutes.
- Local, via the script: `sh run_sim.sh --extended` (or `EXTENDED=1 sh run_sim.sh`). It runs the default
  suite plus `spi_top_20ms`.
- Local, one test only:
  `iverilog -g2005 -Ptb_reflex_top_spi.FRAME_US=20000 -Ptb_reflex_top_spi.WATCHDOG_NS=900000000 -o sim_spi_20ms rtl/reflex_top.v rtl/lut_engine.v rtl/safety_governor.v rtl/servo_pwm_generator.v rtl/adc_spi_interface.v rtl/reflex_top_spi.v tb/mcp3008_model.v tb/tb_reflex_top_spi.v && vvp -n sim_spi_20ms`
- EDA Playground (no `-P` parameter overrides): testbench pane `tb_reflex_top_spi.v`; design pane the four
  core `rtl/` files + `adc_spi_interface.v` + `reflex_top_spi.v` + `mcp3008_model.v`. In the testbench pane,
  edit the two defaults before running: `parameter FRAME_US = 2500;` -> `20000` and
  `parameter WATCHDOG_NS = 300_000_000;` -> `900_000_000`. Do not copy the edited testbench back to the repo.
  The run is long (about 3 minutes on a laptop), so it may exceed EDA Playground's time limit. That
  procedure has not been tried on EDA Playground.

Integration test (`tb_reflex_top_spi.v`) also covers a reset in the middle of a conversion and
MISO stuck low. Stuck-low is a **known undetectable fault**: every frame looks valid and reads
0 (no force), so no fault is raised; the test documents that behaviour, it is not a protection.
A disconnected (open) MISO *is* detected, through the null bit and the ADC timeout.
All results are simulation only; nothing here is validated on hardware.
