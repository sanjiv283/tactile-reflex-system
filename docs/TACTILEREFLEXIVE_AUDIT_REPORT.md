# TactileReflexive: A Deterministic FPGA-Based Tactile Reflex Controller

**Audit, latency analysis and project documentation** — prepared 2026-10-19 from the repository working tree in the assistant's cloud workspace.

> **Status in one paragraph.** The RTL is implemented and passes the simulation regression in the assistant's cloud workspace
> (Icarus Verilog 12.0). It has **not** been compiled in Quartus, **no** pin assignment has been verified against the official
> DE2-115 manual, and **nothing** has been tested on hardware. No latency has been measured on hardware. The force thresholds and
> the LUT are **uncalibrated placeholders**. The design is **not** safety-certified and **not** fail-safe; a push-button
> "emergency stop" on the FPGA board does not remove actuator power.

Evidence categories used throughout:

| Tag | Meaning |
|---|---|
| **[RTL]** | Implemented in the source files (read from the code, with line numbers) |
| **[SIM]** | Demonstrated by a simulation the assistant executed in its cloud workspace (Icarus 12.0) |
| **[LOCAL]** | Verified by tool execution on the user's own machine (only what the user has reported; not re-confirmed here) |
| **[QUARTUS]** | Verified in Quartus — **nothing yet** |
| **[HW]** | Verified on physical hardware — **nothing yet** |
| **[FUTURE]** | Proposed future work |

---

## 1. Project overview

TactileReflexive reads a force-sensitive resistor (FSR) through an MCP3008 SPI ADC, maps the 10-bit reading to a servo pulse width
with a 64-entry lookup table (LUT), and passes the result through a hard-limit safety governor before a servo PWM generator.
The whole force-to-command path is plain clocked logic in an FPGA (Terasic DE2-115, Cyclone IV E EP4CE115F29C7, 50 MHz clock):
no CPU, no operating system, no software in the control path. **[RTL]**

## 2. Problem statement and motivation

Industrial grippers need to react to contact force faster and more predictably than a software loop scheduled by an operating
system can guarantee. A fixed-function hardware pipeline has a bounded, countable delay (clock cycles), no jitter from
scheduling, and a safety layer (clamping, fault latching) that a table upload or a software fault cannot override.
The motivation is determinism and bounded latency. This report quantifies what that determinism does and does not deliver
(section 15): the digital decision is fast (40 ns), but the ADC, SPI transfer and, above all, the 20 ms servo PWM frame dominate
the end-to-end response.

## 3. Objectives and design requirements

| # | Requirement | Status |
|---|---|---|
| R1 | Read an FSR via MCP3008 (SPI mode 0) | Implemented **[RTL]**, simulated against a behavioural model **[SIM]** |
| R2 | Map force to servo command with a LUT in hardware | Implemented **[RTL]**, simulated **[SIM]**; table is a placeholder |
| R3 | Hard safety limits that no table can exceed (1000–2000 µs, over-force and range faults, ADC timeout, e-stop) | Implemented **[RTL]**, simulated **[SIM]** |
| R4 | Deterministic servo PWM (20 ms frame, 1 µs resolution) | Implemented **[RTL]**, simulated **[SIM]** |
| R5 | DE2-115 board integration at 50 MHz | Wrapper written **[RTL]**, simulated **[SIM]**; Quartus compile **not done** |
| R6 | Low, bounded latency | Digital stage 40 ns **[SIM]**; end-to-end see section 15; hardware measurement **not done** |
| R7 | Independent physical safety | **Not provided by this design** (section 19) |

## 4. Hardware and software tools

| Item | Detail | Status |
|---|---|---|
| FPGA board | Terasic DE2-115 | Not physically available during development |
| FPGA | Intel Cyclone IV E EP4CE115F29C7 | Taken from the user's project settings; not verified against the manual in this audit |
| Clock | 50 MHz (`CLOCK_50`) | Assumed; wrapper line 46 sets `CLK_HZ = 50_000_000`; to be confirmed against the manual |
| ADC | MCP3008 (SPI, 10 bit, 8 channels; channel 0 used) | Modelled in simulation only |
| Sensor | FSR | No sensor data exists |
| Actuator | Hobby servo (PWM) | Not connected |
| HDL | Verilog-2005 (`iverilog -g2005 -Wall` clean; `-g2012` elaborates) | **[SIM]** |
| Simulation | Icarus Verilog 12.0 (cloud workspace); user reports Icarus 13.0, MSYS2 UCRT64 | 12.0 **[SIM]**; 13.0 **[LOCAL]** reported earlier, re-run result after fixes not yet received |
| Scripting | Python 3 (`lut_gen.py`, `check_sdc_ports.py`) | 3.13 in cloud workspace; 3.14 reported locally |
| Synthesis | Intel Quartus Prime Lite 20.1 | **Not run** by anyone yet |

## 5. System architecture

