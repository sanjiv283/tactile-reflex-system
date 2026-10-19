# DE2-115 integration of the Tactile Reflex System (first hardware milestone)

**Status.** Verified only by simulation (Icarus Verilog): the wrapper, the six RTL files it uses, and the MCP3008 model.
**Not** compiled in Quartus, **not** programmed, **not** tested on hardware. No pin assignment is verified. The LUT is the
placeholder curve and the force thresholds are placeholders: nothing here is calibrated for a physical gripper, and a board
push-button is not a certified emergency stop.

## Folder structure (one consistent snapshot)
```
TactileReflexive_snapshot/            <- your Quartus project root: put TactileReflexive.qpf / .qsf here
  rtl/                                 synthesisable RTL (the 6 files below are the ones this build uses)
    reflex_top_spi.v  reflex_top.v  adc_spi_interface.v  lut_engine.v  safety_governor.v  servo_pwm_generator.v
    (also: lut_upload_ctrl.v reflex_top_uart.v uart_rx.v uart_tx.v upload_resp_tx.v  - UART upload, NOT used by this build)
  quartus/
    TactileReflexive.v                 board wrapper = top-level entity TactileReflexive
    TactileReflexive.sdc               timing constraints
    TactileReflexive_assignments.tcl   adds sources / top-level / SDC / MISO pull-up to the open project
    check_sdc_ports.py                 checks the SDC against the wrapper's real ports
    README_DE2_115.md                  this file
  tb/                                  testbenches and the MCP3008 model (simulation only, never added to Quartus)
  python/lut_gen.py  docs/  run_sim.sh  CHECKSUMS.sha256  README.md
```
The TCL script expects `rtl/` and `quartus/` to be siblings. It adds only the 6 RTL files + wrapper + SDC to the project.

## What the wrapper does
`TactileReflexive` instantiates `reflex_top_spi` (existing, simulated): MCP3008 SPI master -> LUT -> safety governor -> servo PWM.
`reflex_top` alone has no ADC interface; `reflex_top_spi` already connects `adc_spi_interface` to it (data -> `adc_value`,
`data_valid` -> `adc_valid`), so nothing is driven twice and the governor cannot be bypassed. Parameters: `CLK_HZ = 50 MHz`
(the RTL default is 100 MHz), `SCLK_HZ = 1 MHz`, `FRAME_US = 20000` (wrapper parameter `FRAME_US`, shortened only in a fast
simulation). LUT write ports are tied inactive (no UART upload in this milestone).

| Wrapper port | Function | Notes |
|---|---|---|
| `CLOCK_50` | 50 MHz clock | confirm in the board manual |
| `KEY[0]` | reset | board button idles high, low when pressed; wrapper inverts (design is active high) |
| `KEY[1]` | emergency stop (development input) | inverted; latched until reset. **Not a certified/fail-safe e-stop** |
| `SW[0]` | grip enable | 1 = enabled; power-up default disabled. **Check that "switch up = 1" on your board** |
| `GPIO[0]` `[1]` `[2]` | MCP3008 CS, CLK, DIN | outputs, 3.3 V |
| `GPIO[3]` | MCP3008 DOUT | input, weak pull-up set by the TCL |
| `GPIO[4]` | servo signal | output; **do not connect a servo for first output checks** |
| `LEDR[3:0]` | faults: 3 e-stop, 2 ADC timeout, 1 ADC range, 0 over-force | |
| `LEDR[4]` `[5]` | ADC frame error, command toggle | |
| `LEDG[0..3]` | servo mirror, active bank, reset requested, e-stop requested | other LEDs driven 0 |

