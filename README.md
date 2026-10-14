# Tactile Reflex System (FPGA)

FSR force -> MCP3008 (SPI) -> LUT -> safety governor -> servo PWM. See `docs/sdg_alignment.md` for scope.
Academic prototype, not a certified safety system.

## Layout
| File | Role |
|---|---|
| `rtl/lut_engine.v`, `safety_governor.v`, `servo_pwm_generator.v`, `reflex_top.v` | Stage 1 core (ADC value + 1-clock valid in, servo PWM out) |
| `rtl/adc_spi_interface.v` | MCP3008 SPI master (mode 0, single-ended, 17 SCLK edges) |
| `rtl/reflex_top_spi.v` | Stage 2 top: SPI interface + unchanged `reflex_top`, continuous sampling of channel 0 |
| `tb/tb_reflex_top.v` | Stage 1 regression |
| `tb/tb_adc_spi_interface.v`, `mcp3008_model.v` | ADC test + behavioural MCP3008 with datasheet timing checks |
| `tb/tb_reflex_top_spi.v` | Stage 2 integration test |
| `tb/tb_adc_bad_param.v` | Must fail to compile (SCLK_HZ out of range) |
| `lut_gen.py`, `run_sim.sh`, `CHECKSUMS.sha256` | Table reference, run-everything script, file fingerprints |

## Run
`sh run_sim.sh` (needs Icarus Verilog). Prints `ALL TESTS PASSED` and exits 0, otherwise exits 1.

EDA Playground, one testbench per run:
- Stage 1: testbench `tb_reflex_top.v`; design = the four core RTL files.
- ADC: testbench `tb_adc_spi_interface.v`; design = `adc_spi_interface.v` + `mcp3008_model.v`.
- Integration: testbench `tb_reflex_top_spi.v`; design = four core files + `adc_spi_interface.v` + `reflex_top_spi.v` + `mcp3008_model.v` (about 28 ms simulated; takes a while).

## Behaviour
- Pulse: `2000 - adc` us (0 -> 2000, 320 -> 1680, 640 -> 1360, 880 -> 1120), clamped 1000..2000.
- Over-force: trips at adc >= 900, resumes below 800. Range fault: adc >= 1015, latched. E-stop and ADC timeout (1000 us without a valid sample): latched. All force the open pulse (2000 us); reset clears them.
- After reset the command stays open until the first valid sample.
- ADC timeout is restarted only by `adc_valid` (a completed frame with null bit = 0). Requests and `frame_err` frames never restart it.
- SPI: 1 MHz default (10 kHz..1.35 MHz, `CLK_HZ >= 16*SCLK_HZ`, otherwise compile error). 1751 clocks (17.51 us) per conversion at 100 MHz / 1 MHz. `reflex_top_spi` refuses to compile if fewer than 4 samples fit in the timeout window.
- `ADC_TIMEOUT_US` in `reflex_top_spi.v` duplicates the governor default (1000); change both together.

## Status
Simulated (Icarus Verilog 12): all tests pass, including 27 MHz / 1.35 MHz. Not done: synthesis, timing closure, board constraints (waiting on board model), measurement on hardware.

## Known limits
- Disconnected MISO is detected only if the pin pull-up is enabled in the constraints. MISO stuck low or a broken FSR wire reads as "no force" and cannot be detected.
- FSR (~10 kOhm source) may need a lower SCLK (try 500 kHz) if readings are low.
- Simulated 2-clock latency (CS rise -> command) excludes FPGA I/O delays.
- Not applied yet (awaiting approval): governor/servo parameter-range checks, boundary and simultaneous-fault tests beyond those in the testbenches, LUT write/swap rule for a future UART loader.
- The Stage 1 files in this repo were rewritten from the described behaviour; they are not the files that passed on EDA Playground.