```
 FSR --(divider)--> MCP3008 --SPI--> adc_spi_interface --data,data_valid--> lut_engine --lut_pulse_us--> safety_governor --pulse_us--> servo_pwm_generator --> servo signal
                                            ^                     (64 entries,            (clamp 1000..2000,           (latched once per
                                            |                      2 banks)                 faults, e-stop,              20 ms frame)
                                      reflex_top_spi                                        SAFE = 1000 us)
 KEY0 (reset) , KEY1 (e-stop) , SW0 (grip enable) --(2-flop synchronisers in reflex_top)--> safety_governor / all reset inputs
```

`TactileReflexive.v` (board wrapper) → `reflex_top_spi` → { `adc_spi_interface`, `reflex_top` → { `lut_engine`, `safety_governor`,
`servo_pwm_generator` } }. One clock domain (`CLOCK_50`). All `always` blocks are `posedge clk`. **[RTL]**

## 6. Data flow from force sensor to actuator command

1. The ADC samples the analog input (assumed ~6.0 µs after CS falls; see section 15).
2. `adc_spi_interface` shifts in 17 bits; if the null bit is 0 it presents `data[9:0]` with a one-clock `data_valid` pulse; if the
   null bit is 1 it pulses `frame_err` instead and `data` is not updated (`adc_spi_interface.v:96-104`).
3. `lut_engine` uses `adc_value[9:4]` as the table index (64 levels of 16 ADC codes each) and registers `lut_pulse_us` and `lut_valid` one clock later (`lut_engine.v:44,52-54`).
4. `safety_governor` registers `pulse_us`: SAFE (1000 µs) if any fault is active or grip is disabled, else the LUT value clamped to 1000–2000 µs (`safety_governor.v:72-74,95-96`).
5. `servo_pwm_generator` copies `pulse_us` into `pulse_latched` only at the end of each frame and drives `servo_out` high for that many microseconds (`servo_pwm_generator.v:46-52`).

## 7. Module-by-module RTL explanation

| Module | File | Responsibility | Key facts (line refs) |
|---|---|---|---|
| `TactileReflexive` | `quartus/TactileReflexive.v` | DE2-115 wrapper: inverts active-low buttons, maps GPIO bits, LEDs; instantiates `reflex_top_spi` with `CLK_HZ=50e6`, `SCLK_HZ=1e6`, `FRAME_US=20000`; LUT write ports tied to 0 | lines 38-40 (controls), 46-48 (parameters), 60-63 (LUT ports off) |
| `reflex_top_spi` | `rtl/reflex_top_spi.v` | Joins the SPI ADC to `reflex_top`; `start = ~busy`, channel 0; own reset synchroniser; guard requires ≥ 4 samples per ADC timeout | lines 48-50, 57, 65; timeout copy `ADC_TIMEOUT_US = 1000` at line 37 |
| `adc_spi_interface` | `rtl/adc_spi_interface.v` | MCP3008 SPI master, mode 0, 17 rising edges, MISO 2-flop synchronised; `data_valid`/`frame_err` | HALF line 42; frame lines 82-109; reset into GAP lines 73-78 |
| `reflex_top` | `rtl/reflex_top.v` | 2-flop synchronisers for reset/e-stop/grip; instantiates LUT, governor, PWM | lines 27-33 (synchronisers), 38 (LUT), 46-56 |
| `lut_engine` | `rtl/lut_engine.v` | 2 × 64 × 12-bit banks; reads active bank, writes inactive bank, one-clock `swap`; default 2000 − 16·i | init 27-37; lookup 52-54 |
| `safety_governor` | `rtl/safety_governor.v` | Clamp, over-force with hysteresis, range fault, ADC timeout, e-stop latch, grip override | parameters 10-17; logic 72-98 |
| `servo_pwm_generator` | `rtl/servo_pwm_generator.v` | Per-frame pulse latch, 1 µs tick, `servo_out` | lines 40-54 |
| `lut_upload_ctrl`, `uart_rx`, `uart_tx`, `upload_resp_tx`, `reflex_top_uart` | `rtl/` | UART LUT upload with checksum and replies | Implemented and simulated, **not used in the DE2-115 build** |

## 8. SPI interface and ADC communication

Confirmed from `adc_spi_interface.v`, `reflex_top_spi.v` and the wrapper:

| Parameter | Value | Source |
|---|---|---|
| FPGA clock | 50 MHz, period 20 ns | `TactileReflexive.v:46` |
| SPI clock | 1 MHz requested; `HALF = ceil(50e6 / (2·1e6)) = 25` clocks → SCLK period 50 clocks = 1.000 µs | `adc_spi_interface.v:42` |
| SPI mode | 0 (SCLK idles low, MISO sampled on the rising edge, MOSI changes on the falling edge) | file header, lines 3-5 |
| Frame | CS low, 17 rising edges: start, SGL/DIFF, D2 D1 D0, (sample), null bit, B9…B0 | header lines 6-8; `rises == 17` at line 96 |
| Null bit | must read 0, else `frame_err` and no sample | lines 99-104 |
| Conversion period | `35·HALF + 1 = 876` clocks = 17.52 µs (57.1 kS/s) | `reflex_top_spi.v:39`; measured 876 **[SIM]** |
| SCLK limit guard | `SCLK_HZ` 10 kHz … 1.35 MHz and `HALF ≥ 8` | lines 49-53 |