Ports that need pins: `CLOCK_50`, `KEY[0]`, `KEY[1]`, `SW[0]`, `GPIO[0..4]`, `LEDR[5:0]`, `LEDG[3:0]` (the remaining LED and
GPIO bits are constants or high impedance; with Terasic's file imported they get their board pins anyway).

## Pins: nothing here is verified
No pin number is written in any file. Use Terasic's own DE2-115 pin-assignment file (DE2-115 System CD / Terasic download page)
with *Assignments > Import Assignments*; the wrapper uses the same port names (`CLOCK_50`, `KEY`, `SW`, `LEDR`, `LEDG`, `GPIO`).
Warnings about assignments to ports this design does not have are expected. Check every used pin in Pin Planner against the
manual, including the header's 3.3 V / GND positions and the 3.3 V I/O standard. Secondary (third-party) tables suggest
`CLOCK_50` = `PIN_Y2` and `KEY[0]` = `PIN_M23`, but they were not confirmed against the manual.
Also set *Assignments > Device > Device and Pin Options > Unused Pins* to **As input tri-stated** so unused header pins never
drive anything.

## Timing constraints (`TactileReflexive.sdc`)
20 ns clock on `CLOCK_50`, `derive_clock_uncertainty`, and exactly two exceptions, each with its reason in the file:
false path **from** `KEY[*] SW[*]` (asynchronous, synchronised in the RTL) and **from** `GPIO[3]` (MISO: launched by the ADC
up to ~200 ns after an FPGA-generated SCLK edge and sampled >= 25 clocks later through a 2-flop synchroniser). There is
**no exception on any output** and no invented `set_input_delay` / `set_output_delay`: the LEDs, SPI outputs and servo output
will show as *unconstrained* in the Timing Analyzer. `check_sdc_ports.py` (run by `run_sim.sh`) verifies that every pattern
matches a real wrapper port and that no false path targets outputs. Real input/output delays would need the MCP3008 data-sheet
timing at your supply voltage plus board/wiring delays: not available yet.

## Simulation (no Quartus needed)
`tb/tb_de2_wrapper.v` drives the wrapper with the MCP3008 model (which also checks data-sheet SPI timing at 50 MHz). It checks
reset, start-up (no false ADC timeout), normal operation, over-force with hysteresis, range fault (latched), e-stop (latched),
ADC disconnected (invalid frames -> timeout, latched, recovers only after reset), grip disable, and every servo pulse 1000..2000 us
and low during reset. Fast run (2.5 ms frame, ~15 s): `sh run_sim.sh` row `de2_wrapper`; real 20 ms frame (~90 s):
`sh run_sim.sh --extended` row `de2_wrapper_20ms`. On Windows without `sh`, from the snapshot root in PowerShell:
```
iverilog -g2005 -o sim_de2 quartus\TactileReflexive.v rtl\reflex_top_spi.v rtl\reflex_top.v rtl\adc_spi_interface.v rtl\lut_engine.v rtl\safety_governor.v rtl\servo_pwm_generator.v tb\mcp3008_model.v tb\tb_de2_wrapper.v
vvp -n sim_de2
```
Expect `=== DONE: 0 error(s) ===`. (`-Ptb_de2_wrapper.FRAME_US_TB=20000` on the iverilog line selects the real 20 ms frame.)
Also: `python quartus\check_sdc_ports.py` and `python python\lut_gen.py --test`.

## Steps in Quartus Prime Lite 20.1
1. Use a short path outside OneDrive if possible (OneDrive can lock Quartus `db` files). Keep your original project untouched; use a copy.
2. Open the copy's `TactileReflexive.qpf`; the title bar / Project Navigator must show the copy's path.
3. Back up the `.qsf` (`Copy-Item .\TactileReflexive.qsf .\TactileReflexive.qsf.bak`).
4. *Tools > Tcl Scripts...* run `quartus\TactileReflexive_assignments.tcl` (the project must be open). Check *Project > Add/Remove Files*
   (6 RTL files, wrapper, SDC; nothing from `tb\`) and that the top-level entity is `TactileReflexive`. Compare the `.qsf` with the backup.
5. *Assignments > Import Assignments...* Terasic's DE2-115 pin file; confirm device `EP4CE115F29C7`; verify pins; set Unused Pins as above.
6. *Processing > Start Analysis & Synthesis*. If `$clog2` is rejected, set *Settings > Compiler Settings > Verilog HDL Input* to
   SystemVerilog_2005 (a commented line in the TCL does this) and retry. Read the report: inferred latches, unconnected ports,
   how `lut_engine` memory was built, `$readmemh`/`initial` handling.
7. *Start Compilation*; in the Timing Analyzer expect setup/hold slack >= 0 on `CLOCK_50`, and the unconstrained outputs noted above.
8. Do not program the board until the pin report matches the manual and the wiring below has been reviewed.

## Quartus 20.1 compatibility: what is and is not verified
Verified (Icarus only): the 7 source files elaborate under `-g2005 -Wall` with no warnings, also under `-g2012`; all `always`
blocks are clocked on `posedge CLOCK_50` (no latch-style combinational blocks); one clock domain; asynchronous inputs have 2-flop
synchronisers. **Assumptions needing Quartus:** `$clog2` accepted (7 uses in `rtl/`); the parameter guards (instantiating a
non-existent module in a not-taken `generate` branch) accepted -- the older guard-free `safety_governor.v` / `servo_pwm_generator.v`
are functionally identical if Quartus objects; `initial`/`$readmemh` LUT initialisation (the wrapper passes an empty file name, so
the built-in table is used); whether the two 64x12 LUT arrays become block RAM or logic cells; port-declaration initial values
(`rst_s = 2'b11`, ...) as power-up values.

## Safety notes (read before connecting anything)
* **Push-button e-stop.** `KEY[1]` forces the SAFE pulse (1000 us) and latches until reset. The servo stays powered and still gets a
  signal. Use an independent hardware cut-off for actuator power; never rely on this logic for personnel safety.
* **Fault latency.** The servo generator latches its command once per 20 ms frame, so a fault can take up to one frame (two in the
  worst case) to reach the pin. Measure on a scope.
* **ADC start-up and failure.** After reset the output is SAFE until the first valid sample (about 35 us); the 1 ms ADC timeout does
  not fire at start-up (simulated). A disconnected ADC (MISO pulled high) is detected (frame error -> timeout -> latched SAFE).
  **MISO stuck low is NOT detected**: it reads as a valid code 0, which the placeholder LUT maps to the largest pulse (2000 us;
  assumed to be the most-closed command). An FSR wired so that a broken wire reads 0 behaves the same way. Decide whether a
  "reading too low for too long" fault is wanted before any load.
* **Uncalibrated values.** `FORCE_MAX 900`, `FORCE_RESUME 800`, `ADC_FAULT_HI 1015` and the 2000 - 16*i LUT are placeholders.
* **Electrical.** 3.3 V logic on the header; power the MCP3008 from 3.3 V; separate servo supply with common ground; servo unloaded and
  disconnected for the first output checks; confirm switch polarity and the header's supply pins in the manual.
