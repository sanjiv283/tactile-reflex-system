# Hardware validation guide

**Status: nothing in this guide has been done. Hardware validation is 0 %.** Every stage below is **BLOCKED** until a DE2-115, an AD7476A-class ADC with a force sensor, a DRV8871
driver, a motor, instruments and a person to supervise are available. Do not treat any simulation result in this repository as a hardware result.

Rules for the whole plan
* A stage starts only when the previous stage's gate is met and signed. A failed gate stops the plan; fix, re-verify in simulation (`sh sim/run_all.sh`), and repeat the stage.
* Record **measurements, not impressions**: instrument, setting, date, operator, raw file. Put them in `results/hardware/<stage>/` (create it) and never edit a result afterwards.
* Never power the motor supply until stage 4's gate is met. First powered motor tests use a current-limited supply and no mechanical load. A second person is present for every motor stage.
* The e-stop must work **before** the first motor movement, and must be tested again after every wiring change.
* Open hazards that must be resolved or explicitly accepted before stage 4: H-03 (e-stop is FPGA-only), H-04 (pin state during FPGA configuration), H-05 (stuck PWM). See `HAZARD_ANALYSIS.md`, `docs/DRV8871_SAFE_STATE_ANALYSIS.md`.

## Stage 0: prerequisites (no hardware needed, but currently blocked)

| Gate | How | Evidence | Today |
|---|---|---|---|
| Pin file verified | obtain Terasic's `DE2_115.qsf`; `python3 tools/check_pins.py --reference DE2_115.qsf --emit constraints/de2_115_from_reference.qsf`, then `--strict` | `results/pin_check.json` says `VERIFIED AGAINST REFERENCE`, 0 unassigned | **BLOCKED** (Terasic host not reachable; file not supplied) |
| GPIO wiring chosen and confirmed | check `constraints/gpio_map.txt` against the real Pmod/driver/e-stop wiring | signed wiring table | **BLOCKED** |
| Quartus project builds | `python3 tools/make_quartus_project.py --pins ... --reference ...` then `quartus_sh --flow compile` | clean compile, no unassigned pins, no critical warnings | **BLOCKED** (Quartus not installed) |
| Timing met at 50 MHz | Quartus timing report, slow and fast corners | report with positive slack on every constraint, including the SDC's false paths reviewed | **BLOCKED** |
| Datasheet facts obtained | fill the worksheet in `docs/DRV8871_SAFE_STATE_ANALYSIS.md` section 5 from the TI and Intel documents | completed worksheet | **BLOCKED** (hosts not allowed from the development environment) |

## Stage 1: board alone (no ADC, no driver, no motor)

1. Program the FPGA. Confirm clock, LEDs and keys map as in the README (a wrong pin file shows up here). Evidence: photo/log per LED and key.
2. **Pin state during configuration (H-04).** With a scope or logic analyser on the `PWM_OUT` pin and the driver connector disconnected from any supply: power-cycle and capture the level
   from power-on through configuration. Gate: the pin is at its safe level (inputs low, coast) for the whole time, or an external pull-down brings it there. Record the level and the duration.
3. UART: loopback test at 115200 8N1 with `python3 host/ai_host.py --selftest` then the real port: telemetry frames decode with zero dropped bytes over a long capture.
4. Reset and clear key: measure that KEY3 resets at any instant, that KEY1 releases only on a deliberate press, and that holding KEY1 during reset does not clear. Bounce with a real key
   (the debounce time on the board is 1,000,000 clocks = 20 ms; simulation used 32 clocks).

## Stage 2: sensing chain with a substitute for the sensor