## 9. LUT mapping and command generation

* Index = `adc_value[9:4]` → entry *i* serves ADC codes 16·i … 16·i + 15. **[RTL]** (`lut_engine.v:44`)
* Default table: `2000 − 16·i` µs (entry 63 = 992 µs, clamped to 1000 by the governor). **Uncalibrated placeholder.** (`lut_engine.v:25-26,34`)
* `lut_gen.py` writes a validated 64-entry hex file (`LUT_INIT_FILE`); the wrapper passes an empty file name, so the built-in table is used. **[RTL]** **[SIM]** (file loading verified in simulation only)
* Two banks with a one-clock atomic swap exist for UART upload; unused in this build. **[RTL]** **[SIM]**
* Direction of the mapping (assumption, not verified against any gripper): larger pulse = more closing; SAFE = 1000 µs = open (`safety_governor.v:13`).

## 10. Safety governor, thresholds and fault handling

| Quantity | Value | Calibrated? | Source |
|---|---|---|---|
| `PULSE_MIN_US` / `PULSE_MAX_US` | 1000 / 2000 µs | design limits, check against the actual gripper | `safety_governor.v:11-12` |
| `SAFE_PULSE_US` | 1000 µs | design choice | line 13 |
| `FORCE_MAX` | 900 (trip when code ≥ 900) | **uncalibrated placeholder** | line 14 |
| `FORCE_RESUME` | 800 (over-force clears when a sample < 800) | **uncalibrated placeholder** | line 15 |
| `ADC_FAULT_HI` | 1015 (range fault, latched, when code ≥ 1015) | **uncalibrated placeholder** | line 16 |
| `ADC_TIMEOUT_US` | 1000 µs without a valid sample (= 50 000 clocks) → fault, latched | design choice | line 17; logic 83-85 |

Fault flags (`fault_led` = {e-stop, timeout, range, over-force}): e-stop, timeout and range latch until reset; over-force clears with
hysteresis. `trip` is the OR of all of them plus the live synchronised e-stop (`safety_governor.v:72`); while it or `!grip_en` holds,
`pulse_us` = SAFE (line 95). Parameter guards (Stage 6B.1) reject invalid configurations at elaboration. **[RTL]** **[SIM]**

## 11. Servo PWM generation

* Frame `FRAME_US = 20 000` µs (50 Hz) in the board build; `FRAME_US > 2000` is enforced. 1 µs resolution (`TICKS_PER_US = 50`). **[RTL]**
* `pulse_latched <= pulse_us` only when `us_cnt == FRAME_US − 1` (`servo_pwm_generator.v:46-48`); `servo_out <= (us_cnt < pulse_latched)` (line 52).
* Reset clears the latched width and the output; the first pulse after reset starts one full frame later. **[RTL]** **[SIM]**
* Pulse limits seen at the pin in simulation: 1000–2000 µs (`tb_de2_wrapper`: min 1000, max 2000, never high > 2000 µs). **[SIM]**

## 12. Reset and emergency-stop behavior

* `KEY[0]` pressed (0) → inverted → active-high reset (`TactileReflexive.v:38`). Reset passes through 2-flop synchronisers (`reflex_top.v:27-33`, `reflex_top_spi.v:48-50`); the registers power up asserted (`2'b11`).
* `KEY[1]` pressed (0) → inverted → e-stop, latched in the governor until reset (`safety_governor.v:81`). Output command goes to SAFE (1000 µs) within 3 clock edges (**measured 3 [SIM]**).
* **The e-stop is a development input.** It does not cut actuator power; the servo keeps receiving a 1000 µs pulse. It is not a certified emergency stop.
* Grip disable (`SW[0]` = 0): SAFE pulse, not a latched fault. Power-up default: disabled (`grip_s` starts 0).

## 13. Simulation architecture and test strategy

* `run_sim.sh` runs 30+ self-checking testbenches under `tb/` with Icarus Verilog and a per-test PASS/FAIL summary; exit status is nonzero on any failure (requires a clean `=== DONE: 0 error(s) ===`, at least one PASS line, no FAIL line and `vvp` exit 0).
* Layers: unit (ADC, UARTs, LUT, governor, servo), integration (`reflex_top`, `reflex_top_spi`, `reflex_top_uart`), board wrapper (`tb_de2_wrapper.v` with the MCP3008 model, which also checks datasheet SPI timing), parameter negative/acceptance tests (compile-only), Python tests (`lut_gen.py --test`, `check_sdc_ports.py`), lint (`-Wall`).
* Characterisation tests (labelled) document current behaviour that is not a requirement: reset around COMMIT, fault-latency windows, `x` entries from missing LUT files, stuck-low MISO.

## 14. Verified simulation results

