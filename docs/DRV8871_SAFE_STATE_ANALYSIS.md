# DRV8871 safe-state analysis

**Status: DESIGN ANALYSIS, NOT HARDWARE-VALIDATED.** No driver, motor or board was powered. The Texas Instruments DRV8871 datasheet
(`ti.com/lit/ds/symlink/drv8871.pdf`) and the Cyclone IV handbook could not be fetched from the development environment (host not on the session
allowlist). Every device fact below is therefore tagged:

| Tag | Meaning |
|---|---|
| **[TI-snippet]** | text of the TI datasheet page seen in a web-search result (not the full PDF) |
| **[secondary]** | a distributor/third-party document (e.g. a breakout-board manual); not authoritative |
| **[sibling]** | the TI DRV8872 table, a sibling part, seen in a search result |
| **[VERIFY]** | needed for the conclusion but **not obtained**; check the TI PDF / Intel Cyclone IV handbook before relying on it |
| **[design]** | a fact about this project's own circuit/RTL (checked in the repository) |

## 1. What the circuit does (as designed) **[design]**

`PWM_OUT` (FPGA GPIO) -> DRV8871 `IN1`; `IN2` tied low (one drive direction); 12 V supply through a 2 A fuse; the e-stop (normally-closed contact) and the
"Fault/safe state" logic act **only inside the FPGA** (`KEY[0] & ESTOP_EXT_N` -> two-flop synchroniser -> `fault_handler` latch -> `safety_governor.safe_state`
-> `pwm_generator.kill`). The motor supply has no switch in the e-stop path (`docs/circuit_diagram.svg`: fuse only).

## 2. Driver input states used

| IN1 | IN2 | Output | Source |
|---|---|---|---|
| 0 | 0 | **Coast**: bridge high-impedance; after about 1 ms of both inputs low the device enters low-power **sleep** | [TI-snippet] (sleep ~1 ms), [sibling] and [secondary] (coast) |
| PWM | 0 | forward drive with PWM; slow-decay behaviour during the off time | [TI-snippet] (page describes slow decay) / [VERIFY] exact table row |
| 1 | 1 | brake (low-side slow decay): **not used by this design** | [sibling], [secondary] |
| inputs | | active high, internal pull-downs to GND (value in an unreviewed wiki: about 100 kOhm) | [secondary] / [VERIFY] value, VIL/VIH thresholds |

Consequence: the project's "safe state" is `PWM_OUT = 0`, i.e. IN1 = IN2 = 0 = **coast**, not brake. For a gripper this means the motor stops driving and the
load can back-drive the mechanism. That is the intended "release/cut" behaviour for an over-force limit, but it is a design decision that must be confirmed
for the actual mechanism (a self-locking gearbox may hold the force even when coasting).

## 3. Safe-state analysis by life-cycle phase

| Phase | FPGA pin `PWM_OUT` | Result at the driver | Status |
|---|---|---|---|
| Board unpowered | undriven | IN1 pulled to GND by the driver's internal pull-down -> coast | [secondary] the pull-down exists; [VERIFY] value |
| **FPGA configuration (power-up, before the design runs)** | Cyclone IV user I/O are tri-stated during configuration; whether a weak internal pull-**up** is active depends on the `nIO_PULLUP` pin wiring on the DE2-115 | if a weak pull-up (tens of kOhm) fights a ~100 kOhm pull-down, the pin can sit **above VIH -> motor driven during configuration** | **[VERIFY] OPEN HAZARD H-04.** Mitigation: add an external pull-down on `PWM_OUT` sized from the Cyclone IV pull-up range and the DRV8871 VIH (fill the table in section 5); verify with a scope/meter on the bench with the motor supply disconnected |
| Reset held (KEY3 low) | `pwm_out` register async/sync-reset to 0 | coast | simulation: `tb_reset_recovery`, `tb_de2_115_top`; PWM low within one clock of reset |
| Normal run, force below limit | PWM per LUT command | drive | simulation |
| Safe state (force limit, fault, e-stop, invalid ADC) | `kill` forces `pwm_out` low on the next clock | coast | simulation: `safety_monitor` S2, formal P2; e-stop to PWM low within 7 clocks (`tb_reset_recovery`) |
| FPGA clock lost or FPGA hung while `pwm_out` = 1 | **register holds its last value** | **motor stays driven**: no RTL can protect against the FPGA itself failing | **OPEN HAZARD H-05**, see section 4 |
| Sensor unplugged | ADC reads rail / invalid frames | `adc_invalid` / `sensor_fault` -> safe state after `INVALID_LIMIT` frames | simulation (`tb_top`, `tb_adc_interface`); the limit counts frames, not time (about 4 frames) |
| Laptop/AI crash | AI advice goes stale after 10 ms | AI ignored; hard limits unchanged | simulation (`tb_ai_control_interface`, `tb_host_link`) |