Use a stable resistor or potentiometer instead of the force sensor and a voltmeter.
0. **Sampling margin (H-16, unresolved hardware blocker).** With a scope on `ADC_CS_N`, `ADC_SCLK` and `ADC_MISO` at the FPGA pins, measure (a) the delay from chip-select falling to the first data bit being valid, and (b) the delay from each SCLK falling edge to valid data, over many frames and temperatures. Compare with the AD7476A datasheet output-delay figures **[VERIFY: not obtained]**. The RTL's two-flop MISO synchroniser samples the first bit only **1 clock (20 ns)** after chip-select falls and every later bit **4 clocks (80 ns)** after launch (3 clocks / 60 ns and 6 clocks / 120 ns without it). In simulation against an idealised delayed model the RTL tolerates an ADC output delay of up to 20 ns with the synchroniser and up to 60 ns without it (`tools/adc_timing_sweep.py`); these simulated windows are **not** a hardware margin. Gate: the measured first-bit delay plus pin and trace delay must leave a margin that you decide and record; if not, the MISO structure has to change (a decision that needs approval) before stage 2 can pass.
1. ADC frame alignment: apply known voltages and compare the telemetry force to the expected count; confirm the 4 leading-zero convention. (The simulation used a behavioural ADC, so this is the first time the RTL meets the real part.)
2. Fault paths: short and open the input; confirm `adc_invalid` / sensor-fault behaviour and the 4-frame rule; unplug the ADC and confirm the watchdog.
3. Input noise: log a constant input and record the count spread. Gate: noise is well below the margin you intend to use.

## Stage 3: e-stop and safe-state timing (still no motor)

1. With the scope on KEY0 (or the external contact) and `PWM_OUT`: measure press-to-PWM-low. Simulation predicts 5 clocks (100 ns) plus input and synchroniser effects; record the real distribution over at least 100 presses.
2. Repeat for a force-limit trip using a signal generator or divider step at the ADC input; record the input-to-PWM-low distribution (simulation: 105 to 192 clocks, dominated by the ADC frame phase).
3. Confirm that a cut e-stop wire stops the output (normally-closed contact), and that the latch holds after release until a deliberate clear.
4. **Stuck-PWM test (H-05)** only with the driver disconnected: stop or hold the FPGA clock / reconfigure while `PWM_OUT` is high and record what the output does. The result decides whether an independent protection is required.

## Stage 4: driver with the motor disconnected

1. Add the independent e-stop cut of the motor supply if you decided to (recommended in `docs/DRV8871_SAFE_STATE_ANALYSIS.md`), and test it with a dummy load before the driver.
2. Current-limited bench supply, set well below the motor's stall current and the fuse rating. Measure the driver output with a scope: PWM present when commanded, absent (coast) in the safe state, absent while the FPGA is unconfigured, behaviour on supply brown-out.
3. Gate: with the supply on and no motor, every safe-state condition produces no driver drive. Record each condition.

## Stage 5: motor, unloaded

Fixed, guarded, nobody near moving parts. Start at the lowest duty. Verify: a force-limit event, an e-stop press, a sensor unplug and a reset each stop the drive; coast behaviour of the mechanism after the stop (does the load back-drive?); measured stop time end to end (input to motor current zero), not only to PWM low.

## Stage 6: gripper with a soft, harmless load

Compliant test object, no body parts. Repeat the stop tests with load. Record the force overshoot after a trip (the distance and force reached while stopping): this, plus reaction time, is the margin that `tools/calibrate.py` does **not** include.

## Stage 7: calibration and limits

Run `CALIBRATION_GUIDE.md`, apply the thresholds, re-verify the trips at the masses on the bench, repeat after reassembly and on another day.

## Stage 8: soak and review

Hours of operation with logged telemetry (`host/ai_host.py --log`): count faults, spurious trips, dropped telemetry. Independent review of the evidence against `HAZARD_ANALYSIS.md`; update the hazard table with measured results. Only then may anything be said about the behaviour of the real system.

## What would count as hardware-validated

Each requirement R-01 to R-17 in `HAZARD_ANALYSIS.md` re-verified on the board with a measurement file, every OPEN/BLOCKED hazard closed or formally accepted by a named person, and the evidence archived with the RTL commit it was taken on.