Executed by the assistant in its cloud workspace on a **copy of the current working tree** (not the user's Windows folder):

| Check | Command | Exit | PASS | FAIL | SKIPPED |
|---|---|---|---|---|---|
| Standard suite | `bash run_sim.sh` | 0 | 79 | 0 | 8 (optional extended tests) |
| Extended suite | `bash run_sim.sh --extended` | 0 | 87 | 0 | 0 |
| LUT generator self-test | `python3 -B python/lut_gen.py --test` | 0 | passed | — | — |
| SDC vs wrapper ports | `python3 -B quartus/check_sdc_ports.py` | 0 | 4 patterns match 6 ports | — | — |
| Checksums | `sha256sum -c CHECKSUMS.sha256` | 0 | 50 OK | 0 | — |

Tool versions: Icarus Verilog 12.0 (stable), Python 3.13, GNU bash. Expected console noise: the LUT-file negative tests print `$readmemh` WARNING/ERROR lines on purpose.
Not run: Quartus (not installed), Verilator, Yosys. The user's own Icarus 13.0 run after the two testbench declaration-order fixes has **not** been reported back yet; the earlier local failures were testbench compile errors (`ctrl_timing`, `ctrl_timing_2m`, `safety_up`), classified as a **tool-version compatibility issue in the testbenches**, not a design defect.

## 15. Latency analysis and timing budget

### 15.1 Source parameters

`CLK_HZ = 50 MHz` (clock period 20 ns), `SCLK_HZ = 1 MHz`, `HALF = 25`, `FRAME_US = 20 000`, `ADC_TIMEOUT_US = 1000`.

### 15.2 Latency budget (cycle counts are exact for the RTL; ADC internals are assumptions)

| Stage | Domain | Cycles / bound | Time | Evidence | Assumptions |
|---|---|---|---|---|---|
| FSR + divider settling | analog | not modelled | unknown | — | needs measurement |
| Wait for the next ADC sample instant | SPI/ADC | 0 … 876 clocks | 0 … 17.52 µs | conversion period `35·HALF+1` (`reflex_top_spi.v:39`); **measured 876 [SIM]** | continuous conversions (`start = ~busy`) |
| CS fall → analog sample instant | ADC | 12·HALF = 300 clocks | 6.00 µs | `tb/mcp3008_model.v:71-75` | **model assumption**; confirm against the MCP3008 datasheet |
| Sample instant → `data_valid` | SPI | 850 − 300 = 550 clocks | 11.00 µs | CS fall → `data_valid` = 34·HALF = 850 clocks, **measured 850 [SIM]** (`adc_spi_interface.v:89-104`) | exact for the RTL |
| `data_valid` → `lut_valid`, `lut_pulse_us` | clk | 1 clock | 20 ns | `lut_engine.v:52-54`; measured 1 **[SIM]** | exact |
| `lut_valid` → `pulse_us` (governor) | clk | 1 clock | 20 ns | `safety_governor.v:95-96`; `data_valid` → command measured **2 [SIM]** | exact |
| Over-force: `data_valid` → SAFE command | clk | 2 clocks | 40 ns | `f_over` at `:89`, `trip` at `:72`, SAFE at `:95`; measured 2 **[SIM]** | exact |
| E-stop button → SAFE command | clk | 3 clock edges | ≤ 60 ns | 2-flop sync + governor; measured 3 **[SIM]** | button asynchronous |
| Reset button → servo output low | clk | ≈ 3 clock edges | ≈ 60 ns | `reflex_top.v:27-33`, `servo_pwm_generator.v:42` | derived; `tb_de2_wrapper` monitors "low after every reset clock" **[SIM]** |
| Command → servo latch | clk | wait until frame boundary: 0 … 20 000 µs | 0 … 20 ms | `servo_pwm_generator.v:46-48` | frame is free-running; fault arrival is asynchronous to it |
| Latch → output | clk | +1 clock (`pulse_latched`) +1 (`servo_out`) | 40 ns | `:48,52` | exact |
| New width observable at the pin (falling edge) | PWM | W = 1000 … 2000 µs after the frame start | 1 … 2 ms | `:52` | SAFE = 1000 µs |
| Detect missing ADC (timeout) | clk | 50 000 clocks after the last valid sample | 1000 µs | `ADC_TIMEOUT_US` (`:17`) | then SAFE command +1 clock |

### 15.3 Derived totals (formulas)

* Digital decision (valid sample → command): `2 × 20 ns = 40 ns`.
* Force change → command, **best case** (force changes just before the sample instant): `550 + 2 = 552 clocks = 11.04 µs`.
* Force change → command, **worst case** (change just after a sample instant): `876 + 550 + 2 = 1428 clocks = 28.56 µs`.
  (Analog/FSR settling excluded; sample instant from the model assumption.)
* Fault (from a sample or e-stop) → **start of the first pulse carrying the new command**: at most one frame later,
  `≤ 20 ms + 3 clocks`.
* Fault → **end (falling edge) of that first pulse** for SAFE: `≤ 20 ms + 1.0 ms ≈ 21 ms`; for a general command W ≤ 2 ms: `≤ 22 ms`.
* Force change → servo pin, worst case: `28.56 µs + 20 ms + 1 ms ≈ 21.03 ms` (SAFE) — **derived from RTL, not measured**.
* The Stage 5 fault-latency simulation (`tb_fault_latency`, INFO lines) found the same structure: a fault reaches the next pulse unless it arrives in the last 5 clocks before a frame boundary for e-stop/grip (47 clocks for over-force with the test's 50-clock sampling); the pulse after that is always SAFE. In the missed case the fault itself arrives immediately before the boundary, so the bound relative to the fault is still about one frame. (The main README's "up to one frame, and in the worst case two frames" is a conservative wording relative to the start of the running pulse; the derivation here gives about one frame plus the pulse width.)

### 15.4 Answers

* **Does the implementation achieve sub-microsecond end-to-end response?** **No.** Only the digital decision after a valid sample is sub-microsecond (40 ns). The SPI frame alone takes 17.0 µs to `data_valid`, the sample-to-command latency is 11–29 µs, and the servo PWM interface adds up to 20 ms plus 1–2 ms.
* **Fastest response from the current architecture:** about 11 µs from force change to the internal command (best phase alignment), and then at best a few clocks to a pulse start; the changed pulse width is only visible at the falling edge 1–2 ms later.
* **Worst case:** about 28.6 µs to the command and about 21–22 ms until the changed pulse has finished at the servo pin.
* **Dominant stages:** (1) the 20 ms PWM frame latch, (2) the ADC/SPI transfer (≈ 17 µs), (3) a fixed 1–2 ms pulse width before the new width is visible. The 50 MHz logic is negligible.
* **Improvements without redesigning the system:** (a) route `trip`/e-stop to the output so a fault forces the servo signal to SAFE immediately instead of waiting for the frame boundary; (b) allow only *shortening* of a running pulse from the live command; (c) shorten the PWM frame if the servo accepts it (digital servos often accept a few ms — servo-dependent); (d) raise SCLK to 1.35 MHz (`HALF = 19`, frame to `data_valid` 34·19 = 646 clocks = 12.9 µs instead of 17.0 µs, ≈ 24 % faster; subject to wiring and the 3.3 V limit); (e) a different ADC or an analog comparator for the over-force reflex would cut the sensing stage to tens of nanoseconds.
* **Would faster sampling, parallel logic, different ADC timing or a different actuator interface help?** Faster sampling/ADC: moderately (microseconds). Parallel logic: no (40 ns already). A different actuator interface (e.g. an enable/brake line or driver input controlled directly by the fault flag): yes, by orders of magnitude (ms → tens of ns for the *signal*; the mechanism's own response time remains and is not knowable from RTL).
* **Changes needing new simulation and hardware validation:** every item above (each changes servo-signal behaviour and the safety logic).

### 15.5 Measurement plan (start and end events must be fixed first)

| Event | Definition | How to observe |
|---|---|---|
| T0 | Analog stimulus crosses the over-force level (use a bench source into the ADC input, not a mechanical touch) | oscilloscope CH1 on the ADC input or the stimulus generator trigger |
| T1 | `data_valid` pulse | Signal Tap (50 MHz = 20 ns resolution) or a spare GPIO bit |
| T2 | `pulse_cmd` becomes 1000 (SAFE) | Signal Tap / spare GPIO |
| T3 | Servo signal rising edge of the first pulse with the new command | CH2 on `GPIO[4]` |
| T4 | Falling edge of that pulse (1000 µs after T3 for SAFE) | CH2 |

1. **Simulation first:** a dedicated testbench (not yet in the repository) that timestamps T1–T4 with a stimulus applied at random phases of the frame; assert bounds from section 15.3.
2. **Internal capture:** Signal Tap on `data_valid`, `pulse_cmd`, `servo_out` (requires a Quartus compile — not yet done).
3. **Scope on the real pin** with the servo disconnected: report T3 − T0 and T4 − T0 over ≥ 1000 random-phase trials (min/typ/max).
4. Report quartus timing analysis (`quartus_sta`) separately from this architectural calculation; a passing 50 MHz timing report says nothing about the end-to-end response.

## 16. Quartus project configuration

* Device `EP4CE115F29C7`, top-level entity `TactileReflexive` (user's project settings; the repository contains no `.qpf`/`.qsf`).
* Source list added by `quartus/TactileReflexive_assignments.tcl`: `reflex_top_spi.v`, `reflex_top.v`, `adc_spi_interface.v`, `lut_engine.v`, `safety_governor.v`, `servo_pwm_generator.v`, `quartus/TactileReflexive.v`, plus `quartus/TactileReflexive.sdc`. No testbench or MCP3008 model.
* SDC: `create_clock -period 20.000 CLOCK_50`, `derive_clock_uncertainty`, false paths only from `KEY[*] SW[*]` and `GPIO[3]` (MISO). No exceptions on outputs; no invented input/output delays; outputs will show as unconstrained. `check_sdc_ports.py` verifies the patterns against the wrapper ports **[SIM/LOCAL tool]**.
* **[QUARTUS] none.** Assumptions needing Quartus: `$clog2`; the parameter-guard idiom (missing module in a not-taken `generate` branch); `initial`/`$readmemh` LUT initialisation (empty file name used); memory inference for the 64×12 arrays; port-declaration power-up values.

## 17. Pin-assignment and I/O-standard verification status

**No pin assignment is verified against the official manual, and none is written in any repository file.** Third-party tables found by web search suggest the following; they are listed only as candidates:

| Port | Candidate pin | Voltage per third-party table | Status |
|---|---|---|---|
| `CLOCK_50` | PIN_Y2 | 3.3 V | unverified |
| `KEY[0]`, `KEY[1]` | PIN_M23, PIN_M21 | "depending on JP7" | unverified |
| `SW[0]` | PIN_AB28 | "depending on JP7" | unverified |
| `GPIO[0]`, `GPIO[1]` | PIN_AB22, PIN_AC15 | "depending on JP6" | unverified |
| `GPIO[2]` | PIN_AB21 (single secondary source) | — | unverified |
| `GPIO[3]`, `GPIO[4]`, `LEDR[0..5]`, `LEDG[0..3]` | not obtained (LEDR0 PIN_G19 and LEDG0 PIN_E21 at 2.5 V seen once) | — | unverified |

Unresolved: JP6/JP7 positions and their voltage options (must be read from the manual and the physical jumpers). The I/O standard
must be set explicitly per pin; the Quartus default for Cyclone IV is believed to be 2.5 V, not 3.3 V (unverified). The safest
route is to import Terasic's own DE2-115 pin file; the wrapper uses its port names.

## 18. Hardware bring-up checklist

1. Quartus compile: no errors; review every warning (latches, unconnected ports, memory inference); timing slack ≥ 0.
2. Verify pins, JP6/JP7 and I/O standards against the manual; set unused pins "as input tri-stated".
3. Program with **servo, motor and any actuator power disconnected**; check LEDs (reset, fault, bank).
4. Scope `GPIO[4]`: no pulse during reset; 1000–2000 µs pulses every 20 ms afterwards.
5. Scope SPI (`GPIO[0..3]`): 1 MHz SCLK, CS timing, 17 clocks; verify MCP3008 supply is 3.3 V.
6. Feed a known analog level; compare ADC code with expectation; test ADC disconnect → timeout; test MISO shorted low (known gap).
7. Test e-stop and reset behaviour; **add an independent hardware actuator-power cut-off** before any actuator is connected.
8. Measure fault-to-pin latency (section 15.5).
9. Calibrate thresholds/LUT with the actuator unloaded, then with a compliant load; only then a real object.

## 19. Known limitations and safety risks

See also the matrix in the audit (appendix A). Summary: stuck-low MISO and FSR open-circuit are undetected; the e-stop does not remove actuator power; a fault takes up to one 20 ms frame to reach the servo pin; thresholds and LUT are uncalibrated; reset near a UART COMMIT is ambiguous to a host; pins, voltages, Quartus acceptance and all hardware behaviour are unverified. **The design must not be called fail-safe or safety-certified; any hazard to people or equipment needs an independent physical power cut-off and a proper safety assessment.**

## 20. AI/ML extension opportunities (future work only)

No machine-learning component exists in the repository; the LUT is a fixed placeholder curve generated by `lut_gen.py`, not an AI/ML model. **[FUTURE]** options: offline-trained mapping (force → command) exported as a LUT through the existing validated upload path; contact classification (slip/impact) from the ADC stream on a host or soft core, advisory only, never in the hard-limit path; anomaly detection on sensor streams to flag stuck/open sensors (which would also close the plausibility gap). Any ML output must stay inside the governor's clamps and fault logic.

## 21. Future improvements

Sensor plausibility checks (minimum/dynamic-range/stuck-value), fault-forced output gating independent of the PWM frame, hardware-visible watchdog, calibrated thresholds exposed as top-level parameters, shorter PWM frame (servo permitting), measured latency testbench, UART upload build on the board, Signal Tap instrumentation, formal checks of the governor.

## 22. Conclusion

The deterministic digital path is implemented, small, and extensively simulated: 40 ns from valid sample to command, hard 1000–2000 µs clamping, latched faults, parameter guards, a board wrapper and a clean simulation regression (87 PASS, 0 FAIL in the cloud workspace). It is **not** a sub-microsecond end-to-end system: the SPI ADC and especially the 20 ms servo frame dominate. Hardware readiness is blocked on verified pin assignments, a Quartus compile, an independent power cut-off, sensor-fault handling decisions, and measurements.

## 23. Reproducible commands for tests and builds

From the project root (`bash`/MSYS2 or Linux; Icarus Verilog and Python 3 required):

```
bash run_sim.sh                  # standard suite
bash run_sim.sh --extended       # standard + extended (real 20 ms frame wrapper test, slower repeats)
python3 -B python/lut_gen.py --test
python3 -B quartus/check_sdc_ports.py
sha256sum -c CHECKSUMS.sha256
```
Board-level simulation only (PowerShell):
```
iverilog -g2005 -o sim_de2 quartus\TactileReflexive.v rtl\reflex_top_spi.v rtl\reflex_top.v rtl\adc_spi_interface.v rtl\lut_engine.v rtl\safety_governor.v rtl\servo_pwm_generator.v tb\mcp3008_model.v tb\tb_de2_wrapper.v
vvp -n sim_de2
```
Quartus (user's machine, on a copy of the project, after pins are verified): run `quartus/TactileReflexive_assignments.tcl` from *Tools > Tcl Scripts*, then `quartus_sh --flow compile TactileReflexive` and `quartus_sta TactileReflexive`. **None of these has been run.**

---

# Appendix A — Safety and fault-coverage matrix

Legend: **Source** = behaviour guaranteed by the code; **Sim** = demonstrated by the executed regression; **HW** = unverified on hardware (true for every row).

| # | Scenario | Source logic | Expected | Behaviour inferred from RTL | Existing tests | Executed result | Gap / potential defect | Sev. | Action |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Normal ADC sampling / SPI | `adc_spi_interface.v:82-109`, `reflex_top_spi.v:57,65` | valid samples every 17.52 µs | continuous conversions; 10-bit `data` + `data_valid` | `tb_adc_spi_interface` (+27/16/50 MHz variants), `tb_reflex_top_spi`, `tb_de2_wrapper` | PASS (std and ext) | analog sample instant is a model assumption | Low | confirm MCP3008 datasheet timing on hardware |
| 2 | ADC disconnected / MISO stuck **high** | null bit = 1 → `frame_err` (`:99-104`); `since_sample` (`governor:83-85`) → `f_timeout`, latched; SAFE (`:95`) | SAFE and fault | no `data_valid` → after 1000 µs timeout fault, SAFE until reset | `tb_adc_spi_interface` (MISO open), `tb_reflex_top_spi`, `tb_de2_wrapper` ("ADC disconnected…", "timeout latched") | PASS | old command stays active up to 1000 µs (+ frame latch) = stale-sample window | Medium | accept and document; or shorten `ADC_TIMEOUT_US` (needs recalculation of the guard) |
| 3 | MISO stuck **low** | null bit 0, all data 0 → valid code 0 → LUT[0] = 2000 µs (`lut_engine.v:34`) | fault | **no fault; commands the maximum pulse** | `tb_de2_wrapper` "CHARACTERISATION: MISO stuck low" (documents the gap) | PASS (as characterisation) | **undetected stuck-low / ambiguous with "no force"** | **High** | add minimum-plausibility or dynamic-range check, or bias the sensor so rest ≠ 0; decide gripper direction semantics |
| 4 | FSR open / short / implausible | `f_range` at code ≥ 1015 (`:88`); no low or dynamic checks | detect open and short | short-to-high detected (if wired that way); **open (reads ~0) and constant readings undetected** | `tb_governor_boundary` (1014/1015), `tb_governor_priority`, `tb_de2_wrapper` range fault | PASS | no stuck-value or minimum check; polarity depends on divider wiring | **High** | define divider wiring; add plausibility monitor (future change) |
| 5 | SPI timeout, frame length, framing errors | fixed 17-edge FSM (`:96`); only null bit checked | detect corrupt frames | wrong bits that keep the null bit 0 are accepted; no CRC in MCP3008 | `tb_adc_spi_interface` (model timing checks, `violations == 0`), `tb_adc_bad_param` | PASS | undetectable data corruption inside a "valid" frame | Medium | hardware limitation; add sanity filtering if needed |
| 6 | Force threshold exceeded | `adc_value >= FORCE_MAX` (`:89`) → `f_over`; `trip` (`:72`) | SAFE | over-force → SAFE 2 clocks after `data_valid` | `tb_governor_boundary` (899/900), `tb_governor_priority`, `tb_de2_wrapper` | PASS | threshold 900 is a placeholder | Medium | calibrate (section 18) |
| 7 | Hysteresis / resume | clear when sample < `FORCE_RESUME` (`:90`) | resumes below 800 | holds 800–899 | `tb_governor_boundary` (799/800), `tb_governor_priority`, `tb_de2_wrapper` (790 resumes) | PASS | placeholder values | Low | calibrate |
| 8 | ADC range fault, latching | `>= ADC_FAULT_HI` (`:88`), latched until reset | latched SAFE | latched; also sets over-force | `tb_governor_boundary` (1014/1015), `tb_de2_wrapper` | PASS | placeholder 1015 | Low | calibrate |
| 9 | E-stop assertion and reset | `if (estop) f_estop <= 1` (`:81`); `trip` includes live e-stop (`:72`); reset clears (`:78`); wrapper polarity (`TactileReflexive.v:38-39`) | SAFE and latched | SAFE in 3 edges; latched; reset clears | `tb_governor_priority`, `tb_reflex_top`, `tb_de2_wrapper` | PASS | **board button is not a safety device; actuator power not removed; open wire = not pressed on a normally-open design** | **High** (system) | independent hardware power cut-off; normally-closed e-stop wiring (future wrapper change) |
| 10 | Reset during an SPI transaction / near command update | ADC reset → `S_GAP`, CS high ≥ HALF clocks (`adc:73-78`); governor reset (`:77-79`); servo reset (`servo:42`) | clean abort | aborted frame produces no `data_valid`; command SAFE | `tb_adc_spi_interface` (reset mid-frame), `tb_governor_priority` (sample in reset clock), `tb_servo_pwm`, `tb_de2_wrapper` (servo low after reset) | PASS | pulse truncated by reset is exempt from width checks; reset exactly at `data_valid` clock covered only in the governor unit test | Low | acceptable |
| 11 | LUT bank switch / incomplete upload | write ports tied off in this build (`TactileReflexive.v:60-63`); UART build has atomic swap | n/a for this build | unused in the DE2-115 build | `tb_lut_engine`, `tb_lut_upload_ctrl`, `tb_commit_reset_race`, `tb_lut_uart_top_load`, `tb_safety_vs_upload` | PASS | reset around a UART COMMIT is ambiguous to the host (characterised, INFO-only) | Low (this build) / Medium (UART build) | host must re-upload after reset |
| 12 | Servo PWM min / max / malformed commands | governor clamps to 1000–2000 (`:73-74,96`); servo module itself takes 0…4095 | pulses 1000–2000 µs | pin pulses stay within limits | `tb_servo_pwm` (exact widths, width 0 silent), `tb_servo_bad_param`, `tb_de2_wrapper` (min 1000, max 2000, none > 2000 µs) | PASS | servo module has no own clamp (relies on the governor); `FRAME_US > 2000` assumes governor max | Low | keep governor in the path |
| 13 | Fault propagation to the servo output | command in 2–3 clocks; latch only at frame boundary (`servo:46-48`) | prompt | **up to ~20 ms + pulse width** | `tb_fault_latency` (INFO windows; structure asserted), `tb_de2_wrapper` | PASS (structure); numbers derived | unacceptable if requirement is ≪ 20 ms | **High** | fault-forced output gating / shorter frame (needs new simulation + hardware validation) |
| 14 | Simultaneous faults | `trip` is an OR (`:72`); flags independent | all flagged, SAFE | e.g. e-stop + range + over-force = `1011` | `tb_governor_priority` | PASS | none found | Low | — |
| 15 | Startup before the first valid sample | reset → SAFE (`:79`); servo low until first latch (`servo:42,46-48`); synchronisers start in reset (`reflex_top.v:27`) | SAFE | first CS fall 28 clocks after reset release, first `data_valid` 878 clocks (17.55 µs) < 1000 µs timeout, first pulse ≥ 1 frame later | `tb_de2_wrapper` (start-up, no false timeout), `tb_reflex_top_spi` | PASS | power-up values depend on Quartus honouring register initialisers | Low | check synthesis report; scope at power-up |

**Hazards that need an external measure (not solvable in this FPGA logic alone):** actuator power removal on e-stop, loss of the FPGA clock or configuration, a hung FPGA output, wiring faults at the servo, and any personnel-safety function. A hardware emergency stop that cuts actuator power independently of the FPGA is required before any actuator is attached.

# Appendix B — Milestones

| Milestone | Status |
|---|---|
| Core RTL (ADC, LUT, governor, PWM) | Completed, simulated |
| UART LUT upload and replies | Completed, simulated, unused on the board build |
| Parameter guards and negative tests | Completed |
| Python LUT generator and loading tests | Completed |
| DE2-115 wrapper, SDC, TCL, SDC checker | Completed in simulation |
| Quartus compile and timing report | **Pending** (not run) |
| Verified pin assignments and I/O standards | **Blocked** (official manual needed) |
| Hardware bring-up, calibration, latency measurement | **Blocked** (board and sensor) |
| Sensor-plausibility and fault-gated output | Proposed |

# Appendix C — Verification record

| Item | Detail |
|---|---|
| Repository | `/home/user/tactile-reflex-system` (assistant's cloud workspace), branch `claude/gallant-turing-hw1leg`. The audit was performed in that cloud workspace (not on a Windows machine), on base commit `c1870c3` plus then-uncommitted changes (two testbench fixes, `CHECKSUMS.sha256`, `README.md`, `run_sim.sh`, new `quartus/` and `tb/tb_de2_wrapper.v`); those changes are included in the commit that adds this report |
| Relation to the user's Windows project | **Not verified identical.** The snapshot zip sent earlier has SHA-256 `4b314edb397f7d6fefa6b0ebf35c26b71e2d6cc17039b82b6796d02e6eb69ef9`; compare it with the user's copy |
| Test runs | on scratch copies of the working tree (ignored artifacts untouched); see section 14 |
| Latency probes | scratch testbench outside the repository (not added): CS fall → `data_valid` 850 clocks; `data_valid` → `lut_valid` 1; → command 2; period 876; over-force 2; e-stop button → command 3 edges; reset release → first CS fall 28, first `data_valid` 878 |
| Not run | Quartus (all stages), SignalTap, hardware, user-side Icarus 13 re-run after the fixes |