## 4. Findings that matter

1. **The e-stop is not a hardware e-stop.** Pressing it asks the FPGA to stop driving `IN1`. It does not interrupt the motor supply. If the FPGA is mis-configured,
   unconfigured, hung, clock-less, or the PWM pin is shorted high, the stop is ineffective. The only independent protections today are the 2 A fuse and the driver's
   own current limit. **Recommendation (design change, not applied):** place an independent disconnect (a normally-closed e-stop contact in series with the 12 V motor
   supply, or a relay/contactor held in by the same contact) so that a stop works with the FPGA in any state. This is the standard expectation of an e-stop
   and the single most valuable hardware change.
2. **Stuck-high PWM (H-05).** A frozen `pwm_out` flip-flop keeps IN1 high. Options to evaluate: AC-couple the PWM into IN1 so that a DC level cannot hold the
   motor on (needs the duty range and the 12.2 kHz carrier checked against the driver's VIH and the coupling time constant); or an external watchdog that gates the
   driver-enable path if the FPGA stops toggling a heartbeat. Neither is implemented. **[VERIFY]** by bench test.
3. **Configuration-time state (H-04)**: see the table; requires the Cyclone IV handbook (pull-up current/range) and the DRV8871 VIH/VIL to size a resistor.
4. **Coast vs brake**: confirm the mechanism's behaviour in coast; if holding is required in the safe state, brake (IN1 = IN2 = 1) would be a different design
   with different failure modes (it also stops a coasting motor quickly, which may or may not be desired).
5. **Sleep/wake**: with both inputs low for about 1 ms the driver sleeps **[TI-snippet]**; the first PWM edge after sleep has a wake-up delay **[VERIFY]**. The
   RTL's PWM is 12.2 kHz; duty 0 produces a permanently low input, so after a safe state the first drive command is delayed by the wake time (not a safety problem;
   it affects the response after release).
6. **VM undervoltage lockout** exists in the driver **[TI-snippet: section title only]**; thresholds and recovery **[VERIFY]**. A supply brown-out is not monitored by the
   FPGA.

## 5. Worksheet to complete before powering a motor (values come from the datasheets, not from this repository)

| Quantity | Value | Source document / page |
|---|---|---|
| DRV8871 input pull-down resistance (typ / min) | _fill in_ | TI DRV8871 datasheet |
| DRV8871 VIH min, VIL max | _fill in_ | TI DRV8871 datasheet |
| Cyclone IV weak pull-up resistance range during configuration; `nIO_PULLUP` wiring on DE2-115 | _fill in_ | Intel Cyclone IV handbook; DE2-115 schematic |
| FPGA GPIO output high/low levels at the load | _fill in_ | Cyclone IV datasheet (3.3-V LVTTL) |
| External pull-down value that keeps IN1 < VIL(max) in the worst case during configuration | _compute_: `R_pd <= VIL_max / I_pullup_max` and `R_pd` must also not overload the GPIO output | calculation |
| Driver wake-up time from sleep; UVLO thresholds; current-limit resistor value used (ILIM) | _fill in_ | TI DRV8871 datasheet |

## 6. Not done / blocked

* Reading the authoritative TI and Intel documents: **BLOCKED** (`ti.com`, `intel.com` are not allowed from this environment; allow them or place the PDFs in the repository to continue).
* Any bench measurement (pin level during configuration, behaviour with a stuck PWM, e-stop with the FPGA unprogrammed): **BLOCKED** (no hardware).
